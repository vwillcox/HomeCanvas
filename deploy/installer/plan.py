"""What the installer decides, kept apart from how it asks.

Everything here is plain functions over plain data — the catalogue of
widgets and themes, the extras, a person's choices, the config file — so it
can be tested without a terminal. homecanvas_setup.py does the asking.

Standard library only: it runs before anything else is installed.
"""

import json
import os
import re
import shutil
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
APP_DIR = os.path.dirname(os.path.dirname(HERE))
CONFIG = os.path.expanduser("~/.config/homecanvas/config.json")
VOICE_DIR = os.path.expanduser("~/.local/share/homecanvas/voice")
VOICE_PYTHON = os.path.join(VOICE_DIR, "venv", "bin", "python")

# The dashboard's grid, as lib/dashboard/dashboard_model.dart has it.
COLUMNS, ROWS = 12, 8


def load_json(name):
    with open(os.path.join(HERE, name)) as f:
        return json.load(f)


class Catalogue:
    """The widgets, themes, extras and presets there are to choose from."""

    def __init__(self, catalogue=None, modules=None):
        catalogue = catalogue or load_json("catalogue.json")
        modules = modules or load_json("modules.json")
        self.categories = catalogue["categories"]
        self.widgets = {w["type"]: w for w in catalogue["widgets"]}
        self.themes = catalogue["themes"]
        self.modules = modules["modules"]
        self.presets = modules["presets"]

    def by_category(self):
        """[(category, [widget, …])], in the editor's order, by name within."""
        out = []
        for c in self.categories:
            ws = sorted((w for w in self.widgets.values() if w["category"] == c),
                        key=lambda w: w["name"].lower())
            if ws:
                out.append((c, ws))
        return out

    def preset(self, preset_id):
        return next((p for p in self.presets if p["id"] == preset_id), None)

    def theme(self, theme_id):
        return next((t for t in self.themes if t["id"] == theme_id), self.themes[0])

    def modules_for(self, widgets, voice=False, apt=True):
        """The extras worth offering for [widgets] (and voice control)."""
        chosen = set(widgets)
        out = []
        for m in self.modules:
            if m.get("apt_only") and not apt:
                continue
            if chosen & set(m.get("widgets", [])) or (voice and m.get("with_voice")):
                out.append(m)
        return out


# ---- the dashboard ------------------------------------------------------------

def place(taken, width, height):
    """The first free cell for a [width]×[height] widget on a page whose
    cells in use are [taken], scanning row by row as the editor does; None
    when it does not fit."""
    for y in range(ROWS - height + 1):
        for x in range(COLUMNS - width + 1):
            cells = {(x + i, y + j) for i in range(width) for j in range(height)}
            if not cells & taken:
                return x, y
    return None


def layout(catalogue, chosen, first_page=0, first_id=1):
    """Pages and widgets for [chosen] widget types: a page for each category
    that has any, in the editor's order — sharing the page before when all
    of it fits there, two categories to a page at most. Gives back (pages,
    widgets) as config.json has them, pages numbered from [first_page] and
    ids from w[first_id]."""
    pages, widgets = [], []
    page, taken, next_id = first_page - 1, None, first_id

    def add(w, spot, on):
        nonlocal next_id
        widgets.append({
            "id": f"w{next_id}", "type": w["type"], "x": spot[0], "y": spot[1],
            "width": w["width"], "height": w["height"], "page": on,
            "fontFamily": "", "fontScale": 1.0, "options": {},
        })
        next_id += 1
        taken.update(_cells(spot, w))

    for category, ws in catalogue.by_category():
        # The big ones first: they pack better, and small ones fill the gaps.
        mine = sorted((w for w in ws if w["type"] in chosen),
                      key=lambda w: -w["width"] * w["height"])
        if not mine:
            continue
        shared = None
        if taken is not None and " · " not in pages[-1]["name"]:
            shared = _fit_all(taken, mine)
        if shared is not None:
            pages[-1]["name"] += " · " + category
            for w, spot in zip(mine, shared):
                add(w, spot, page)
            continue
        page += 1
        pages.append(_page(category))
        taken, more = set(), 1
        for w in mine:
            spot = place(taken, w["width"], w["height"])
            if spot is None:
                # The page is full: the rest of the category on another.
                page += 1
                more += 1
                pages.append(_page(f"{category} {more}"))
                taken = set()
                spot = place(taken, w["width"], w["height"]) or (0, 0)
            add(w, spot, page)
    return pages, widgets


def _fit_all(taken, ws):
    """Where each of [ws] would go on a page with [taken] in use, or None if
    they don't all fit."""
    trial, spots = set(taken), []
    for w in ws:
        spot = place(trial, w["width"], w["height"])
        if spot is None:
            return None
        spots.append(spot)
        trial |= _cells(spot, w)
    return spots


def _cells(spot, w):
    x, y = spot
    return {(x + i, y + j) for i in range(w["width"]) for j in range(w["height"])}


def _page(name):
    return {"name": name, "schedule": {"from": "", "to": "", "days": ""}}


# ---- the config ---------------------------------------------------------------

def read_config(path=CONFIG):
    try:
        with open(path) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def write_config(config, path=CONFIG):
    """Writes [config] whole, readable by its owner alone, with the one it
    replaces kept beside it."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        shutil.copy2(path, f"{path}.before-installer-{time.strftime('%Y%m%d-%H%M%S')}")
    tmp = path + ".part"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(config, f, indent=2)
    os.replace(tmp, path)


def existing_widgets(config):
    return list(((config.get("dashboard") or {}).get("widgets")) or [])


def apply_dashboard(config, catalogue, chosen, theme_id, how, open_on_start):
    """[config] with the dashboard as chosen. [how] is "replace", "add" (new
    pages after the ones there) or "keep" (only the theme changes)."""
    d = config.setdefault("dashboard", {})
    d["enabled"] = True
    d["themeId"] = theme_id
    if open_on_start is not None:
        d["showOnLaunch"] = open_on_start
    if how == "keep" or not chosen:
        return config
    old = existing_widgets(config)
    if how == "add" and old:
        first_page = max(int(w.get("page", 0)) for w in old) + 1
        ids = [int(m.group(1)) for w in old if (m := re.fullmatch(r"w(\d+)", str(w.get("id"))))]
        pages_before = list(d.get("pages") or [])
        while len(pages_before) < first_page:
            pages_before.append(_page(""))
        pages, widgets = layout(catalogue, chosen, first_page, max(ids, default=0) + 1)
        d["pages"] = pages_before[:first_page] + pages
        d["widgets"] = old + widgets
    else:
        pages, widgets = layout(catalogue, chosen)
        d["pages"], d["widgets"] = pages, widgets
    return config


def apply_answers(config, module_id, answers):
    """[config] with what was asked for an extra saved where the app reads
    it."""
    if module_id == "weather" and answers.get("location"):
        w = config.setdefault("weather", {})
        w["location"] = answers["location"].strip()
        w["enabled"] = True
        # Found again by the app from the new place.
        for k in ("latitude", "longitude", "resolvedLabel"):
            w.pop(k, None)
    elif module_id == "home-assistant" and answers.get("token"):
        ha = config.setdefault("homeAssistant", {})
        ha["baseUrl"] = answers["url"].rstrip("/")
        ha["token"] = answers["token"].strip()
    elif module_id == "homey" and answers.get("key"):
        config["homey"] = {"address": answers["address"].strip().rstrip("/"),
                           "apiKey": answers["key"].strip()}
    return config


def apply_voice(config, wake_json, enabled=True):
    s = config.setdefault("screen", {})
    s["voiceControl"] = enabled
    if wake_json is not None:
        s["wakeWord"] = wake_json
    return config


def apply_immich(config, url, key):
    config["immichUrl"] = url
    config["apiKey"] = key
    return config


# ---- checking what is typed -----------------------------------------------------

def _get(url, headers=None, timeout=8):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read()


def check_immich(url, key=None):
    """(ok, message, url as it answered). Without [key], only that an Immich
    server answers at [url]."""
    url = url.strip().rstrip("/")
    if not re.match(r"^https?://", url):
        url = "https://" + url
    try:
        _, body = _get(url + "/api/server/ping")
        if b"pong" not in body:
            return False, f"Something answered at {url}, but it isn't Immich.", url
    except (urllib.error.URLError, OSError, ValueError) as e:
        return False, f"No Immich server answered at {url} ({_why(e)}).", url
    if key is None:
        return True, f"Found Immich at {url}.", url
    try:
        _get(url + "/api/users/me", {"x-api-key": key.strip()})
        return True, "Immich accepted the key.", url
    except urllib.error.HTTPError as e:
        return False, f"Immich didn't accept that key (HTTP {e.code}).", url
    except (urllib.error.URLError, OSError) as e:
        return False, f"Couldn't ask Immich ({_why(e)}).", url


def check_home_assistant(answers):
    url = answers.get("url", "").strip().rstrip("/")
    try:
        _get(url + "/api/", {"Authorization": "Bearer " + answers.get("token", "").strip()})
        return True, f"Home Assistant at {url} accepted the token."
    except urllib.error.HTTPError as e:
        return False, f"Home Assistant refused the token (HTTP {e.code})."
    except (urllib.error.URLError, OSError, ValueError) as e:
        return False, f"Nothing answered at {url} ({_why(e)})."


def check_homey(answers):
    address = answers.get("address", "").strip().rstrip("/")
    base = address if "://" in address else "http://" + address
    roots = [base] if ":" in base.split("://", 1)[1] else [base, base + ":4859"]
    for root in roots:
        try:
            _, body = _get(root + "/api/manager/devices/device",
                           {"Authorization": "Bearer " + answers.get("key", "").strip()})
            return True, f"Homey at {root} answered: {len(json.loads(body))} devices."
        except urllib.error.HTTPError as e:
            return False, f"Homey at {root} refused the key (HTTP {e.code})."
        except (urllib.error.URLError, OSError, ValueError):
            continue
    return False, f"Nothing answered at {address}."


CHECKS = {"home_assistant": check_home_assistant, "homey": check_homey}


def _why(e):
    reason = getattr(e, "reason", None) or e
    return str(reason).strip("<>") or e.__class__.__name__


# ---- this machine ---------------------------------------------------------------

def run(cmd, timeout=10):
    """[cmd]'s exit code and output. Its input is nothing, never the
    terminal: Flutter, for one, puts a terminal it is given back into the
    mode it found it in, under the installer's feet."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           stdin=subprocess.DEVNULL)
        return r.returncode, r.stdout
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""


def microphones(status_text=None):
    """[(id, name, default)] for the microphones PipeWire knows, from
    `wpctl status`: its Audio section's Sources."""
    if status_text is None:
        _, status_text = run(["wpctl", "status"])
    mics, section, in_audio = [], None, False
    for line in status_text.splitlines():
        stripped = line.strip(" │├└─")
        if line.startswith("Audio"):
            in_audio = True
            continue
        if line and not line[0].isspace() and line[0] not in "│├└":
            in_audio = line.startswith("Audio")
        if not in_audio:
            continue
        heading = re.match(r"^(Devices|Sinks|Sources|Filters|Streams):", stripped)
        if heading:
            section = heading.group(1)
            continue
        if section != "Sources":
            continue
        m = re.match(r"^(\*?)\s*(\d+)\.\s+(.+?)(?:\s+\[vol:.*\])?$", stripped)
        if m:
            mics.append((m.group(2), m.group(3).strip(), m.group(1) == "*"))
    return mics


def kiosk_running():
    return run(["systemctl", "--user", "is-active", "--quiet", "homecanvas.service"])[0] == 0


def installed():
    arch = {"aarch64": "arm64", "arm64": "arm64", "x86_64": "x64"}.get(os.uname().machine, "")
    binary = os.path.join(APP_DIR, "build", "linux", arch, "release", "bundle", "homecanvas")
    unit = os.path.expanduser("~/.config/systemd/user/homecanvas.service")
    return os.access(binary, os.X_OK) and os.path.exists(unit)


def voice_ready():
    return run(["bash", os.path.join(APP_DIR, "scripts", "setup-voice.sh"), "--check"])[0] == 0


def apt_family():
    return shutil.which("apt-get") is not None


def say_to_kiosk(text):
    """What the kiosk made of [text], typed to it as if heard; None when it
    isn't answering."""
    url = "http://127.0.0.1:8766/voice?say=" + urllib.parse.quote(text)
    try:
        with urllib.request.urlopen(urllib.request.Request(url, method="POST"), timeout=10) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read())
        except ValueError:
            return {"error": f"HTTP {e.code}"}
    except (urllib.error.URLError, OSError, ValueError):
        return None

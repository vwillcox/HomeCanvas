#!/usr/bin/env python3
"""HomeCanvas's installer, in the terminal: it asks, then it does.

    bash install.sh            (which starts this on a terminal)
    bash install.sh --voice    straight to voice control and the wake word

It asks everything first — your Immich, the widgets you want and how the
dashboard should look, voice control and its wake word, the extras the
widgets need — shows what it will do, and then does it all in one go:
install.sh builds and installs the app, the extras' scripts set up what they
need, and the wake word is learned from you saying it. Nothing is changed
until you've seen the list and said go.

plan.py decides; tui.py draws; this asks the questions in order.
"""

import json
import os
import re
import select
import shutil
import socket
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import plan  # noqa: E402
import tui  # noqa: E402
import wake_word as ww  # noqa: E402
from tui import ACCENT, BAD, BLUE, BACK, DIM, OK, PEACH, WARN  # noqa: E402

LOG = os.path.expanduser("~/homecanvas-setup.log")
KIOSK_LOG = "/tmp/kiosk.log"
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
NEXT = object()

# The steps each way through, as the rail shows them.
FLOWS = {
    "full": ["Welcome", "Photos", "Name", "Dashboard", "Widgets", "Theme",
             "Voice", "Extras", "Review", "Install", "Wake word", "Done"],
    "change": ["Welcome", "Dashboard", "Widgets", "Theme", "Voice", "Extras",
               "Review", "Install", "Wake word", "Done"],
    "voice": ["Welcome", "Voice", "Review", "Install", "Wake word", "Done"],
    "update": ["Welcome", "Install", "Done"],
}


class Setup:
    def __init__(self, ui, args):
        self.ui = ui
        self.args = args
        self.cat = plan.Catalogue()
        self.config = plan.read_config()
        self.installed = plan.installed()
        self.mode = "voice" if "--voice" in args else ("full" if not self.installed else None)
        self.immich = None            # (url, key) to save, or None to leave
        self.hostname = None
        self.dashboard_how = "replace"
        self.preset = "starter"
        self.widgets = set()
        self.theme = (self.config.get("dashboard") or {}).get("themeId") or "lcars"
        self.open_on_start = True
        self.voice = bool((self.config.get("screen") or {}).get("voiceControl"))
        self.wake = ww.WakeWord.from_json((self.config.get("screen") or {}).get("wakeWord"))
        self.modules = []             # ids ticked
        self.answers = {}             # module id -> {key: value}
        self.results = []             # (what, ok, note) from the install
        self.trained = None           # the wake word as learned, once saved
        self.going_back = False
        self._sudo_keepalive = None

    # ---- the order of things -----------------------------------------------------

    def main(self):
        self.ui.stages = FLOWS[self.mode or "full"]
        i = 0
        while True:
            stages = FLOWS[self.mode or "full"]
            self.ui.stages = stages
            i = max(0, min(i, len(stages) - 1))
            self.ui.stage = i
            name = stages[i]
            result = getattr(self, "stage_" + name.lower().replace(" ", "_"))()
            if result is BACK:
                self.going_back = True
                i -= 1
            else:
                self.going_back = False
                if name == "Done":
                    return 0
                i += 1

    # ---- Welcome ----------------------------------------------------------------

    def machine(self):
        pretty = "Linux"
        try:
            with open("/etc/os-release") as f:
                for line in f:
                    if line.startswith("PRETTY_NAME="):
                        pretty = line.split("=", 1)[1].strip().strip('"')
        except OSError:
            pass
        return pretty, os.uname().machine, socket.gethostname()

    def stage_welcome(self):
        self.ui.wait("Welcome", "Looking at this machine…")
        pretty, arch, host = self.machine()
        _, check = plan.run(["bash", os.path.join(plan.APP_DIR, "install.sh"), "--check"], timeout=30)
        missing = [ANSI.sub("", l).split("✗", 1)[1].strip()
                   for l in check.splitlines() if "✗" in l]
        lines = [
            ("Photos from Immich and a dashboard for your wall — set up from here, "
             "in one go. It asks everything first, shows you the list, and only "
             "then changes anything.", 0),
            ("", 0),
            (f"This machine   {pretty}, {arch}, called {host}", BLUE),
            (f"HomeCanvas     {plan.APP_DIR}", BLUE),
            ("Installed      " + ("yes" if self.installed else "not yet"), BLUE),
            ("Voice control  " + ("ready" if plan.voice_ready() else "not set up"), BLUE),
            ("", 0),
        ]
        if missing:
            lines.append((f"Still to install: {', '.join(missing)} — the installer does that.", WARN))
        else:
            lines.append(("Everything needed to build HomeCanvas is here.", OK))
        if self.mode == "voice":
            pick = self.ui.message("Welcome", lines + [("", 0), (
                "You asked for voice control: it goes straight there.", ACCENT)],
                ("Continue", "Quit"))
            return NEXT if pick == 0 else self._quit()
        if not self.installed:
            pick = self.ui.message("Welcome", lines, ("Start", "Quit"))
            return NEXT if pick == 0 else self._quit()
        pick = self.ui.choose(
            "Welcome back",
            "HomeCanvas is already installed here. What would you like to do?",
            [
                ("Update to the latest version", "Fetches the new version, rebuilds it and restarts the panel. Your settings stay as they are."),
                ("Change widgets, theme and extras", "Pick widgets for the dashboard, a theme, voice control and the software and keys they need. No rebuild."),
                ("Voice control and the wake word", "Set up voice control, or choose and teach it a new wake word."),
                ("Set everything up again", "Every question, from the start. Your settings are kept unless you change them."),
                ("Quit", ""),
            ],
        )
        if pick is BACK or pick == 4:
            return self._quit()
        self.mode = ["update", "change", "voice", "full"][pick]
        return NEXT

    def _quit(self):
        raise SystemExit(0)

    # ---- Photos -----------------------------------------------------------------

    def stage_photos(self):
        current = self.config.get("immichUrl", "")
        if current and "example.com" not in current:
            pick = self.ui.choose(
                "Your photos",
                f"HomeCanvas is connected to the Immich server at {current}.",
                [("Keep it", ""), ("Connect to a different server", ""), ],
            )
            if pick is BACK:
                return BACK
            if pick == 0:
                self.immich = None
                return NEXT
        while True:
            url = self.ui.text(
                "Your photos",
                "HomeCanvas shows the photos on your Immich server. Type its address. "
                "Leave it empty to skip: you can connect from the panel's own Settings later.",
                "Immich address", example="https://photos.example.com or 192.168.1.20:2283")
            if url is BACK:
                return BACK
            if not url:
                self.immich = None
                return NEXT
            self.ui.wait("Your photos", f"Looking for Immich at {url}…")
            ok, msg, url = plan.check_immich(url)
            if not ok:
                if self.ui.message("Your photos", [(msg, BAD)], ("Try again", "Skip")) == 1:
                    return NEXT
                continue
            while True:
                key = self.ui.text(
                    "Your photos",
                    f"{msg}\n\nNow an API key from Immich: Account Settings → API Keys → "
                    "New API Key. It won't show as you type or paste.",
                    "API key", secret=True)
                if key is BACK:
                    break
                self.ui.wait("Your photos", "Checking the key…")
                ok, msg2, url = plan.check_immich(url, key)
                if ok:
                    self.immich = (url, key)
                    self.ui.message("Your photos", [(msg2, OK)])
                    return NEXT
                if self.ui.message("Your photos", [(msg2, BAD)], ("Try again", "Skip")) == 1:
                    return NEXT

    # ---- Name -------------------------------------------------------------------

    def stage_name(self):
        current = socket.gethostname()
        default = current if current not in ("raspberrypi", "localhost", "debian", "ubuntu") else "homecanvas"

        def check(name):
            if not name:
                return [("bad", "It needs a name.")]
            if not re.fullmatch(r"[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?", name.lower()):
                return [("bad", "Letters, digits and hyphens only, not starting or ending with a hyphen.")]
            return [("ok", f"You'll reach it as {name.lower()}.local")]

        name = self.ui.text(
            "A name on your network",
            "So you can reach the panel and its editor as <name>.local instead of by its address.",
            "Name", default=self.hostname or default, check=check)
        if name is BACK:
            return BACK
        self.hostname = name.lower()
        return NEXT

    # ---- Dashboard and widgets ----------------------------------------------------

    def stage_dashboard(self):
        old = plan.existing_widgets(self.config)
        if old:
            pages = len({w.get("page", 0) for w in old})
            pick = self.ui.choose(
                "The dashboard",
                f"There is a dashboard already: {len(old)} widgets on {pages} pages.",
                [
                    ("Keep it as it is", "Only the theme and extras are asked about."),
                    ("Add new pages to it", "The widgets you pick go on new pages after yours."),
                    ("Start again with a new one", "Yours is replaced. (The old config is kept beside the new one.)"),
                ],
                default={"keep": 0, "add": 1, "replace": 2}.get(self.dashboard_how, 0),
            )
            if pick is BACK:
                return BACK
            self.dashboard_how = ["keep", "add", "replace"][pick]
            if self.dashboard_how == "keep":
                self.widgets = set()
                return NEXT
        presets = self.cat.presets
        pick = self.ui.choose(
            "The dashboard",
            "Start from one of these, and change it on the next page. Every widget "
            "can be moved, resized and set up afterwards in the editor, from a phone or computer.",
            [(p["name"], p["about"]) for p in presets],
            default=next((i for i, p in enumerate(presets) if p["id"] == self.preset), 0),
        )
        if pick is BACK:
            return BACK
        if presets[pick]["id"] != self.preset or not self.widgets:
            self.widgets = set(presets[pick]["widgets"])
        self.preset = presets[pick]["id"]
        return NEXT

    def stage_widgets(self):
        if self.dashboard_how == "keep":
            return BACK if self.going_back else NEXT
        needs = {}
        for m in self.cat.modules:
            for t in m.get("widgets", []):
                needs.setdefault(t, []).append(m["name"].lower())
        groups = [
            (c, [(w["type"], w["name"], w["description"], w["type"] in self.widgets) for w in ws])
            for c, ws in self.cat.by_category()
        ]

        def detail(t):
            w = self.cat.widgets[t]
            # First, so a long description can't push it out of sight.
            extra = f"Needs {', '.join(needs[t])}. " if t in needs else ""
            return extra + w["description"]

        chosen = self.ui.checklist(
            "Widgets",
            "Tick what you'd like on the dashboard. They're laid out a page per group; "
            "rearrange them later in the editor.",
            groups, detail=detail)
        if chosen is BACK:
            return BACK
        self.widgets = chosen
        return NEXT

    # ---- Theme ---------------------------------------------------------------------

    def stage_theme(self):
        themes = self.cat.themes
        default = next((i for i, t in enumerate(themes) if t["id"] == self.theme), 0)
        pick = self.ui.choose(
            "Theme",
            "How the whole kiosk looks. Change it any time in the editor or in Settings.",
            [(t["name"], self.theme_note(t)) for t in themes],
            default=default, draw=self.draw_theme)
        if pick is BACK:
            return BACK
        self.theme = themes[pick]["id"]
        start = self.ui.choose(
            "When it starts",
            "What should the panel show when it starts?",
            [("The dashboard", "The widgets, in the theme you just picked."),
             ("The photo albums", "Your Immich albums; the dashboard is a tap away.")],
            default=0 if self.open_on_start else 1)
        if start is BACK:
            return self.stage_theme()
        self.open_on_start = start == 0
        return NEXT

    @staticmethod
    def theme_note(t):
        bg = blend(t["background"][0], "#000000")
        light = sum(int(bg[i:i + 2], 16) for i in (1, 3, 5)) > 384
        style = "drawn as a starship's console" if t.get("style") == "lcars" else "tiles"
        return f"{'Light' if light else 'Dark'}, {style}."

    def draw_theme(self, ui, index, top, left, width, height):
        """A small picture of the dashboard in theme [index]: its background,
        two tiles and its accent, as near as the terminal's colours go."""
        t = self.cat.themes[index]
        if width < 20 or height < 8:
            return
        bg = blend(t["background"][0], "#000000")
        surface = blend(t["surface"], bg)
        accent = blend(t["accent"], bg)
        text = blend(t["textPrimary"], bg)
        p_bg, p_tile = ui.truecolour_pair(bg, 1), ui.truecolour_pair(surface, 2)
        p_acc, p_text = ui.truecolour_pair(accent, 3), ui.truecolour_pair(text, 4)
        w, h = min(width, 44), min(height, 12)
        for y in range(h):
            ui.put(top + y, left, " " * w, p_bg)
        if t.get("style") == "lcars":
            palette = [blend(c, bg) for c in t.get("palette", [])] or [accent]
            pairs = [ui.truecolour_pair(c, 10 + i) for i, c in enumerate(palette)]
            ui.put(top + 1, left + 1, "▄" * (w - 2), 0)
            for i in range(w - 2):
                ui.put(top + 1, left + 1 + i, " ", pairs[(i // 6) % len(pairs)])
            for y in range(2, h - 1):
                ui.put(top + y, left + 1, "  ", pairs[y % len(pairs)])
            ui.put(top + 3, left + 5, "12:06", ui.colour(ACCENT) | 0)
            ui.put(top + 5, left + 5, "PARTLY CLOUDY", ui.colour(PEACH))
        else:
            half = (w - 5) // 2
            for y in range(1, h - 1):
                ui.put(top + y, left + 2, " " * half, p_tile)
                ui.put(top + y, left + 3 + half, " " * half, p_tile)
            ui.put(top + 2, left + 4, " 12:06 ", p_acc)
            ui.put(top + 4, left + 5 + half, " 12° ", p_acc)
        y = top + h + 1
        for label, pair in (("background", p_bg), ("tiles", p_tile), ("accent", p_acc), ("text", p_text)):
            ui.put(y, left, "    ", pair)
            ui.put(y, left + 5, label, ui.colour(DIM))
            y += 1

    # ---- Voice ---------------------------------------------------------------------

    def stage_voice(self):
        pick = self.ui.choose(
            "Voice control",
            "Talk to the panel: “show the stocks”, “next page”, “pause the music”, and anything "
            "else goes to Home Assistant. Heard and understood on this machine; nothing is sent "
            "anywhere. It needs a microphone, and about 300 MB for the speech engine.",
            [("Yes, set up voice control", "Then you'll choose the words that wake it."),
             ("No thanks", "You can add it later: bash install.sh --voice")],
            default=0 if (self.voice or self.mode == "voice") else 1)
        if pick is BACK:
            return BACK
        self.voice = pick == 0
        if not self.voice:
            if self.mode == "voice":
                return self._quit()
            return NEXT
        if self.choose_wake_word() is BACK:
            return self.stage_voice()
        return NEXT

    def choose_wake_word(self):
        options = [(p, why) for p, why in ww.SUGGESTIONS]
        current = self.wake.phrase
        if current not in [p for p, _ in options]:
            options.insert(0, (current, "what it answers to now"))
        options.append(("Something else…", "Type your own: two or three words, three or more syllables."))
        pick = self.ui.choose(
            "The wake word",
            "What you'll say to get the panel's attention, before a command: "
            "“hey canvas, next page”. Next, after installing, it listens to you say it a few "
            "times and learns how you say it.",
            [(f"“{p}”" if i < len(options) - 1 else p, why) for i, (p, why) in enumerate(options)],
            default=next((i for i, (p, _) in enumerate(options) if p == current), 0))
        if pick is BACK:
            return BACK
        if pick < len(options) - 1:
            phrase = options[pick][0]
        else:
            def check(text):
                found = ww.assess(text)
                if text and not found:
                    found = [("ok", "A good wake word.")]
                return found
            phrase = self.ui.text(
                "Your own wake word",
                "Pick something you'd never say to anyone else in the room: an unusual name works "
                "well, with or without a greeting in front. Avoid commands (“next”, “stop”) and "
                "names of people in the house.",
                "Wake word", default="", check=check, example="hey jarvis")
            if phrase is BACK:
                return self.choose_wake_word()
        if ww.words(phrase) != ww.words(self.wake.phrase):
            self.wake = ww.WakeWord(phrase)
        return NEXT

    # ---- Extras ---------------------------------------------------------------------

    def offered(self):
        chosen = self.widgets or {w.get("type") for w in plan.existing_widgets(self.config)}
        return self.cat.modules_for(chosen, self.voice, plan.apt_family())

    def stage_extras(self):
        offered = self.offered()
        if not offered:
            return BACK if self.going_back else NEXT
        ticked = self.ui.checklist(
            "Extras",
            "What your widgets and voice control need. Untick anything you'd rather set up later.",
            [("For your widgets", [(m["id"], m["name"], m["about"],
                                    m["id"] in self.modules or not self.modules) for m in offered])])
        if ticked is BACK:
            return BACK
        self.modules = [m["id"] for m in offered if m["id"] in ticked]
        for m in offered:
            if m["id"] not in ticked or not m.get("questions"):
                continue
            if self.ask_module(m) is BACK:
                return self.stage_extras()
        return NEXT

    def ask_module(self, m):
        answers = dict(self.answers.get(m["id"], {}))
        for i, q in enumerate(m["questions"]):
            value = self.ui.text(
                m["name"], m["about"] if i == 0 else "", q["label"],
                default=answers.get(q["key"], q.get("default", "")),
                secret=q.get("secret", False), example=q.get("example", ""))
            if value is BACK:
                return BACK
            answers[q["key"]] = value
        if not all(answers.get(q["key"]) for q in m["questions"]):
            self.modules.remove(m["id"])
            return NEXT
        if m.get("check"):
            self.ui.wait(m["name"], "Checking… (an address that doesn't answer takes a few seconds)")
            ok, msg = plan.CHECKS[m["check"]](answers)
            if not ok:
                pick = self.ui.message(m["name"], [(msg, BAD)],
                                       ("Try again", "Save it anyway", "Skip this"))
                if pick == 0:
                    return self.ask_module(m)
                if pick == 2 or pick is BACK:
                    self.modules.remove(m["id"])
                    return NEXT
            else:
                self.ui.message(m["name"], [(msg, OK)])
        self.answers[m["id"]] = answers
        return NEXT

    # ---- Review ---------------------------------------------------------------------

    def plan_lines(self):
        lines = []
        if self.mode in ("full",):
            lines.append(("Install everything HomeCanvas needs to build, and Flutter if it isn't here", 0))
            lines.append(("Build HomeCanvas (a few minutes on a Pi) and start it with the desktop", 0))
            lines.append((f"Call this machine {self.hostname}.local, set up the touchscreen, "
                          "and put the editor on a simple address", 0))
        if self.immich:
            lines.append((f"Connect to Immich at {self.immich[0]}", 0))
        if self.mode in ("full", "change"):
            if self.dashboard_how == "keep" or not self.widgets:
                lines.append(("Keep the dashboard's widgets as they are", 0))
            else:
                pages, _ = plan.layout(self.cat, self.widgets)
                verb = "Add" if self.dashboard_how == "add" else "Lay out"
                lines.append((f"{verb} {len(self.widgets)} widgets on {len(pages)} pages", 0))
            lines.append((f"Use the {self.cat.theme(self.theme)['name']} theme; start on the "
                          f"{'dashboard' if self.open_on_start else 'photo albums'}", 0))
        for m in self.cat.modules:
            if m["id"] in self.modules:
                lines.append((m["action"].format(**self.answers.get(m["id"], {})), 0))
        if self.voice:
            lines.append((f"Set up voice control, then teach it “{self.wake.phrase}”", 0))
        elif self.mode in ("full", "change"):
            lines.append(("No voice control", DIM))
        return lines

    def stage_review(self):
        lines = [("This is what will happen:", ACCENT), ("", 0)]
        lines += [("• " + text, colour) for text, colour in self.plan_lines()]
        if self.needs_sudo():
            lines += [("", 0), ("It will ask for your password once, to install software.", DIM)]
        pick = self.ui.message("Ready", lines, ("Install", "Go back"))
        if pick is BACK or pick == 1:
            return BACK
        return NEXT

    # ---- Install --------------------------------------------------------------------

    def needs_sudo(self):
        """Whether anything chosen installs system packages. A change of
        widgets, or a wake word on a machine that has the speech engine,
        needs no password."""
        if self.mode in ("full", "update") or "spotify-connect" in self.modules:
            return True
        if self.voice and not plan.voice_ready():
            missing_venv = plan.run(["python3", "-c", "import ensurepip"])[0] != 0
            return missing_venv or shutil.which("pw-record") is None
        return False

    def stage_install(self):
        if self.going_back:
            return BACK
        if self.needs_sudo():
            self.sudo()
        tasks = []
        engine_env = {
            "HC_UPDATE": "y" if self.mode == "update" else "n",
            "HC_HOSTNAME": self.hostname or socket.gethostname(),
            "HC_TOUCH": "y", "HC_POWEROFF": "y",
        }
        # The settings first, so the build's own restart of the panel starts
        # it with them. An update changes none.
        if self.mode != "update":
            tasks.append(("Settings", self.save_settings, None))
        if self.mode in ("full", "update"):
            tasks.append(("HomeCanvas itself", ["bash", os.path.join(plan.APP_DIR, "install.sh"), "--engine"], engine_env))
        for m in self.cat.modules:
            if m["id"] in self.modules and m.get("script"):
                tasks.append((m["name"], ["bash", os.path.join(plan.APP_DIR, m["script"])], None))
        if self.voice:
            tasks.append(("Voice control's speech engine",
                          ["bash", os.path.join(plan.APP_DIR, "scripts", "setup-voice.sh")], None))
        if self.mode in ("change", "voice") or self.voice:
            # Started before the speech engine was there, the panel would
            # say voice control isn't installed until it was restarted.
            tasks.append(("Restarting the panel", self.restart_kiosk, None))
        self.run_tasks(tasks)
        return NEXT

    def save_settings(self, log):
        """Writes what was chosen into the config — with the kiosk stopped,
        so it can't save its own copy over it — before anything starts it."""
        if plan.kiosk_running():
            log("Stopping the panel while its settings change")
            plan.run(["systemctl", "--user", "stop", "homecanvas.service"])
        config = plan.read_config()
        if self.immich:
            plan.apply_immich(config, *self.immich)
            log(f"Immich: {self.immich[0]}")
        if self.mode in ("full", "change"):
            how = self.dashboard_how if plan.existing_widgets(config) else "replace"
            plan.apply_dashboard(config, self.cat, self.widgets, self.theme, how, self.open_on_start)
            log(f"Dashboard: {len(self.widgets)} widgets, {self.theme} theme")
        for module_id, answers in self.answers.items():
            if module_id in self.modules:
                plan.apply_answers(config, module_id, answers)
                log(f"Saved the settings for {module_id}")
        if self.voice:
            plan.apply_voice(config, self.wake.to_json(), enabled=True)
        plan.write_config(config)
        log(f"Wrote {plan.CONFIG}")
        return True

    def restart_kiosk(self, log):
        code, out = plan.run(["systemctl", "--user", "restart", "homecanvas.service"], timeout=30)
        log(out.strip() or ("Restarted" if code == 0 else
                            "Couldn't start it now; it starts with the desktop"))
        return True

    def sudo(self):
        """Asks for the password once, in the plain terminal, and keeps it
        fresh while things install."""
        if plan.run(["sudo", "-n", "true"])[0] != 0:
            self.ui.suspend()
            print("\n\033[1mHomeCanvas needs your password to install software.\033[0m")
            print("(It's asked for by sudo, here, once.)\n")
            ok = subprocess.run(["sudo", "-v"]).returncode == 0
            self.ui.resume()
            if not ok:
                self.ui.message("Install", [("Without your password nothing can be installed.", BAD)],
                                ("Quit",))
                raise SystemExit(1)

        def keep():
            while True:
                time.sleep(50)
                subprocess.run(["sudo", "-n", "-v"], capture_output=True, stdin=subprocess.DEVNULL)
        if self._sudo_keepalive is None:
            self._sudo_keepalive = threading.Thread(target=keep, daemon=True)
            self._sudo_keepalive.start()

    def run_tasks(self, tasks):
        """Runs [tasks] — (what, argv or function, env) — one after another,
        showing each as it goes, with the log's last lines under them."""
        state = ["waiting"] * len(tasks)
        lines = []
        sub = {}

        def log(line):
            line = ANSI.sub("", line.rstrip("\n"))
            if not line.strip():
                return
            lines.append(line)
            with open(LOG, "a") as f:
                f.write(line + "\n")
            m = re.match(r"^\s*\[(\d+)/(\d+)\]\s+(.*)", line)
            if m:
                sub["step"] = (int(m.group(1)), int(m.group(2)), m.group(3))

        def draw(current):
            area = self.ui.frame("Installing", "please wait · the full log is in " + LOG)
            if area is None:
                return
            top, left, width, height = area
            y = top
            marks = {"waiting": ("·", DIM), "running": ("▶", ACCENT), "ok": ("✓", OK),
                     "failed": ("✗", BAD), "skipped": ("–", WARN)}
            for (what, _, _), st in zip(tasks, state):
                mark, colour = marks[st]
                self.ui.put(y, left, f"{mark} {what}", self.ui.colour(colour))
                y += 1
            if current is not None and "step" in sub:
                n, total, title = sub["step"]
                bar_w = max(10, width - 20)
                filled = int(bar_w * (n - 1) / max(1, total))
                self.ui.put(y + 1, left, f"{n}/{total} {title}", self.ui.colour(PEACH))
                self.ui.put(y + 2, left, "█" * filled + "░" * (bar_w - filled), self.ui.colour(BLUE))
                y += 3
            y += 1
            room = top + height - y
            for line in lines[-room:] if room > 0 else []:
                self.ui.put(y, left, line, self.ui.colour(DIM), width)
                y += 1
            self.ui.scr.refresh()

        with open(LOG, "a") as f:
            f.write(f"\n=== HomeCanvas setup, {time.ctime()}\n")
        for i, (what, action, env) in enumerate(tasks):
            while True:
                state[i] = "running"
                sub.pop("step", None)
                draw(i)
                log(f"--- {what}")
                if callable(action):
                    try:
                        ok = action(log)
                    except Exception as e:  # noqa: BLE001 - shown, and the log has it
                        log(f"Failed: {e}")
                        ok = False
                else:
                    ok = self.stream(action, env, log, lambda: draw(i))
                if ok:
                    state[i] = "ok"
                    self.results.append((what, True, ""))
                    break
                state[i] = "failed"
                draw(i)
                pick = self.ui.message(
                    "Something went wrong",
                    [(f"{what} didn't finish.", BAD), ("", 0)]
                    + [(l, DIM) for l in lines[-8:]]
                    + [("", 0), (f"The full log is in {LOG}.", 0)],
                    ("Try again", "Skip it", "Quit"))
                if pick == 0:
                    continue
                if pick == 2:
                    raise SystemExit(1)
                state[i] = "skipped"
                self.results.append((what, False, "skipped"))
                break
        draw(None)

    def stream(self, argv, env, log, redraw):
        """Runs [argv], its output to [log], redrawing as it comes."""
        full_env = dict(os.environ, **(env or {}))
        try:
            p = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 stdin=subprocess.DEVNULL, env=full_env, cwd=plan.APP_DIR)
        except OSError as e:
            log(f"Couldn't run {argv[0]}: {e}")
            return False
        buf = b""
        last = 0.0
        while True:
            ready, _, _ = select.select([p.stdout], [], [], 0.2)
            if ready:
                chunk = os.read(p.stdout.fileno(), 4096)
                if not chunk:
                    break
                buf += chunk
                # install.sh's "Building… done" arrives as two halves of a line.
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    log(line.decode(errors="replace"))
            if time.time() - last > 0.25:
                redraw()
                last = time.time()
            self.ui.key(timeout=0)
        if buf:
            log(buf.decode(errors="replace"))
        return p.wait() == 0

    # ---- Wake word --------------------------------------------------------------------

    def stage_wake_word(self):
        if not self.voice or self.going_back:
            return BACK if self.going_back else NEXT
        if not plan.voice_ready():
            self.ui.message("The wake word", [(
                "The speech engine isn't set up, so there's nothing to listen with. "
                "Run this again once it is: bash install.sh --voice", WARN)])
            return NEXT
        if self.pick_microphone() is BACK:
            return NEXT
        while True:
            result = self.train()
            if result == "again":
                continue
            if result == "other":
                if self.choose_wake_word() is BACK:
                    continue
                continue
            break
        return NEXT

    def pick_microphone(self):
        mics = plan.microphones()
        if not mics:
            self.ui.message("Microphone", [(
                "PipeWire doesn't list a microphone. Plug one in (USB microphone, speakerphone or "
                "webcam), then choose Look again.", WARN)], ("Look again",))
            return self.pick_microphone() if plan.microphones() else BACK
        if len(mics) > 1:
            default = next((i for i, m in enumerate(mics) if m[2]), 0)
            pick = self.ui.choose(
                "Microphone",
                "Which microphone should the panel listen with? It becomes this machine's default.",
                [(name, "the default now" if is_default else "") for _, name, is_default in mics],
                default=default)
            if pick is BACK:
                return BACK
            if not mics[pick][2]:
                plan.run(["wpctl", "set-default", mics[pick][0]])
        return NEXT

    def trainer(self):
        argv = [plan.VOICE_PYTHON, os.path.join(plan.APP_DIR, "deploy", "wake_trainer.py")]
        # For trying the wizard out without a room: a recording of the mic
        # check, the phrase five times and the two sentences, in that order.
        if os.environ.get("HOMECANVAS_WAKE_FROM"):
            argv += ["--from", os.environ["HOMECANVAS_WAKE_FROM"]]
        return subprocess.Popen(
            argv,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, text=True)

    def events(self, proc, until, seconds, draw):
        """Reads the trainer's events, calling [draw](event) on each, until
        [until](event) is true or [seconds] pass. Gives back the event that
        ended it, "timeout", or BACK if Esc was pressed."""
        end = time.time() + seconds
        while time.time() < end:
            ready, _, _ = select.select([proc.stdout], [], [], 0.05)
            if ready:
                line = proc.stdout.readline()
                if not line:
                    return {"event": "error", "message": "the listener stopped"}
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                draw(event)
                if event.get("event") == "error" or until(event):
                    return event
            k = self.ui.key(timeout=0)
            if k == "\x1b":
                return BACK
            if k == "\x03":
                raise SystemExit(1)
        return "timeout"

    def meter(self, y, left, width, event):
        level, speech = event.get("level", 0), event.get("speech", 1) or 1
        scale = max(speech * 3, 1)
        bar_w = width - 12
        filled = min(bar_w, int(bar_w * level / scale))
        mark = min(bar_w - 1, int(bar_w * speech / scale))
        talking = level >= speech
        bar = "█" * filled + "░" * (bar_w - filled)
        self.ui.put(y, left, "mic ", self.ui.colour(DIM))
        self.ui.put(y, left + 4, bar, self.ui.colour(OK if talking else BLUE))
        self.ui.put(y, left + 4 + mark, "│", self.ui.colour(WARN))
        self.ui.put(y + 1, left + 4, " " * bar_w, 0)
        self.ui.put(y + 1, left + 4 + max(0, mark - 8), "speech ↑", self.ui.colour(DIM))

    def train(self):
        phrase = self.wake.phrase
        base = ww.WakeWord(phrase) if phrase != ww.DEFAULT_PHRASE else ww.WakeWord()
        self.ui.wait("Teaching it", "Loading the speech engine…")
        proc = self.trainer()
        try:
            return self._train(proc, phrase, base)
        finally:
            proc.terminate()

    def _train(self, proc, phrase, base):
        state = {"level": {}, "takes": [], "prompt": "", "note": ""}

        def draw(event=None):
            if event and event.get("event") == "level":
                state["level"] = event
            area = self.ui.frame("Teaching it “" + phrase + "”", "Esc stop")
            if area is None:
                return
            top, left, width, height = area
            y = self.ui.paragraph(top, left, width, state["prompt"], self.ui.colour(ACCENT) | 0)
            if state["note"]:
                y = self.ui.paragraph(y + 1, left, width, state["note"], self.ui.colour(DIM))
            self.meter(y + 1, left, width, state["level"] or {"level": 0, "speech": 1})
            y += 4
            for n, (texts, woke) in enumerate(state["takes"], 1):
                mark, colour = ("✓", OK) if woke else ("·", WARN)
                heard = " / ".join(dict.fromkeys(t for t in texts if t)) or "(nothing)"
                self.ui.put(y, left, f"{mark} {n}. heard: {heard}", self.ui.colour(colour), width)
                y += 1
            self.ui.scr.refresh()

        ready = self.events(proc, lambda e: e.get("event") == "ready", 60, lambda e: None)
        if ready is BACK:
            return "done"
        if not isinstance(ready, dict) or ready.get("event") != "ready":
            msg = ready.get("message") if isinstance(ready, dict) else "it didn't start"
            self.ui.message("Teaching it", [(f"The speech engine couldn't listen: {msg}", BAD)])
            return "done"

        # 1. That the microphone hears them.
        state["prompt"] = "First, say anything — “testing, one, two, three” — to check the microphone hears you."
        state["note"] = "The bar goes green when it hears speech."
        heard = self.events(proc, lambda e: e.get("event") == "said", 25, draw)
        if heard is BACK:
            return "done"
        if heard == "timeout":
            pick = self.ui.message("Microphone", [(
                "It didn't hear anything. Is the microphone plugged in, switched on and not muted? "
                "(alsamixer or the desktop's sound settings can tell.)", WARN)],
                ("Try again", "Skip the wake word"))
            return "again" if pick == 0 else "done"

        # 2. The phrase, five times.
        takes = 5
        for n in range(1, takes + 1):
            state["prompt"] = f"Say “{phrase}” — just that — in your normal voice. ({n} of {takes})"
            state["note"] = "From where you'd usually stand. Wait for it to appear below before the next one."
            said = self.events(proc, lambda e: e.get("event") == "said", 20, draw)
            if said is BACK:
                return "done"
            if said == "timeout":
                state["takes"].append(([], False))
                continue
            texts = said.get("texts", [])
            state["takes"].append((texts, any(base.ends(t) for t in texts)))
        draw()
        all_heard = [t for texts, _ in state["takes"] for t in texts if t]
        before = sum(1 for _, woke in state["takes"] if woke)
        learned = ww.learn(base, all_heard)
        after = sum(1 for texts, _ in state["takes"] if any(learned.ends(t) for t in texts))

        # 3. Everyday speech, which must not wake it.
        false_alarms = []
        for sentence in ww.EVERYDAY:
            state["prompt"] = "Now read this aloud — it shouldn't wake the panel:"
            state["note"] = f"“{sentence}”"
            said = self.events(proc, lambda e: e.get("event") == "said", 25, draw)
            if said is BACK:
                return "done"
            if said != "timeout":
                false_alarms.extend(said.get("texts", []))
        learned, unforgiven = ww.forgive(learned, false_alarms)
        after = sum(1 for texts, _ in state["takes"] if any(learned.ends(t) for t in texts))

        # 4. How it went.
        new_words = [w for w in learned.lookalikes if w not in base.lookalikes]
        new_phrases = [" ".join(v) for v in learned.variants if v not in base.variants]
        lines = [(f"Heard “{phrase}” {before} of {takes} times as it was.", 0)]
        if new_words or new_phrases:
            lines.append((f"Learned how you say it: {', '.join(new_words + new_phrases)}", BLUE))
            lines.append((f"With that it hears it {after} of {takes} times.", 0))
        if unforgiven:
            lines.append(("", 0))
            lines.append(("It woke on an everyday sentence, so it may wake by itself now and then.", WARN))
        lines.append(("", 0))
        if after >= 4 and not unforgiven:
            lines.append(("That's a good wake word.", OK))
            buttons = ("Save it", "Try again", "Choose another")
        elif after >= 2:
            lines.append(("It works, but not every time. Saying it a little more deliberately helps; "
                          "so does trying again from where you'll usually be.", WARN))
            buttons = ("Save it", "Try again", "Choose another")
        else:
            lines.append(("It hardly heard it. A longer or more unusual phrase will do better.", BAD))
            buttons = ("Choose another", "Try again", "Save it anyway")
        pick = self.ui.message("How it went", lines, buttons)
        choice = buttons[pick] if pick is not BACK else "Try again"
        if choice.startswith("Try"):
            return "again"
        if choice.startswith("Choose"):
            return "other"
        proc.terminate()
        self.save_wake(learned)
        self.live_test(learned)
        return "done"

    def save_wake(self, wake):
        running = plan.kiosk_running()
        if running:
            plan.run(["systemctl", "--user", "stop", "homecanvas.service"])
        config = plan.read_config()
        plan.apply_voice(config, wake.to_json(), enabled=True)
        plan.write_config(config)
        self.trained = wake
        if running or self.mode != "voice":
            plan.run(["systemctl", "--user", "start", "homecanvas.service"])

    def live_test(self, wake):
        if not plan.kiosk_running():
            self.ui.message("Try it", [(
                f"Saved. Once the panel is running, say “{wake.phrase}, next page”.", OK)])
            return
        self.ui.wait("Try it", "Waiting for the panel to start listening…", seconds=8)
        start = os.path.getsize(KIOSK_LOG) if os.path.exists(KIOSK_LOG) else 0
        prompt = f"Now for real: say “{wake.phrase}, next page” and watch the panel."
        end = time.time() + 30
        heard = None
        while time.time() < end and heard is None:
            area = self.ui.frame("Try it", "Esc skip")
            if area:
                top, left, width, _ = area
                y = self.ui.paragraph(top, left, width, prompt, self.ui.colour(ACCENT))
                self.ui.paragraph(y + 1, left, width,
                                  f"Listening for {int(end - time.time())} more seconds…", self.ui.colour(DIM))
                self.ui.scr.refresh()
            try:
                with open(KIOSK_LOG, errors="replace") as f:
                    f.seek(start)
                    for line in f:
                        if "Voice: heard" in line:
                            heard = line.split("Voice: ", 1)[1].strip()
            except OSError:
                pass
            if self.ui.key(timeout=0.5) == "\x1b":
                break
        if heard:
            ok = "not understood" not in heard
            self.ui.message("Try it", [(f"The panel {heard}.", OK if ok else WARN), ("", 0), (
                "Voice control is on." if ok else
                "It heard you but didn't understand the command — VOICE.md lists what you can say.", 0)])
        else:
            self.ui.message("Try it", [(
                "The panel didn't hear it that time. It's saved and switched on — try again in a "
                "moment, a little closer to the microphone.", WARN)])

    # ---- Done ------------------------------------------------------------------------

    def stage_done(self):
        name = self.hostname or socket.gethostname()
        lines = []
        failed = [w for w, ok, _ in self.results if not ok]
        if failed:
            lines.append((f"Done, except: {', '.join(failed)}. Run this again to retry.", WARN))
        else:
            lines.append(("HomeCanvas is set up.", OK))
        lines.append(("", 0))
        lines.append((f"Arrange the dashboard   http://{name}.local  (from a phone or computer at home)", 0))
        if self.trained:
            lines.append((f"Talk to it              “{self.trained.phrase}, show the weather”", 0))
        lines.append(("Change any of this      bash ~/homecanvas/install.sh", 0))
        lines.append(("", 0))
        todo = []
        if "spotify" in self.widgets:
            todo.append("Spotify: Settings → Music → Spotify on the panel, to sign in")
        if self.widgets & {"youtube", "floatplane", "nebula"}:
            todo.append("Videos: sign in from Settings → Music → Videos, or skip it")
        if self.widgets & {"calendar", "news", "stocks", "trains", "fuel"}:
            todo.append("Calendars, feeds, stocks and stations are set in each widget, in the editor")
        if todo:
            lines.append(("Still to do on the panel:", ACCENT))
            lines += [("• " + t, 0) for t in todo]
        self.ui.message("Done", lines, ("Finish",))
        return NEXT


def blend(colour, under):
    """[colour] (#AARRGGBB or #RRGGBB) over [under] (#RRGGBB), as #RRGGBB."""
    c = colour.lstrip("#")
    alpha = int(c[:2], 16) / 255 if len(c) == 8 else 1.0
    rgb = c[-6:]
    u = under.lstrip("#")[-6:]
    mixed = [round(int(rgb[i:i + 2], 16) * alpha + int(u[i:i + 2], 16) * (1 - alpha)) for i in (0, 2, 4)]
    return "#" + "".join(f"{v:02x}" for v in mixed)


def main(argv):
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print("The installer needs a terminal. For an unattended install: bash install.sh --yes")
        return 2
    cols, rows = shutil.get_terminal_size()
    if cols < tui.MIN_W or rows < tui.MIN_H:
        print(f"Make the terminal at least {tui.MIN_W}×{tui.MIN_H} (it is {cols}×{rows}), "
              "or use bash install.sh --classic")
        return 2
    try:
        return tui.run(lambda ui: Setup(ui, argv).main())
    except SystemExit as e:
        return e.code or 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

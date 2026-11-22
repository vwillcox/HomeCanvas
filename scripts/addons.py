#!/usr/bin/env python3
"""Fetches widget add-ons from the catalogue, for the panel to build in.

    addons.py list                     what the catalogue has
    addons.py fetch --dest DIR ID…     download these, checked, into DIR
    addons.py ensure                   install what this panel's dashboard needs

The catalogue is a repository of its own — vwillcox/HomeCanvas-Widgets —
whose `catalogue` branch carries an index.json written by its own checks:
every add-on that passed them, the commit it was read at, and the SHA-256 of
each of its files. Nothing is taken that does not match its sum.

Which repository is read can be changed on the panel only: the environment's
HOMECANVAS_ADDONS_REPO, or "addonsRepo" under "dashboard" in config.json.
Either is `owner/name` on GitHub, or a folder — a checkout of the catalogue.

`ensure` is run before a build by install.sh and sync.sh. A panel whose
dashboard was laid out when its widgets were built in keeps them: whatever
its dashboard uses and does not have is fetched. A panel with no dashboard
yet is given the starter set.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import urllib.error
import urllib.request

DEFAULT_REPO = "vwillcox/HomeCanvas-Widgets"
BRANCH = "catalogue"
RAW = "https://raw.githubusercontent.com"
AGENT = "HomeCanvas-addons"

HOME = os.path.expanduser("~")
CONFIG = os.path.join(HOME, ".config", "homecanvas", "config.json")
ADDONS = os.environ.get("HOMECANVAS_ADDONS") or os.path.join(
    HOME, ".config", "homecanvas", "addons"
)

ID = re.compile(r"^[a-z][a-z0-9_]{1,39}$")
REPO = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9_][A-Za-z0-9_.-]*$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")
# A file of an add-on: Dart beside its addon.json, or the one JSON widget.
PART = re.compile(r"^[a-z][a-z0-9_]*\.(dart|json)$")
MAX_FILE = 512 * 1024
MAX_INDEX = 4 * 1024 * 1024

# The widgets the app still has in it: nothing need be fetched for these.
CORE_TYPES = {"calendar", "parcels"}


class Refused(Exception):
    """Why something was not taken, in words for whoever asked."""


def config():
    try:
        with open(CONFIG) as f:
            j = json.load(f)
        return j if isinstance(j, dict) else {}
    except (OSError, ValueError):
        return {}


def source(arg=None):
    dash = config().get("dashboard")
    named = dash.get("addonsRepo") if isinstance(dash, dict) else None
    repo = arg or os.environ.get("HOMECANVAS_ADDONS_REPO") or named or DEFAULT_REPO
    if os.path.isdir(repo):
        return os.path.abspath(repo)
    if not REPO.match(repo):
        raise Refused(f"{repo} is neither a folder nor owner/name on GitHub.")
    return repo


def get(url, most):
    request = urllib.request.Request(url, headers={"User-Agent": AGENT})
    try:
        with urllib.request.urlopen(request, timeout=30) as r:
            data = r.read(most + 1)
    except urllib.error.HTTPError as e:
        raise Refused(f"The catalogue answered {e.code} for {url}.")
    except (urllib.error.URLError, OSError) as e:
        raise Refused(f"The catalogue could not be reached: {e}.")
    if len(data) > most:
        raise Refused(f"{url} is too big.")
    return data


def files_of(folder):
    """An add-on's own files in a checkout: not its tests or its picture."""
    out = []
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if name == "addon.json" or not os.path.isfile(path):
            continue
        if not PART.match(name):
            continue
        with open(path, "rb") as f:
            data = f.read()
        out.append(
            {"path": name, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
        )
    return out


def index(src):
    """The catalogue: {"commit": …, "addons": [{"id": …, "files": […]}, …]}."""
    if os.path.isdir(src):
        written = os.path.join(src, "index.json")
        if os.path.isfile(written):
            with open(written) as f:
                return check_index(json.load(f))
        # A checkout as it is being worked on: read as it stands.
        addons = []
        root = os.path.join(src, "widgets")
        for id in sorted(os.listdir(root)) if os.path.isdir(root) else []:
            try:
                with open(os.path.join(root, id, "addon.json")) as f:
                    m = json.load(f)
            except (OSError, ValueError):
                continue
            addons.append({**m, "id": id, "files": files_of(os.path.join(root, id))})
        return check_index({"commit": None, "addons": addons})
    try:
        j = json.loads(get(f"{RAW}/{src}/{BRANCH}/index.json", MAX_INDEX))
    except ValueError:
        raise Refused("The catalogue's index is not JSON.")
    return check_index(j)


def check_index(j):
    if not isinstance(j, dict) or not isinstance(j.get("addons"), list):
        raise Refused("The catalogue's index is not one this panel can read.")
    commit = j.get("commit")
    if commit is not None and not (isinstance(commit, str) and COMMIT.match(commit)):
        raise Refused("The catalogue's index names no commit.")
    good = []
    for a in j["addons"]:
        if not isinstance(a, dict) or not ID.match(str(a.get("id", ""))):
            continue
        if a.get("kind") not in ("dart", "json"):
            continue
        files = a.get("files")
        if not isinstance(files, list) or not files:
            continue
        if not all(
            isinstance(f, dict)
            and PART.match(str(f.get("path", "")))
            and re.fullmatch(r"[0-9a-f]{64}", str(f.get("sha256", "")))
            for f in files
        ):
            continue
        if not isinstance(a.get("types"), list):
            continue
        good.append(a)
    return {"commit": commit, "addons": good}


def fetch(src, cat, ids, dest):
    """Downloads [ids] into dest/<id>/, each file checked against its sum."""
    by_id = {a["id"]: a for a in cat["addons"]}
    for id in ids:
        if id not in by_id:
            raise Refused(f"The catalogue has no add-on called {id}.")
    os.makedirs(dest, exist_ok=True)
    for id in ids:
        a = by_id[id]
        part = os.path.join(dest, f".{id}.part")
        shutil.rmtree(part, ignore_errors=True)
        os.makedirs(part)
        for f in a["files"]:
            if os.path.isdir(src):
                with open(os.path.join(src, "widgets", id, f["path"]), "rb") as fh:
                    data = fh.read()
            else:
                data = get(
                    f"{RAW}/{src}/{cat['commit']}/widgets/{id}/{f['path']}", MAX_FILE
                )
            if hashlib.sha256(data).hexdigest() != f["sha256"]:
                shutil.rmtree(part, ignore_errors=True)
                raise Refused(
                    f"{id}/{f['path']} is not the file the catalogue checked. "
                    "Nothing was installed."
                )
            with open(os.path.join(part, f["path"]), "wb") as out:
                out.write(data)
        manifest = {k: v for k, v in a.items() if k != "files"}
        manifest["commit"] = cat["commit"]
        manifest["files"] = [f["path"] for f in a["files"]]
        with open(os.path.join(part, "addon.json"), "w") as out:
            json.dump(manifest, out, indent=2)
            out.write("\n")
        whole = os.path.join(dest, id)
        shutil.rmtree(whole, ignore_errors=True)
        os.rename(part, whole)


def place_described(ids):
    """Puts add-ons described in JSON where the app reads such widgets from.

    One written in Dart is built in from its folder. One described in JSON
    is read by the running app, from the folder its uploads are kept in,
    under the name its own "type" gives it.
    """
    widgets = os.path.join(os.path.dirname(ADDONS), "widgets")
    for id in ids:
        folder = os.path.join(ADDONS, id)
        try:
            with open(os.path.join(folder, "addon.json")) as f:
                m = json.load(f)
            if m.get("kind") != "json":
                continue
            with open(os.path.join(folder, m["files"][0]), "rb") as f:
                data = f.read()
            type = json.loads(data).get("type", "")
        except (OSError, ValueError, KeyError, IndexError, AttributeError):
            continue
        if not ID.match(str(type)):
            continue
        os.makedirs(widgets, exist_ok=True)
        with open(os.path.join(widgets, f"{type}.json"), "wb") as out:
            out.write(data)


def installed():
    """id -> its addon.json, for what this panel has."""
    out = {}
    for id in sorted(os.listdir(ADDONS)) if os.path.isdir(ADDONS) else []:
        try:
            with open(os.path.join(ADDONS, id, "addon.json")) as f:
                m = json.load(f)
        except (OSError, ValueError):
            continue
        if isinstance(m, dict):
            out[id] = m
    return out


def wanted(cat, dashboard, have):
    """The add-ons to fetch: what [dashboard] uses and [have] does not bring."""
    widgets = dashboard.get("widgets") if isinstance(dashboard, dict) else None
    used = {
        w.get("type")
        for w in (widgets if isinstance(widgets, list) else [])
        if isinstance(w, dict)
    }
    brought = set(CORE_TYPES)
    for m in have.values():
        brought.update(m.get("types") or [])
    if not used and not have:
        return [a["id"] for a in cat["addons"] if a.get("starter") is True]
    missing = {t for t in used if isinstance(t, str)} - brought
    return [
        a["id"]
        for a in cat["addons"]
        if a["id"] not in have and missing.intersection(a["types"])
    ]


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--repo", help="owner/name on GitHub, or a checkout")
    sub = p.add_subparsers(dest="action", required=True)
    sub.add_parser("list")
    f = sub.add_parser("fetch")
    f.add_argument("--dest", required=True)
    f.add_argument("ids", nargs="+")
    sub.add_parser("ensure")
    args = p.parse_args()

    try:
        if args.action == "ensure":
            # A panel that cannot reach the catalogue is still built: with
            # what it has, and the rest offered in the editor afterwards.
            try:
                src = source(args.repo)
                cat = index(src)
                ids = wanted(cat, config().get("dashboard"), installed())
                if ids:
                    fetch(src, cat, ids, ADDONS)
                    place_described(ids)
                    print("Add-ons installed: " + ", ".join(ids))
            except Refused as e:
                print(f"Add-ons were not fetched: {e}", file=sys.stderr)
            return 0
        src = source(args.repo)
        cat = index(src)
        if args.action == "list":
            for a in cat["addons"]:
                print(f"{a['id']}\t{a.get('version', '')}\t{a.get('name', '')}")
        else:
            for id in args.ids:
                if not ID.match(id):
                    raise Refused(f"{id} is no name for an add-on.")
            fetch(src, cat, args.ids, args.dest)
    except Refused as e:
        print(e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

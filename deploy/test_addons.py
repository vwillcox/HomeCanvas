"""scripts/addons.py and the registry scripts/widget-build.sh writes.

    python3 -m unittest deploy/test_addons.py
"""

import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location(
    "addons", os.path.join(ROOT, "scripts", "addons.py")
)
addons = importlib.util.module_from_spec(spec)
spec.loader.exec_module(addons)


def checkout(root, **widgets):
    """A catalogue as a folder: {id: (manifest, {file: contents})}."""
    for id, (manifest, files) in widgets.items():
        folder = os.path.join(root, "widgets", id)
        os.makedirs(folder)
        with open(os.path.join(folder, "addon.json"), "w") as f:
            json.dump(manifest, f)
        for name, body in files.items():
            with open(os.path.join(folder, name), "w") as f:
                f.write(body)
    return root


def dart(id, types=None, **more):
    return (
        {"name": id, "kind": "dart", "entry": f"{id}.dart", "types": types or [id],
         "version": "1.0.0", **more},
        {f"{id}.dart": f"final widgetTypes = [];// {id}\n", "screenshot.png": "png",
         "notes.txt": "not a part"},
    )


class Fetching(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.repo = checkout(
            os.path.join(self.dir, "repo"),
            clock=dart("clock", starter=True),
            unifi=dart("unifi", ["unifi_health", "unifi_isp"]),
            weather=dart("weather", starter=True),
        )
        self.was = addons.ADDONS
        addons.ADDONS = os.path.join(self.dir, "home", "addons")

    def tearDown(self):
        addons.ADDONS = self.was
        shutil.rmtree(self.dir)

    def test_only_an_addons_own_files_are_listed(self):
        cat = addons.index(self.repo)
        files = {a["id"]: [f["path"] for f in a["files"]] for a in cat["addons"]}
        self.assertEqual(files["clock"], ["clock.dart"])

    def test_what_is_fetched_is_whole_and_says_where_it_came_from(self):
        cat = addons.index(self.repo)
        dest = os.path.join(self.dir, "in")
        addons.fetch(self.repo, cat, ["clock", "unifi"], dest)
        self.assertEqual(sorted(os.listdir(dest)), ["clock", "unifi"])
        self.assertEqual(sorted(os.listdir(os.path.join(dest, "clock"))), ["addon.json", "clock.dart"])
        with open(os.path.join(dest, "unifi", "addon.json")) as f:
            m = json.load(f)
        self.assertEqual(m["types"], ["unifi_health", "unifi_isp"])
        self.assertEqual(m["files"], ["unifi.dart"])

    def test_a_file_that_does_not_match_its_sum_installs_nothing(self):
        cat = addons.index(self.repo)
        with open(os.path.join(self.repo, "widgets", "clock", "clock.dart"), "a") as f:
            f.write("// and something slipped in afterwards\n")
        dest = os.path.join(self.dir, "in")
        with self.assertRaises(addons.Refused):
            addons.fetch(self.repo, cat, ["clock"], dest)
        self.assertEqual(os.listdir(dest), [])

    def test_an_index_naming_files_outside_the_addon_is_not_read(self):
        sly = {"commit": "a" * 40, "addons": [
            {"id": "sly", "kind": "dart", "types": ["sly"],
             "files": [{"path": "../../.bashrc", "sha256": "0" * 64}]},
            {"id": "../up", "kind": "dart", "types": [], "files": [{"path": "a.dart", "sha256": "0" * 64}]},
            {"id": "fine", "kind": "dart", "types": ["fine"],
             "files": [{"path": "fine.dart", "sha256": "0" * 64}]},
        ]}
        self.assertEqual([a["id"] for a in addons.check_index(sly)["addons"]], ["fine"])
        with self.assertRaises(addons.Refused):
            addons.check_index({"commit": "main", "addons": []})

    def test_a_dashboard_is_given_what_it_uses_and_no_more(self):
        cat = addons.index(self.repo)
        dash = {"widgets": [{"type": "unifi_isp"}, {"type": "calendar"}, {"type": "custom_x"}]}
        self.assertEqual(addons.wanted(cat, dash, {}), ["unifi"])
        # What it has already is not fetched again.
        have = {"unifi": {"types": ["unifi_health", "unifi_isp"]}}
        self.assertEqual(addons.wanted(cat, dash, have), [])

    def test_one_from_a_library_is_fetched_from_it(self):
        other = checkout(os.path.join(self.dir, "other"), tide=dart("tide"))
        dest = os.path.join(self.dir, "dest")
        was = addons.REPO
        # A folder stands in for owner/name here.
        addons.REPO = __import__("re").compile(r".+")
        try:
            import sys
            argv = sys.argv
            sys.argv = ["addons.py", "--repo", self.repo, "fetch", "--dest", dest,
                        "clock", f"tide@{other}"]
            self.assertEqual(addons.main(), 0)
            sys.argv = ["addons.py", "--repo", self.repo, "fetch", "--dest", dest, "tide"]
            self.assertEqual(addons.main(), 1)
        finally:
            sys.argv = argv
            addons.REPO = was
        self.assertEqual(sorted(os.listdir(dest)), ["clock", "tide"])

    def test_the_theme_in_use_is_kept(self):
        cat = {"addons": [
            {"id": "theme_lcars", "kind": "theme", "types": [], "themes": ["lcars"]},
            {"id": "clock", "types": ["clock"]},
        ]}
        have = {"clock": {"types": ["clock"]}}
        dash = {"themeId": "lcars", "widgets": [{"type": "clock"}]}
        self.assertEqual(addons.wanted(cat, dash, have), ["theme_lcars"])
        # Not Glass, which the app has; not one already in the themes
        # folder, made by hand or fetched before; not one taken off.
        self.assertEqual(addons.wanted(cat, {**dash, "themeId": "glass"}, have), [])
        self.assertEqual(addons.wanted(cat, dash, have, themes={"lcars"}), [])
        self.assertEqual(addons.wanted(cat, dash, have, gone={"theme_lcars"}), [])

    def test_a_theme_is_put_where_the_app_reads_themes(self):
        with tempfile.TemporaryDirectory() as d:
            was = (addons.ADDONS, addons.THEMES)
            addons.ADDONS, addons.THEMES = os.path.join(d, "addons"), os.path.join(d, "themes")
            try:
                folder = os.path.join(addons.ADDONS, "theme_lcars")
                os.makedirs(folder)
                with open(os.path.join(folder, "addon.json"), "w") as f:
                    json.dump({"kind": "theme", "themes": ["lcars"], "types": []}, f)
                with open(os.path.join(folder, "theme.json"), "w") as f:
                    json.dump({"id": "lcars", "name": "LCARS"}, f)
                addons.place_described(["theme_lcars"])
                self.assertEqual(addons.theme_files(), {"lcars"})
            finally:
                addons.ADDONS, addons.THEMES = was

    def test_what_was_taken_off_by_hand_is_not_fetched_back(self):
        cat = {"addons": [{"id": "history", "types": ["history"]},
                          {"id": "clock", "types": ["clock"]}]}
        dash = {"widgets": [{"type": "history"}, {"type": "clock"}]}
        self.assertEqual(addons.wanted(cat, dash, {}, gone={"history"}), ["clock"])
        # Nor the albums, taken off a panel on Immich.
        cat["addons"].append({"id": "immich_albums", "types": ["immich_albums"]})
        self.assertEqual(
            addons.wanted(cat, {"widgets": [{"type": "clock"}]}, {"clock": {"types": ["clock"]}},
                          connected=True, gone={"immich_albums"}), [])

    def test_removed_is_noted_and_forgotten(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            was = addons.REMOVED
            addons.REMOVED = os.path.join(d, "addons-removed.json")
            try:
                self.assertEqual(addons.removed(), set())
                addons.note_removed(add=["history", "clock"])
                self.assertEqual(addons.removed(), {"history", "clock"})
                addons.note_removed(drop=["clock"])
                self.assertEqual(addons.removed(), {"history"})
            finally:
                addons.REMOVED = was

    def test_a_panel_on_immich_keeps_its_albums(self):
        cat = {"addons": [{"id": "immich_albums", "types": ["immich_albums"]},
                          {"id": "clock", "types": ["clock"]}]}
        dash = {"widgets": [{"type": "clock"}]}
        have = {"clock": {"types": ["clock"]}}
        self.assertEqual(addons.wanted(cat, dash, have, connected=True), ["immich_albums"])
        # Not on Immich, or given its tile already: nothing more.
        self.assertEqual(addons.wanted(cat, dash, have, connected=False), [])
        given = {**dash, "albumsOffered": True}
        self.assertEqual(addons.wanted(cat, given, have, connected=True), [])
        # A photos-only panel: no dashboard yet, but connected.
        self.assertEqual(addons.wanted(cat, {"widgets": []}, {"clock": {"types": ["clock"]}}, connected=True), ["immich_albums"])

    def test_a_panel_with_no_dashboard_is_given_the_starter_set(self):
        cat = addons.index(self.repo)
        self.assertEqual(addons.wanted(cat, None, {}), ["clock", "weather"])
        self.assertEqual(addons.wanted(cat, {"widgets": []}, {}), ["clock", "weather"])
        # But not one that has add-ons and an empty dashboard: that is a choice.
        self.assertEqual(addons.wanted(cat, {"widgets": []}, {"clock": {"types": ["clock"]}}), [])


class Registry(unittest.TestCase):
    """widget-build.sh generate, with what is installed held in a folder."""

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        # A tree of its own: generate writes beside the script it is run
        # from, and the registry the app is built with is never touched.
        self.root = os.path.join(self.dir, "tree")
        os.makedirs(os.path.join(self.root, "scripts"))
        for name in ("widget-build.sh", "addons.py"):
            shutil.copy(os.path.join(ROOT, "scripts", name), os.path.join(self.root, "scripts"))
        self.dest = os.path.join(self.root, "lib", "dashboard", "widgets", "custom")
        self.tests = os.path.join(self.root, "test", "addons")
        self.home = os.path.join(self.dir, "home")
        os.makedirs(self.home)

    def tearDown(self):
        shutil.rmtree(self.dir)

    def generate(self, **env):
        clean = {k: v for k, v in os.environ.items() if not k.startswith("HOMECANVAS_")}
        subprocess.run(
            ["bash", os.path.join(self.root, "scripts", "widget-build.sh"), "generate"],
            check=True,
            env={**clean, "HOME": self.home,
                 "HOMECANVAS_WIDGETS": os.path.join(self.dir, "src"),
                 "HOMECANVAS_WIDGET_STATE": os.path.join(self.dir, "state"),
                 "HOMECANVAS_ADDONS": os.path.join(self.dir, "repo", "widgets"), **env},
        )
        with open(os.path.join(self.dest, "custom_registry.dart")) as f:
            return f.read()

    def test_addons_in_dart_are_registered_and_the_rest_left_out(self):
        described = ({"name": "sea", "kind": "json", "types": ["custom_sea"]}, {"sea.json": "{}"})
        nameless = ({"name": "x", "kind": "dart", "entry": "../../main.dart", "types": []}, {"x.dart": ""})
        repo = checkout(os.path.join(self.dir, "repo"), clock=dart("clock"), sea=described, sly=nameless)
        os.makedirs(os.path.join(repo, "widgets", "clock", "test"))
        with open(os.path.join(repo, "widgets", "clock", "test", "clock_test.dart"), "w") as f:
            f.write("void main() {}\n")
        os.makedirs(os.path.join(self.dir, "src"))
        with open(os.path.join(self.dir, "src", "tide.dart"), "w") as f:
            f.write("final widgetType = null;\n")

        registry = self.generate()
        self.assertIn("import 'addons/clock/clock.dart' as a0;", registry)
        self.assertIn("'clock': () => a0.widgetTypes,", registry)
        self.assertIn("import 'tide.dart' as w0;", registry)
        self.assertNotIn("sea", registry)
        self.assertNotIn("sly", registry)
        built = os.path.join(self.dest, "addons")
        self.assertEqual(os.listdir(built), ["clock"])
        self.assertEqual(sorted(os.listdir(os.path.join(built, "clock"))), ["addon.json", "clock.dart"])
        # Tests come along only when asked for.
        self.assertFalse(os.path.isdir(self.tests))
        self.generate(HOMECANVAS_ADDON_TESTS="1")
        self.assertTrue(os.path.isfile(os.path.join(self.tests, "clock", "clock_test.dart")))

    def test_with_nothing_installed_the_registry_is_empty_and_whole(self):
        os.makedirs(os.path.join(self.dir, "repo", "widgets"))
        registry = self.generate()
        self.assertNotIn("as a0", registry)
        self.assertIn("void registerCustomCodeWidgets()", registry)
        self.assertFalse(os.path.isdir(os.path.join(self.dest, "addons")))

    def test_code_from_a_library_is_built_in_only_with_the_switch_on(self):
        checkout(
            os.path.join(self.dir, "repo"),
            clock=dart("clock"),
            unifi=dart("unifi", repo=addons.DEFAULT_REPO),
            tide=dart("tide", repo="someone/library"),
        )
        registry = self.generate()
        # From a checkout, and from the catalogue: built in.
        self.assertIn("'clock': () =>", registry)
        self.assertIn("'unifi': () =>", registry)
        # From a library, with the switch off: left out, wherever it came from.
        self.assertNotIn("tide", registry)
        self.assertEqual(sorted(os.listdir(os.path.join(self.dest, "addons"))), ["clock", "unifi"])

        write_config(self.home, codeWidgets=True)
        registry = self.generate()
        self.assertIn("'tide': () =>", registry)


def write_config(home, **dashboard):
    """A panel's config.json under [home], with [dashboard] as its dashboard."""
    folder = os.path.join(home, ".config", "homecanvas")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "config.json"), "w") as f:
        json.dump({"dashboard": dashboard}, f)


def described(id, type):
    """An add-on described in JSON, bringing custom_[type]."""
    return (
        {"name": id, "kind": "json", "types": [f"custom_{type}"], "version": "1.0.0"},
        {f"{id}.json": json.dumps({"type": type, "name": id})},
    )


def theme(id, named):
    return (
        {"name": id, "kind": "theme", "types": [], "themes": [named], "version": "1.0.0"},
        {"theme.json": json.dumps({"id": named, "name": named})},
    )


class GitHub:
    """Stands in for raw.githubusercontent.com: owner/name -> a checkout,
    published as the catalogue's checks would publish it."""

    def __init__(self):
        self.repos, self.files, self.broken = {}, {}, set()

    def publish(self, name, folder, extra=()):
        """[folder] as [name]'s index, with [extra] entries put in as they
        are — however wrong — the way a library's own index could have them."""
        cat = addons.index(folder)
        commit = hashlib.sha1(name.encode()).hexdigest()
        listed = [dict(a) for a in cat["addons"]] + list(extra)
        self.repos[name] = json.dumps({"commit": commit, "addons": listed}).encode()
        for a in cat["addons"]:
            for f in a["files"]:
                with open(os.path.join(folder, "widgets", a["id"], f["path"]), "rb") as fh:
                    self.files[f"{addons.RAW}/{name}/{commit}/widgets/{a['id']}/{f['path']}"] = fh.read()

    def get(self, url, most):
        for name, data in self.repos.items():
            if url == f"{addons.RAW}/{name}/{addons.BRANCH}/index.json":
                if name in self.broken:
                    raise addons.Refused(f"The catalogue could not be reached: {name}.")
                return data
        if url in self.files:
            return self.files[url]
        raise addons.Refused(f"The catalogue answered 404 for {url}.")


class Panel(unittest.TestCase):
    """A panel of its own: its config, add-ons and themes in a folder, and
    GitHub a stand-in."""

    LIBRARY = "someone/library"

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.home = os.path.join(self.dir, "home")
        config = os.path.join(self.home, ".config", "homecanvas")
        self.was = {k: getattr(addons, k) for k in ("CONFIG", "ADDONS", "THEMES", "REMOVED", "get")}
        self.github = GitHub()
        addons.CONFIG = os.path.join(config, "config.json")
        addons.ADDONS = os.path.join(config, "addons")
        addons.THEMES = os.path.join(config, "themes")
        addons.REMOVED = os.path.join(config, "addons-removed.json")
        addons.get = self.github.get
        self.env = {k: os.environ.pop(k) for k in list(os.environ) if k.startswith("HOMECANVAS_")}
        self.github.publish(addons.DEFAULT_REPO, checkout(
            os.path.join(self.dir, "catalogue"),
            clock=dart("clock"),
            weather=dart("weather"),
            theme_lcars=theme("theme_lcars", "lcars"),
        ))

    def tearDown(self):
        for k, v in self.was.items():
            setattr(addons, k, v)
        os.environ.update(self.env)
        shutil.rmtree(self.dir)

    def library(self, extra=(), name=LIBRARY, **widgets):
        self.github.publish(name, checkout(os.path.join(self.dir, name.replace("/", "_")), **widgets), extra)

    def config(self, **dashboard):
        write_config(self.home, **dashboard)

    def installed(self):
        return sorted(addons.installed())


class Ensuring(Panel):
    """addons.py ensure, as install.sh runs it before every build."""

    def test_a_library_brings_code_only_with_the_switch_on(self):
        self.library(tide=dart("tide"), sea=described("sea", "sea"))
        dash = {"addonLibraries": [self.LIBRARY],
                "widgets": [{"type": "clock"}, {"type": "tide"}, {"type": "custom_sea"}]}
        self.config(**dash)
        self.assertEqual(addons.ensure(), 0)
        # JSON from a library is not code; Dart from one is.
        self.assertEqual(self.installed(), ["clock", "sea"])
        self.config(**dash, codeWidgets=True)
        self.assertEqual(addons.ensure(), 0)
        self.assertEqual(self.installed(), ["clock", "sea", "tide"])
        with open(os.path.join(addons.ADDONS, "tide", "addon.json")) as f:
            self.assertEqual(json.load(f)["repo"], self.LIBRARY)

    def test_a_library_never_stands_in_for_the_catalogue(self):
        # Weather and LCARS taken off by hand, their tile and theme still
        # in use: the catalogue has them, so no library is asked — not even
        # with code allowed, and not under another name.
        self.library(
            weather_alt=dart("weather_alt", ["weather"]),
            weather_json=({"name": "w", "kind": "json", "types": ["weather"]}, {"w.json": "{}"}),
            weather=dart("weather"),
            theme_lcars_too=theme("theme_lcars_too", "lcars"),
        )
        self.config(addonLibraries=[self.LIBRARY], codeWidgets=True, themeId="lcars",
                    widgets=[{"type": "clock"}, {"type": "weather"}])
        addons.note_removed(add=["weather", "theme_lcars"])
        self.assertEqual(addons.ensure(), 0)
        self.assertEqual(self.installed(), ["clock"])
        self.assertEqual(addons.theme_files(), set())

    def test_what_the_catalogue_lacks_a_library_may_fill(self):
        self.library(theme_neon=theme("theme_neon", "neon"), tide=dart("tide"))
        self.config(addonLibraries=[self.LIBRARY], themeId="neon", widgets=[{"type": "clock"}])
        addons.ensure()
        self.assertEqual(self.installed(), ["clock", "theme_neon"])
        self.assertEqual(addons.theme_files(), {"neon"})

    def test_without_the_catalogue_no_library_is_read(self):
        self.library(tide=dart("tide"))
        self.github.broken.add(addons.DEFAULT_REPO)
        self.config(addonLibraries=[self.LIBRARY], codeWidgets=True, widgets=[{"type": "tide"}])
        self.assertEqual(addons.ensure(), 0)
        self.assertEqual(self.installed(), [])

    def test_a_library_is_never_the_starter_set(self):
        # An empty dashboard and nothing installed — the catalogue's starter
        # set, here none — is not a gap for a library to fill.
        self.library(tide=dart("tide", starter=True))
        self.config(addonLibraries=[self.LIBRARY], codeWidgets=True, widgets=[])
        self.assertEqual(addons.ensure(), 0)
        self.assertEqual(self.installed(), [])

    def test_a_malformed_entry_costs_only_itself(self):
        good = {"kind": "json", "files": [{"path": "x.json", "sha256": "0" * 64}]}
        self.library(
            extra=[
                {**good, "id": "unhashable", "types": [{}]},
                {**good, "id": "listed", "types": [["tide"]]},
                {**good, "id": "themed", "types": ["tide"], "themes": [{}]},
                {**good, "id": "nameless", "types": ["tide", None]},
            ],
            tide=dart("tide"),
        )
        self.assertEqual([a["id"] for a in addons.index(self.LIBRARY)["addons"]], ["tide"])
        self.config(addonLibraries=[self.LIBRARY], codeWidgets=True,
                    widgets=[{"type": "clock"}, {"type": "tide"}])
        self.assertEqual(addons.ensure(), 0)
        self.assertEqual(self.installed(), ["clock", "tide"])

    def test_one_library_going_wrong_stops_neither_the_catalogue_nor_the_rest(self):
        self.library(tide=dart("tide"))
        self.library(name="other/library", surf=dart("surf"))
        self.config(addonLibraries=[self.LIBRARY, "other/library"], codeWidgets=True,
                    widgets=[{"type": "clock"}, {"type": "tide"}, {"type": "surf"}])
        index = addons.index

        def unforeseen(src):
            if src == self.LIBRARY:
                raise TypeError("unhashable type: 'dict'")
            return index(src)

        addons.index = unforeseen
        try:
            self.assertEqual(addons.ensure(), 0)
        finally:
            addons.index = index
        self.assertEqual(self.installed(), ["clock", "surf"])

    def test_an_addon_json_of_the_wrong_shape_stops_nothing(self):
        folder = os.path.join(addons.ADDONS, "odd")
        os.makedirs(folder)
        with open(os.path.join(folder, "addon.json"), "w") as f:
            json.dump({"kind": "json", "types": [{}, "weather"], "themes": [[]]}, f)
        self.config(widgets=[{"type": "clock"}, {"type": {}}, {"type": "weather"}])
        self.assertEqual(addons.ensure(), 0)
        self.assertEqual(self.installed(), ["clock", "odd"])

    def test_what_landed_before_a_failure_is_put_in_place(self):
        self.github.publish(addons.DEFAULT_REPO, checkout(
            os.path.join(self.dir, "catalogue2"),
            theme_lcars=theme("theme_lcars", "lcars"),
            sea=described("sea", "sea"),
            zebra=dart("zebra"),
        ))
        # The last of the batch is not what the catalogue checked.
        for url in self.github.files:
            if "/zebra/" in url:
                self.github.files[url] += b"// slipped in\n"
        self.config(themeId="lcars", widgets=[{"type": "custom_sea"}, {"type": "zebra"}])
        self.assertEqual(addons.ensure(), 0)
        self.assertEqual(self.installed(), ["sea", "theme_lcars"])
        self.assertEqual(addons.theme_files(), {"lcars"})
        widgets = os.path.join(os.path.dirname(addons.ADDONS), "widgets")
        self.assertEqual(os.listdir(widgets), ["sea.json"])

    def test_a_library_cannot_say_it_is_the_catalogue(self):
        self.library(tide=dart("tide", repo=addons.DEFAULT_REPO))
        self.config(addonLibraries=[self.LIBRARY], codeWidgets=True, widgets=[{"type": "tide"}])
        addons.ensure()
        with open(os.path.join(addons.ADDONS, "tide", "addon.json")) as f:
            self.assertEqual(json.load(f)["repo"], self.LIBRARY)


class BuildingIn(Panel):
    """addons.py dart: which add-ons generate builds into the app."""

    def install(self, id, **more):
        folder = os.path.join(addons.ADDONS, id)
        os.makedirs(folder)
        manifest, files = dart(id, **more)
        with open(os.path.join(folder, "addon.json"), "w") as f:
            json.dump(manifest, f)
        with open(os.path.join(folder, f"{id}.dart"), "w") as f:
            f.write(files[f"{id}.dart"])

    def built(self):
        return [id for id, _ in addons.dart_addons()]

    def test_code_from_a_library_waits_for_the_switch(self):
        self.install("clock")  # from a checkout of the catalogue: nothing noted
        self.install("unifi", repo=addons.DEFAULT_REPO)
        self.install("radio", repo="VWillcox/homecanvas-widgets")
        self.install("tide", repo=self.LIBRARY)
        self.config()
        self.assertEqual(self.built(), ["clock", "radio", "unifi"])
        self.config(codeWidgets=True)
        self.assertEqual(self.built(), ["clock", "radio", "tide", "unifi"])
        # Only true is on.
        self.config(codeWidgets="yes")
        self.assertEqual(self.built(), ["clock", "radio", "unifi"])

    def test_the_catalogue_is_the_one_this_panel_reads(self):
        self.install("clock", repo="someone/fork")
        self.install("unifi", repo=addons.DEFAULT_REPO)
        self.config(addonsRepo="someone/fork")
        self.assertEqual(self.built(), ["clock"])

    def test_one_downloaded_from_a_library_in_the_editor_is_built_in(self):
        """The editor's download: widget-build.sh addons tide@owner/name,
        which runs `addons.py fetch`, with the switch on — the editor asks
        for code from a library only then."""
        import sys
        self.library(tide=dart("tide"))
        self.config(addonLibraries=[self.LIBRARY], codeWidgets=True)
        argv = sys.argv
        sys.argv = ["addons.py", "fetch", "--dest", addons.ADDONS, f"tide@{self.LIBRARY}", "clock"]
        try:
            self.assertEqual(addons.main(), 0)
        finally:
            sys.argv = argv
        self.assertEqual(self.built(), ["clock", "tide"])
        self.config(addonLibraries=[self.LIBRARY])
        self.assertEqual(self.built(), ["clock"])


if __name__ == "__main__":
    unittest.main()

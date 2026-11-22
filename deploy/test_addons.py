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
        self.dest = os.path.join(ROOT, "lib", "dashboard", "widgets", "custom")
        self.kept = os.path.join(self.dir, "kept")
        shutil.copytree(self.dest, self.kept)
        self.tests = os.path.join(ROOT, "test", "addons")
        self.kept_tests = os.path.join(self.dir, "kept-tests")
        if os.path.isdir(self.tests):
            shutil.copytree(self.tests, self.kept_tests)

    def tearDown(self):
        # Whatever was built in before is put back as it was.
        shutil.rmtree(self.dest)
        shutil.copytree(self.kept, self.dest)
        shutil.rmtree(self.tests, ignore_errors=True)
        if os.path.isdir(self.kept_tests):
            shutil.copytree(self.kept_tests, self.tests)
        shutil.rmtree(self.dir)

    def generate(self, **env):
        subprocess.run(
            ["bash", os.path.join(ROOT, "scripts", "widget-build.sh"), "generate"],
            check=True,
            env={**os.environ, "HOMECANVAS_WIDGETS": os.path.join(self.dir, "src"),
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


if __name__ == "__main__":
    unittest.main()

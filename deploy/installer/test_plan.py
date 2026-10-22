"""Tests for what the installer decides.

Run from the repository root:  python3 -m unittest deploy/installer/test_plan.py

No terminal, no network and no config of yours: plan.py is plain functions.
"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import homecanvas_setup as setup  # noqa: E402
import plan  # noqa: E402

CAT = plan.Catalogue()

WPCTL = """PipeWire 'pipewire-0' [1.4.2, pi@homecanvas, cookie:1062180111]
 └─ Clients:
        33. WirePlumber                         [1.4.2, pi@homecanvas, pid:1135]

Audio
 ├─ Devices:
 │      49. Built-in Audio                      [alsa]
 │      84. Webcam C270                         [alsa]
 │
 ├─ Sinks:
 │  *   75. Buildwin Media-Player Analog Stereo [vol: 1.00]
 │
 ├─ Sources:
 │      48. Buildwin Media-Player Mono          [vol: 1.00]
 │  *   87. Webcam C270 Analog Stereo           [vol: 1.00]
 │
 ├─ Filters:
 │
 └─ Streams:
        82. pw-record

Video
 ├─ Devices:
 │      85. HD Webcam C270: HD Webcam C270      [libcamera]
 ├─ Sources:
 │  *   99. HD Webcam C270 (V4L2)
"""


class TheCatalogue(unittest.TestCase):
    def test_presets_and_extras_name_real_widgets(self):
        for group in (CAT.presets, CAT.modules):
            for item in group:
                for t in item.get("widgets", []):
                    self.assertIn(t, CAT.widgets, f"{item['id']}: {t}")

    def test_every_widget_is_in_a_category_it_is_shown_under(self):
        shown = {w["type"] for _, ws in CAT.by_category() for w in ws}
        self.assertEqual(shown, set(CAT.widgets))

    def test_extras_follow_the_widgets(self):
        ids = [m["id"] for m in CAT.modules_for({"youtube", "weather"})]
        self.assertEqual(ids, ["weather", "videos"])
        self.assertIn("speech", [m["id"] for m in CAT.modules_for(set(), voice=True)])
        self.assertNotIn("spotify-connect", [m["id"] for m in CAT.modules_for({"spotify"}, apt=False)])


class Layout(unittest.TestCase):
    def check(self, pages, widgets):
        for w in widgets:
            self.assertLessEqual(w["x"] + w["width"], plan.COLUMNS, w)
            self.assertLessEqual(w["y"] + w["height"], plan.ROWS, w)
            self.assertLess(w["page"], len(pages))
        for i, a in enumerate(widgets):
            for b in widgets[i + 1:]:
                if a["page"] != b["page"]:
                    continue
                apart = (a["x"] + a["width"] <= b["x"] or b["x"] + b["width"] <= a["x"]
                         or a["y"] + a["height"] <= b["y"] or b["y"] + b["height"] <= a["y"])
                self.assertTrue(apart, f"{a['type']} overlaps {b['type']}")

    def test_every_preset_lays_out_without_overlaps(self):
        for p in CAT.presets:
            pages, widgets = plan.layout(CAT, set(p["widgets"]))
            self.assertEqual({w["type"] for w in widgets}, set(p["widgets"]))
            self.check(pages, widgets)

    def test_everything_at_once(self):
        pages, widgets = plan.layout(CAT, set(CAT.widgets))
        self.assertEqual(len(widgets), len(CAT.widgets))
        self.check(pages, widgets)
        self.assertEqual(len({w["id"] for w in widgets}), len(widgets))

    def test_nothing_is_no_pages(self):
        self.assertEqual(plan.layout(CAT, set()), ([], []))


class Config(unittest.TestCase):
    def old(self):
        return {"dashboard": {"themeId": "glass", "pages": [{"name": "Mine"}],
                              "widgets": [{"id": "w7", "type": "clock", "page": 0}]},
                "apiKey": "secret"}

    def test_replace(self):
        c = plan.apply_dashboard(self.old(), CAT, {"weather", "news"}, "lcars", "replace", True)
        d = c["dashboard"]
        self.assertEqual(d["themeId"], "lcars")
        self.assertTrue(d["enabled"] and d["showOnLaunch"])
        self.assertEqual({w["type"] for w in d["widgets"]}, {"weather", "news"})
        self.assertEqual(c["apiKey"], "secret")

    def test_add_goes_on_new_pages_with_new_ids(self):
        d = plan.apply_dashboard(self.old(), CAT, {"weather"}, "lcars", "add", None)["dashboard"]
        self.assertEqual(d["widgets"][0]["id"], "w7")
        self.assertEqual(d["widgets"][1]["id"], "w8")
        self.assertEqual(d["widgets"][1]["page"], 1)
        self.assertEqual(d["pages"][0]["name"], "Mine")
        self.assertNotIn("showOnLaunch", d)

    def test_keep_changes_only_the_theme(self):
        d = plan.apply_dashboard(self.old(), CAT, {"weather"}, "paper", "keep", None)["dashboard"]
        self.assertEqual(d["themeId"], "paper")
        self.assertEqual([w["type"] for w in d["widgets"]], ["clock"])

    def test_answers_land_where_the_app_reads_them(self):
        c = {"weather": {"location": "X", "latitude": 1.0, "resolvedLabel": "X"}}
        plan.apply_answers(c, "weather", {"location": " Colchester "})
        self.assertEqual(c["weather"], {"location": "Colchester", "enabled": True})
        plan.apply_answers(c, "home-assistant", {"url": "http://ha:8123/", "token": "t"})
        self.assertEqual(c["homeAssistant"], {"baseUrl": "http://ha:8123", "token": "t"})
        plan.apply_answers(c, "homey", {"address": "10.0.0.5", "key": "k"})
        self.assertEqual(c["homey"], {"address": "10.0.0.5", "apiKey": "k"})

    def test_voice(self):
        c = plan.apply_voice({}, {"phrase": "computer"})
        self.assertEqual(c["screen"], {"voiceControl": True, "wakeWord": {"phrase": "computer"}})

    def test_written_privately_with_the_old_one_kept(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "config.json")
            plan.write_config({"a": 1}, path)
            plan.write_config({"a": 2}, path)
            with open(path) as f:
                self.assertEqual(json.load(f), {"a": 2})
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            kept = [f for f in os.listdir(d) if f.startswith("config.json.before-installer-")]
            self.assertEqual(len(kept), 1)

    def test_a_missing_or_broken_config_reads_as_empty(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(plan.read_config(os.path.join(d, "none.json")), {})
            path = os.path.join(d, "bad.json")
            with open(path, "w") as f:
                f.write("{not json")
            self.assertEqual(plan.read_config(path), {})


class ThisMachine(unittest.TestCase):
    def test_microphones_from_wpctl(self):
        self.assertEqual(plan.microphones(WPCTL), [
            ("48", "Buildwin Media-Player Mono", False),
            ("87", "Webcam C270 Analog Stereo", True),
        ])

    def test_no_pipewire_is_no_microphones(self):
        self.assertEqual(plan.microphones(""), [])


class Colours(unittest.TestCase):
    def test_blend(self):
        self.assertEqual(setup.blend("#ffff9900", "#000000"), "#ff9900")
        self.assertEqual(setup.blend("#0b0c10", "#ffffff"), "#0b0c10")
        self.assertEqual(setup.blend("#80ffffff", "#000000"), "#808080")


if __name__ == "__main__":
    unittest.main()

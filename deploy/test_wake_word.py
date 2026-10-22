"""Tests for the wake words: finding them, learning them, judging them.

Run from the repository root:  python3 -m unittest deploy/test_wake_word.py
"""
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import wake_word as ww  # noqa: E402

FIXTURE = os.path.join(os.path.dirname(__file__), "..", "test", "fixtures", "wake_words.json")


class SharedCases(unittest.TestCase):
    """The cases the kiosk's Dart is checked against too."""

    def test_every_case(self):
        with open(FIXTURE) as f:
            fixture = json.load(f)
        for name, text, want in fixture["cases"]:
            wake = ww.WakeWord.from_json(fixture["wakes"][name])
            with self.subTest(wake=name, text=text):
                self.assertEqual(wake.ends(text), want)


class Kept(unittest.TestCase):
    def test_the_default_is_hey_canvas_and_its_lookalikes(self):
        wake = ww.WakeWord()
        self.assertEqual(wake.phrase, "hey canvas")
        self.assertIn("campus", wake.lookalikes)

    def test_another_phrase_starts_with_nothing_learned(self):
        self.assertEqual(ww.WakeWord("Hey, Jarvis!").to_json(),
                         {"phrase": "hey jarvis", "lookalikes": [], "variants": []})

    def test_round_trip(self):
        wake = ww.WakeWord("hey jarvis", ["service"], ["hijarvis"])
        self.assertEqual(ww.WakeWord.from_json(wake.to_json()).to_json(), wake.to_json())

    def test_rubbish_in_the_config_is_hey_canvas(self):
        self.assertEqual(ww.WakeWord.from_json("nonsense").phrase, "hey canvas")
        self.assertEqual(ww.WakeWord.from_json({"phrase": "!!"}).phrase, "hey canvas")


class Learning(unittest.TestCase):
    def test_a_misheard_name_after_the_greeting_is_a_lookalike(self):
        wake = ww.learn(ww.WakeWord("hey jarvis"), ["hey service", "hey jarvis"])
        self.assertEqual(wake.lookalikes, ["service"])
        self.assertTrue(wake.ends("hey service next page"))

    def test_anything_else_distinctive_is_kept_whole(self):
        wake = ww.learn(ww.WakeWord("hey jarvis"), ["hijarvis", "hey jar this"])
        self.assertEqual(wake.to_json()["variants"], ["hijarvis", "hey jar this"])

    def test_what_already_wakes_it_teaches_nothing(self):
        wake = ww.learn(ww.WakeWord("hey jarvis"), ["hey jervis", "jarvis"])
        self.assertEqual(wake.to_json(), ww.WakeWord("hey jarvis").to_json())

    def test_ordinary_words_and_commands_are_never_learned(self):
        wake = ww.learn(ww.WakeWord("hey jarvis"),
                        ["hey the", "hey next", "a", "oh", "", "it is the"])
        self.assertEqual(wake.lookalikes, [])
        self.assertEqual(wake.variants, [])


class Forgiving(unittest.TestCase):
    def test_what_it_learned_that_fires_in_conversation_is_dropped(self):
        wake = ww.WakeWord("hey jarvis", ["service"], ["the table"])
        wake, left = ww.forgive(wake, ["hey service me", "pass the table salt"])
        self.assertEqual(wake.lookalikes, [])
        self.assertEqual(wake.variants, [])
        self.assertEqual(left, [])

    def test_the_phrase_itself_said_in_passing_is_reported(self):
        wake, left = ww.forgive(ww.WakeWord("computer"), ["the computer is off"])
        self.assertEqual(left, ["the computer is off"])

    def test_everyday_sentences_do_not_wake_the_suggestions(self):
        for phrase, _ in ww.SUGGESTIONS:
            for sentence in ww.EVERYDAY:
                with self.subTest(phrase=phrase, sentence=sentence):
                    self.assertFalse(ww.WakeWord(phrase).ends(sentence))


class Judging(unittest.TestCase):
    def levels(self, phrase):
        return {level for level, _ in ww.assess(phrase)}

    def test_good_phrases_pass(self):
        for phrase in ["hey canvas", "computer", "hey jarvis", "okay house"]:
            self.assertNotIn("bad", self.levels(phrase), phrase)

    def test_commands_and_common_words_are_refused(self):
        self.assertIn("bad", self.levels("next"))
        self.assertIn("bad", self.levels("hey the"))
        self.assertIn("bad", self.levels(""))
        self.assertIn("bad", self.levels("hey number 5"))
        self.assertIn("bad", self.levels("one two three four five"))

    def test_short_ones_are_warned_about(self):
        self.assertIn("warn", self.levels("hal"))

    def test_syllables(self):
        self.assertEqual(ww.syllables("canvas"), 2)
        self.assertEqual(ww.syllables("computer"), 3)
        self.assertEqual(ww.syllables("house"), 1)
        self.assertEqual(ww.syllables("jarvis"), 2)


if __name__ == "__main__":
    unittest.main()

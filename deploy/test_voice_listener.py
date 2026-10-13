"""Tests for how the listener cuts up what it hears and knows its name.

Run from the repository root:  python3 -m unittest deploy/test_voice_listener.py

No microphone and no recogniser needed: Hearing is fed how loud each moment
was, and `woken` the words a recogniser made.
"""
import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import voice_listener as vl  # noqa: E402

LOUD, QUIET = 2000.0, 15.0


def hear(levels):
    """What Hearing hands back for `levels`, a tenth of a second each: the
    length of each thing said, in tenths."""
    hearing = vl.Hearing()
    said = []
    for level in levels:
        sound = hearing.chunk(b"..", level)
        if sound is not None:
            said.append(len(sound) // 2)
    return said


class ThingsSaid(unittest.TestCase):
    def test_nothing_is_said_in_a_quiet_room(self):
        self.assertEqual(hear([QUIET] * 200), [])

    def test_a_sentence_is_handed_over_once_it_is_quiet_after_it(self):
        room = [QUIET] * 20
        self.assertEqual(hear(room + [LOUD] * 12 + [QUIET] * 5), [])
        # The lead-in before it, the sentence, and the quiet that ended it.
        self.assertEqual(hear(room + [LOUD] * 12 + [QUIET] * 6), [3 + 12 + 6])

    def test_a_short_pause_is_part_of_the_sentence(self):
        levels = [QUIET] * 20 + [LOUD] * 6 + [QUIET] * 4 + [LOUD] * 8 + [QUIET] * 6
        self.assertEqual(hear(levels), [3 + 6 + 4 + 8 + 6])

    def test_a_long_pause_makes_two_of_it(self):
        # "Hey canvas" … and then, after a think, the rest.
        levels = [QUIET] * 20 + [LOUD] * 6 + [QUIET] * 15 + [LOUD] * 8 + [QUIET] * 6
        self.assertEqual(len(hear(levels)), 2)

    def test_a_knock_is_not_a_word(self):
        self.assertEqual(hear([QUIET] * 20 + [LOUD] * 2 + [QUIET] * 10), [])

    def test_sound_that_goes_on_and_on_is_let_go_by(self):
        # The television: never a breath, so never a thing said.
        self.assertEqual(hear([QUIET] * 20 + [LOUD, QUIET] * 100), [])

    def test_and_it_listens_again_once_that_stops(self):
        droning = [QUIET] * 20 + [LOUD, QUIET] * 100
        after = [QUIET] * 60 + [LOUD] * 10 + [QUIET] * 6
        self.assertEqual(len(hear(droning + after)), 1)

    def test_speech_is_judged_against_the_room(self):
        # Over music, the music is not somebody talking; louder than it is.
        music = [600.0] * 60
        self.assertEqual(hear(music + [900.0] * 10 + music), [])
        self.assertEqual(len(hear(music + [3000.0] * 10 + [600.0] * 6)), 1)


class TheWakeWords(unittest.TestCase):
    def test_as_they_are(self):
        self.assertEqual(vl.woken("Hey, canvas."), 2)
        self.assertEqual(vl.woken("hey canvas show stocks"), 2)
        self.assertEqual(vl.woken("Canvas, next page."), 1)

    def test_as_they_have_been_heard_at_the_panel(self):
        for text in [
            "Hey, Cambus.",
            "Hey, Congress.",
            "Hey, Douglas,",
            "A canvas",
            "Hedy canvas.",
            "Hate canvas",
            "hey, countless, show me the news.",
        ]:
            self.assertTrue(vl.woken(text), text)

    def test_not_other_things_said_in_the_room(self):
        for text in [
            "",
            "And he said,",
            "Hey, tell us.",
            "Take on this.",
            "Hey, can you pass me that",
            "Show stocks",
            "Next page",
            "Congress voted today",
            "I spoke to Douglas about it",
            # Far enough in, it is being talked about, not talked to.
            "I think we should paint it on a canvas",
        ]:
            self.assertFalse(vl.woken(text), text)

    def test_where_they_end_says_whether_anything_followed(self):
        self.assertEqual(len(vl.words("Hey, canvas.")) - vl.woken("Hey, canvas."), 0)
        self.assertEqual(
            len(vl.words("Hey canvas, next page")) - vl.woken("Hey canvas, next page"), 2
        )


class Loudness(unittest.TestCase):
    def test_of_silence_and_of_a_steady_level(self):
        self.assertEqual(vl.loudness(struct.pack("<4h", 0, 0, 0, 0)), 0)
        self.assertEqual(vl.loudness(struct.pack("<4h", 100, -100, 100, -100)), 100)
        self.assertEqual(vl.loudness(b""), 0)


if __name__ == "__main__":
    unittest.main()

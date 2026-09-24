"""Tests for the wake-touch logic in screen_control.py.

Run from the repository root:  python3 -m unittest deploy/test_screen_control.py

No panel needed: WakeTouch is fed events and times directly.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import screen_control as sc  # noqa: E402

DOWN = [(sc.EV_KEY, sc.BTN_TOUCH, 1), (sc.EV_ABS, sc.ABS_MT_TRACKING_ID, 7)]
MOVE = [(sc.EV_ABS, 0x35, 400), (sc.EV_ABS, 0x36, 300)]
UP = [(sc.EV_KEY, sc.BTN_TOUCH, 0), (sc.EV_ABS, sc.ABS_MT_TRACKING_ID, -1)]


def asleep(at=0.0):
    """A WakeTouch whose screen went off at `at`, now grabbed and settled."""
    w = sc.WakeTouch()
    w.screen(False, at)
    assert w.want_grab(at + 5)
    w.grabbed = True
    return w


class Grabbing(unittest.TestCase):
    def test_nothing_is_held_while_the_screen_is_on(self):
        w = sc.WakeTouch()
        self.assertFalse(w.want_grab(10))

    def test_the_panel_is_held_once_the_screen_is_off(self):
        w = sc.WakeTouch()
        w.screen(False, 10)
        self.assertTrue(w.want_grab(10))

    def test_never_grabbed_while_a_finger_is_still_moving(self):
        # A grab taken mid-touch would hide the lift from the compositor and
        # leave the app holding a touch that never ends.
        w = sc.WakeTouch()
        w.events(DOWN + MOVE, 9.9)
        w.screen(False, 10)
        self.assertFalse(w.want_grab(10.1))
        self.assertTrue(w.want_grab(10.1 + w.QUIET))


class TheWakingTouch(unittest.TestCase):
    def test_a_touch_while_off_wakes_the_screen(self):
        w = asleep()
        self.assertTrue(w.events(DOWN, 10))
        self.assertFalse(w.off)

    def test_and_is_kept_until_the_finger_lifts(self):
        w = asleep()
        w.events(DOWN, 10)
        self.assertTrue(w.want_grab(10.5), "finger still down")
        w.events(MOVE, 11)
        self.assertTrue(w.want_grab(11.2), "still down, now dragging")
        w.events(UP, 12)
        self.assertTrue(w.want_grab(12.1), "just lifted — hold briefly")
        self.assertFalse(w.want_grab(12 + w.RELEASE_AFTER))

    def test_a_quick_tap_in_one_read_is_let_go_promptly(self):
        # Down and up can arrive in the same read. The lift must still count,
        # or every touch for the next few seconds would be swallowed too.
        w = asleep()
        self.assertTrue(w.events(DOWN + UP, 10))
        self.assertFalse(w.want_grab(10 + w.RELEASE_AFTER))

    def test_the_next_touch_is_an_ordinary_one(self):
        w = asleep()
        w.events(DOWN + UP, 10)
        self.assertFalse(w.want_grab(11))
        w.grabbed = False
        self.assertFalse(w.events(DOWN, 12), "screen is on; nothing to wake")
        self.assertFalse(w.want_grab(12.1))

    def test_a_lift_that_is_never_reported_does_not_hold_forever(self):
        w = asleep()
        w.events(DOWN, 10)
        self.assertTrue(w.want_grab(10 + w.GIVE_UP - 0.1))
        self.assertFalse(w.want_grab(10 + w.GIVE_UP))

    def test_a_resting_finger_does_not_wake_it_straight_back_up(self):
        w = sc.WakeTouch()
        w.screen(False, 10)
        w.grabbed = True
        self.assertFalse(w.events(MOVE, 10.5))
        self.assertTrue(w.off)

    def test_touches_while_on_are_left_alone(self):
        w = sc.WakeTouch()
        self.assertFalse(w.events(DOWN, 10))
        self.assertFalse(w.events(UP, 10.1))
        self.assertFalse(w.want_grab(10.2))


class WhenSomethingElseChangesTheScreen(unittest.TestCase):
    def test_switched_on_by_alexa_while_held_lets_go(self):
        w = asleep()
        w.screen(True, 20)
        self.assertFalse(w.want_grab(20))

    def test_switched_off_again_mid_wake_starts_over(self):
        w = asleep()
        w.events(DOWN, 10)
        w.screen(False, 11)
        self.assertFalse(w.waking)
        self.assertTrue(w.off)

    def test_tracking_ids_alone_are_enough_on_a_panel_without_btn_touch(self):
        w = asleep()
        down = [(sc.EV_ABS, sc.ABS_MT_TRACKING_ID, 3)]
        up = [(sc.EV_ABS, sc.ABS_MT_TRACKING_ID, -1)]
        self.assertTrue(w.events(down, 10))
        self.assertTrue(w.want_grab(10.2))
        w.events(up, 10.3)
        self.assertFalse(w.want_grab(10.3 + w.RELEASE_AFTER))


class EventLayout(unittest.TestCase):
    def test_input_event_is_the_native_kernel_size(self):
        # 24 bytes on a 64-bit Pi; 16 on a 32-bit one. Reading the wrong size
        # would misalign every event after the first.
        import struct
        self.assertEqual(sc.EVENT.size, struct.calcsize("llHHi"))


if __name__ == "__main__":
    unittest.main()

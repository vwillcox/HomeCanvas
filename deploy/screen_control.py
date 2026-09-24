#!/usr/bin/env python3
"""A small HTTP control surface for the kiosk display.

Home Assistant runs in a container and has no way to reach the host's Wayland
session, so it can't call `wlopm` itself. This runs on the host as the user who
owns that session and exposes the display over localhost instead. Keeping it
separate from the Flutter app means the screen can still be turned on when the
kiosk isn't running, and it survives Home Assistant image updates.

Endpoints (all GET, so Home Assistant's command_line can just curl them):

    /screen              current state as JSON
    /screen/on           power the panel back up
    /screen/off          power the panel down
    /screen/toggle
    /screen/brightness?value=0-100

Binds to localhost only. Home Assistant uses host networking, so it can reach
this, but nothing off the machine can.
"""

import fcntl
import glob
import json
import os
import re
import selectors
import struct
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

LISTEN = ("127.0.0.1", 8765)

# Power changes and wakes are rare and worth a record — without one, working out
# why the screen did or didn't come back means catching it live. Routine state
# polling is not logged; Home Assistant does that every 30 seconds.
LOG = os.path.expanduser("~/.cache/immich_kiosk_pi/screen_control.log")
_log_lock = threading.Lock()


def log(message):
    line = time.strftime("%Y-%m-%d %H:%M:%S ") + message + "\n"
    try:
        with _log_lock:
            os.makedirs(os.path.dirname(LOG), exist_ok=True)
            # Keep it small; this runs for months on a kiosk.
            if os.path.exists(LOG) and os.path.getsize(LOG) > 64_000:
                with open(LOG) as f:
                    tail = f.readlines()[-200:]
                with open(LOG, "w") as f:
                    f.writelines(tail)
            with open(LOG, "a") as f:
                f.write(line)
    except OSError:
        pass

# wlopm needs to talk to the compositor the kiosk user is logged into.
os.environ.setdefault("WAYLAND_DISPLAY", "wayland-0")
os.environ.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")


def _wlopm(args=()):
    return subprocess.run(
        ["wlopm", *args], capture_output=True, text=True, timeout=10
    ).stdout


def outputs():
    """Map of output name -> True when powered on, parsed from `wlopm`."""
    found = {}
    for line in _wlopm().splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1] in ("on", "off"):
            found[parts[0]] = parts[1] == "on"
    return found


def set_output(on):
    """Power every output up or down."""
    flag = "--on" if on else "--off"
    for name in outputs():
        _wlopm([flag, name])
    return outputs()


# Brightness to come back to. Seeded from whatever the panel is showing now.
_restore_to = 100


def set_power(on, deep=False):
    """Turn the display off or on.

    "Off" means backlight to zero, leaving the output powered. That matters:
    cutting the DSI output also cuts power to the touch controller, so the panel
    stops reporting touches entirely and nothing short of another command can
    bring it back. Measured on this display — 13 touch events with the output
    on, none at all with it off.

    `deep` restores the old behaviour and genuinely powers the output down. It
    saves a little more, but the screen can then only be woken by Alexa or by
    /screen/on.
    """
    global _restore_to
    if on:
        set_output(True)
        set_brightness(_restore_to)
        log(f"on (brightness {_restore_to})")
    else:
        current = brightness()
        if current:
            _restore_to = current
        set_brightness(0)
        if deep:
            set_output(False)
        log("off deep - touch cannot wake this" if deep else "off (backlight 0)")
    return state()


def _backlight():
    paths = glob.glob("/sys/class/backlight/*/")
    return paths[0] if paths else None


def brightness():
    """Backlight as a percentage, or None when there's no backlight device."""
    path = _backlight()
    if not path:
        return None
    try:
        with open(path + "brightness") as f:
            current = int(f.read().strip())
        with open(path + "max_brightness") as f:
            maximum = int(f.read().strip())
        return round(current * 100 / maximum) if maximum else None
    except OSError:
        return None


def set_brightness(percent):
    path = _backlight()
    if not path:
        return None
    percent = max(0, min(100, percent))
    with open(path + "max_brightness") as f:
        maximum = int(f.read().strip())
    # Anything above zero should stay visible, so never round down to off.
    value = max(1, round(percent * maximum / 100)) if percent else 0
    with open(path + "brightness", "w") as f:
        f.write(str(value))
    return brightness()


def state():
    powered = outputs()
    level = brightness()
    return {
        # Visibly on: a powered output showing a lit backlight.
        "on": any(powered.values()) and (level is None or level > 0),
        "outputs": powered,
        "brightness": level,
        "restoreTo": _restore_to,
    }


class Handler(BaseHTTPRequestHandler):
    # The default handler logs every request to stderr, which would fill the
    # journal given Home Assistant polls this on a timer.
    def log_message(self, *args):
        pass

    def _reply(self, body, code=200):
        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        url = urlparse(self.path)
        path = url.path.rstrip("/") or "/"
        try:
            if path == "/screen":
                return self._reply(state())
            if path == "/screen/on":
                set_power(True)
                waker.note_power(True)
                return self._reply(state())
            if path == "/screen/off":
                deep = parse_qs(url.query).get("deep", ["0"])[0] not in ("0", "")
                set_power(False, deep=deep)
                waker.note_power(False)
                return self._reply(state())
            if path == "/screen/toggle":
                target = not state()["on"]
                set_power(target)
                waker.note_power(target)
                return self._reply(state())
            if path == "/screen/brightness":
                raw = parse_qs(url.query).get("value", [None])[0]
                if raw is None or not re.fullmatch(r"\d{1,3}", raw):
                    return self._reply({"error": "value must be 0-100"}, 400)
                global _restore_to
                value = int(raw)
                set_brightness(value)
                if value:
                    _restore_to = value
                waker.note_power(value > 0)
                return self._reply(state())
            self._reply({"error": "not found"}, 404)
        except Exception as exc:  # noqa: BLE001 - report, don't take the server down
            self._reply({"error": str(exc)}, 500)


def pointer_devices():
    """Event devices for the touchscreen (and any mouse).

    /proc/bus/input/devices lists a `Handlers=` line per device; pointer devices
    get a `mouse` handler, which on this Pi picks out the touch panel and
    nothing else. Deliberately excludes keyboard-style devices — the paired
    phone's AVRCP media keys appear as one, and a track change shouldn't wake
    the screen.
    """
    found = []
    try:
        with open("/proc/bus/input/devices") as f:
            blocks = f.read().split("\n\n")
    except OSError:
        return found
    for block in blocks:
        handlers = ""
        for line in block.splitlines():
            if line.startswith("H: Handlers="):
                handlers = line.split("=", 1)[1]
        if "mouse" not in handlers:
            continue
        for token in handlers.split():
            if token.startswith("event"):
                found.append("/dev/input/" + token)
    return found


# struct input_event from <linux/input.h>, in this machine's native layout:
# a timeval (two longs), then type, code and value.
EVENT = struct.Struct("llHHi")
EV_KEY = 0x01
EV_ABS = 0x03
BTN_TOUCH = 0x14A
ABS_MT_TRACKING_ID = 0x39

# _IOW('E', 0x90, int): take the device for ourselves, or give it back.
EVIOCGRAB = 0x40044590


class WakeTouch:
    """Decides what to do with the touchscreen while the screen is off.

    Pure logic, fed with events and the time, so it can be tested without a
    panel to touch. `Waker` does the reading and grabbing.

    The problem it solves: "off" is only the backlight at zero, so the panel
    keeps reporting touches, and the touch that woke the screen also landed on
    whatever was underneath it — the TV remote's power button, a headline, a
    link. Now, while the screen is off, the device is grabbed: touches come
    here and nowhere else. The first one wakes the screen, and the grab is held
    until that finger lifts, so the whole touch is swallowed. The next touch is
    an ordinary one.

    Grabbing is never done mid-touch. A grab taken while a finger is down
    would leave the compositor seeing the finger go down but never come up,
    and the app could be left holding a touch that never ends. So it waits for
    the panel to be still first, and lets go only once the finger has lifted.
    """

    # Ignore touches for a moment after the screen goes off: a finger still
    # resting on the panel would otherwise wake it straight back up.
    SETTLE = 1.5

    # How long the panel must have been still before it is grabbed.
    QUIET = 0.3

    # After the waking finger lifts, how long before the device is given back.
    RELEASE_AFTER = 0.25

    # A lift that is never reported must not hold the device for ever: after
    # this long with the screen on and no input at all, it is given back.
    GIVE_UP = 3.0

    def __init__(self):
        self.off = False
        self.grabbed = False
        self.waking = False
        self._off_at = float("-inf")
        self._last_input = float("-inf")
        self._lifted_at = None
        # Whether a finger is on the panel, carried across reads: a quick tap
        # can arrive as one read holding both the touch and the lift.
        self._down = False
        # Once BTN_TOUCH has been seen it is trusted over tracking ids, which
        # only describe one finger at a time.
        self._has_btn_touch = False

    def screen(self, on, now):
        """The screen was switched on or off (by anyone)."""
        if on == (not self.off):
            return
        self.off = not on
        if self.off:
            self._off_at = now
            self.waking = False

    def events(self, batch, now):
        """Input arrived. Returns True when it should wake the screen."""
        self._last_input = now
        for type_, code, value in batch:
            if type_ == EV_KEY and code == BTN_TOUCH:
                self._has_btn_touch = True
                self._down = value == 1
            elif (
                type_ == EV_ABS
                and code == ABS_MT_TRACKING_ID
                and not self._has_btn_touch
            ):
                self._down = value != -1

        woke = False
        if self.off and self.grabbed and now - self._off_at >= self.SETTLE:
            # The waking touch: from here until the finger lifts, it is ours.
            self.off = False
            self.waking = True
            woke = True
        if self.waking:
            if self._down:
                self._lifted_at = None
            elif self._lifted_at is None:
                self._lifted_at = now
        return woke

    def want_grab(self, now):
        """Whether the device should be held right now."""
        if self.off:
            # Take it once the panel is still, never mid-touch.
            return self.grabbed or now - self._last_input >= self.QUIET
        if self.waking:
            lifted = (
                self._lifted_at is not None
                and now - self._lifted_at >= self.RELEASE_AFTER
            )
            stale = now - self._last_input >= self.GIVE_UP
            if lifted or stale:
                self.waking = False
                return False
            return True
        return False


class Waker:
    """Turns the screen back on when the panel is touched — and keeps that
    touch to itself. See `WakeTouch` for why and how.
    """

    # How often to check the backlight for changes made some other way — the
    # brightness endpoint, or anything writing sysfs directly. A file read,
    # so cheap enough to do often.
    RECHECK = 2.0

    def __init__(self):
        self.touch = WakeTouch()
        self._lock = threading.Lock()
        self._checked = 0.0

    def note_power(self, on):
        """Record a state we set ourselves, so the watcher stays in step."""
        with self._lock:
            self.touch.screen(on, time.monotonic())
            self._checked = time.monotonic()

    def _resync(self, now):
        if now - self._checked < self.RECHECK:
            return
        level = brightness()
        with self._lock:
            self._checked = now
            if level is not None and not self.touch.waking:
                self.touch.screen(level > 0, now)

    def _set_grab(self, fds, want):
        if want == self.touch.grabbed:
            return
        for fd in fds:
            try:
                fcntl.ioctl(fd, EVIOCGRAB, 1 if want else 0)
            except OSError as exc:
                log(f"could not {'grab' if want else 'release'} touch: {exc}")
        self.touch.grabbed = want

    def run(self):
        devices = pointer_devices()
        if not devices:
            return
        sel = selectors.DefaultSelector()
        opened = []
        for path in devices:
            try:
                fd = open(path, "rb", buffering=0)
            except OSError:
                continue  # Needs membership of the `input` group.
            opened.append(fd)
            sel.register(fd, selectors.EVENT_READ)
        if not opened:
            return
        while True:
            now = time.monotonic()
            self._resync(now)
            with self._lock:
                self._set_grab(opened, self.touch.want_grab(now))
            # Short while anything is changing hands, so a lift is acted on
            # promptly; long otherwise, since nothing needs doing.
            busy = self.touch.off or self.touch.waking
            for key, _ in sel.select(timeout=0.05 if busy else 1.0):
                try:
                    raw = key.fileobj.read(EVENT.size * 64)
                except OSError:
                    continue
                batch = [
                    EVENT.unpack_from(raw, i)[2:]
                    for i in range(0, len(raw) - EVENT.size + 1, EVENT.size)
                ]
                with self._lock:
                    wake = self.touch.events(batch, time.monotonic())
                if wake:
                    log("touch while off - waking, and keeping that touch")
                    set_power(True)
                    with self._lock:
                        self._checked = time.monotonic()


waker = Waker()


if __name__ == "__main__":
    # Come back to whatever the panel is set to now, not an arbitrary default.
    _restore_to = brightness() or 100
    devices = pointer_devices()
    log(f"started; watching {devices or 'NO POINTER DEVICES'} for touch")
    threading.Thread(target=waker.run, daemon=True).start()
    ThreadingHTTPServer(LISTEN, Handler).serve_forever()

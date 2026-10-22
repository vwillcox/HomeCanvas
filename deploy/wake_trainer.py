#!/usr/bin/env python3
"""Listens for the installer's wake-word wizard, and says what it heard.

The wizard runs in the system's Python, where there is no speech engine; this
runs in voice control's own (~/.local/share/homecanvas/voice/venv) and only
hears. It reads the microphone the way the listener does, cuts it into
things said the same way, and makes words of each with the same two
recognisers — so what the wizard learns is what the listener will hear.
Nothing is kept or sent anywhere.

Each thing to say is a line of JSON on standard output:

    {"event": "ready"}
    {"event": "level", "level": 840.0, "speech": 360.0}
                          how loud, ten times a second, and how loud counts
                          as somebody talking
    {"event": "said", "texts": ["hey jarvis", "hey jervis"], "seconds": 1.2}
                          a thing said, as each recogniser made it out
    {"event": "error", "message": "…"}

It runs until it is stopped. `--from FILE` hears a raw recording (16 kHz
16-bit mono) instead of the room, and stops at its end; `--target` picks a
microphone other than the default.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voice_listener as vl  # noqa: E402


def say(event, **more):
    print(json.dumps({"event": event, **more}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--from", dest="file", help="hear a raw recording instead")
    parser.add_argument("--target", help="the microphone, by PipeWire id or name")
    args = parser.parse_args()
    try:
        recognisers = vl.load_recognisers()
        mic = open(args.file, "rb") if args.file else vl.microphone(args.target)
    except Exception as exc:  # noqa: BLE001 - said, for the wizard to show
        say("error", message=str(exc))
        return 1

    hearing = vl.Hearing()
    say("ready")
    while True:
        chunk = mic.read(vl.CHUNK)
        if len(chunk) < vl.CHUNK:
            if args.file:
                return 0
            say("error", message="the microphone stopped")
            return 1
        level = vl.loudness(chunk)
        sound = hearing.chunk(chunk, level)
        say("level", level=round(level, 1), speech=round(hearing.speech, 1))
        if sound is not None:
            texts = vl.transcribe(recognisers, sound)
            say("said", texts=texts, seconds=round(len(sound) / 2 / vl.RATE, 1))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)

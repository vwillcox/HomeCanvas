#!/usr/bin/env python3
"""Listens for "hey canvas" and for what is said after it.

Everything happens on this machine: the microphone is read through PipeWire
and the speech is recognised here by sherpa-onnx. Nothing is sent anywhere
and nothing is kept — the sound is held for a few seconds, in memory, and
only the words made of it leave this program.

This program only hears. What the words mean is the kiosk's business
(`lib/services/voice_commands.dart`), which knows the dashboard's pages.
Each thing heard is a line of JSON on standard output:

    {"event": "ready"}                      listening
    {"event": "wake"}                       the wake words, just now
    {"event": "heard", "text": "hey canvas next page", "other": "…"}
                                            what was said with them, as
                                            words — and as the second
                                            recogniser heard it, to try
                                            when the first means nothing
    {"event": "error", "message": "…"}      and why it is not listening

Run by the kiosk while voice control is switched on, with the Python that
has sherpa-onnx in it:

    ~/.local/share/homecanvas/voice/venv/bin/python deploy/voice_listener.py

With `--post` it also tells the kiosk itself, over its local control port:
for trying it out from a terminal, with the kiosk none the wiser. With
`--keep FOLDER` each thing said to the panel is also saved there as sound,
to find out why one was misheard — never otherwise, and not something to
leave switched on. `--from FILE` hears a recording instead of the room.
"""

import argparse
import collections
import json
import math
import os
import re
import struct
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import wave

RATE = 16000
# A tenth of a second of 16-bit mono at a time.
CHUNK = RATE // 10 * 2

HOME = os.path.expanduser("~/.local/share/homecanvas/voice")
# Two recognisers, a larger one and a small, both run on everything said.
# Neither hears "canvas" every time, and they miss it at different times:
# of twelve "hey canvas" recorded at the panel one heard nine and the other
# ten, and between them eleven.
MODELS = [
    os.path.join(HOME, "models/sherpa-onnx-moonshine-base-en-int8"),
    os.path.join(HOME, "models/sherpa-onnx-moonshine-tiny-en-int8"),
]
KIOSK = "http://127.0.0.1:8766"


def say(event, **more):
    print(json.dumps({"event": event, **more}), flush=True)


def loudness(chunk):
    """Root mean square of a chunk of signed 16-bit samples."""
    count = len(chunk) // 2
    if not count:
        return 0.0
    samples = struct.unpack(f"<{count}h", chunk[: count * 2])
    return math.sqrt(sum(s * s for s in samples) / count)


class Hearing:
    """Cuts what the microphone hears into things said.

    Fed a tenth of a second at a time, with how loud it was; hands back the
    sound of each thing said once it has been quiet after it. Nothing is
    recognised while the room is quiet, which is most of the day.

    Pure — no microphone, no recogniser — so it can be tested with numbers.
    """

    # Tenths of a second kept from before the first sound: the start of a
    # word is quieter than the rest of it.
    LEAD = 3
    # Quiet for this long and it has been said.
    QUIET = 6
    # Too short to be a word: a door, a cup put down.
    SHORTEST = 3
    # Nobody talks to the panel this long without a breath. Sound that goes
    # on is the television, or music, and is let go by unheard.
    LONGEST = 80

    def __init__(self):
        # How loud the last five seconds were, for telling speech from room.
        self.levels = collections.deque(maxlen=50)
        self.before = collections.deque(maxlen=self.LEAD)
        self.sound = None
        self.loud = 0
        self.quiet = 0
        self.droning = False

    @property
    def speech(self):
        """How loud counts as somebody talking: well above the room — three
        times its quieter moments — and never less than a microphone's hiss.
        """
        if not self.levels:
            return 120.0
        room = sorted(self.levels)[len(self.levels) // 4]
        return max(room * 3, 120.0)

    def chunk(self, chunk, level):
        """Another tenth of a second. The sound of a thing said, when this
        was the end of one; otherwise None."""
        talking = level >= self.speech
        self.levels.append(level)
        self.quiet = 0 if talking else self.quiet + 1
        if self.droning:
            self.droning = self.quiet < self.QUIET
            return None
        if self.sound is None:
            if talking:
                self.sound = [*self.before, chunk]
                self.loud = 1
            else:
                self.before.append(chunk)
            return None
        self.sound.append(chunk)
        self.loud += talking
        if len(self.sound) > self.LONGEST:
            self.sound = None
            self.droning = True
            return None
        if self.quiet < self.QUIET:
            return None
        said, loud = self.sound, self.loud
        self.sound = None
        self.before.clear()
        return b"".join(said) if loud >= self.SHORTEST else None


def words(text):
    return re.sub(r"[^a-z0-9 ]+", " ", text.lower().replace("'", "")).split()


def _slips(a, b):
    """How many letters apart two words are."""
    row = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        last, row[0] = row[0], i
        for j, y in enumerate(b, 1):
            last, row[j] = row[j], min(row[j] + 1, row[j - 1] + 1, last + (x != y))
    return row[-1]


# What "hey" has been heard as.
HEYS = {"hey", "hay", "hi", "he", "a", "eh", "hate", "hedy", "hake", "hae"}
# What "canvas" has been heard as, after a "hey", that is not within a letter
# or two of it. All of them from recordings at the panel.
LOOKALIKES = {"cambus", "campus", "congress", "douglas", "countless", "compass"}


def woken(text):
    """Where the wake words end in [text], counted in words; 0 for nowhere.

    "Canvas" itself, near the start, is enough. What a recogniser makes of
    it otherwise — "cambus", "congress" — counts only straight after a "hey"
    at the very start: nobody says "hey, Congress" to a room.
    """
    said = words(text)
    for i, word in enumerate(said[:4]):
        if word in ("canvas", "canvass", "canvases"):
            return i + 1
    if len(said) >= 2 and said[0] in HEYS:
        if _slips(said[1], "canvas") <= 2 or said[1] in LOOKALIKES:
            return 2
    return 0


def tell_kiosk(texts):
    for text in texts:
        try:
            request = urllib.request.Request(
                f"{KIOSK}/voice?say={urllib.parse.quote(text)}", method="POST"
            )
            urllib.request.urlopen(request, timeout=3).close()
            return
        except OSError:
            pass  # Not understood is a 404: the other hearing is tried.


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--post", action="store_true", help="tell the kiosk too")
    parser.add_argument("--keep", metavar="FOLDER", help="save what is said to it")
    parser.add_argument("--from", dest="file", help="hear a raw recording instead")
    args = parser.parse_args()

    try:
        import numpy
        import sherpa_onnx

        recognisers = [
            sherpa_onnx.OfflineRecognizer.from_moonshine(
                preprocessor=os.path.join(model, "preprocess.onnx"),
                encoder=os.path.join(model, "encode.int8.onnx"),
                uncached_decoder=os.path.join(model, "uncached_decode.int8.onnx"),
                cached_decoder=os.path.join(model, "cached_decode.int8.onnx"),
                tokens=os.path.join(model, "tokens.txt"),
                num_threads=2,
            )
            for model in MODELS
        ]
        if args.file:
            mic = open(args.file, "rb")
        else:
            # With no --target it follows the default microphone, whichever
            # that is at the time.
            mic = subprocess.Popen(
                ["pw-record", "--channels=1", f"--rate={RATE}", "--format=s16",
                 "--latency=100ms", "-"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            ).stdout
    except Exception as exc:  # noqa: BLE001 - said, for the kiosk to show
        say("error", message=str(exc))
        return 1

    def heard(sound):
        """What was said in [sound], as each recogniser made it out."""
        samples = numpy.frombuffer(sound, dtype=numpy.int16).astype(numpy.float32) / 32768
        texts = []
        for recogniser in recognisers:
            stream = recogniser.create_stream()
            stream.accept_waveform(RATE, samples)
            recogniser.decode_stream(stream)
            texts.append(stream.result.text.lower().strip())
        return texts

    def keep(sound):
        if not args.keep:
            return
        os.makedirs(args.keep, mode=0o700, exist_ok=True)
        with wave.open(os.path.join(args.keep, f"{time.time():.1f}.wav"), "wb") as f:
            f.setnchannels(1)
            f.setsampwidth(2)
            f.setframerate(RATE)
            f.writeframes(sound)

    def tell(texts):
        texts = [t for t in dict.fromkeys(texts) if t]
        say("heard", text=texts[0] if texts else "", other=" ".join(texts[1:2]))
        if args.post:
            tell_kiosk(texts)

    hearing = Hearing()
    # Tenths of a second left for the rest, after "hey canvas" and a pause.
    waiting = 0
    say("ready")

    while True:
        chunk = mic.read(CHUNK)
        if len(chunk) < CHUNK:
            if args.file:
                return 0
            say("error", message="the microphone stopped")
            return 1
        sound = hearing.chunk(chunk, loudness(chunk))
        if waiting and hearing.sound is None and sound is None:
            waiting -= 1
            if not waiting:
                tell([])  # Woken, and then nothing.
        if sound is None:
            continue
        texts = heard(sound)
        # The hearing with the wake words in it first; it is likelier right.
        texts.sort(key=lambda t: not woken(t))
        ends = woken(texts[0])
        if ends and len(words(texts[0])) == ends:
            # The wake words and no more: the rest is waited for. Said
            # again while waiting, they are waited after again.
            say("wake")
            keep(sound)
            waiting = 40
        elif ends or waiting:
            # The wake words and a command in one breath — or whatever is
            # said next after them, which is the command.
            if not waiting:
                say("wake")
            waiting = 0
            keep(sound)
            tell(texts)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)

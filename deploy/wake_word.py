"""The words that wake the panel: what they are, and how they are heard.

The panel has no keyword spotter. Everything said is turned into words by
the recognisers, and the wake words are found in those words. So a wake word
is a phrase — "hey canvas", "computer", "okay house" — and what the
recognisers make of it when somebody says it: "hey campus", "a canvas". The
installer's wizard listens to the person who will use it say their phrase,
and keeps what the recognisers heard as lookalikes and variants of it.

Standard library only: the listener uses this, and so does the installer,
which runs before there is any Python but the system's.

`lib/services/wake_word.dart` does the same in the kiosk, for words typed to
it rather than heard; `test/fixtures/wake_words.json` holds the cases both
are tested against, so the two agree.
"""

import re

DEFAULT_PHRASE = "hey canvas"

# What a greeting word has been heard as. "Hey" from recordings at the panel.
GREETING_FORMS = {
    "hey": {"hey", "hay", "hi", "he", "a", "eh", "hate", "hedy", "hake", "hae"},
    "hi": {"hi", "hey", "high", "hai"},
    "okay": {"okay", "ok", "o", "k"},
    "ok": {"okay", "ok", "o", "k"},
}

# What "canvas" has been heard as, after a "hey", that is not within a letter
# or two of it. All of them from recordings at the panel.
CANVAS_LOOKALIKES = ["cambus", "campus", "congress", "douglas", "countless", "compass"]

# Words too ordinary to be learned as a wake word: kept, they would wake the
# panel at every other sentence.
COMMON = {
    "a", "an", "the", "and", "or", "but", "is", "it", "its", "i", "im", "you",
    "he", "she", "we", "they", "me", "my", "to", "of", "in", "on", "at", "for",
    "with", "that", "this", "what", "so", "oh", "um", "uh", "er", "yes", "no",
    "yeah", "ok", "okay", "hey", "hi", "hello", "there", "be", "do", "go",
    "can", "will", "just", "not", "have", "has", "was", "are", "if", "then",
    "thank", "thanks", "you", "please", "well", "right", "now", "all",
}

# Words the panel takes as commands. A wake word made of one would fire on
# the command itself.
COMMANDS = {
    "next", "previous", "back", "forward", "close", "exit", "home", "photos",
    "albums", "dashboard", "remote", "forecast", "play", "pause", "stop",
    "skip", "louder", "quieter", "mute", "unmute", "hold", "resume",
    "continue", "camera", "page", "show", "open",
}


def words(text):
    """[text] as words: lower case, no punctuation, "&" spoken as "and"."""
    text = text.lower().replace("&", " and ")
    text = re.sub(r"[’']", "", text)
    return re.sub(r"[^a-z0-9]+", " ", text).split()


def slips(a, b):
    """How many letters apart two words are."""
    row = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        last, row[0] = row[0], i
        for j, y in enumerate(b, 1):
            last, row[j] = row[j], min(row[j] + 1, row[j - 1] + 1, last + (x != y))
    return row[-1]


def syllables(word):
    """Roughly how many syllables [word] has: its groups of vowels, less a
    silent e. Good enough to tell "hal" from "jarvis"."""
    groups = re.findall(r"[aeiouy]+", word)
    count = len(groups)
    if word.endswith("e") and not word.endswith(("le", "ee")) and count > 1:
        count -= 1
    return max(count, 1)


class WakeWord:
    """A wake phrase, and what it has been heard as.

    The last word of the phrase is its name — "canvas" — and any words before
    it a greeting — "hey". [lookalikes] are words heard in place of the name,
    after the greeting; [variants] are whole phrases heard in place of the
    phrase ("hijarvis", "hey jar this").
    """

    def __init__(self, phrase=DEFAULT_PHRASE, lookalikes=None, variants=None):
        said = words(phrase) or words(DEFAULT_PHRASE)
        self.phrase = " ".join(said)
        self.name = said[-1]
        self.greeting = said[:-1]
        if lookalikes is None:
            lookalikes = CANVAS_LOOKALIKES if self.phrase == DEFAULT_PHRASE else []
        self.lookalikes = sorted({w for l in lookalikes for w in words(l)[:1]})
        seen = []
        for v in variants or []:
            v = tuple(words(v))
            if 0 < len(v) <= 5 and v not in seen:
                seen.append(v)
        self.variants = seen

    @classmethod
    def from_json(cls, data):
        if not isinstance(data, dict):
            return cls()
        return cls(
            phrase=str(data.get("phrase") or DEFAULT_PHRASE),
            lookalikes=[str(w) for w in data.get("lookalikes") or []]
            if "lookalikes" in data else None,
            variants=[str(v) for v in data.get("variants") or []],
        )

    def to_json(self):
        return {
            "phrase": self.phrase,
            "lookalikes": list(self.lookalikes),
            "variants": [" ".join(v) for v in self.variants],
        }

    @property
    def name_forms(self):
        """The name as said, and as heard with an ending on it: "canvass"."""
        return {self.name, self.name + "s", self.name + "es"}

    def _greets(self, heard, want):
        return (
            heard == want
            or heard in GREETING_FORMS.get(want, ())
            or (len(want) >= 4 and slips(heard, want) <= 1)
        )

    def ends(self, text):
        """Where the wake words end in [text], counted in words; 0 for none.

        A phrase as learned, at the start or after one stray word. The name
        itself near the start — enough on its own. Or the greeting, then
        something like the name: nobody says "hey, Congress" to a room, so
        a word a letter or two from the name counts there, and only there.
        """
        said = words(text)
        whole = tuple(self.greeting) + (self.name,)
        for v in sorted(self.variants + [whole], key=len, reverse=True):
            for start in (0, 1):
                if tuple(said[start:start + len(v)]) == v:
                    return start + len(v)
        if len(self.name) >= 4:
            for i, word in enumerate(said[:max(4, len(self.greeting) + 2)]):
                if word in self.name_forms:
                    return i + 1
        g = len(self.greeting)
        if len(said) > g and all(self._greets(said[i], w) for i, w in enumerate(self.greeting)):
            heard = said[g]
            if heard in self.lookalikes or (
                len(self.name) >= 5 and slips(heard, self.name) <= 2
            ):
                return g + 1
        return 0

    def which(self, text):
        """What in this wake word [text] woke: ("variant", v), ("lookalike",
        w), ("name", None) — or None when it does not."""
        if not self.ends(text):
            return None
        said = words(text)
        for v in self.variants:
            for start in (0, 1):
                if tuple(said[start:start + len(v)]) == v:
                    return ("variant", v)
        g = len(self.greeting)
        if len(said) > g and said[g] in self.lookalikes:
            return ("lookalike", said[g])
        return ("name", None)

    def without(self, kind, item):
        """A copy without one learned lookalike or variant."""
        data = self.to_json()
        if kind == "lookalike":
            data["lookalikes"] = [w for w in data["lookalikes"] if w != item]
        elif kind == "variant":
            data["variants"] = [v for v in data["variants"] if tuple(words(v)) != tuple(item)]
        return WakeWord.from_json(data)


def learnable(said):
    """Whether a run of words is distinctive enough to wake the panel."""
    if not said or len(said) > 5:
        return False
    # Something in it that is neither ordinary nor a command: "hey next"
    # would fire whenever "next" was said after a "hey".
    meaningful = [w for w in said if w not in COMMON and w not in COMMANDS]
    if not meaningful:
        return False
    return len(said) > 1 or len(said[0]) >= 4


def learn(wake, heard):
    """[wake], with what it missed in [heard] learned.

    [heard] is everything the recognisers made of the phrase being said, one
    text each. A text that wakes it already teaches nothing. One that starts
    with the greeting and then says something else for the name gives a
    lookalike; anything else, if it is distinctive, is kept whole.
    """
    data = wake.to_json()
    lookalikes, variants = set(data["lookalikes"]), list(data["variants"])
    g = len(wake.greeting)
    for text in heard:
        if wake.ends(text):
            continue
        said = words(text)
        if not said:
            continue
        if (
            g
            and len(said) == g + 1
            and all(wake._greets(said[i], w) for i, w in enumerate(wake.greeting))
        ):
            name = said[g]
            if name not in COMMON and name not in COMMANDS and len(name) >= 3:
                lookalikes.add(name)
                continue
        if learnable(said):
            joined = " ".join(said)
            if joined not in variants:
                variants.append(joined)
    data["lookalikes"], data["variants"] = sorted(lookalikes), variants
    return WakeWord.from_json(data)


def forgive(wake, sentences):
    """[wake] without whatever it learned that wakes it in [sentences] —
    things said in a room that are not the wake words. Gives back the new
    wake word and what the sentences set off that could not be unlearned:
    the phrase itself, said in passing."""
    unforgiven = []
    for sentence in sentences:
        while True:
            fired = wake.which(sentence)
            if fired is None:
                break
            kind, item = fired
            if kind == "name":
                unforgiven.append(sentence)
                break
            wake = wake.without(kind, item)
    return wake, unforgiven


def assess(phrase):
    """What might go wrong with [phrase] as a wake word, as (level, text):
    level "bad" stops it being chosen, "warn" is said and left to them."""
    said = words(phrase)
    if not said:
        return [("bad", "Type the words you'll say to wake the panel.")]
    found = []
    if any(w.isdigit() for w in said):
        found.append(("bad", "Spell numbers out as words — they're heard as words."))
    if len(said) > 4:
        found.append(("bad", "Four words at most. Long wake words are tiring to say."))
    name = said[-1]
    if name in COMMANDS:
        found.append(("bad", f"“{name}” is already a command, so it would fire on its own."))
    elif name in COMMON:
        found.append(("bad", f"“{name}” is too common: the panel would wake whenever it's said."))
    total = sum(syllables(w) for w in said)
    if total < 3:
        found.append(("warn", "Short wake words are easily misheard and set off by accident. "
                              "Three or more syllables work best."))
    if syllables(name) < 2 and len(said) == 1:
        found.append(("warn", "A one-syllable name on its own is hard to pick out of a room."))
    if len(said) == 1 and len(name) < 6:
        found.append(("warn", "A greeting in front (“hey …”) makes a short name more reliable."))
    return found


# What the installer offers, with why each is a good wake word.
SUGGESTIONS = [
    ("hey canvas", "the panel's own name; works out of the box"),
    ("computer", "three clear syllables, as on the starship"),
    ("hey jarvis", "short, and unlike anything said in a kitchen"),
    ("okay house", "says what it's for"),
    ("hey panel", "plain, and two clear words"),
]

# Read aloud in the wizard: things said in a room that must not wake it.
EVERYDAY = [
    "Can you pass me the remote? It's on the table by the window.",
    "I think we should have chicken for dinner on Thursday, then go for a walk.",
]

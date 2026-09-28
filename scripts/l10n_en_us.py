#!/usr/bin/env python3
"""Writes assets/l10n/en-US.arb from the British source, l10n/en-GB.arb.

American spelling is mostly mechanical (colour -> color), so a word list does
that; where the wording itself differs (a bin day is a trash day), whole
strings are given by key below. Only strings that come out different are
written: the rest fall back to the British text, which is the same.

Run after regenerating the source pack:

    python3 scripts/l10n_en_us.py
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# British -> American, whole words, matched case-insensitively and written
# back in the original's case.
SPELLING = {
    "colour": "color", "colours": "colors", "coloured": "colored",
    "favourite": "favorite", "favourites": "favorites",
    "centre": "center", "centres": "centers", "centred": "centered",
    "metre": "meter", "metres": "meters", "litre": "liter", "litres": "liters",
    "grey": "gray", "greyed": "grayed",
    "behaviour": "behavior", "neighbour": "neighbor", "neighbours": "neighbors",
    "honour": "honor", "flavour": "flavor", "humour": "humor",
    "licence": "license", "licences": "licenses",
    "defence": "defense", "offence": "offense",
    "programme": "program", "programmes": "programs",
    "catalogue": "catalog", "dialogue": "dialog",
    "travelled": "traveled", "travelling": "traveling",
    "cancelled": "canceled", "cancelling": "canceling",
    "labelled": "labeled", "labelling": "labeling",
    "modelled": "modeled", "signalled": "signaled", "dialled": "dialed",
    "tyre": "tire", "tyres": "tires", "aluminium": "aluminum",
    "jewellery": "jewelry", "pyjamas": "pajamas",
    "whilst": "while", "amongst": "among",
    "learnt": "learned", "spelt": "spelled",
    "mum": "mom", "maths": "math",
    "analyse": "analyze", "analysed": "analyzed",
    "recognise": "recognize", "recognises": "recognizes",
    "recognised": "recognized",
    "organise": "organize", "organised": "organized",
    "customise": "customize", "customised": "customized",
    "minimise": "minimize", "maximise": "maximize",
    "prioritise": "prioritize", "summarise": "summarize",
    "apologise": "apologize", "realise": "realize",
    "optimise": "optimize", "optimised": "optimized",
    "synchronise": "synchronize", "synchronised": "synchronized",
    "authorise": "authorize", "authorised": "authorized",
    "personalise": "personalize", "personalised": "personalized",
    "favour": "favor",
}

# Where the wording, not just the spelling, differs. By key.
PHRASES = {
    "widget.bins.name": "Trash day",
    "widget.bins.description":
        "Which trash and recycling go out next and when. From the evening "
        "before it says to put them out; tap it once they are out.",
    "widget.bins.option.bins.label": "Trash and recycling",
    "widget.bins.option.bins.addLabel": "Add a collection",
    "widget.bins.option.bins.help":
        "One row per collection. The date is any one pickup of it — from "
        "the city’s schedule — written as 2026-10-01.",
    "widget.bins.option.speakAt.help":
        "A time the evening before, like 7:00 PM or 19:00, to hear what goes "
        "out. Leave empty for no reminder.",
    "widget.countdowns.description":
        "Days until the things you are looking forward to — birthdays, "
        "vacations, trips. The soonest first.",
    "widget.countdowns.option.bankHolidays.label": "UK bank holidays",
}


def american(text: str) -> str:
    def swap(m: re.Match) -> str:
        word = m.group(0)
        us = SPELLING.get(word.lower())
        if us is None:
            return word
        if word.isupper():
            return us.upper()
        if word[0].isupper():
            return us[0].upper() + us[1:]
        return us

    return re.sub(r"[A-Za-z]+", swap, text)


def main() -> None:
    source = json.loads((ROOT / "l10n/en-GB.arb").read_text())
    out = {
        "@@locale": "en-US",
        "@@x-ai-created": True,
        "@@x-translator":
            "Claude (AI), from the British source, with "
            "scripts/l10n_en_us.py — not yet checked by a person.",
    }
    for key, text in source.items():
        if key.startswith("@"):
            continue
        us = PHRASES.get(key) or american(text)
        if us != text:
            out[key] = us
    path = ROOT / "assets/l10n/en-US.arb"
    path.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n")
    print(f"{path.relative_to(ROOT)}: {len(out) - 3} strings differ")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Checks language packs against the British source, l10n/en-GB.arb.

    python3 scripts/l10n_check.py            # every pack in assets/l10n
    python3 scripts/l10n_check.py fr de      # just these

For each pack: valid JSON, marked as AI-created or not, no keys the app
lacks, every {placeholder} kept by name, and braces balanced. Reports the
keys still untranslated (fine — they fall back to British English), and
exits non-zero if anything is wrong.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def placeholders(s: str) -> set:
    return set(re.findall(r"\{\s*(\w+)\s*[,}]", s))


def balanced(s: str) -> bool:
    depth = 0
    for c in s:
        depth += (c == "{") - (c == "}")
        if depth < 0:
            return False
    return depth == 0


def check(path: Path, source: dict) -> list:
    problems = []
    try:
        pack = json.loads(path.read_text())
    except Exception as e:
        return [f"not valid JSON: {e}"]
    if "@@x-ai-created" not in pack:
        problems.append('missing "@@x-ai-created"')
    if pack.get("@@locale") != path.stem:
        problems.append(f'"@@locale" should be "{path.stem}"')
    for key, text in pack.items():
        if key.startswith("@"):
            continue
        if key not in source:
            problems.append(f"{key}: not in the app")
            continue
        if not isinstance(text, str) or not text.strip():
            problems.append(f"{key}: empty")
            continue
        if not balanced(text):
            problems.append(f"{key}: unbalanced braces")
        if placeholders(text) != placeholders(source[key]):
            problems.append(
                f"{key}: placeholders {sorted(placeholders(text))} should be "
                f"{sorted(placeholders(source[key]))}"
            )
    missing = [k for k in source if not k.startswith("@") and k not in pack]
    print(
        f"{path.relative_to(ROOT)}: {len(pack) - sum(k.startswith('@') for k in pack)} "
        f"translated, {len(missing)} untranslated, {len(problems)} problems"
    )
    if missing and len(missing) <= 20:
        for k in missing:
            print(f"  untranslated: {k}")
    return problems


def main() -> int:
    source = json.loads((ROOT / "l10n/en-GB.arb").read_text())
    codes = sys.argv[1:]
    paths = (
        [ROOT / f"assets/l10n/{c}.arb" for c in codes]
        if codes
        else sorted((ROOT / "assets/l10n").glob("*.arb"))
    )
    bad = 0
    for p in paths:
        for problem in check(p, source):
            print(f"  PROBLEM {problem}")
            bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

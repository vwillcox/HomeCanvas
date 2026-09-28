#!/usr/bin/env python3
"""Marks a web page's English for translation — the HTML twin of
l10n_wrap.py.

    python3 scripts/l10n_wrap_html.py list  assets/dashboard/notes.html
    python3 scripts/l10n_wrap_html.py apply assets/dashboard/notes.html \\
        web.notes [--skip 3,7] [--only 1,2]

Candidates are numbered: element text in the markup (given a data-t
attribute, which i18n.js translates where it stands) and double-quoted
strings in the page's scripts (wrapped as t("key", "English")). Skip any
that are not on screen — ids, classes, keys, API paths.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from l10n_wrap import slug  # noqa: E402

TAG = re.compile(
    r"<(label|button|option|p|span|small|h1|h2|h3|div|output|strong|b|a|li|th|td|title|legend|summary)"
    r"(\s[^<>]*)?>([^<]*[A-Za-z]{2}[^<]*)<"
)
JS_STR = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


def words(text: str) -> bool:
    t = text.strip()
    if t == "use strict" or re.fullmatch(r"[A-Z]{2,7}", t):
        return False  # a directive, an HTTP method
    if not re.search(r"[A-Za-z]{2}", t):
        return False
    if re.fullmatch(r"[\w\-./:#?=&%\[\]*]+", t) and not re.search(r"[A-Z]", t):
        return False
    return bool(re.search(r"[A-Z]", t) or " " in t)


def js_ok(src: str, start: int, end: int) -> bool:
    before = src[max(0, start - 50):start]
    if re.search(r"""\bt\(\s*["'][\w.\-]+["']\s*,\s*$""", src[max(0, start - 120):start]):
        return False  # the English of a t() call already
    after = src[end:end + 3]
    if re.match(r"\s*:", after):
        return False  # an object key
    if re.search(
        r"(querySelector(All)?|getElementById|classList\.\w+|addEventListener|"
        r"createElement|setAttribute|getAttribute|removeAttribute|dataset\.\w+\s*=|"
        r"api\.\w+|fetch|localStorage\.\w+|\bt|fillIn|RegExp|===?|!==?|\bcase|"
        r"\.type\s*=|\.className\s*=|\.style\.\w+\s*=|\.cssText\s*=|\.id\s*=|"
        r"\.value\s*=|\.key\s*=|\.includes|\.startsWith|\.endsWith|\.split|"
        r"\.replace(All)?|\.join|\.match|\bnew\s+Intl\.\w+)\s*\(?\s*$",
        before,
    ):
        return False
    return True


def candidates(src: str):
    """(kind, start, end, text) for each, in page order."""
    out = []
    head_end = src.find("<script")
    markup = src if head_end < 0 else src[:head_end]
    for m in TAG.finditer(markup):
        attrs = m.group(2) or ""
        text = m.group(3)
        if "data-t=" in attrs or not words(text):
            continue
        out.append(("tag", m.start(), m.end(), text.strip(), m))
    for sm in re.finditer(r"<script>(.*?)</script>", src, re.S):
        base = sm.start(1)
        code = sm.group(1)
        # Skip comments.
        masked = re.sub(r"/\*.*?\*/", lambda x: " " * len(x.group(0)), code, flags=re.S)
        masked = re.sub(r"(?<![:\\])//[^\n]*", lambda x: " " * len(x.group(0)), masked)
        for m in JS_STR.finditer(masked):
            text = m.group(1)
            if not words(text) or "<" in text:
                continue
            if not js_ok(masked, m.start(), m.end()):
                continue
            out.append(("js", base + m.start(), base + m.end(), text, None))
    out.sort(key=lambda c: c[1])
    return out


def main():
    mode, path = sys.argv[1], Path(sys.argv[2])
    src = path.read_text()
    cands = candidates(src)
    if mode == "list":
        for n, (kind, start, _, text, _) in enumerate(cands, 1):
            line = src.count("\n", 0, start) + 1
            print(f"{n:4} {kind:3} L{line:<5} {text[:100]}")
        return
    prefix = sys.argv[3]
    args = sys.argv[4:]
    skip, only = set(), None
    for a, b in zip(args, args[1:] + [""]):
        if a == "--skip":
            skip = {int(x) for x in b.split(",") if x}
        if a == "--only":
            only = {int(x) for x in b.split(",") if x}
    used = {}
    chosen = [c for n, c in enumerate(cands, 1)
              if n not in skip and (only is None or n in only)]
    for kind, start, end, text, m in reversed(chosen):
        english = re.sub(r"\s+", " ", text)
        key = f"{prefix}.{slug(english)}"
        k = 2
        while key in used and used[key] != english:
            key = f"{prefix}.{slug(english)}{k}"
            k += 1
        used[key] = english
        if kind == "tag":
            tag_open = src[start:end]
            name_end = start + 1 + len(m.group(1))
            src = src[:name_end] + f' data-t="{key}"' + src[name_end:]
        else:
            src = src[:start] + f't("{key}", "{text}")' + src[end:]
    path.write_text(src)
    print(f"{path}: marked {len(chosen)} strings under {prefix}.")


if __name__ == "__main__":
    main()

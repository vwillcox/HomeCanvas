#!/usr/bin/env python3
"""Wraps a Dart file's on-screen English in tr(), for translation.

    python3 scripts/l10n_wrap.py list  lib/services/weather_service.dart
    python3 scripts/l10n_wrap.py apply lib/services/weather_service.dart \\
        weather [--skip 3,7,12] [--only 1,2]

`list` numbers every candidate string: single-quoted literals that look like
words (a capital, or a space), outside comments, not map keys, not compared,
not already translated. Adjacent literals ('a ' 'b') count as one. `apply`
wraps them — all, or --only some, less --skip — as tr('<prefix>.<slug>',
'English', {...}), turning ${expr} and $name into {name} placeholders. It
takes the `const` off anything the new call now sits in, as far as it can
see; `flutter analyze` finds the rest.

A string that is not on screen (an id, a log line, a key sent to a server)
must be skipped: judge each from the list.
"""

import re
import sys
from pathlib import Path

LITERAL = re.compile(r"'(?:[^'\\\n]|\\.)*'")


def scan(src: str):
    """Yields (start, end, [literal spans]) for each run of adjacent
    single-quoted literals outside comments, raw strings and triple quotes."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            i = src.find("\n", i)
            i = n if i < 0 else i
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i)
            i = n if j < 0 else j + 2
            continue
        if src.startswith("'''", i) or src.startswith('"""', i):
            j = src.find(src[i:i + 3], i + 3)
            i = n if j < 0 else j + 3
            continue
        if c == '"':
            m = re.compile(r'"(?:[^"\\\n]|\\.)*"').match(src, i)
            i = m.end() if m else i + 1
            continue
        if c == "r" and i + 1 < n and src[i + 1] in "'\"" and not (src[i - 1].isalnum() or src[i - 1] == "_"):
            m = re.compile(r"r'[^'\n]*'|r\"[^\"\n]*\"").match(src, i)
            i = m.end() if m else i + 1
            continue
        if c == "'":
            spans = []
            j = i
            while True:
                m = LITERAL.match(src, j)
                if not m:
                    break
                spans.append((m.start(), m.end()))
                k = m.end()
                while k < n and src[k] in " \t\n":
                    k += 1
                if k < n and src[k] == "'" and not src.startswith("'''", k):
                    j = k
                    continue
                break
            if not spans:
                i += 1
                continue
            yield spans[0][0], spans[-1][1], spans
            i = spans[-1][1]
            continue
        i += 1


def body(src, spans):
    return "".join(src[a + 1:b - 1] for a, b in spans)


def looks_like_words(text: str) -> bool:
    plain = re.sub(r"\$\{[^}]*\}|\$\w+", "", text)
    if not re.search(r"[A-Za-z]{2}", plain):
        return False
    if re.fullmatch(r"[a-z0-9_.\-/:]+", plain):  # ids, keys, paths
        return False
    if re.search(r"https?://|\.dart|\.json|\.png|\.svg|^[#/]", plain):
        return False
    return bool(re.search(r"[A-Z]", plain) or " " in plain.strip())


def context_ok(src, start, end) -> bool:
    before = src[max(0, start - 40):start]
    after = src[end:end + 3]
    line_start = src.rfind("\n", 0, start) + 1
    line = src[line_start:src.find("\n", end) if src.find("\n", end) >= 0 else len(src)]
    if re.match(r"\s*(import|export|part|library)\b", line):
        return False
    if re.search(r"\b(tr|debugPrint|print|RegExp|Uri\.parse|Key|ValueKey|assert|throw\s+\w*\(?)\s*\(\s*$", before):
        return False
    if re.search(r"(==|!=|\bcase|\.contains\(|\.startsWith\(|\.endsWith\(|\.split\(|\[|\.option\(|\.rows\(|headers:|'[\w-]+':\s*)\s*$", before):
        return False
    if re.match(r"\s*:(?!:)", after) and not re.search(r"\?\s*[^:]*$", before):
        return False  # a map key
    if re.match(r"\s*(==|!=)", after):
        return False
    return True


# Text inside these is translated by key from the widget's description
# (widget.<type>.option.<key>…), so it must stay a plain literal.
DESCRIPTORS = {"WidgetOption", "DashboardWidgetType", "PreviewLine"}


def enclosing_calls(src: str, pos: int):
    """The names of the calls [pos] sits inside, innermost first."""
    names, depth, i = [], 0, pos - 1
    while i >= 0:
        ch = src[i]
        if ch in ")]}":
            depth += 1
        elif ch in "([{":
            if depth:
                depth -= 1
            elif ch == "(":
                m = re.search(r"([A-Za-z_][\w.]*)\s*(?:<[^()]*>)?\s*$", src[max(0, i - 60):i])
                if m:
                    names.append(m.group(1).split(".")[-1])
        i -= 1
    return names


def candidates(src):
    out = []
    for start, end, spans in scan(src):
        text = body(src, spans)
        # An interpolation with quotes inside it ('${x.padLeft(2, '0')}')
        # isn't parsed whole; leave it for a hand.
        if text.count("${") != text.count("}") and "${" in text:
            continue
        if not (looks_like_words(text) and context_ok(src, start, end)):
            continue
        calls = enclosing_calls(src, start)
        if DESCRIPTORS & set(calls):
            continue
        # Already translated, or not for the screen.
        if calls and calls[0] in {"tr", "debugPrint", "print", "RegExp", "ValueKey", "Key"}:
            continue
        # Only constants may go here: a parameter's default, an enum value.
        # These need translating where they are used, by hand.
        before = src[max(0, start - 60):start]
        if re.search(r"\bthis\.\w+\s*=\s*$|[{,(]\s*(required\s+)?[\w<>?]+\s+\w+\s*=\s*$", before):
            continue
        if inside_enum(src, start):
            continue
        out.append((start, end, spans, text))
    return out


def slug(text: str) -> str:
    plain = re.sub(r"\$\{[^}]*\}|\$\w+|\{[^}]*\}", " ", text)
    plain = re.sub(r"\\.", " ", plain)
    words = re.findall(r"[A-Za-z0-9]+", plain)[:5]
    if not words:
        return "text"
    first, rest = words[0].lower(), [w.capitalize() for w in words[1:]]
    return first + "".join(rest)


def placeholder_name(expr: str, used: dict) -> str:
    ident = re.findall(r"[A-Za-z_]\w*", expr)
    name = ident[-1] if ident else "value"
    if name in ("toString", "round", "length", "abs", "toStringAsFixed", "isEmpty", "join"):
        name = ident[-2] if len(ident) > 1 else "value"
    base, k = name, 2
    while name in used and used[name] != expr:
        name = f"{base}{k}"
        k += 1
    used[name] = expr
    return name


def convert(text: str):
    """English with {placeholders}, and the args map's source."""
    used = {}

    def sub_braced(m):
        return "{" + placeholder_name(m.group(1), used) + "}"

    def sub_plain(m):
        return "{" + placeholder_name(m.group(1), used) + "}"

    english = re.sub(r"\$\{([^}]*)\}", sub_braced, text)
    english = re.sub(r"\$([A-Za-z_]\w*)", sub_plain, english)
    args = ", ".join(f"'{k}': {v}" for k, v in used.items())
    return english, (f"{{{args}}}" if args else None)


def uncons(src: str, pos: int) -> str:
    """Takes `const` off every expression [pos] sits inside, out to the
    edge of its statement — an outer `const [...]` makes all of it constant
    — and turns a constant declaration it is part of (`static const x =`)
    into `final`, since a call is never constant."""
    cuts = []  # (index of "const", replacement)
    depth, i = 0, pos - 1
    while i > 0:
        ch = src[i]
        if ch in ")]}":
            depth += 1
        elif ch in "([{":
            if depth:
                depth -= 1
            else:
                head = src[max(0, i - 120):i]
                prev = head.rstrip()[-1:] if head.rstrip() else ""
                if ch == "{" and prev not in "=,([:?>" and not head.rstrip().endswith("const"):
                    break  # a block or a class body: the statement's edge
                m = re.search(r"\bconst\s+(?:[\w.<>?, ]*)?$", head)
                if m:
                    cuts.append((max(0, i - 120) + m.start(), ""))
        elif ch == ";" and depth == 0:
            break
        elif depth == 0 and src.startswith("=", i) and src[i - 1:i] not in "=!<>" and src[i + 1:i + 2] != "=":
            # The declaration this expression is the value of.
            line_start = src.rfind("\n", 0, i) + 1
            decl = src[line_start:i]
            m = re.search(r"\bconst\b", decl)
            if m and re.match(r"\s*(static\s+)?const\s", decl):
                cuts.append((line_start + m.start(), "final "))
            break
        i -= 1
    for at, repl in sorted(set(cuts), reverse=True):
        src = src[:at] + repl + src[at + len("const "):]
    return src


def inside_enum(src: str, pos: int) -> bool:
    """Whether [pos] is among an enum's values, where only constants go."""
    headers = list(re.finditer(r"\benum\s+\w+[^{;]*\{", src[:pos]))
    if not headers:
        return False
    depth = 0
    for ch in src[headers[-1].end():pos]:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth < 0:
                return False  # the enum closed before [pos]
        elif ch == ";" and depth == 0:
            return False  # past its values, into its members
    return True


TR_CALL = re.compile(r"\btr\(\s*'([\w.\-]+)'\s*,\s*'((?:[^'\\]|\\.)*)'")


def existing_keys() -> dict:
    out = {}
    for f in Path("lib").rglob("*.dart"):
        for m in TR_CALL.finditer(f.read_text()):
            out.setdefault(m.group(1), m.group(2))
    return out


def call_text(src, start, key, english, argmap) -> str:
    """The tr() call, on one line if it fits in 80 columns with what
    precedes it, else one argument to a line as dart format would."""
    line_start = src.rfind("\n", 0, start) + 1
    line_end = src.find("\n", start)
    before = src[line_start:start]
    one = f"tr('{key}', '{english}'" + (f", {argmap}" if argmap else "") + ")"
    rest = src[start:line_end if line_end >= 0 else len(src)]
    after = rest[rest.find("'", 1) + 1:] if rest.startswith("'") else ""
    # Split only a call that starts its own line; mid-line, a split reads
    # worse than a long line.
    if len(before) + len(one) + 2 <= 80 or before.strip():
        return one
    indent = re.match(r"\s*", before).group(0)
    inner = indent + "  "
    parts = [f"'{key}'", f"'{english}'"] + ([argmap] if argmap else [])
    return "tr(\n" + "".join(f"{inner}{p},\n" for p in parts) + f"{indent})"


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    mode, path = sys.argv[1], Path(sys.argv[2])
    src = path.read_text()
    cands = candidates(src)
    if mode == "list":
        for n, (start, end, spans, text) in enumerate(cands, 1):
            line = src.count("\n", 0, start) + 1
            print(f"{n:4} L{line:<5} {text[:110]}")
        return
    prefix = sys.argv[3]
    args = sys.argv[4:]
    skip, only = set(), None
    for a, b in zip(args, args[1:] + [""]):
        if a == "--skip":
            skip = {int(x) for x in b.split(",") if x}
        if a == "--only":
            only = {int(x) for x in b.split(",") if x}
    chosen = [
        c for n, c in enumerate(cands, 1)
        if n not in skip and (only is None or n in only)
    ]
    # Every key already used in the app, so the same English under the same
    # prefix reuses its key and different English never takes one.
    keys = existing_keys()
    by_english = {(k.rsplit(".", 1)[0], e): k for k, e in keys.items()}
    # One at a time from the end, finding each afresh: taking a `const` off
    # moves everything after it, so positions found up front go stale.
    targets = [(src.count("\n", 0, s) + 1, text) for s, _, _, text in chosen]
    for line, text in reversed(targets):
        found = [
            c for c in candidates(src)
            if c[3] == text and src.count("\n", 0, c[0]) + 1 == line
        ]
        if not found:
            print(f"  lost track of L{line} {text[:50]!r}; wrap it by hand")
            continue
        start, end, spans, _ = found[0]
        english, argmap = convert(text)
        key = by_english.get((prefix, english))
        if key is None:
            base = f"{prefix}.{slug(english)}"
            key, k = base, 2
            while key in keys and keys[key] != english:
                key = f"{base}{k}"
                k += 1
            keys[key] = english
            by_english[(prefix, english)] = key
        src = src[:start] + call_text(src, start, key, english, argmap) + src[end:]
        src = uncons(src, start)
    if "l10n/l10n.dart" not in src and chosen:
        depth = len(path.relative_to("lib").parts) - 1
        imp = "import '" + "../" * depth + "l10n/l10n.dart';"
        lines = src.split("\n")
        imports = [i for i, l in enumerate(lines) if l.startswith("import ")]
        if imports:
            lines.insert(imports[-1] + 1, imp)
        else:
            # After `library;` if there is one, else at the very top.
            lib = [i for i, l in enumerate(lines) if l.startswith("library")]
            at = lib[0] + 1 if lib else 0
            lines[at:at] = ["", imp, ""] if lib else [imp, ""]
        src = "\n".join(lines)
    path.write_text(src)
    print(f"{path}: wrapped {len(chosen)} strings under {prefix}.")


if __name__ == "__main__":
    main()

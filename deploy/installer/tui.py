"""The installer's screens, drawn in the terminal with curses.

A frame like the panel's LCARS theme — a bar across the top, a rail of the
steps down the left — and a handful of things to put in it: a message, a
choice, a checklist, a line to type in, a running task. Each runs until it
has an answer and gives it back, or BACK when Esc was pressed, so the
installer can be written as a list of questions.

Standard library only, and every colour has a plain fallback: it has to work
in the Pi's own terminal, over SSH, and in a bare console.
"""

import curses
import locale
import os
import sys
import textwrap
import time

BACK = object()

MIN_W, MIN_H = 80, 24
RAIL = 24  # width of the left rail, with its gap

# Colour pairs.
BAR, RAILC, ACCENT, DIM, OK, WARN, BAD, PICK, BLUE, PEACH, TEXT = range(1, 12)


def run(main):
    """Runs [main](ui) inside curses, putting the terminal back however it
    ends."""
    locale.setlocale(locale.LC_ALL, "")
    os.environ.setdefault("ESCDELAY", "25")
    use_known_terminal()
    return curses.wrapper(lambda scr: main(UI(scr)))


def use_known_terminal():
    """Falls back to a terminal this machine knows when it has no entry for
    the one in TERM — kitty, ghostty and wezterm over SSH set their own, which
    a Pi has never heard of."""
    fd = sys.__stdout__.fileno()
    for term in (os.environ.get("TERM"), "xterm-256color", "xterm", "vt100"):
        if not term:
            continue
        try:
            curses.setupterm(term=term, fd=fd)
        except curses.error:
            continue
        os.environ["TERM"] = term
        return


def nearest_256(r, g, b):
    """The xterm colour nearest (r, g, b): from its 6×6×6 cube or its greys."""
    levels = [0, 95, 135, 175, 215, 255]

    def step(v):
        return min(range(6), key=lambda i: abs(levels[i] - v))

    cube = (step(r), step(g), step(b))
    cube_rgb = [levels[i] for i in cube]
    grey = min(23, max(0, round((sum((r, g, b)) / 3 - 8) / 10)))
    grey_v = 8 + grey * 10

    def far(c):
        return sum((x - y) ** 2 for x, y in zip(c, (r, g, b)))

    if far((grey_v,) * 3) < far(cube_rgb):
        return 232 + grey
    return 16 + 36 * cube[0] + 6 * cube[1] + cube[2]


class UI:
    def __init__(self, scr):
        self.scr = scr
        self.stages = []
        self.stage = 0
        self.title = "HOMECANVAS SETUP"
        curses.curs_set(0)
        scr.keypad(True)
        self._colours()

    # ---- colours ---------------------------------------------------------------

    def _colours(self):
        if not curses.has_colors():
            self.colour = lambda pair: curses.A_REVERSE if pair in (BAR, RAILC, PICK) else 0
            return
        curses.start_color()
        try:
            curses.use_default_colors()
            bg = -1
        except curses.error:
            bg = curses.COLOR_BLACK
        many = curses.COLORS >= 256
        orange = 208 if many else curses.COLOR_YELLOW
        lilac = 183 if many else curses.COLOR_MAGENTA
        blue = 111 if many else curses.COLOR_CYAN
        peach = 216 if many else curses.COLOR_YELLOW
        grey = 244 if many else curses.COLOR_WHITE
        black = curses.COLOR_BLACK
        pairs = {
            BAR: (black, orange), RAILC: (black, lilac), ACCENT: (orange, bg),
            DIM: (grey, bg), OK: (curses.COLOR_GREEN, bg),
            WARN: (curses.COLOR_YELLOW, bg), BAD: (curses.COLOR_RED, bg),
            PICK: (black, peach), BLUE: (blue, bg), PEACH: (peach, bg),
            TEXT: (-1 if bg == -1 else curses.COLOR_WHITE, bg),
        }
        for n, (fg, b) in pairs.items():
            curses.init_pair(n, fg, b)
        self.colour = curses.color_pair

    def truecolour_pair(self, hex_colour, n):
        """A pair with [hex_colour] as its background, for a theme's
        swatches: the nearest of the terminal's 256 colours (or 8). Not the
        colour itself — redefining the palette is ignored by tmux and by
        many terminals, and would change it under everything else."""
        if not curses.has_colors() or curses.COLORS < 8:
            return 0
        r, g, b = (int(hex_colour.lstrip("#")[-6:][i:i + 2], 16) for i in (0, 2, 4))
        if curses.COLORS >= 256:
            slot = nearest_256(r, g, b)
        else:
            slot = (1 if r > 127 else 0) | (2 if g > 127 else 0) | (4 if b > 127 else 0)
        pair = 40 + n % 80
        curses.init_pair(pair, curses.COLOR_BLACK, slot)
        return curses.color_pair(pair)

    # ---- drawing ---------------------------------------------------------------

    @property
    def size(self):
        return self.scr.getmaxyx()

    def put(self, y, x, text, attr=0, width=None):
        h, w = self.size
        if y < 0 or y >= h or x >= w:
            return
        room = w - x - (1 if y == h - 1 else 0)
        if width is not None:
            room = min(room, width)
        if room <= 0:
            return
        try:
            self.scr.addstr(y, x, text[:room], attr)
        except curses.error:
            pass

    def frame(self, heading, keys="↑↓ move · Enter choose · Esc back · q quit"):
        """Clears the screen and draws the bar, the rail and [heading];
        gives back (top, left, width, height) of the space inside."""
        self.scr.erase()
        h, w = self.size
        if h < MIN_H or w < MIN_W:
            self.put(0, 0, f"Make this window at least {MIN_W}×{MIN_H}", self.colour(WARN))
            self.put(1, 0, f"(it is {w}×{h} now)")
            return None
        bar = self.colour(BAR) | curses.A_BOLD
        # The bar: an end cap, the title, and the step on the right.
        self.put(0, 0, "  ", bar)
        self.put(0, 3, f" {self.title} ", self.colour(ACCENT) | curses.A_BOLD)
        start = 5 + len(self.title)
        step = f" {self.stage + 1}/{len(self.stages)} " if self.stages else ""
        self.put(0, start, " " * max(0, w - start - len(step) - 1), bar)
        self.put(0, w - len(step) - 1, step, self.colour(PICK) | curses.A_BOLD)
        # The rail: each step as a block, the current one picked out.
        rail = self.colour(RAILC)
        self.put(1, 0, " " * (RAIL - 2), bar)
        for i, name in enumerate(self.stages):
            y = 2 + i
            if y >= h - 2:
                break
            if i < self.stage:
                label, attr = f" ✓ {name}", self.colour(BLUE)
            elif i == self.stage:
                label, attr = f" ▶ {name.upper()}", self.colour(PICK) | curses.A_BOLD
            else:
                label, attr = f"   {name}", self.colour(DIM)
            self.put(y, 0, label.ljust(RAIL - 2), attr)
        for y in range(2 + len(self.stages), h - 1):
            self.put(y, 0, "  ", rail)
        self.put(h - 2, 0, " " * (RAIL - 2), bar)
        # The heading, and the keys along the bottom.
        self.put(2, RAIL, heading.upper(), self.colour(ACCENT) | curses.A_BOLD)
        self.put(3, RAIL, "━" * min(len(heading) + 4, w - RAIL - 1), self.colour(ACCENT))
        self.put(h - 1, 0, " " + keys, self.colour(DIM))
        return 5, RAIL, w - RAIL - 2, h - 7

    def wrap(self, text, width):
        out = []
        for para in text.split("\n"):
            # A bullet's later lines line up under its words.
            indent = "  " if para.startswith(("• ", "✓ ", "✗ ", "! ")) else ""
            out.extend(textwrap.wrap(para, width, subsequent_indent=indent) or [""])
        return out

    def paragraph(self, y, x, width, text, attr=0, limit=None):
        """[text], wrapped, from (y, x); gives back the row after it."""
        lines = self.wrap(text, width)
        if limit is not None:
            lines = lines[:limit]
        for line in lines:
            self.put(y, x, line, attr)
            y += 1
        return y

    def key(self, timeout=None):
        # Taken back each time: a program run meanwhile may have put the
        # terminal back to echoing and waiting for lines.
        curses.noecho()
        curses.cbreak()
        self.scr.timeout(-1 if timeout is None else int(timeout * 1000))
        try:
            k = self.scr.get_wch()
        except curses.error:
            return None
        except KeyboardInterrupt:
            return "\x03"
        if k == curses.KEY_RESIZE:
            return "resize"
        return k

    def is_back(self, k):
        return k in ("\x1b", curses.KEY_LEFT) or k == 27

    def is_enter(self, k):
        return k in ("\n", "\r", curses.KEY_ENTER, 10, 13)

    def quit_check(self, k):
        if k in ("q", "Q", "\x03"):
            if self.confirm("Quit the installer?",
                            "Nothing more will be changed. What's done so far is kept.",
                            default=1):
                raise SystemExit(1)
            return True
        return False

    # ---- things to put in it ---------------------------------------------------

    def message(self, heading, text, buttons=("Continue",), attrs=None, default=0):
        """[text] and a row of [buttons]; the index of the one pressed, or
        BACK. [text] may be a list of (line, colour) for a coloured list."""
        pick = default
        while True:
            area = self.frame(heading, "←→ choose · Enter · Esc back · q quit")
            if area is None:
                if self.key() == "\x03":
                    raise SystemExit(1)
                continue
            top, left, width, height = area
            y = top
            items = text if isinstance(text, list) else [(text, 0)]
            for line, colour in items:
                y = self.paragraph(y, left, width, line, self.colour(colour) if colour else 0,
                                   limit=max(1, top + height - 2 - y))
            # Under what they answer, not at the foot of a tall window.
            self._buttons(min(y + 1, top + height), left, buttons, pick)
            k = self.key()
            if k in (curses.KEY_RIGHT, "\t", "l") and len(buttons) > 1:
                pick = (pick + 1) % len(buttons)
            elif k in (curses.KEY_LEFT, "h") and len(buttons) > 1:
                pick = (pick - 1) % len(buttons)
            elif self.is_enter(k):
                return pick
            elif k == "\x1b":
                return BACK
            elif self.quit_check(k):
                continue

    def _buttons(self, y, x, buttons, pick):
        for i, b in enumerate(buttons):
            label = f"  {b}  "
            attr = self.colour(PICK) | curses.A_BOLD if i == pick else self.colour(RAILC)
            self.put(y, x, label, attr)
            x += len(label) + 2

    def confirm(self, heading, text, default=0):
        return self.message(heading, text, ("Yes", "No"), default=default) == 0

    def choose(self, heading, intro, options, default=0, detail=None, draw=None):
        """One of [options] — (label, note) pairs — by its index, or BACK.
        [draw](ui, index, top, left, width, height) may draw a preview of
        the highlighted one beside the list."""
        pick = max(0, min(default, len(options) - 1))
        scroll = 0
        while True:
            area = self.frame(heading)
            if area is None:
                if self.key() == "\x03":
                    raise SystemExit(1)
                continue
            top, left, width, height = area
            y = self.paragraph(top, left, width, intro, limit=4) + 1 if intro else top
            list_w = width if draw is None else min(34, width // 2)
            rows = top + height - y - 3
            scroll = min(max(scroll, pick - rows + 1), pick)
            for i, (label, note) in enumerate(options[scroll:scroll + rows]):
                n = scroll + i
                attr = self.colour(PICK) | curses.A_BOLD if n == pick else 0
                mark = "▶ " if n == pick else "  "
                self.put(y + i, left, (mark + label).ljust(list_w - 1), attr, list_w - 1)
            note = options[pick][1] if options else ""
            if draw is not None:
                draw(self, pick, y, left + list_w + 2, width - list_w - 2, rows)
            if note:
                self.paragraph(top + height - 2, left, width, note, self.colour(DIM), limit=3)
            k = self.key()
            if k in (curses.KEY_DOWN, "j"):
                pick = (pick + 1) % len(options)
            elif k in (curses.KEY_UP, "k"):
                pick = (pick - 1) % len(options)
            elif k == curses.KEY_NPAGE:
                pick = min(len(options) - 1, pick + rows)
            elif k == curses.KEY_PPAGE:
                pick = max(0, pick - rows)
            elif self.is_enter(k):
                return pick
            elif k == "\x1b":
                return BACK
            elif self.quit_check(k):
                continue

    def checklist(self, heading, intro, groups, detail=None):
        """Ticks in [groups] — (heading, [(key, label, note, ticked)]) — and
        gives back the set of keys ticked, or BACK."""
        rows_all = []
        for g, items in groups:
            rows_all.append(("group", g, None))
            for key, label, note, ticked in items:
                rows_all.append(("item", key, (label, note)))
        ticked = {key for _, items in groups for key, _, _, t in items if t}
        items_at = [i for i, r in enumerate(rows_all) if r[0] == "item"]
        if not items_at:
            return set()
        pick = items_at[0]
        scroll = 0
        keys = "↑↓ move · Space tick · a all in group · Enter done · Esc back"
        while True:
            area = self.frame(heading, keys)
            if area is None:
                if self.key() == "\x03":
                    raise SystemExit(1)
                continue
            top, left, width, height = area
            y = self.paragraph(top, left, width, intro, limit=3) + 1 if intro else top
            rows = top + height - y - 4
            scroll = min(max(scroll, pick - rows + 1), pick)
            if scroll > 0 and rows_all[scroll - 1][0] == "group" and pick - scroll + 1 < rows:
                scroll -= 1
            for i, (kind, key, extra) in enumerate(rows_all[scroll:scroll + rows]):
                n = scroll + i
                if kind == "group":
                    count = sum(1 for k in self._group_keys(rows_all, n) if k in ticked)
                    self.put(y + i, left, f"{key}  ", self.colour(BLUE) | curses.A_BOLD)
                    self.put(y + i, left + len(key) + 2, f"{count} ticked", self.colour(DIM))
                    continue
                box = "[✓]" if key in ticked else "[ ]"
                attr = self.colour(PICK) | curses.A_BOLD if n == pick else 0
                self.put(y + i, left + 2, f"{box} {extra[0]}".ljust(width - 3), attr, width - 3)
            total = len(ticked)
            self.put(top + height - 3, left, f"{total} chosen", self.colour(ACCENT))
            note = rows_all[pick][2][1]
            if detail:
                note = detail(rows_all[pick][1]) or note
            self.paragraph(top + height - 2, left, width, note or "", self.colour(DIM), limit=3)
            k = self.key()
            if k in (curses.KEY_DOWN, "j"):
                later = [i for i in items_at if i > pick]
                pick = later[0] if later else items_at[0]
            elif k in (curses.KEY_UP, "k"):
                earlier = [i for i in items_at if i < pick]
                pick = earlier[-1] if earlier else items_at[-1]
            elif k == curses.KEY_NPAGE:
                later = [i for i in items_at if i >= pick + rows]
                pick = later[0] if later else items_at[-1]
            elif k == curses.KEY_PPAGE:
                earlier = [i for i in items_at if i <= pick - rows]
                pick = earlier[-1] if earlier else items_at[0]
            elif k == " ":
                ticked ^= {rows_all[pick][1]}
            elif k in ("a", "A"):
                g = max(i for i, r in enumerate(rows_all[:pick]) if r[0] == "group")
                group = set(self._group_keys(rows_all, g))
                ticked = ticked - group if group <= ticked else ticked | group
            elif self.is_enter(k):
                return ticked
            elif k == "\x1b":
                return BACK
            elif self.quit_check(k):
                continue

    @staticmethod
    def _group_keys(rows_all, g):
        for kind, key, _ in rows_all[g + 1:]:
            if kind == "group":
                break
            yield key

    def text(self, heading, intro, label, default="", secret=False, check=None, example=""):
        """A line typed in, or BACK. [check](text) gives back a list of
        (level, message) to show as it is typed; "bad" ones stop Enter."""
        value = default
        while True:
            area = self.frame(heading, "type · Enter done · Esc back")
            if area is None:
                if self.key() == "\x03":
                    raise SystemExit(1)
                continue
            top, left, width, height = area
            y = self.paragraph(top, left, width, intro, limit=height - 8) + 1 if intro else top
            self.put(y, left, label, self.colour(ACCENT))
            shown = "•" * len(value) if secret else value
            box_w = width - 2
            self.put(y + 1, left, "▌" + (shown[-(box_w - 2):] + "▁").ljust(box_w - 1), self.colour(PICK))
            if example and not value:
                self.put(y + 2, left + 1, "e.g. " + example, self.colour(DIM))
            found = check(value) if check else []
            yy = y + 3
            for level, msg in found:
                colour = {"bad": BAD, "warn": WARN, "ok": OK}.get(level, DIM)
                mark = {"bad": "✗ ", "warn": "! ", "ok": "✓ "}.get(level, "  ")
                yy = self.paragraph(yy, left, width, mark + msg, self.colour(colour), limit=3)
            k = self.key()
            if self.is_enter(k):
                if not any(level == "bad" for level, _ in found):
                    return value.strip()
            elif k == "\x1b":
                return BACK
            elif k == "\x03":
                self.quit_check(k)
            elif k in (curses.KEY_BACKSPACE, "\x7f", "\b", 127, 8):
                value = value[:-1]
            elif k == "\x15":  # Ctrl-U: clear
                value = ""
            elif isinstance(k, str) and k.isprintable():
                value += k

    def wait(self, heading, text, seconds=None):
        """[text] with no buttons, while something happens elsewhere."""
        area = self.frame(heading, "please wait…")
        if area:
            top, left, width, _ = area
            self.paragraph(top, left, width, text)
        self.scr.refresh()
        if seconds:
            time.sleep(seconds)

    def suspend(self):
        """Hands the terminal back, for something that talks to it directly
        (sudo asking for a password). resume() takes it again."""
        curses.def_prog_mode()
        curses.endwin()

    def resume(self):
        curses.reset_prog_mode()
        self.scr.refresh()

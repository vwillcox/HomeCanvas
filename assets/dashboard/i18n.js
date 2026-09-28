/* The words of HomeCanvas's web pages — the dashboard editor, the notes
   board, the shopping list, the senders page and video sign-in — in the
   panel's language, from the same packs the panel reads. Loaded by every
   page with <script src="/i18n.js">; a page calls loadWords() once, before
   it draws anything of its own.

   Markup marked data-t="key" is translated where it stands; text built by
   script asks t(key, english). Whatever a pack lacks stays in British
   English, the language the pages are written in. */

let WORDS = {};
let LANGUAGE = "en-GB";
let LANGUAGES = [];

function t(key, english, args) {
  const s = WORDS[key] ?? english;
  return args ? fillIn(s, args) : s;
}

/* {name} from args, and {n, plural, one{…} other{…}} by the language's own
   plural rules, # standing for the number — the same forms the panel reads. */
function fillIn(s, args) {
  let out = "";
  let i = 0;
  while (i < s.length) {
    const open = s.indexOf("{", i);
    if (open < 0) { out += s.slice(i); break; }
    out += s.slice(i, open);
    let depth = 0, close = -1;
    for (let j = open; j < s.length; j++) {
      if (s[j] === "{") depth++;
      if (s[j] === "}" && --depth === 0) { close = j; break; }
    }
    if (close < 0) { out += s.slice(open); break; }
    const body = s.slice(open + 1, close);
    const m = body.match(/^\s*(\w+)\s*,\s*plural\s*,([\s\S]*)$/);
    if (m) {
      const n = Number(args[m[1]]);
      const cases = {};
      const re = /\s*(=?\w+)\s*\{/g;
      let rest = m[2], k;
      while ((k = re.exec(rest))) {
        let d = 1, j = re.lastIndex;
        for (; j < rest.length && d; j++) { if (rest[j] === "{") d++; if (rest[j] === "}") d--; }
        cases[k[1]] = rest.slice(re.lastIndex, j - 1);
        re.lastIndex = j;
      }
      const which = cases["=" + n] ?? cases[new Intl.PluralRules(LANGUAGE).select(n)] ?? cases.other ?? "";
      out += fillIn(which, args).replaceAll("#", String(n));
    } else {
      const name = body.trim();
      out += name in args ? String(args[name]) : "{" + body + "}";
    }
    i = close + 1;
  }
  return out;
}

/* Replaces an element's own words and leaves its children — a heading's
   fold arrow — where they are. */
function setOwnText(el, text) {
  const node = [...el.childNodes].find(
    n => n.nodeType === Node.TEXT_NODE && n.textContent.trim());
  if (node) node.textContent = text; else el.textContent = text;
}

function translatePage(root = document) {
  // Whole sentences with markup in them — a link, a bold word, a span the
  // page fills in — so a translation can put them where its grammar needs.
  // Only ever from the panel's own packs.
  for (const el of root.querySelectorAll("[data-t-html]")) {
    const s = WORDS[el.dataset.tHtml];
    if (s) el.innerHTML = s;
  }
  for (const el of root.querySelectorAll("[data-t]")) {
    const s = WORDS[el.dataset.t];
    if (s) setOwnText(el, s);
  }
  for (const el of root.querySelectorAll("[data-t-title]")) {
    const s = WORDS[el.dataset.tTitle];
    if (s) el.title = s;
  }
  for (const el of root.querySelectorAll("[data-t-placeholder]")) {
    const s = WORDS[el.dataset.tPlaceholder];
    if (s) el.placeholder = s;
  }
  for (const el of root.querySelectorAll("[data-t-aria]")) {
    const s = WORDS[el.dataset.tAria];
    if (s) el.setAttribute("aria-label", s);
  }
}

async function loadWords() {
  try {
    const res = await fetch("/api/strings");
    if (!res.ok) return;
    const r = await res.json();
    WORDS = r.strings || {};
    LANGUAGE = r.language || "en-GB";
    LANGUAGES = r.languages || [];
    document.documentElement.lang = LANGUAGE;
    translatePage();
  } catch {
    // An older panel: the editor stays in British English.
  }
}


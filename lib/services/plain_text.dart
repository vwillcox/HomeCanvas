import 'package:html/parser.dart' as html;

/// Text from the web as a person would read it: tags gone, HTML entities
/// decoded, and the invisible characters that come with them removed.
///
/// For headlines and summaries on the news tile, and for everything read
/// aloud — where a stray `&rsquo;` is spelt out letter by letter.
String plainText(String s) {
  var out = s;
  if (_tag.hasMatch(out)) {
    // A break or the end of a block is a gap between words; without this,
    // "one</p><p>two" would run together as "onetwo".
    out = out
        .replaceAll(_blockEnd, ' ')
        .replaceAll(_tag, '');
  }
  out = decodeEntities(out);
  return out
      .replaceAll(_oddSpaces, ' ')
      .replaceAll(_invisible, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// [plainText], then made for a voice. Written text is full of things a
/// reader's eye skips over and a voice reads out literally — "f slash four",
/// "one slash three", "aitch tee tee pee ess colon" — so each is said the way
/// a person reading it aloud would:
///
/// - a standalone "&" is "and";
/// - web addresses are "a link";
/// - f-stops are "f 1.8";
/// - simple fractions are words: "one third", "three quarters";
/// - "24/7" is "twenty-four seven", "km/h" "kilometres an hour";
/// - numbers in a date are read as numbers, not "slash";
/// - "and/or", "iOS/Android" are "and or", "iOS or Android";
/// - any slash left over is a pause, not the word "slash".
String speakable(String s) {
  var out = plainText(s).replaceAll(RegExp(r'\s+&\s+'), ' and ');
  out = out.replaceAll(_url, 'a link');
  out = out.replaceAllMapped(
    RegExp(r'\b[fF]/(\d+(?:\.\d+)?)'),
    (m) => 'f ${m[1]}',
  );
  out = out.replaceAll(RegExp(r'\b24/7\b'), 'twenty-four seven');
  _units.forEach((k, v) => out = out.replaceAll(RegExp('\\b$k\\b'), v));
  // Dates: 25/9/2026, 25/09/26 — read as the numbers they are.
  out = out.replaceAllMapped(
    RegExp(r'\b(\d{1,4})/(\d{1,2})/(\d{2,4})\b'),
    (m) => '${m[1]} ${m[2]} ${m[3]}',
  );
  out = out.replaceAllMapped(
    RegExp(r'(?<![\d/.])(\d{1,2})/(\d{1,2})(?![\d/])'),
    (m) => _fraction(int.parse(m[1]!), int.parse(m[2]!)) ?? '${m[1]} ${m[2]}',
  );
  // "and/or" already says "or"; the rule below would say it twice.
  out = out.replaceAll(RegExp(r'\band/or\b', caseSensitive: false), 'and or');
  // Word or name on both sides: an alternative.
  out = out.replaceAllMapped(
    RegExp(r'(?<=[A-Za-z0-9])/(?=[A-Za-z])|(?<=[A-Za-z])/(?=[A-Za-z0-9])'),
    (_) => ' or ',
  );
  // Anything else: a pause.
  return out
      .replaceAll('/', ', ')
      .replaceAll(RegExp(r'\s+,'), ',')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

final _url = RegExp(
  r'\bhttps?://\S+|\bwww\.\S+|\b[\w-]+(?:\.[\w-]+)*\.(?:com|org|net|co\.uk|io|gov|edu)/\S*',
  caseSensitive: false,
);

const _units = {
  'km/h': 'kilometres an hour',
  'kph': 'kilometres an hour',
  'mph': 'miles an hour',
  'm/s': 'metres a second',
  'Mb/s': 'megabits a second',
  'Gb/s': 'gigabits a second',
  'MB/s': 'megabytes a second',
  'GB/s': 'gigabytes a second',
  'fps': 'frames a second',
};

const _counts = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
  'nine', 'ten', 'eleven', 'twelve',
];
const _parts = {
  2: ('half', 'halves'),
  3: ('third', 'thirds'),
  4: ('quarter', 'quarters'),
  5: ('fifth', 'fifths'),
  6: ('sixth', 'sixths'),
  8: ('eighth', 'eighths'),
  10: ('tenth', 'tenths'),
  12: ('twelfth', 'twelfths'),
};

/// "one third", "three quarters" — for the fractions people say in words.
/// Anything else (7/9, 13/4) is left to be read as two numbers.
String? _fraction(int n, int d) {
  final part = _parts[d];
  if (part == null || n < 1 || n >= d || n >= _counts.length) return null;
  return '${_counts[n]} ${n == 1 ? part.$1 : part.$2}';
}

final _tag = RegExp(r'<\/?[a-zA-Z!][^<>]*>');
final _blockEnd = RegExp(
  r'<(br|/p|/div|/li|/h[1-6]|/blockquote|/tr)\b[^<>]*>',
  caseSensitive: false,
);

/// No-break, figure, thin, hair and narrow spaces: all just a space here.
final _oddSpaces = RegExp('[       　]');

/// Zero-width spaces and joiners, the word joiner, the byte-order mark and
/// soft hyphens — there to guide a browser's line breaks, and nothing to see
/// or say.
final _invisible = RegExp('[​‌‍⁠﻿­]');

final _entity = RegExp(r'&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]{1,31});');

/// Decodes HTML entities — every named one HTML knows (`&rsquo;`, `&hellip;`,
/// `&eacute;`), and numeric ones in decimal or hex — in **one** pass.
///
/// One pass on purpose. Feeds are often encoded twice, but the XML parser has
/// already taken one layer off by the time text gets here: `&amp;#8217;` in a
/// feed arrives as `&#8217;`, which this makes an apostrophe. A second pass
/// would turn a literal `&lt;` — written as `&amp;lt;` — into a `<` that was
/// never meant to be one. Numbers that are not characters, and names HTML
/// does not know, are left exactly as they were.
String decodeEntities(String s) => s.replaceAllMapped(_entity, (m) {
      final body = m[1]!;
      if (body.startsWith('#')) {
        final hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
        final code = int.tryParse(
          body.substring(hex ? 2 : 1),
          radix: hex ? 16 : 10,
        );
        if (code == null ||
            code < 0x20 ||
            code > 0x10FFFF ||
            (code >= 0xD800 && code <= 0xDFFF)) {
          return m[0]!;
        }
        return String.fromCharCode(code);
      }
      // A named one: the HTML parser holds the full table. It also knows
      // the old forms written without a semicolon, so "&notathing;" would
      // come back as "¬athing;" — only a whole entity turned into a
      // character or two counts.
      final decoded = html.parseFragment(m[0]!).text ?? '';
      final whole = decoded.isNotEmpty &&
          decoded.runes.length <= 2 &&
          !decoded.contains(';');
      return whole ? decoded : m[0]!;
    });

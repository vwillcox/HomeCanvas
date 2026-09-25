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

/// [plainText], then made for a voice: a standalone "&" is "and", which a
/// voice would otherwise read as "ampersand", or skip.
String speakable(String s) =>
    plainText(s).replaceAll(RegExp(r'\s+&\s+'), ' and ');

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

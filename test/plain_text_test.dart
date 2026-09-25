import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/article_text.dart';
import 'package:home_canvas/services/plain_text.dart';

void main() {
  group('entities', () {
    test('every named one HTML knows, not just the common few', () {
      expect(plainText('It&rsquo;s here&hellip;'), 'It’s here…');
      expect(plainText('Caf&eacute; &mdash; open'), 'Café — open');
      expect(plainText('&ldquo;Quote&rdquo;'), '“Quote”');
      expect(plainText('&pound;5 &amp; &euro;6'), '£5 & €6');
    });

    test('decimal and hex', () {
      expect(plainText('It&#8217;s &#x2014; ok'), 'It’s — ok');
    });

    test('one pass only: an escaped entity stays literal', () {
      // "&amp;lt;" means the text "&lt;", not a "<".
      expect(decodeEntities('&amp;lt;'), '&lt;');
    });

    test('names HTML does not know, and numbers that are not characters, '
        'are left alone', () {
      expect(plainText('&notathing; and &#99999999;'),
          '&notathing; and &#99999999;');
      expect(plainText('100&#; off'), '100&#; off');
      expect(plainText('AT&T and R&D'), 'AT&T and R&D');
    });
  });

  group('markup', () {
    test('tags go, and a block end is a gap between words', () {
      expect(plainText('<p>One.</p><p>Two <b>bold</b> words.</p>'),
          'One. Two bold words.');
      expect(plainText('Line<br>break'), 'Line break');
    });

    test('a less-than sign in prose is not taken for a tag', () {
      expect(plainText('3 < 5 and 6 > 4'), '3 < 5 and 6 > 4');
    });
  });

  group('invisible and odd characters', () {
    test('no-break and thin spaces become spaces', () {
      expect(plainText('10 km north'), '10 km north');
      expect(plainText('10&nbsp;km'), '10 km');
    });

    test('zero-width characters and soft hyphens are dropped', () {
      expect(plainText('in­cred​ible﻿'), 'incredible');
    });
  });

  group('for the voice', () {
    test('a standalone ampersand is said as "and"', () {
      expect(speakable('Fish &amp; chips'), 'Fish and chips');
      expect(speakable('AT&T'), 'AT&T');
    });
  });

  group('in an article', () {
    test('the embedded article body is decoded, and keeps its paragraphs',
        () {
      const p = 'The council agreed on Tuesday to extend the scheme for '
          'another three years, after a consultation drew many responses.';
      final page = '<html><head><meta property="og:title" '
          'content="It&amp;rsquo;s extended"><script type="application/ld+json">'
          '{"@type":"NewsArticle","articleBody":"<p>It&#8217;s done. $p</p>'
          '<p>Caf&eacute; owners &amp; others. $p</p><p>Third. $p</p>"}'
          '</script></head><body></body></html>';
      final a = ArticleText.extract(page)!;
      expect(a.title, 'It’s extended');
      expect(a.paragraphs, hasLength(3));
      expect(a.paragraphs[0], startsWith('It’s done.'));
      expect(a.paragraphs[1], startsWith('Café owners & others.'));
      for (final para in a.paragraphs) {
        expect(para, isNot(matches(RegExp(r'&[a-zA-Z#][a-zA-Z0-9]*;'))));
        expect(para, isNot(contains('<')));
      }
    });
  });
}

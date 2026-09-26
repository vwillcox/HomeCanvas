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
    test('the camera article that read out "slash": f-stops and fractions',
        () {
      expect(
        speakable('manual mode: f/1.48, f/1.8, f/2.8, and f/4.'),
        'manual mode: f 1.48, f 1.8, f 2.8, and f 4.',
      );
      expect(
        speakable('from f/1.48 to f/4.0 in 1/3 stop increments'),
        'from f 1.48 to f 4.0 in one third stop increments',
      );
      expect(speakable('three quarters, or 3/4, and 1/2'),
          'three quarters, or three quarters, and one half');
    });

    test('no slash is ever said', () {
      for (final s in [
        'f/4', '1/3', '24/7', '120 km/h', '25/9/2026', 'and/or',
        'iOS/Android', 'see wired.com/newsletters', 'https://x.com/a/b',
        '7/9 of them', '4G/5G', 'Gear / Deals',
      ]) {
        expect(speakable(s), isNot(contains('/')), reason: s);
      }
    });

    test('each read as a person would say it', () {
      expect(speakable('open 24/7'), 'open twenty-four seven');
      expect(speakable('at 120 km/h'), 'at 120 kilometres an hour');
      expect(speakable('on 25/9/2026'), 'on 25 9 2026');
      expect(speakable('you and/or me'), 'you and or me');
      expect(speakable('iOS/Android apps'), 'iOS or Android apps');
      expect(speakable('Read more at https://wired.com/story/x today'),
          'Read more at a link today');
      expect(speakable('7/9 of them'), '7 9 of them');
    });

    test('decimals and version numbers are left whole', () {
      expect(speakable('It costs 3.5 million'), 'It costs 3.5 million');
    });

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

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:immich_kiosk_pi/services/article_reader.dart';
import 'package:immich_kiosk_pi/services/article_text.dart';

const _para =
    'The council agreed on Tuesday to extend the town centre scheme for '
    'another three years, after a consultation drew more responses than any '
    'before it.';

String _page({String body = '', String head = ''}) =>
    '<html><head><meta property="og:title" content="Scheme extended">'
    '$head</head><body>$body</body></html>';

/// A voice that says nothing, but remembers what it was given, and plays
/// each piece until told to finish — so a test can pause, skip and stop.
class FakeOutput implements SpeechOutput {
  final said = <String>[];
  final made = <String>[];
  Completer<void>? playing;
  bool paused = false;
  final _files = <File, String>{};

  @override
  Future<File?> synthesise(String text) async {
    made.add(text);
    final f = File('${Directory.systemTemp.path}/fake-${made.length}-'
        '${DateTime.now().microsecondsSinceEpoch}.wav')
      ..writeAsStringSync(text);
    _files[f] = text;
    return f;
  }

  @override
  Future<void> play(File file, double volume) {
    said.add(_files[file]!);
    playing = Completer<void>();
    return playing!.future;
  }

  /// The piece being said comes to its end.
  void finishOne() {
    final p = playing;
    if (p != null && !p.isCompleted) p.complete();
  }

  @override
  Future<void> pause() async => paused = true;

  @override
  Future<void> resume() async => paused = false;

  @override
  Future<void> stop() async => finishOne();
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('taking the article out of a page', () {
    test('uses the article body a page gives search engines', () {
      final page = _page(
        head: '<script type="application/ld+json">'
            '{"@context":"https://schema.org","@type":"NewsArticle",'
            '"articleBody":"$_para\\n\\n$_para And more besides."}'
            '</script>',
        body: '<nav>Home News Sport</nav><p>Cookie settings</p>',
      );
      final a = ArticleText.extract(page)!;
      expect(a.title, 'Scheme extended');
      expect(a.paragraphs, hasLength(2));
      expect(a.paragraphs.first, _para);
    });

    test('finds it inside a @graph too', () {
      final page = _page(
        head: '<script type="application/ld+json">'
            '{"@graph":[{"@type":"WebPage"},{"@type":["Article"],'
            '"articleBody":"$_para $_para $_para"}]}</script>',
      );
      expect(ArticleText.extract(page)!.paragraphs.single, contains('council'));
    });

    test('otherwise reads the page, leaving the furniture out', () {
      final page = _page(
        body: '<header><p>Sign up to our newsletter for the best stories.</p></header>'
            '<nav><a>Home</a></nav>'
            '<article><h1>Scheme extended</h1>'
            '<p>$_para</p>'
            '<div class="share-bar"><p>Share this on every platform you use today.</p></div>'
            '<h2>What happens next</h2>'
            '<p>$_para</p>'
            '<figure><figcaption>A photo caption that is long enough.</figcaption></figure>'
            '<p>Advertisement</p>'
            '</article>'
            '<aside class="related"><p>Related: something else entirely, at length.</p></aside>'
            '<footer><p>Copyright the paper, all rights reserved, forever.</p></footer>',
      );
      final a = ArticleText.extract(page)!;
      expect(a.paragraphs, [_para, 'What happens next.', _para]);
    });

    test('a paragraph repeated straight after itself is said once', () {
      final page = _page(
        body: '<article><p>$_para</p><p>$_para</p><p>Then more. $_para</p>'
            '<p>And more again. $_para</p></article>',
      );
      expect(ArticleText.extract(page)!.paragraphs, hasLength(3));
    });

    test('stops where the other stories start, and drops sign-up pitches',
        () {
      final page = _page(
        body: '<article><p>First. $_para</p><p>Second. $_para</p>'
            '<p>Third. $_para</p>'
            '<p>Power up with unlimited access to the paper. Subscribe Today.</p>'
            '<h2>Related topics</h2><ul><li>Another story entirely, about '
            'something else, which nobody asked to hear read out</li></ul>'
            '<p>International story. Published9 May</p></article>',
      );
      final a = ArticleText.extract(page)!;
      expect(a.paragraphs, hasLength(3));
      expect(a.paragraphs.last, 'Third. $_para');
    });

    test('a teaser is not an article', () {
      expect(ArticleText.extract(_page(body: '<p>Watch the video.</p>')), isNull);
    });

    test('long paragraphs are split between sentences, short ones kept whole',
        () {
      final long = List.filled(8, 'This is one sentence of a long paragraph.')
          .join(' ');
      final chunks = speakableChunks(['Short.', long], max: 120);
      expect(chunks.first, 'Short.');
      expect(chunks.length, greaterThan(2));
      for (final c in chunks.skip(1)) {
        expect(c.length, lessThanOrEqualTo(120));
        expect(c, endsWith('.'));
      }
      expect(chunks.skip(1).join(' '), long);
    });
  });

  group('reading it out', () {
    late FakeOutput out;
    late int started;
    late int ended;

    ArticleReader reader({Future<String> Function(String)? fetch}) =>
        ArticleReader(
          output: out,
          volume: () => 45,
          onStart: () => started++,
          onEnd: () => ended++,
          fetch: fetch ??
              (_) async => _page(
                  body: '<article><p>First. $_para</p><p>Second. $_para</p>'
                      '<p>Third. $_para</p></article>'),
        );

    setUp(() {
      out = FakeOutput();
      started = 0;
      ended = 0;
    });

    test('reads the headline, then the article, in order', () async {
      final r = reader();
      unawaited(r.read(title: 'Scheme extended', link: 'https://x/1'));
      await settle();
      expect(r.status, ReaderStatus.reading);
      expect(started, 1);
      for (var i = 0; i < 4; i++) {
        await settle();
        out.finishOne();
      }
      await settle();
      expect(out.said, [
        'Scheme extended.',
        'First. $_para',
        'Second. $_para',
        'Third. $_para',
      ]);
      expect(r.active, isFalse);
      expect(ended, 1);
    });

    test('works on the next piece while this one is said', () async {
      final r = reader();
      unawaited(r.read(title: 'Scheme extended', link: 'https://x/1'));
      await settle();
      // Saying the headline, and the first paragraph is already made.
      expect(out.said, ['Scheme extended.']);
      expect(out.made, ['Scheme extended.', 'First. $_para']);
      await r.stop();
    });

    test('reads the summary, and says so, when the page cannot be had',
        () async {
      final r = reader(fetch: (_) async => throw const SocketException('down'));
      unawaited(r.read(
          title: 'Scheme extended', link: 'https://x/1', summary: 'In short.'));
      await settle();
      expect(r.summaryOnly, isTrue);
      for (var i = 0; i < 3; i++) {
        await settle();
        out.finishOne();
      }
      await settle();
      expect(out.said.last, 'In short.');
      expect(out.said[1], contains('summary'));
    });

    test('pause holds it, and it carries on from the same place', () async {
      final r = reader();
      unawaited(r.read(title: 'Scheme extended', link: 'https://x/1'));
      await settle();
      await r.pause();
      expect(r.status, ReaderStatus.paused);
      expect(out.paused, isTrue);
      await r.resume();
      expect(r.status, ReaderStatus.reading);
      expect(r.position, 0);
      await r.stop();
    });

    test('skip moves on to the next paragraph', () async {
      final r = reader();
      unawaited(r.read(title: 'Scheme extended', link: 'https://x/1'));
      await settle();
      await r.skip();
      await settle();
      expect(r.position, 1);
      expect(out.said.last, 'First. $_para');
      await r.stop();
    });

    test('stop ends it at once, and the music comes back once', () async {
      final r = reader();
      unawaited(r.read(title: 'Scheme extended', link: 'https://x/1'));
      await settle();
      await r.stop();
      await settle();
      expect(r.active, isFalse);
      expect(out.said, ['Scheme extended.']);
      expect(ended, 1);
    });

    test('a second article takes over without the music coming back between',
        () async {
      final r = reader();
      unawaited(r.read(title: 'First', link: 'https://x/1'));
      await settle();
      unawaited(r.read(title: 'Second', link: 'https://x/2'));
      await settle();
      expect(r.title, 'Second');
      expect(started, 1);
      expect(ended, 0);
      await r.stop();
      expect(ended, 1);
    });
  });
}

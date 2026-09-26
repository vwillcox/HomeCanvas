import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/article_reader.dart';
import 'package:home_canvas/services/article_text.dart';
import 'package:home_canvas/services/tts_service.dart';

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
  final voices = <String?>[];
  Completer<void>? playing;
  bool paused = false;
  final _files = <File, String>{};

  final speeds = <double>[];

  @override
  Future<File?> synthesise(String text, {String? voice, double speed = 1}) async {
    made.add(text);
    voices.add(voice);
    speeds.add(speed);
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

    test("a decimal point is not the end of a sentence", () {
      // Joined back up, a split at "1." read aloud as "one. forty-eight".
      final long = List.filled(6,
              'You can set the aperture from f/1.48 to f/4.0 in 1/3 stops.')
          .join(' ');
      final chunks = speakableChunks([long], max: 130);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c, isNot(contains('1. 48')));
        expect(c, isNot(contains('4. 0')));
      }
      expect(chunks.join(' '), long);
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

  group('the author', () {
    String withRecord(String author) => _page(
          head: '<script type="application/ld+json">{"@type":"NewsArticle",'
              '"author":$author,"articleBody":"First. $_para\\nSecond. '
              '$_para\\nThird. $_para"}</script>',
        );

    test('a Person in the article record', () {
      expect(ArticleText.extract(withRecord('{"@type":"Person","name":"Steven Levy"}'))!.author,
          'Steven Levy');
    });

    test('several, as a byline says them', () {
      expect(
          ArticleText.extract(withRecord(
                  '[{"name":"Anna Smith"},{"name":"Raj Patel"},{"name":"Li Wei"}]'))!
              .author,
          'Anna Smith, Raj Patel and Li Wei');
    });

    test("the page's author tag, when the record has none", () {
      final page = _page(
        head: '<meta name="author" content="By Jo Bloggs">',
        body: '<article><p>First. $_para</p><p>Second. $_para</p>'
            '<p>Third. $_para</p></article>',
      );
      expect(ArticleText.extract(page)!.author, 'Jo Bloggs');
    });

    test('a profile link is not a name', () {
      final page = _page(
        head: '<meta property="article:author" content="https://x.com/people/jo">',
        body: '<article><p>First. $_para</p><p>Second. $_para</p>'
            '<p>Third. $_para</p></article>',
      );
      expect(ArticleText.extract(page)!.author, isNull);
    });
  });

  group('a voice per author', () {
    test('the same name always gets the same voice, however it is written',
        () {
      final i = TtsService.voiceIndex('Steven Levy', 2);
      expect(TtsService.voiceIndex('steven  levy', 2), i);
      expect(TtsService.voiceIndex('By Steven Levy', 2), i);
      expect(TtsService.voiceIndex('Steven Levy', 2), i);
    });

    test('different writers are spread across the voices', () {
      final names = ['Steven Levy', 'Lauren Goode', 'Anna Smith', 'Raj Patel',
          'Li Wei', 'Jo Bloggs', 'Sam Jones', 'Alex Kim'];
      final used = names.map((n) => TtsService.voiceIndex(n, 2)).toSet();
      expect(used, {0, 1});
    });

    test('the reader says who wrote it, and reads it all in their voice',
        () async {
      final out = FakeOutput();
      final r = ArticleReader(
        output: out,
        volume: () => 45,
        voiceFor: (author) async => author == null ? null : '/voices/$author',
        fetch: (_) async => _page(
          head: '<meta name="author" content="Jo Bloggs">',
          body: '<article><p>First. $_para</p><p>Second. $_para</p>'
              '<p>Third. $_para</p></article>',
        ),
      );
      unawaited(r.read(title: 'Scheme extended', link: 'https://x/1'));
      await settle();
      expect(r.author, 'Jo Bloggs');
      for (var i = 0; i < 5; i++) {
        await settle();
        out.finishOne();
      }
      await settle();
      expect(out.said.take(2), ['Scheme extended.', 'By Jo Bloggs.']);
      expect(out.voices.toSet(), {'/voices/Jo Bloggs'});
    });
  });

  group('voice settings', () {
    ArticleReader readerWith(FakeOutput out) => ArticleReader(
          output: out,
          volume: () => 45,
          voiceFor: (author) async => author == null ? null : '/v/alan.onnx',
          voiceId: (path) => path.split('/').last.replaceAll('.onnx', ''),
          fetch: (_) async => _page(
            head: '<meta name="author" content="Jo Bloggs">',
            body: '<article><p>First. $_para</p><p>Second. $_para</p>'
                '<p>Third. $_para</p></article>',
          ),
        );

    test("each voice reads at the speed set for it", () async {
      final out = FakeOutput();
      final r = readerWith(out);
      unawaited(r.read(
        title: 'Scheme extended',
        link: 'https://x/1',
        speeds: {'alan': 1.15, 'main': 0.85},
      ));
      await settle();
      await r.stop();
      expect(out.speeds, isNotEmpty);
      expect(out.speeds.toSet(), {1.15});
    });

    test('a voice with no speed set reads at its own pace', () async {
      final out = FakeOutput();
      final r = readerWith(out);
      unawaited(r.read(title: 'Scheme extended', link: 'https://x/1'));
      await settle();
      await r.stop();
      expect(out.speeds.toSet(), {1.0});
    });

    test('"Say who wrote it" off leaves the byline out', () async {
      final out = FakeOutput();
      final r = readerWith(out);
      unawaited(r.read(
          title: 'Scheme extended', link: 'https://x/1', sayAuthor: false));
      await settle();
      out.finishOne();
      await settle();
      expect(out.said, isNot(contains('By Jo Bloggs.')));
      expect(out.made[1], startsWith('First.'));
      await r.stop();
    });
  });
}

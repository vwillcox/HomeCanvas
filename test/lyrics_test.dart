import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/look.dart';
import 'package:home_canvas/services/lyrics.dart';
import 'package:home_canvas/services/now_playing_service.dart';
import 'package:home_canvas/services/playback_source.dart';
import 'package:home_canvas/widgets/lyrics_view.dart';

/// A song's words: reading LRCLIB's timed and plain lyrics, picking the
/// right one of its search results, and the view lighting the line being
/// sung.
void main() {
  group('parseLrc', () {
    test('reads times, in order, with their words', () {
      final l = parseLrc('''
[ar:Imagine Dragons]
[ti:Thunder]
[00:00.55]Just a young gun with a quick fuse
[00:03.18]I was uptight, wanna let loose
[00:06.1]I was dreaming of bigger things and
''')!;
      expect(l.synced, isTrue);
      expect(l.lines.map((x) => x.text), [
        'Just a young gun with a quick fuse',
        'I was uptight, wanna let loose',
        'I was dreaming of bigger things and',
      ]);
      expect(l.lines[0].at, const Duration(milliseconds: 550));
      expect(l.lines[1].at, const Duration(seconds: 3, milliseconds: 180));
      // One digit after the point is tenths, not thousandths.
      expect(l.lines[2].at, const Duration(seconds: 6, milliseconds: 100));
    });

    test('a chorus with several times is sung at each', () {
      final l = parseLrc('[00:10.00][01:20.00]Thunder\n[00:12.00]Feel it')!;
      expect(l.lines.map((x) => (x.at.inSeconds, x.text)), [
        (0, ''), // the intro, a break before the first words
        (10, 'Thunder'),
        (12, 'Feel it'),
        (80, 'Thunder'),
      ]);
    });

    test('a break is kept once, and none is left at the end', () {
      final l = parseLrc('''
[00:01.00]One
[00:05.00]
[00:06.00]
[00:09.00]Two
[00:12.00]
''')!;
      expect(l.lines.map((x) => x.text), ['One', '', 'Two']);
      expect(l.lines[1].isBreak, isTrue);
    });

    test('an intro of more than a few seconds starts with a break', () {
      final l = parseLrc('[00:21.40]At last')!;
      expect(l.lines.first.isBreak, isTrue);
      expect(l.lines.first.at, Duration.zero);
      expect(parseLrc('[00:02.00]Straight in')!.lines.first.isBreak, isFalse);
    });

    test('an offset moves every line', () {
      final l = parseLrc('[offset:+500]\n[00:03.00]Sooner')!;
      expect(l.lines.single.at, const Duration(milliseconds: 2500));
    });

    test('nothing with a time is no lyrics at all', () {
      expect(parseLrc('just words\nand more'), isNull);
      expect(parseLrc(''), isNull);
    });
  });

  group('Lyrics.lineAt', () {
    final l = parseLrc('''
[00:01.00]One
[00:05.00]Two
[00:09.00]Three
''')!;

    test('the last line whose time has come', () {
      expect(l.lineAt(Duration.zero), -1);
      expect(l.lineAt(const Duration(seconds: 1)), 0);
      expect(l.lineAt(const Duration(seconds: 4, milliseconds: 999)), 0);
      expect(l.lineAt(const Duration(seconds: 5)), 1);
      expect(l.lineAt(const Duration(minutes: 3)), 2);
    });

    test('plain words have no line being sung', () {
      expect(
        parsePlainLyrics('One\nTwo')!.lineAt(const Duration(seconds: 30)),
        -1,
      );
    });
  });

  test('plain words keep one break between verses', () {
    final l = parsePlainLyrics('One\nTwo\n\n\nThree\n\n')!;
    expect(l.synced, isFalse);
    expect(l.lines.map((x) => x.text), ['One', 'Two', '', 'Three']);
  });

  test('titles and artists as a lyrics site files them', () {
    expect(plainTitle('Come Together - Remastered 2009'), 'Come Together');
    expect(plainTitle('Titanium (feat. Sia)'), 'Titanium');
    expect(plainTitle('Star Wars (Main Theme)'), 'Star Wars (Main Theme)');
    expect(plainTitle('Fix You - Live in Buenos Aires'), 'Fix You');
    expect(
      firstArtist('John Williams, London Symphony Orchestra'),
      'John Williams',
    );
    expect(firstArtist('Simon & Garfunkel'), 'Simon');
    expect(firstArtist('Adele'), 'Adele');
  });

  group('lyricsFromRecord', () {
    test('timed words before plain', () {
      final l = lyricsFromRecord({
        'syncedLyrics': '[00:01.00]Timed',
        'plainLyrics': 'Plain',
      })!;
      expect(l.synced, isTrue);
      expect(l.lines.single.text, 'Timed');
    });

    test('plain words where there are no timed ones', () {
      final l = lyricsFromRecord({'syncedLyrics': null, 'plainLyrics': 'A\nB'});
      expect(l!.synced, isFalse);
      expect(l.lines.length, 2);
    });

    test('an instrumental says so', () {
      expect(lyricsFromRecord({'instrumental': true})!.instrumental, isTrue);
      expect(lyricsFromRecord({})?.hasWords ?? false, isFalse);
    });
  });

  group('bestRecord', () {
    Map rec(
      String artist,
      String title,
      num duration, {
      bool synced = true,
      bool plain = true,
      bool instrumental = false,
    }) => {
      'artistName': artist,
      'trackName': title,
      'duration': duration,
      'instrumental': instrumental,
      'syncedLyrics': synced ? '[00:01.00]x' : null,
      'plainLyrics': plain ? 'x' : null,
    };

    test('the same song, as long, with timed words', () {
      final best = bestRecord(
        [
          rec('Imagine Dragons', 'Thunder', 165), // another length
          rec('Imagine Dragons', 'Thunder', 187, synced: false),
          rec('Imagine Dragons', 'Thunder', 188),
          rec('Someone Else', 'Thunder', 187),
        ],
        artist: 'Imagine Dragons',
        title: 'Thunder',
        duration: const Duration(seconds: 187),
      );
      expect(best?['duration'], 188);
    });

    test('nothing by another artist, of another name, or far longer', () {
      expect(
        bestRecord(
          [
            rec('Someone Else', 'Thunder', 187),
            rec('Imagine Dragons', 'Believer', 187),
            rec('Imagine Dragons', 'Thunder', 240),
          ],
          artist: 'Imagine Dragons',
          title: 'Thunder',
          duration: const Duration(seconds: 187),
        ),
        isNull,
      );
    });

    test('an instrumental only where nothing has words', () {
      final best = bestRecord(
        [
          rec(
            'John Williams, London Symphony Orchestra',
            'Star Wars (Main Theme)',
            344,
            synced: false,
            plain: false,
            instrumental: true,
          ),
        ],
        artist: 'John Williams, London Symphony Orchestra',
        title: 'Star Wars (Main Theme)',
        duration: const Duration(seconds: 346),
      );
      expect(lyricsFromRecord(best!)!.instrumental, isTrue);
    });
  });

  group('LyricsFinder', () {
    const thunder = {
      'artistName': 'Imagine Dragons',
      'trackName': 'Thunder',
      'albumName': 'Evolve',
      'duration': 187.0,
      'instrumental': false,
      'syncedLyrics': '[00:00.55]Just a young gun with a quick fuse',
      'plainLyrics': 'Just a young gun with a quick fuse',
    };

    LyricsFinder finder(_Lrclib lrclib) =>
        LyricsFinder(dio: Dio()..httpClientAdapter = lrclib);

    Future<Lyrics?> thunderFrom(LyricsFinder f) => f.find(
      artist: 'Imagine Dragons',
      title: 'Thunder',
      album: 'Evolve',
      duration: const Duration(seconds: 187),
    );

    test('the exact record first, asked once for the same song', () async {
      final lrclib = _Lrclib({'/api/get': (200, thunder)});
      final f = finder(lrclib);
      final l = await thunderFrom(f);
      expect(l!.lines.last.text, 'Just a young gun with a quick fuse');
      expect(lrclib.asked.single.queryParameters, {
        'artist_name': 'Imagine Dragons',
        'track_name': 'Thunder',
        'album_name': 'Evolve',
        'duration': 187,
      });
      await thunderFrom(f);
      expect(lrclib.asked, hasLength(1));
      expect(f.cached('Imagine Dragons', 'Thunder').known, isTrue);
    });

    test('a search when there is no exact record', () async {
      final lrclib = _Lrclib({
        '/api/get': (404, {'message': 'not found'}),
        '/api/search': (200, [thunder]),
      });
      final l = await thunderFrom(finder(lrclib));
      expect(l!.synced, isTrue);
      expect(lrclib.asked.map((o) => o.path), [
        'https://lrclib.net/api/get',
        'https://lrclib.net/api/search',
      ]);
    });

    test('"none" is kept; LRCLIB out of reach is not', () async {
      final none = _Lrclib({'/api/get': (404, {}), '/api/search': (200, [])});
      final f = finder(none);
      expect(await thunderFrom(f), isNull);
      expect(f.cached('Imagine Dragons', 'Thunder').known, isTrue);

      final down = _Lrclib({});
      final g = finder(down);
      expect(await thunderFrom(g), isNull);
      expect(g.cached('Imagine Dragons', 'Thunder').known, isFalse);
      await thunderFrom(g);
      expect(down.asked, hasLength(4), reason: 'asked again, both ways');
    });
  });

  group('LyricsView', () {
    final words = parseLrc('''
[00:01.00]First line
[00:05.00]Second line
[00:09.00]Third line
[00:20.00]Fourth line
''')!;

    Future<_Source> show(
      WidgetTester tester, {
      required Duration at,
      bool canSeek = true,
      String theme = 'glass',
      Size size = const Size(1200, 700),
    }) async {
      final source = _Source(at: at, canSeek: canSeek);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: KioskLook(
            theme: kBuiltInThemes.firstWhere((t) => t.id == theme),
            child: Scaffold(
              body: LyricsView(lyrics: words, service: source),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return source;
    }

    Color colourOf(WidgetTester tester, String line) {
      final text = tester.widget<Text>(find.text(line));
      return (text.style?.color ??
          DefaultTextStyle.of(tester.element(find.text(line))).style.color)!;
    }

    testWidgets('lights the line being sung, and only that one', (
      tester,
    ) async {
      await show(tester, at: const Duration(seconds: 6));
      final lit = DefaultTextStyle.of(
        tester.element(find.text('Second line')),
      ).style.color!;
      final unlit = DefaultTextStyle.of(
        tester.element(find.text('First line')),
      ).style.color!;
      expect(lit.a, 1.0);
      expect(unlit.a, lessThan(0.5));
    });

    testWidgets('a touch on a line plays from it, where the source can seek', (
      tester,
    ) async {
      final source = await show(tester, at: const Duration(seconds: 2));
      await tester.tap(find.text('Third line'));
      await tester.pump();
      expect(source.seekedTo, const Duration(seconds: 9));
      await tester.pumpAndSettle();
      final lit = DefaultTextStyle.of(
        tester.element(find.text('Third line')),
      ).style.color!;
      expect(lit.a, 1.0);
    });

    testWidgets('a line is not a button where the source cannot seek', (
      tester,
    ) async {
      final source = await show(
        tester,
        at: const Duration(seconds: 2),
        canSeek: false,
      );
      await tester.tap(find.text('Third line'));
      await tester.pump();
      expect(source.seekedTo, isNull);
    });

    testWidgets('on a console, the time of each line is on its block', (
      tester,
    ) async {
      await show(tester, at: const Duration(seconds: 6), theme: 'lcars');
      expect(find.text('00:05'), findsOneWidget);
      expect(find.text('00:20'), findsOneWidget);
      final look = kBuiltInThemes.firstWhere((t) => t.id == 'lcars');
      expect(colourOf(tester, 'Second line'), look.accent);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a small screen and a big one, in every theme', (
      tester,
    ) async {
      for (final t in kBuiltInThemes) {
        for (final size in const [Size(700, 300), Size(1300, 700)]) {
          await show(
            tester,
            at: const Duration(seconds: 12),
            theme: t.id,
            size: size,
          );
          expect(tester.takeException(), isNull, reason: '${t.id} at $size');
        }
      }
    });
  });
}

/// A source at a set place in a song that is not playing — so the view's
/// own count does not move it on during a test.
class _Source extends ChangeNotifier implements PlaybackSource {
  _Source({required Duration at, required this.canSeek})
    : now = NowPlaying(
        title: 'Song',
        artist: 'Singer',
        duration: const Duration(minutes: 3),
        position: at,
        status: 'paused',
      );

  @override
  NowPlaying now;

  @override
  final bool canSeek;

  Duration? seekedTo;

  @override
  Future<void> seek(Duration position) async {
    seekedTo = position;
    now = now.copyWith(position: position);
    notifyListeners();
  }

  @override
  String? get artUrl => null;
  @override
  bool get available => true;
  @override
  bool get idleHidden => false;
  @override
  bool get hasVolume => false;
  @override
  double get volume => 0;
  @override
  bool get muted => false;
  @override
  IconData get sourceIcon => Icons.music_note;
  @override
  bool get canLike => false;
  @override
  bool get isLiked => false;
  @override
  bool get canAddToPlaylist => false;
  @override
  Future<void> playPause() async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> cycleRepeat() async {}
  @override
  Future<void> toggleShuffle() async {}
  @override
  Future<void> setVolume(double fraction) async {}
  @override
  Future<void> toggleMute() async {}
  @override
  Future<void> toggleLike() async {}
  @override
  Future<List<PlaylistInfo>> loadPlaylists() async => const [];
  @override
  Future<void> addToPlaylist(String playlistId) async {}
}

/// LRCLIB, answering each path with a status and a body; a path it has no
/// answer for is a network that is down.
class _Lrclib implements HttpClientAdapter {
  _Lrclib(this.answers);

  final Map<String, (int, Object)> answers;
  final asked = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options);
    final answer = answers[options.uri.path];
    if (answer == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'down',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(answer.$2),
      answer.$1,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

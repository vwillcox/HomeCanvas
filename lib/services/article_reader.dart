import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'article_text.dart';
import 'tts_service.dart';

/// Where the reader's words become sound. An interface so the reading —
/// fetching, chunking, looking ahead, pausing, skipping — can be tested
/// without piper or a speaker.
abstract class SpeechOutput {
  /// [text] as a sound file, or null if it could not be made.
  Future<File?> synthesise(String text);

  /// Plays [file]; completes when it has finished or been stopped.
  Future<void> play(File file, double volume);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
}

/// Piper for the voice, and a player of its own — so reading does not
/// disturb whatever else has a player, and can be paused on its own.
class PiperSpeechOutput implements SpeechOutput {
  PiperSpeechOutput(this.tts);

  final TtsService tts;
  Player? _player;
  Completer<void>? _playing;
  StreamSubscription<bool>? _done;

  @override
  Future<File?> synthesise(String text) => tts.synthesise(text);

  @override
  Future<void> play(File file, double volume) async {
    final player = _player ??= Player();
    final playing = _playing = Completer<void>();
    await _done?.cancel();
    _done = player.stream.completed.listen((done) {
      if (done && !playing.isCompleted) playing.complete();
    });
    await player.setVolume(volume);
    await player.open(Media(file.path));
    await playing.future;
  }

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> resume() async => _player?.play();

  @override
  Future<void> stop() async {
    await _player?.stop();
    final playing = _playing;
    if (playing != null && !playing.isCompleted) playing.complete();
  }

  void dispose() {
    _done?.cancel();
    _player?.dispose();
    _player = null;
  }
}

enum ReaderStatus { idle, fetching, reading, paused }

/// Reads a news article out loud, a paragraph at a time.
///
/// Tapping **Read aloud** on a headline fetches the page, takes the article
/// out of it ([ArticleText]) and reads it through piper, on the Pi. Each piece
/// is synthesised while the one before is being said, so the reading runs on
/// without a pause to think between paragraphs. When the page cannot be read
/// — a paywall, a video page, no network — it reads the feed's own summary
/// instead, and says so.
///
/// Anything playing is paused while it reads and carries on afterwards;
/// music under a voice is two things nobody can follow.
class ArticleReader extends ChangeNotifier {
  ArticleReader({
    required this.output,
    required this.volume,
    this.onStart,
    this.onEnd,
    Future<String> Function(String url)? fetch,
  }) : _fetch = fetch ?? _fetchPage;

  final SpeechOutput output;

  /// How loud, 0–100: the kiosk's speech volume, read at each piece so a
  /// change in Settings is heard straight away.
  final double Function() volume;

  /// Called as reading begins and after it ends, however it ends — for
  /// pausing the music and bringing it back.
  final VoidCallback? onStart;
  final VoidCallback? onEnd;

  final Future<String> Function(String url) _fetch;

  ReaderStatus _status = ReaderStatus.idle;
  ReaderStatus get status => _status;
  bool get active => _status != ReaderStatus.idle;

  String _title = '';
  String get title => _title;

  /// The link being read, so the news tile can mark its headline.
  String? _link;
  String? get link => _link;

  /// The feed's summary is being read, because the page could not be.
  bool _summaryOnly = false;
  bool get summaryOnly => _summaryOnly;

  List<String> _chunks = const [];
  int _index = 0;

  /// How far through: the piece being said, and how many there are.
  int get position => _index;
  int get total => _chunks.length;

  /// Each reading gets a number; anything still running from an older one
  /// sees the number has moved on and stops quietly.
  int _run = 0;
  bool _skipping = false;
  bool _started = false;

  /// Reads the article at [link], or [summary] if it cannot be fetched.
  Future<void> read({
    required String title,
    String? link,
    String? summary,
    String? source,
  }) async {
    // Taking over from a reading already going, the music stays paused
    // rather than coming back for a moment in between.
    final taking = _started;
    final run = ++_run;
    if (taking) await output.stop();
    _title = title;
    _link = link;
    _summaryOnly = false;
    _chunks = const [];
    _index = 0;
    _set(ReaderStatus.fetching);
    if (!taking) {
      _started = true;
      onStart?.call();
    }

    Article? article;
    if (link != null) {
      try {
        article = ArticleText.extract(await _fetch(link), fallbackTitle: title);
      } catch (e) {
        debugPrint('Reader: could not fetch $link: $e');
      }
    }
    if (run != _run) return;

    final parts = <String>['$title.'];
    if (article != null) {
      if (source != null && source.isNotEmpty) parts.add('From $source.');
      parts.addAll(article.paragraphs);
    } else if (summary != null && summary.trim().isNotEmpty) {
      _summaryOnly = true;
      parts.add("The article itself couldn't be read, so here is the summary.");
      parts.add(ArticleText.clean(summary));
    } else {
      parts.add("Sorry, there's nothing here that can be read out.");
    }
    _chunks = speakableChunks(parts);
    _set(ReaderStatus.reading);
    await _readFrom(run);
  }

  Future<void> _readFrom(int run) async {
    Future<File?>? next = output.synthesise(_chunks[_index]);
    try {
      while (run == _run && _index < _chunks.length) {
        final file = await next;
        // Start on the next piece while this one is said.
        next = _index + 1 < _chunks.length
            ? output.synthesise(_chunks[_index + 1])
            : null;
        if (run != _run) {
          _discard(file);
          break;
        }
        if (file != null) {
          await output.play(file, volume());
          _discard(file);
        }
        if (run != _run) break;
        _skipping = false;
        _index++;
        notifyListeners();
      }
    } finally {
      if (next != null) unawaited(next.then(_discard));
      if (run == _run) await _finish();
    }
  }

  /// Holds the reading where it is.
  Future<void> pause() async {
    if (_status != ReaderStatus.reading) return;
    await output.pause();
    _set(ReaderStatus.paused);
  }

  Future<void> resume() async {
    if (_status != ReaderStatus.paused) return;
    await output.resume();
    _set(ReaderStatus.reading);
  }

  /// On to the next paragraph.
  Future<void> skip() async {
    if (_status != ReaderStatus.reading && _status != ReaderStatus.paused) {
      return;
    }
    if (_skipping) return;
    _skipping = true;
    if (_status == ReaderStatus.paused) _set(ReaderStatus.reading);
    await output.stop();
  }

  /// Stops reading altogether.
  Future<void> stop() async {
    if (!active) return;
    _run++;
    await output.stop();
    await _finish();
  }

  Future<void> _finish() async {
    _chunks = const [];
    _index = 0;
    _link = null;
    _skipping = false;
    _set(ReaderStatus.idle);
    if (_started) {
      _started = false;
      onEnd?.call();
    }
  }

  void _set(ReaderStatus s) {
    _status = s;
    notifyListeners();
  }

  static void _discard(File? f) {
    if (f == null) return;
    f.delete().catchError((_) => f);
  }

  /// A browser's user agent: some sites serve a stripped page, or nothing,
  /// to anything that does not look like one.
  static Future<String> _fetchPage(String url) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.plain,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (X11; Linux aarch64; rv:128.0) Gecko/20100101 '
            'Firefox/128.0',
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-GB,en;q=0.8',
      },
    ));
    final r = await dio.get<String>(url);
    return r.data ?? '';
  }
}

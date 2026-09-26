import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Reads text out loud with piper, a local neural text-to-speech engine.
///
/// Local rather than a cloud service, for the same reason as everything else
/// here: a note somebody shares to this panel is private, and reading it out
/// should not mean posting it to anyone. Piper runs comfortably on a Pi 5 —
/// measured at a real-time factor of about 0.16, so a sentence is synthesised
/// in roughly a sixth of the time it takes to say.
///
/// Not `espeak-ng`, which Debian does package: it is intelligible but plainly
/// robotic, and this is read aloud in a room rather than into a headset.
/// Note also that Debian's `piper` package is a *gaming mouse configurator*
/// that happens to share the name — the engine this wants is rhasspy/piper,
/// installed under ~/.local. See INSTALL.md.
class TtsService {
  TtsService();

  /// Where the binary and voice are looked for. Under the home directory
  /// because piper installs without root.
  static const String _binRelative = '.local/bin/piper';
  static const String _voiceRelative = '.local/share/piper/voice.onnx';

  /// More voices, each a piper `.onnx` with its `.onnx.json` beside it. The
  /// reader gives each article's author one of these or the main voice.
  static const String _voicesRelative = '.local/share/piper/voices';

  Player? _player;

  /// One at a time, in order. Two notes arriving together should be read one
  /// after the other rather than on top of each other, which is unintelligible
  /// and sounds like a fault.
  Future<void> _queue = Future.value();

  bool? _availableCache;

  String get _home => Platform.environment['HOME'] ?? '';
  String get _binary => '$_home/$_binRelative';
  String get _voice => '$_home/$_voiceRelative';
  String get _voicesDir => '$_home/$_voicesRelative';

  List<String>? _voicesCache;

  /// Every voice there is: the main one first, then the extra ones in name
  /// order — an order that does not change from one start to the next, so
  /// an author keeps their voice.
  Future<List<String>> voices() async {
    if (_voicesCache != null) return _voicesCache!;
    final found = <String>[];
    if (await File(_voice).exists()) found.add(_voice);
    final dir = Directory(_voicesDir);
    if (await dir.exists()) {
      final extra = <String>[];
      await for (final e in dir.list()) {
        if (e is File &&
            e.path.endsWith('.onnx') &&
            await File('${e.path}.json').exists()) {
          extra.add(e.path);
        }
      }
      found.addAll(extra..sort());
    }
    return _voicesCache = found;
  }

  /// A voice's id, for settings: the model's file name — "main" for the
  /// main voice, which is always called voice.onnx.
  String voiceId(String path) {
    if (path == _voice) return 'main';
    final name = path.split('/').last;
    return name.endsWith('.onnx') ? name.substring(0, name.length - 5) : name;
  }

  /// Every voice as id → a name to show: "Main voice — jenny_dioco",
  /// "alan (en_GB)". For the news widget's speed settings.
  Future<Map<String, String>> voiceChoices() async {
    final out = <String, String>{};
    for (final v in await voices()) {
      String label = voiceId(v);
      try {
        final j = jsonDecode(await File('$v.json').readAsString());
        final dataset = j is Map ? j['dataset']?.toString() : null;
        final language = j is Map ? j['language'] : null;
        final lang = language is Map ? language['code']?.toString() : null;
        if (dataset != null) label = lang == null ? dataset : '$dataset ($lang)';
      } catch (_) {}
      out[voiceId(v)] = v == _voice ? 'Main voice — $label' : label;
    }
    return out;
  }

  /// The voice for an article by [author]: always the same one for the same
  /// name, picked from it rather than from anything the name might suggest
  /// about the person. Null — the main voice — with no author, or only one
  /// voice installed.
  Future<String?> voiceFor(String? author) async {
    if (author == null || author.trim().isEmpty) return null;
    final all = await voices();
    if (all.length < 2) return null;
    return all[voiceIndex(author, all.length)];
  }

  /// Which of [count] voices [author] gets. FNV-1a over the name as written
  /// in any case or spacing, with any "By" in front taken off: a hash that,
  /// unlike [String.hashCode], is the same on every run.
  @visibleForTesting
  static int voiceIndex(String author, int count) {
    final name = author
        .toLowerCase()
        .replaceFirst(RegExp(r'^\s*by\s+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    var h = 0x811c9dc5;
    for (final c in utf8.encode(name)) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h % count;
  }

  /// Whether speech is possible: both the engine and a voice are present.
  Future<bool> available() async {
    if (_availableCache != null) return _availableCache!;
    final ok = await File(_binary).exists() && await File(_voice).exists();
    if (!ok) {
      debugPrint('Tts: piper or its voice is missing — speech disabled');
    }
    return _availableCache = ok;
  }

  /// How long to leave between the sender and the note.
  ///
  /// Long enough to land as two statements rather than one sentence — you are
  /// meant to hear who it is from, then hear what they said.
  static const Duration announcementGap = Duration(milliseconds: 850);

  /// Speaks each part in turn, with [gap] between them.
  ///
  /// Queued as one unit, so a second note arriving cannot slot itself between
  /// somebody's name and their message.
  Future<void> speakAll(List<String> parts,
      {double volume = 100, Duration gap = announcementGap}) {
    final say = parts.map(_tidy).where((p) => p.isNotEmpty).toList();
    if (say.isEmpty) return Future.value();
    return _queue = _queue.then((_) async {
      for (var i = 0; i < say.length; i++) {
        if (i > 0) await Future<void>.delayed(gap);
        await _speakNow(say[i], volume);
      }
    }).catchError((Object e) => debugPrint('Tts: $e'));
  }

  /// Speaks [text], after anything already queued.
  ///
  /// Silently does nothing when piper is not installed: speech is a nicety,
  /// and a panel that works without it should not start erroring because a
  /// voice model was never downloaded.
  Future<void> speak(String text, {double volume = 100}) {
    final trimmed = _tidy(text);
    if (trimmed.isEmpty) return Future.value();
    // Chained rather than awaited here, so callers are not held up by however
    // long the queue ahead of them takes to read.
    return _queue = _queue
        .then((_) => _speakNow(trimmed, volume))
        .catchError((Object e) => debugPrint('Tts: $e'));
  }

  /// What actually gets said.
  ///
  /// Shared text is written to be read, not spoken: URLs become an unbroken
  /// stream of letters, and a wall of one is worse than saying nothing about
  /// it at all.
  @visibleForTesting
  static String tidy(String text) => _tidy(text);

  static final _url = RegExp(r'https?://\S+', caseSensitive: false);
  static final _whitespace = RegExp(r'\s+');

  static String _tidy(String text) {
    var out = text.replaceAll(_url, ' a link ');
    out = out.replaceAll(_whitespace, ' ').trim();
    // Long enough to be a message, short enough not to trap anyone in a
    // recital. The panel still shows the whole thing.
    const limit = 600;
    if (out.length > limit) {
      out = '${out.substring(0, limit).trimRight()}… and there is more on screen';
    }
    return out;
  }

  /// [text] as speech, in a temporary WAV file the caller deletes — or null
  /// when piper is missing or fails. Nothing is trimmed: this is for callers
  /// that chunk their own text, such as an article being read out.
  /// [speed] is how much faster than the voice's own pace: 1.15 is a
  /// little faster, 0.85 a little slower. Piper takes it as a length scale,
  /// the inverse; held to half to twice the pace.
  Future<File?> synthesise(String text, {String? voice, double speed = 1}) async {
    if (text.trim().isEmpty || !await available()) return null;
    // Only ever a voice from the list — never a path from anywhere else.
    final model = voice != null && (await voices()).contains(voice)
        ? voice
        : _voice;
    final wav = File(
      '${Directory.systemTemp.path}/kiosk-tts-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    final pace = speed.clamp(0.5, 2.0);
    final piper = await Process.start(_binary, [
      '--model', model,
      '--output_file', wav.path,
      if (pace != 1) ...['--length_scale', (1 / pace).toStringAsFixed(3)],
    ]);
    // Text arrives on stdin, which avoids any question of quoting or of a
    // shared note — or a web page — being interpreted as arguments.
    piper.stdin.write(text);
    piper.stdin.write('\n');
    await piper.stdin.flush();
    await piper.stdin.close();
    unawaited(piper.stderr.drain<void>().catchError((_) {}));
    unawaited(piper.stdout.drain<void>().catchError((_) {}));

    final code = await piper.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        piper.kill();
        return -1;
      },
    );
    if (code != 0 || !await wav.exists()) {
      debugPrint('Tts: piper exited $code');
      if (await wav.exists()) await wav.delete();
      return null;
    }
    return wav;
  }

  Future<void> _speakNow(String text, double volume) async {
    final wav = await synthesise(text);
    if (wav == null) return;
    try {
      // Its own player, like the chime, so speaking does not disturb whatever
      // music or video is playing.
      final player = _player ??= Player();
      await player.setVolume(volume);
      await player.open(Media(wav.path));
      // Held until it has been said, so the queue really is sequential.
      await player.stream.completed.first
          .timeout(const Duration(minutes: 2), onTimeout: () => true);
    } finally {
      try {
        if (await wav.exists()) await wav.delete();
      } catch (_) {}
    }
  }

  /// A shared note as the pieces to say, in order.
  ///
  /// Two utterances rather than one string, because piper takes no SSML and a
  /// full stop buys only the pause it would give mid-paragraph. Saying them
  /// separately lets a real gap sit between "who this is from" and "what they
  /// said", which is the difference between an announcement and a run-on
  /// sentence.
  static List<String> announcementParts(
    String text,
    String sender, {
    bool withSender = true,
  }) {
    final body = _tidy(text);
    if (body.isEmpty) return const [];
    if (!withSender || sender.trim().isEmpty) return [body];
    return ['Message from $sender.', body];
  }

  /// Kept for the single-string case and for tests; the spoken path uses
  /// [announcementParts] so the gap can be real.
  static String announcement(String text, String sender,
      {bool withSender = true}) {
    final parts = announcementParts(text, sender, withSender: withSender);
    return parts.join(' ');
  }

  void dispose() {
    _player?.dispose();
    _player = null;
  }

  /// The voice's own name, for showing in Settings. Read from the model's
  /// companion JSON rather than guessed from the file name.
  Future<String?> voiceName() async {
    try {
      final f = File('$_voice.json');
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return null;
      final dataset = j['dataset']?.toString();
      final lang = (j['language'] as Map?)?['name_english']?.toString();
      if (dataset == null) return null;
      return lang == null ? dataset : '$dataset ($lang)';
    } catch (_) {
      return null;
    }
  }
}

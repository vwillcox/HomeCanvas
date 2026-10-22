import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'retry_schedule.dart';
import 'wake_word.dart';

/// The listener, running: what it says, a line at a time, and the way to
/// shut it up again.
class VoiceListener {
  VoiceListener({required this.lines, required this.stop});

  /// Lines of JSON — see `deploy/voice_listener.py` for what they say.
  final Stream<String> lines;

  /// Stops it, and with it the microphone.
  final Future<void> Function() stop;
}

/// Starts the listener, listening for [wake]. Injectable so the service can
/// be tested without one.
typedef VoiceListenerOpener = Future<VoiceListener> Function(WakeWord wake);

/// Where voice control has got to, for the panel to show.
enum VoiceStatus {
  /// Switched off, and the microphone closed.
  off,

  /// Switched on, and not listening yet — or not any more.
  starting,

  /// Waiting for "hey canvas".
  listening,

  /// The wake words were heard; listening for what follows.
  awake,

  /// What followed meant nothing to the panel, and is being asked of
  /// something that may know: Home Assistant.
  asking,

  /// What followed was done.
  done,

  /// What followed meant nothing the panel knows.
  missed,

  /// It cannot listen on this machine: nothing is installed to do it with.
  unavailable,
}

/// "Hey canvas", and what is said after it.
///
/// The hearing is done by another program, `deploy/voice_listener.py`, which
/// this starts and stops — the way the visualiser has `pw-record` and reading
/// aloud has piper. It runs only while voice control is switched on, so with
/// it off there is no process and nothing holding the microphone open.
///
/// That program only hears. Each thing heard arrives here as words, and
/// [act] does them: the kiosk decides what was meant, never the listener.
class VoiceService extends ChangeNotifier {
  VoiceService({
    required this.enabled,
    required this.act,
    WakeWord Function()? wake,
    this.onWake,
    this.ask,
    VoiceListenerOpener? open,
    this.linger = const Duration(seconds: 4),
  }) : wake = wake ?? WakeWord.new,
       _open = open ?? _startListener;

  /// Whether voice control is switched on, asked whenever it may have changed.
  final bool Function() enabled;

  /// The words that wake it, asked at the same times: the listener is
  /// started again when they change.
  final WakeWord Function() wake;

  /// Does what was said, and says what that was; null when it meant nothing.
  final String? Function(String heard) act;

  /// The wake words were heard — before anything is said after them.
  final VoidCallback? onWake;

  /// Asked what [act] made nothing of, elsewhere — Home Assistant — and
  /// gives back its answer; null when it made nothing of it either.
  final Future<String?> Function(String heard)? ask;

  /// How long what was heard stays on show.
  final Duration linger;

  final VoiceListenerOpener _open;
  final RetrySchedule _schedule = RetrySchedule(
    settled: const Duration(seconds: 5),
  );

  VoiceListener? _listener;
  StreamSubscription<String>? _sub;
  Timer? _retry;
  Timer? _settle;
  int _generation = 0;
  bool _wanted = false;

  /// The wake words the running listener was started with, as JSON.
  String? _listeningFor;

  VoiceStatus _status = VoiceStatus.off;
  VoiceStatus get status => _status;

  /// What was last heard after the wake words, as the listener made it out.
  String get heard => _heard;
  String _heard = '';

  /// What was said back, when it was asked elsewhere; empty otherwise.
  String get answer => _answer;
  String _answer = '';

  /// Counts what was heard, so an answer that comes back after something
  /// newer was said is not shown over it.
  int _said = 0;

  /// Why it is not listening, when it should be.
  String? get error => _error;
  String? _error;

  /// Starts or stops listening to match the setting. Safe to call whenever
  /// the settings change.
  void sync() {
    final want = enabled();
    final words = jsonEncode(wake().toJson());
    if (want && _wanted && words != _listeningFor) {
      // Other wake words, chosen while it was listening: the listener is
      // stopped and another started for them. Not one after the other — the
      // old one's microphone is closed either way, and its stream winding
      // up is nothing the new one need wait for.
      unawaited(_stop(VoiceStatus.starting));
      unawaited(_start());
      return;
    }
    if (want == _wanted) return;
    _wanted = want;
    if (want) {
      _schedule.reset();
      unawaited(_start());
    } else {
      unawaited(_stop(VoiceStatus.off));
    }
  }

  Future<void> _start() async {
    if (_sub != null) return;
    _retry?.cancel();
    _retry = null;
    final generation = ++_generation;
    _set(VoiceStatus.starting);
    try {
      final words = wake();
      _listeningFor = jsonEncode(words.toJson());
      final listener = await _open(words);
      // Switched off again while it was starting.
      if (generation != _generation || !_wanted) {
        await listener.stop();
        return;
      }
      _listener = listener;
      _sub = listener.lines.listen(
        _line,
        onError: (Object e) => _lost('$e'),
        onDone: () => _lost('the listener stopped'),
      );
    } on ProcessException catch (e) {
      // Nothing to run: voice control is not installed here. Said once, and
      // not tried again until it is switched off and on.
      _error = e.message;
      _set(VoiceStatus.unavailable);
    } catch (e) {
      _lost('$e');
    }
  }

  Future<void> _stop(VoiceStatus status) async {
    _generation++;
    _said++;
    _retry?.cancel();
    _retry = null;
    _settle?.cancel();
    _settle = null;
    final sub = _sub;
    _sub = null;
    final listener = _listener;
    _listener = null;
    _set(status);
    // The microphone first: closed at once, not when the stream winds up.
    await listener?.stop();
    await sub?.cancel();
  }

  /// The listener went — PipeWire restarted, the microphone was unplugged.
  /// Tried again, less and less often, for as long as it is wanted.
  void _lost(String reason) {
    if (_retry != null || !_wanted) return;
    _error = reason;
    debugPrint('Voice: $reason');
    unawaited(_stop(VoiceStatus.starting));
    _retry = Timer(_schedule.next(hasContent: false), () {
      _retry = null;
      if (_wanted) unawaited(_start());
    });
  }

  void _line(String line) {
    final Object? event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      return; // Something a library printed; not ours.
    }
    if (event is! Map) return;
    switch (event['event']) {
      case 'ready':
        _error = null;
        _schedule.reset();
        _set(VoiceStatus.listening);
      case 'wake':
        _settle?.cancel();
        _said++;
        _heard = '';
        _answer = '';
        _set(VoiceStatus.awake);
        onWake?.call();
      case 'heard':
        final said = ++_said;
        _heard = '${event['text'] ?? ''}'.trim();
        _answer = '';
        // Two recognisers listen, and where the first one's words mean
        // nothing the second's may: "show socks", and "show stocks".
        final other = '${event['other'] ?? ''}'.trim();
        var did = _heard.isEmpty ? null : act(_heard);
        if (did == null && other.isNotEmpty) {
          did = act(other);
          if (did != null) _heard = other;
        }
        _settle?.cancel();
        if (did == null && _heard.isNotEmpty && ask != null) {
          unawaited(_askElsewhere(said, [_heard, if (other.isNotEmpty) other]));
          return;
        }
        debugPrint('Voice: heard "$_heard" — ${did ?? 'not understood'}');
        _finish(did != null);
      case 'error':
        // It says why and then stops; the stopping is what is acted on.
        _error = '${event['message'] ?? ''}';
        debugPrint('Voice: listener: $_error');
    }
  }

  /// Asks [texts] of [ask] in turn, until one is understood.
  Future<void> _askElsewhere(int said, List<String> texts) async {
    _set(VoiceStatus.asking);
    String? answer;
    var heard = texts.first;
    for (final text in texts) {
      answer = await ask!(text);
      // Something newer was said meanwhile, or it was switched off.
      if (said != _said) return;
      if (answer != null) {
        heard = text;
        break;
      }
    }
    _heard = heard;
    _answer = answer ?? '';
    debugPrint('Voice: heard "$_heard" — ${answer ?? 'not understood'}');
    _finish(answer != null, longer: answer != null);
  }

  /// Shows how it went for a while — an answer longer, to be read — then
  /// goes back to listening.
  void _finish(bool understood, {bool longer = false}) {
    _set(understood ? VoiceStatus.done : VoiceStatus.missed);
    _settle?.cancel();
    _settle = Timer(longer ? linger * 2 : linger, () {
      if (_sub != null) _set(VoiceStatus.listening);
    });
  }

  void _set(VoiceStatus status) {
    // Heard twice running is still news: the words will have changed.
    const news = {
      VoiceStatus.awake,
      VoiceStatus.asking,
      VoiceStatus.done,
      VoiceStatus.missed,
    };
    if (_status == status && !news.contains(status)) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _wanted = false;
    unawaited(_stop(VoiceStatus.off));
    super.dispose();
  }

  /// The Python that has the recogniser in it, set up by the installer.
  static String get python => p.join(
    Platform.environment['HOME'] ?? '.',
    '.local',
    'share',
    'homecanvas',
    'voice',
    'venv',
    'bin',
    'python', //
  );

  /// The listener's own file: beside the build it came with, or where the
  /// installer puts the source.
  static String get script {
    // …/homecanvas/build/linux/<arch>/release/bundle/homecanvas
    var folder = File(Platform.resolvedExecutable).parent;
    for (var up = 0; up < 6; up++) {
      final here = p.join(folder.path, 'deploy', 'voice_listener.py');
      if (File(here).existsSync()) return here;
      folder = folder.parent;
    }
    return p.join(
      Platform.environment['HOME'] ?? '.',
      'homecanvas',
      'deploy',
      'voice_listener.py', //
    );
  }

  static Future<VoiceListener> _startListener(WakeWord wake) async {
    if (!File(python).existsSync() || !File(script).existsSync()) {
      throw ProcessException(python, [
        script,
      ], 'voice control is not installed');
    }
    // Below the panel's own work: it listens all day, and nothing it does
    // is worth a dropped frame.
    final process = await Process.start('nice', [
      '-n', '10', python, script, //
      '--wake', jsonEncode(wake.toJson()),
    ]);
    // Drained so a chatty library cannot fill its pipe and wedge.
    unawaited(process.stderr.drain<void>().catchError((_) {}));
    return VoiceListener(
      lines: process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
      stop: () async {
        process.kill();
        await process.exitCode;
      },
    );
  }
}

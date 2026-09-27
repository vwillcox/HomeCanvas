import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Whether the panel's screen is lit — true, or false while it is "off".
///
/// "Off" is the backlight at zero, set by `screen_control.py` for the idle
/// switch-off, Alexa or Home Assistant. The output stays powered for the
/// touchscreen's sake, so without this the kiosk had no idea: behind a
/// black screen every animation still ran at full frame rate, the
/// slideshow went on decoding photos, and every tile kept polling, all
/// night. While this is false the app is hidden as a whole — see the
/// `TickerMode` in `main.dart` and [PauseWhenHidden] — and the services
/// that tick for the screen's sake stand still.
///
/// Told at once by `screen_control.py` through the kiosk's control API,
/// and checked against the backlight itself every [recheck] besides, in
/// case that service is not running or a change came some other way.
class ScreenState extends ValueNotifier<bool> {
  ScreenState({String? backlightDir, this.recheck = const Duration(seconds: 15)})
      : _backlightDir = backlightDir,
        super(true);

  final String? _backlightDir;
  final Duration recheck;
  Timer? _timer;

  bool get lit => value;

  void start() {
    unawaited(check());
    _timer ??= Timer.periodic(recheck, (_) => unawaited(check()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Told by `screen_control.py` as it switches the screen.
  void set(bool lit) {
    if (value == lit) return;
    value = lit;
    debugPrint('ScreenState: screen ${lit ? 'lit' : 'dark'}');
  }

  /// Reads the backlight. Left as it is when there is none to read — a
  /// panel without one is taken to be lit.
  Future<void> check() async {
    final level = await backlightLevel(_backlightDir);
    if (level != null) set(level > 0);
  }

  /// The backlight's raw level, or null without one.
  @visibleForTesting
  static Future<int?> backlightLevel([String? dir]) async {
    try {
      final base = dir ?? await _firstBacklight();
      if (base == null) return null;
      final text = await File('$base/brightness').readAsString();
      return int.tryParse(text.trim());
    } catch (_) {
      return null;
    }
  }

  static String? _found;

  static Future<String?> _firstBacklight() async {
    if (_found != null) return _found;
    final dir = Directory('/sys/class/backlight');
    if (!await dir.exists()) return null;
    await for (final e in dir.list()) {
      return _found = e.path;
    }
    return null;
  }
}

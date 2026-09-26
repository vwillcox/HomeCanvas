import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'config_service.dart';

/// The panel's backlight, set from Settings or the editor's web page and
/// put back whenever the kiosk starts.
///
/// Set through `deploy/screen_control.py`, like switching the screen off,
/// so that service knows the level to come back to after an idle switch-off
/// or Alexa — writing the backlight behind its back would have the next
/// wake undo it. Straight to sysfs only when that service isn't running.
///
/// Put back on start because systemd-backlight restores the level saved at
/// shutdown, and a Pi shut down while the screen was asleep saved 0, which
/// it refuses and turns into 1: a panel you can barely see.
class BrightnessService extends ChangeNotifier {
  BrightnessService(
    this._config, {
    Dio? dio,
    String? backlightDir,
    String base = 'http://127.0.0.1:8765',
    Future<void> Function()? save,
  })  : _base = base,
        _save = save ?? _config.save,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 2),
              receiveTimeout: const Duration(seconds: 2),
            )),
        _backlightDir = backlightDir;

  /// Below this the panel is on but unreadable — as good as off, and "off"
  /// is the screen settings' job.
  static const int minimum = 5;

  final ConfigService _config;

  /// Where screen_control.py listens; a test points this somewhere closed
  /// rather than at the real panel.
  final String _base;
  final Dio _dio;

  /// Writes the config file; a test swaps this for one that doesn't touch
  /// the real one.
  final Future<void> Function() _save;
  final String? _backlightDir;

  /// Coalesces a slider's stream of values into one write at a time.
  Timer? _debounce;
  Timer? _saveLater;

  /// Percent, as saved.
  int get level => clamp(_config.config.screen.brightness);

  static int clamp(num v) => v.round().clamp(minimum, 100);

  /// Puts the saved level back — unless the screen is switched off, which
  /// a restart of the kiosk has no business undoing.
  Future<void> start() async {
    final now = await _current();
    if (now == 0) return;
    await _apply(level);
  }

  /// A new level, from a slider as it moves. Shown at once, written to the
  /// panel a moment later, saved once the slider has settled.
  void set(num percent) {
    final v = clamp(percent);
    if (v == _config.config.screen.brightness) return;
    _config.config.screen.brightness = v;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 60), () => _apply(v));
    _saveLater?.cancel();
    _saveLater = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _apply(int percent) async {
    try {
      await _dio.get('$_base/screen/brightness',
          queryParameters: {'value': percent});
      return;
    } catch (e) {
      debugPrint('Brightness: screen_control unreachable ($e); writing sysfs');
    }
    final dir = await _backlight();
    if (dir == null) return;
    try {
      final max = int.parse(
          (await File('$dir/max_brightness').readAsString()).trim());
      final raw = (percent * max / 100).round().clamp(1, max);
      await File('$dir/brightness').writeAsString('$raw');
    } catch (e) {
      debugPrint('Brightness: could not write the backlight: $e');
    }
  }

  /// The panel's level now, in percent; null when it can't be told.
  Future<int?> _current() async {
    try {
      final r = await _dio.get('$_base/screen');
      final b = (r.data as Map)['brightness'];
      if (b is num) return b.round();
    } catch (_) {}
    final dir = await _backlight();
    if (dir == null) return null;
    try {
      final now = int.parse((await File('$dir/brightness').readAsString()).trim());
      final max = int.parse(
          (await File('$dir/max_brightness').readAsString()).trim());
      return max == 0 ? null : (now * 100 / max).round();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _backlight() async {
    if (_backlightDir != null) return _backlightDir;
    final root = Directory('/sys/class/backlight');
    if (!await root.exists()) return null;
    await for (final e in root.list()) {
      return e.path;
    }
    return null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _saveLater?.cancel();
    _dio.close();
    super.dispose();
  }
}

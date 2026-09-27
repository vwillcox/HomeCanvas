import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'private_file.dart';

/// Loads/saves [AppConfig] to ~/.config/homecanvas/config.json and notifies
/// listeners on change. A single instance is shared app-wide.
class ConfigService extends ChangeNotifier {
  AppConfig _config = AppConfig();
  AppConfig get config => _config;

  // Convenience passthroughs.
  String get immichUrl => _config.immichUrl;
  String get apiKey => _config.apiKey;
  String get immichEmail => _config.immichEmail;
  String get immichPassword => _config.immichPassword;
  bool get isConfigured => _config.isConfigured;
  SlideshowSettings get slideshow => _config.slideshow;

  static String get _home => Platform.environment['HOME'] ?? '.';

  File get _file => File('$_home/.config/homecanvas/config.json');

  /// Location used before the project was renamed from TabletPi.
  File get _legacyFile => File('$_home/.config/tabletpi/config.json');

  /// Carry an existing TabletPi config over on first run after the rename, so
  /// upgrades don't lose the server URL, API key or saved login.
  Future<void> _migrateLegacyConfig() async {
    try {
      final f = _file;
      if (await f.exists()) return;
      final legacy = _legacyFile;
      if (!await legacy.exists()) return;
      await f.parent.create(recursive: true);
      await legacy.copy(f.path);
      debugPrint('Migrated config from ${legacy.path} to ${f.path}');
    } catch (e) {
      debugPrint('ConfigService migration error: $e');
    }
  }

  Future<void> load() async {
    await _migrateLegacyConfig();
    try {
      final f = _file;
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _config = AppConfig.fromJson(data);
      }
    } catch (e) {
      debugPrint('ConfigService.load error: $e');
      // Kept aside rather than overwritten by the first save of an empty
      // config, so what was in it can still be recovered by hand.
      try {
        await _file.copy('${_file.path}.unreadable');
      } catch (_) {}
    }
    notifyListeners();
  }

  /// The save under way, so the next waits for it: saves are started from
  /// all over, often without waiting, and two writing at once could finish
  /// in either order.
  Future<void> _saving = Future.value();

  Future<void> save() {
    // What is saved is the config as it is when this save's turn comes.
    final done = _saving.then((_) => _write());
    _saving = done;
    return done.whenComplete(notifyListeners);
  }

  /// Private — it holds the Immich password and every token — and written
  /// whole: a power cut part-way through a save used to leave half a file,
  /// which the next start could not read, and so began again from nothing.
  Future<void> _write() async {
    try {
      await writePrivateFile(_file.path,
          const JsonEncoder.withIndent('  ').convert(_config.toJson()));
    } catch (e) {
      debugPrint('ConfigService.save error: $e');
    }
  }

  Future<void> setConnection(String url, String key) async {
    _config.immichUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    _config.apiKey = key.trim();
    await save();
  }

  Future<void> setCredentials(String email, String password) async {
    _config.immichEmail = email.trim();
    _config.immichPassword = password;
    await save();
  }

  /// Remember the video player's level between videos (and restarts).
  Future<void> setVideoAudio(double volume, bool muted) async {
    _config.videoVolume = volume;
    _config.videoMuted = muted;
    await save();
  }

  Future<void> updateSlideshow(SlideshowSettings s) async {
    _config.slideshow = s;
    await save();
  }
}

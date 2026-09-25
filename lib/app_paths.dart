import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Where HomeCanvas keeps its settings and its cache — and moving them there
/// from the name the project had before.
///
/// The folders are moved rather than copied, on the first start after the
/// rename, and a link is left at each old path so anything still pointing
/// there — a script on the Pi, an old unit file — keeps working.
class AppPaths {
  static const name = 'homecanvas';

  /// Earlier names, newest first. (TabletPi, before that, is carried over
  /// by [ConfigService] itself.)
  static const _legacy = ['immich_kiosk_pi'];

  static String get _home => Platform.environment['HOME'] ?? '.';

  static String get config => p.join(_home, '.config', name);
  static String get cache => p.join(_home, '.cache', name);

  /// Moves an old settings or cache folder to its new name, if there is one
  /// and nothing is at the new name yet. Safe to call on every start.
  static Future<void> migrate() async {
    for (final base in ['.config', '.cache']) {
      final target = Directory(p.join(_home, base, name));
      for (final old in _legacy) {
        final from = Directory(p.join(_home, base, old));
        await moveFolder(from, target);
      }
    }
  }

  /// Moves [from] to [to]. If [to] is already there — something else on
  /// the Pi, such as the screen controller writing its log, can make it a
  /// moment first — whatever it lacks is moved across instead; nothing in it
  /// is overwritten. The old path then becomes a link, once it is empty.
  @visibleForTesting
  static Future<void> moveFolder(Directory from, Directory to) async {
    try {
      if (await FileSystemEntity.isLink(from.path)) return; // done already
      if (!await from.exists()) return;
      if (!await to.exists()) {
        await to.parent.create(recursive: true);
        await from.rename(to.path);
      } else {
        await for (final e in from.list()) {
          final dest = p.join(to.path, p.basename(e.path));
          if (await FileSystemEntity.type(dest, followLinks: false) ==
              FileSystemEntityType.notFound) {
            await e.rename(dest);
          }
        }
        if (!await from.list().isEmpty) {
          debugPrint('AppPaths: left ${from.path} — both had the same files');
          return;
        }
        await from.delete();
      }
      await Link(from.path).create(to.path);
      debugPrint('Moved ${from.path} to ${to.path}');
    } catch (e) {
      debugPrint('AppPaths: could not move ${from.path}: $e');
    }
  }
}

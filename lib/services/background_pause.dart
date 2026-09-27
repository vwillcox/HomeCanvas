import 'dart:io';

import 'package:flutter/foundation.dart';

/// Pauses other programs on the panel that cannot be seen while a video
/// fills the screen, and carries them on afterwards.
///
/// The Pi decodes YouTube on its CPU, and at 1080p60 every core counts. The
/// desktop's taskbar sits permanently behind the kiosk yet redraws itself all
/// day, and the TV remote app is a whole second Flutter program behind it. A
/// stopped process is given no CPU at all, and SIGCONT picks it up exactly
/// where it was, so nothing is lost but a few seconds of the remote's TV
/// connection, which it re-establishes by itself.
///
/// Only the current user's own processes, found by exact name, so nothing
/// else on the machine can be caught by it.
class BackgroundPause {
  BackgroundPause({
    this.names = const ['wf-panel-pi', 'vidaa_remote'],
    Future<List<int>> Function(String name)? find,
    bool Function(int pid, ProcessSignal signal)? signal,
  })  : _find = find ?? _pgrep,
        _signal = signal ?? Process.killPid;

  /// Process names, exactly as `pgrep -x` matches them.
  final List<String> names;
  final Future<List<int>> Function(String name) _find;
  final bool Function(int pid, ProcessSignal signal) _signal;

  final Set<int> _paused = {};
  bool get paused => _paused.isNotEmpty;

  static Future<List<int>> _pgrep(String name) async {
    try {
      final user = Platform.environment['USER'];
      final r = await Process.run(
          'pgrep', ['-x', if (user != null) ...['-u', user], name]);
      if (r.exitCode != 0) return const [];
      return [
        for (final line in (r.stdout as String).split('\n'))
          ?int.tryParse(line.trim()),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> pause() async {
    for (final name in names) {
      for (final pid in await _find(name)) {
        if (_signal(pid, ProcessSignal.sigstop)) _paused.add(pid);
      }
    }
    if (_paused.isNotEmpty) {
      debugPrint('BackgroundPause: paused ${_paused.length} for video');
    }
  }

  /// Carries on everything paused. Also sent at start-up to every process of
  /// these names, in case the kiosk stopped while they were paused.
  Future<void> resume({bool all = false}) async {
    final pids = {..._paused};
    if (all) {
      for (final name in names) {
        pids.addAll(await _find(name));
      }
    }
    for (final pid in pids) {
      _signal(pid, ProcessSignal.sigcont);
    }
    _paused.clear();
  }
}

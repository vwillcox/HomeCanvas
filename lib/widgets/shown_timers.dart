import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'pause_when_hidden.dart';

/// Timers that stand still while their widget cannot be seen.
///
/// For a tile that polls — a server's status, the next trains, the lights —
/// or changes what it shows on a timer. While it is hidden, behind a
/// full-screen video, under Settings, or with the screen dark, its ticks
/// are skipped: no network, no rebuild, no frame, for nobody. A tick missed
/// that way is made up once, the moment it is shown again, so it is never
/// out of date on screen.
mixin ShownTimers<T extends StatefulWidget> on PauseWhenHidden<T> {
  final List<Timer> _timers = [];
  final Map<Timer, VoidCallback> _missed = {};

  /// Calls [tick] every [every] while this is shown. Cancel the timer it
  /// returns to stop it, as with any other; they are all cancelled with the
  /// widget.
  Timer everyWhileShown(Duration every, VoidCallback tick) {
    late final Timer timer;
    timer = Timer.periodic(every, (_) {
      if (!mounted) return;
      if (shown) {
        tick();
      } else {
        _missed[timer] = tick;
      }
    });
    _timers
      ..removeWhere((t) => !t.isActive)
      ..add(timer);
    return timer;
  }

  @override
  void onShownChanged(bool shown) {
    super.onShownChanged(shown);
    if (!shown || _missed.isEmpty) return;
    final due = Map.of(_missed);
    _missed.clear();
    // Told in the middle of a build further up; caught up once it is done.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      due.forEach((timer, tick) {
        if (timer.isActive) tick();
      });
    });
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _missed.clear();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

/// A value running from 0 to 1 over [duration], told to its listeners in
/// [steps] steps rather than on every frame.
///
/// For a slow progress drawn small — a page's time filling a dot a few dozen
/// pixels wide. An AnimationController would ask for a frame sixty times a
/// second for the whole of that time, and on this panel a frame means the
/// glass blur behind the dot drawn again too: some eighteen hundred frames
/// for a thirty-second page, to show forty-four different pictures.
///
/// [hold] stops it without forgetting where it was — for while the progress
/// cannot be seen.
class SteppedTimeline extends ChangeNotifier implements ValueListenable<double> {
  SteppedTimeline({required this.onDone, this.steps = 44});

  /// Called when the value reaches 1.
  final VoidCallback onDone;

  /// How many times over [duration] listeners are told.
  final int steps;

  Duration duration = Duration.zero;

  double _value = 0;
  Timer? _step;
  bool _running = false;
  bool _held = false;

  /// Running forward, whether or not it is held for now.
  bool get isAnimating => _running;

  @override
  double get value => _value;

  set value(double v) {
    _value = v.clamp(0.0, 1.0);
    if (_running) _resume();
    notifyListeners();
  }

  /// Runs on towards 1, from [from] if given, else from where it is.
  void forward({double? from}) {
    if (from != null) _value = from.clamp(0.0, 1.0);
    _running = true;
    _resume();
    notifyListeners();
  }

  /// Stops where it is.
  void stop() {
    _cancel();
    _running = false;
    notifyListeners();
  }

  /// Held, it stands still; let go, it carries on. Only matters while
  /// running.
  void hold(bool held) {
    if (held == _held) return;
    _held = held;
    if (!_running) return;
    held ? _cancel() : _resume();
  }

  /// Counted in steps rather than timed with a clock, so it runs the same
  /// under a test's pretend time as for real. Held part-way through a step,
  /// that step starts again: at most a forty-fourth of the time.
  void _resume() {
    _cancel();
    if (_held || duration <= Duration.zero) return;
    final every = duration ~/ steps;
    _step = Timer.periodic(every > Duration.zero ? every : duration, (_) {
      _value = (_value + 1 / steps).clamp(0.0, 1.0);
      if (_value >= 1 - 1e-9) {
        _finish();
      } else {
        notifyListeners();
      }
    });
  }

  void _finish() {
    _cancel();
    _value = 1;
    _running = false;
    notifyListeners();
    onDone();
  }

  void _cancel() {
    _step?.cancel();
    _step = null;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// For a widget that does work on a timer — decoding the next photo,
/// capturing sound for a visualiser — to stop doing it while it cannot be
/// seen.
///
/// "Seen" is Flutter's own [TickerMode]: the Navigator switches it off for a
/// screen covered by another, and the app switches it off for everything
/// under a full-screen video. Animations stop by themselves when it does;
/// timers and captures do not, and on a Pi playing 1080p60 in software every
/// photo decoded behind the video is a frame the video drops.
mixin PauseWhenHidden<T extends StatefulWidget> on State<T> {
  ValueListenable<TickerModeData>? _mode;

  /// Whether this widget is on screen now.
  bool get shown => _mode?.value.enabled ?? true;

  /// Called when [shown] changes. Timers can simply check [shown] instead;
  /// this is for work that has to be stopped and started, like a capture.
  void onShownChanged(bool shown) {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode = TickerMode.getValuesNotifier(context);
    if (mode == _mode) return;
    _mode?.removeListener(_changed);
    _mode = mode..addListener(_changed);
  }

  void _changed() => onShownChanged(shown);

  @override
  void dispose() {
    _mode?.removeListener(_changed);
    super.dispose();
  }
}

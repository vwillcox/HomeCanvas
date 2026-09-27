import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'pause_when_hidden.dart';

/// Rebuilds once a minute, for a widget whose words are about "now" — "in
/// 3 days", "rain in 20 minutes", "tonight" — which move on even when
/// nothing it reads has changed.
///
/// Not while it cannot be seen: behind a full-screen video or Settings a
/// rebuild is layout and painting for nobody. The minute it missed is
/// caught up the moment it is shown again, so it is never out of date on
/// screen.
mixin RebuildEveryMinute<T extends StatefulWidget> on PauseWhenHidden<T> {
  Timer? _minute;
  bool _missed = false;

  @override
  void initState() {
    super.initState();
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (shown) {
        setState(() {});
      } else {
        _missed = true;
      }
    });
  }

  @override
  void onShownChanged(bool shown) {
    super.onShownChanged(shown);
    if (!shown || !_missed) return;
    _missed = false;
    // Told in the middle of a build further up; rebuilt once it is done.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minute?.cancel();
    super.dispose();
  }
}

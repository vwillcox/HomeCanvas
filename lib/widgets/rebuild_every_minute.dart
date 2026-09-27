import 'package:flutter/widgets.dart';

import 'pause_when_hidden.dart';
import 'shown_timers.dart';

/// Rebuilds once a minute, for a widget whose words are about "now" — "in
/// 3 days", "rain in 20 minutes", "tonight" — which move on even when
/// nothing it reads has changed.
///
/// Not while it cannot be seen: behind a full-screen video, Settings or a
/// dark screen, a rebuild is layout and painting for nobody. The minute it
/// missed is caught up the moment it is shown again — see [ShownTimers].
mixin RebuildEveryMinute<T extends StatefulWidget>
    on PauseWhenHidden<T>, ShownTimers<T> {
  @override
  void initState() {
    super.initState();
    everyWhileShown(const Duration(minutes: 1), () => setState(() {}));
  }
}

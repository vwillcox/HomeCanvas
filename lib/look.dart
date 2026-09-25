import 'package:flutter/material.dart';

import 'dashboard/dashboard_theme.dart';

/// The theme the whole kiosk is drawn in — the one picked for the dashboard,
/// which now dresses every screen: the photo browser, the player, Settings
/// and the rest.
///
/// Placed above the app, so every screen and overlay can reach it with
/// `context.look`. Anywhere it is missing — a widget test, say — gets Glass,
/// the kiosk's own look.
class KioskLook extends InheritedWidget {
  const KioskLook({super.key, required this.theme, required super.child});

  final DashboardTheme theme;

  static DashboardTheme of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KioskLook>()?.theme ??
      kBuiltInThemes.first;

  @override
  bool updateShouldNotify(KioskLook oldWidget) => theme != oldWidget.theme;
}

extension LookContext on BuildContext {
  /// The theme the kiosk is drawn in.
  DashboardTheme get look => KioskLook.of(this);
}

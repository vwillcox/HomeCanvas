// Written by scripts/widget-build.sh from the add-ons installed and the
// widgets uploaded in the editor. Do not edit by hand: it is written again
// at every build.
import 'package:flutter/foundation.dart';

import '../../widget_registry.dart';

/// The add-ons installed from the catalogue and built into this copy of
/// the app, by name: each the widgets it brings.
final Map<String, List<DashboardWidgetType> Function()> addonWidgets = {
};

/// The widgets uploaded as Dart from the editor and built into this copy
/// of the app, by the file each came from.
final Map<String, DashboardWidgetType Function()> customCodeWidgets = {
};

/// Registers them: add-ons first, then uploads. One that throws, or that
/// names itself after a widget there already is, is left out and said so
/// in the log.
void registerCustomCodeWidgets() {
  void add(String from, DashboardWidgetType type) {
    if (WidgetRegistry.find(type.type) != null) {
      debugPrint('Widget $from: "${type.type}" is taken');
      return;
    }
    WidgetRegistry.register(type);
  }

  for (final e in addonWidgets.entries) {
    try {
      for (final type in e.value()) {
        add(e.key, type);
      }
    } catch (error) {
      debugPrint('Add-on ${e.key}: $error');
    }
  }
  for (final e in customCodeWidgets.entries) {
    try {
      add(e.key, e.value());
    } catch (error) {
      debugPrint('Custom widget ${e.key}: $error');
    }
  }
}

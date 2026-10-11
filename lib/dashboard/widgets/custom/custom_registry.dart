// Written by scripts/widget-build.sh from the widgets uploaded in the
// editor. Do not edit by hand: it is written again at every build.
import 'package:flutter/foundation.dart';

import '../../widget_registry.dart';

/// The widgets uploaded as Dart from the editor and built into this copy
/// of the app, by the file each came from.
final Map<String, DashboardWidgetType Function()> customCodeWidgets = {
};

/// Registers them. One that throws, or that names itself after a widget
/// there already is, is left out and said so in the log.
void registerCustomCodeWidgets() {
  for (final e in customCodeWidgets.entries) {
    try {
      final type = e.value();
      if (WidgetRegistry.find(type.type) != null) {
        debugPrint('Custom widget ${e.key}: "${type.type}" is taken');
        continue;
      }
      WidgetRegistry.register(type);
    } catch (error) {
      debugPrint('Custom widget ${e.key}: $error');
    }
  }
}

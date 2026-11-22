import '../widget_registry.dart';
import 'calendar_widget.dart';
import 'custom/custom_registry.dart';
import 'parcels_widget.dart';

/// Every widget type this build of the dashboard has.
///
/// Two are the app's own, because the app itself leans on them: the day's
/// brief reads the calendar, and a shared tracking link becomes a parcel.
/// Every other widget is an add-on, kept in a repository of its own —
/// vwillcox/HomeCanvas-Widgets — installed from the editor's Add-ons page
/// and built in by `scripts/widget-build.sh`, which writes the registry
/// that [registerCustomCodeWidgets] reads. See
/// `lib/dashboard/widgets/README.md`.
void registerBuiltInWidgets() {
  WidgetRegistry.registerAll([calendarWidgetType, parcelsWidgetType]);
  // After the app's own, so none of them can be taken the place of.
  registerCustomCodeWidgets();
}

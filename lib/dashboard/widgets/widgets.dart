import 'custom/custom_registry.dart';

/// Every widget type this build of the dashboard has.
///
/// None is the app's own. Every widget is an add-on, kept in a repository
/// of its own — vwillcox/HomeCanvas-Widgets — installed from the editor's
/// Add-ons page and built in by `scripts/widget-build.sh`, which writes the
/// registry that [registerCustomCodeWidgets] reads. What this folder holds
/// is what widgets are made from. See `lib/dashboard/widgets/README.md`.
void registerBuiltInWidgets() => registerCustomCodeWidgets();

import '../widget_registry.dart';
import 'air_quality_widget.dart';
import 'bins_widget.dart';
import 'calendar_widget.dart';
import 'clock_widget.dart';
import 'news_widget.dart';
import 'omarchy_widget.dart';
import 'spotify_widget.dart';
import 'immich_widget.dart';
import 'lan_speedtest_widget.dart';
import 'memories_widget.dart';
import 'notes_widget.dart';
import 'servers_widget.dart';
import 'services_widget.dart';
import 'speedtest_widget.dart';
import 'sun_moon_widget.dart';
import 'timers_widget.dart';
import 'tv_widget.dart';
import 'unifi_widgets.dart';
import 'weather_widget.dart';

/// Every widget type the dashboard ships with.
///
/// Adding one means writing it, then adding it to this list — see
/// `lib/dashboard/widgets/README.md`. Nothing else needs changing: the
/// editor's palette and its settings form are both generated from the
/// descriptors.
void registerBuiltInWidgets() {
  WidgetRegistry.registerAll([
    clockWidgetType,
    weatherWidgetType,
    spotifyWidgetType,
    calendarWidgetType,
    newsWidgetType,
    tvWidgetType,
    speedtestWidgetType,
    lanSpeedtestWidgetType,
    immichWidgetType,
    omarchyWidgetType,
    unifiHealthWidgetType,
    unifiPresenceWidgetType,
    unifiDevicesWidgetType,
    unifiClientsWidgetType,
    unifiThroughputWidgetType,
    unifiIspWidgetType,
    memoriesWidgetType,
    timersWidgetType,
    sunMoonWidgetType,
    airQualityWidgetType,
    binsWidgetType,
    notesWidgetType,
    serversWidgetType,
    servicesWidgetType,
  ]);
}

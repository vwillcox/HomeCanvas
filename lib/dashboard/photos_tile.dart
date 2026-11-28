import 'dashboard_model.dart';
import 'schedule.dart';
import 'widget_registry.dart';

/// The widget type of the photo albums: an add-on, the Photo albums.
const String albumsWidgetType = 'immich_albums';

/// Gives a panel the albums as a tile, once, when it comes to a build where
/// they are no longer a screen of their own.
///
/// Until 2.0 the kiosk opened on the album browser. Now it opens on the
/// dashboard, and the albums are an add-on. A panel connected to Immich had
/// the browser, so it is given the tile — on a page of its own after the
/// others, named Photos, filling it; on the first page if the dashboard was
/// empty, as on a panel that only ever showed photos. The top bar's Photos
/// button goes to it.
///
/// Waits, saying nothing, until the add-on is built in: the build that
/// brings it is the update itself (`scripts/addons.py ensure` fetches it).
/// True when [settings] were changed, to be saved.
bool offerAlbumsTile(
  DashboardSettings settings, {
  required bool immichConnected,
}) {
  if (settings.albumsOffered) return false;
  if (settings.widgets.any((w) => w.type == albumsWidgetType)) {
    settings.albumsOffered = true;
    return true;
  }
  if (!immichConnected || WidgetRegistry.find(albumsWidgetType) == null) {
    return false;
  }
  final page = settings.widgets.isEmpty ? 0 : settings.pageCount;
  final ids = {for (final w in settings.widgets) w.id};
  var id = 'photos';
  for (var n = 2; ids.contains(id); n++) {
    id = 'photos$n';
  }
  settings.widgets.add(
    DashboardWidgetConfig(
      id: id,
      type: albumsWidgetType,
      x: 0,
      y: 0,
      width: DashboardGrid.columns,
      height: DashboardGrid.rows,
      page: page,
    ),
  );
  final pages = [...settings.pages];
  while (pages.length <= page) {
    pages.add(const DashboardPage());
  }
  pages[page] = const DashboardPage(name: 'Photos');
  settings.pages = pages;
  settings.albumsOffered = true;
  return true;
}

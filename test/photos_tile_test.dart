import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/photos_tile.dart';
import 'package:home_canvas/dashboard/schedule.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';

/// Before 2.0 the kiosk opened on the album browser; since, on the
/// dashboard, with the albums an add-on. A panel that had them is given them
/// as a tile, once.
void main() {
  DashboardWidgetConfig tile(String id, String type, int page) =>
      DashboardWidgetConfig(
        id: id,
        type: type,
        x: 0,
        y: 0,
        width: 3,
        height: 3,
        page: page,
      );

  setUp(() {
    WidgetRegistry.register(
      DashboardWidgetType(
        type: albumsWidgetType,
        category: WidgetCategory.photosAndMedia,
        name: 'Photo albums',
        description: 'Stands in for the add-on.',
        glyph: '🖼️',
        build: (context, w) => const SizedBox(),
      ),
    );
  });
  tearDown(() => WidgetRegistry.unregister(albumsWidgetType));

  test('a panel on Immich gets a page of albums after its others', () {
    final s = DashboardSettings(
      widgets: [tile('photos', 'clock', 0), tile('b', 'news', 2)],
      pages: const [DashboardPage(name: 'Main')],
    );
    expect(offerAlbumsTile(s, immichConnected: true), isTrue);
    final added = s.widgets.last;
    expect(added.type, albumsWidgetType);
    expect(added.page, 3);
    expect(added.id, 'photos2');
    expect((added.width, added.height), (12, 8));
    expect(s.pages.length, 4);
    expect(s.pages[0].name, 'Main');
    expect(s.pages[3].name, 'Photos');
    expect(s.albumsOffered, isTrue);
    expect(s.toJson()['albumsOffered'], isTrue);
    // Once only: taken off again, it stays off.
    s.widgets.removeLast();
    expect(offerAlbumsTile(s, immichConnected: true), isFalse);
    expect(s.widgets.any((w) => w.type == albumsWidgetType), isFalse);
  });

  test('a panel that only showed photos has them as its first page', () {
    final s = DashboardSettings();
    expect(offerAlbumsTile(s, immichConnected: true), isTrue);
    expect(s.widgets.single.page, 0);
    expect(s.pages.single.name, 'Photos');
  });

  test('nothing for a panel never connected to Immich', () {
    final s = DashboardSettings(widgets: [tile('a', 'clock', 0)]);
    expect(offerAlbumsTile(s, immichConnected: false), isFalse);
    expect(s.widgets.length, 1);
    expect(s.albumsOffered, isFalse);
  });

  test('waits while the add-on is not built in', () {
    WidgetRegistry.unregister(albumsWidgetType);
    final s = DashboardSettings(widgets: [tile('a', 'clock', 0)]);
    expect(offerAlbumsTile(s, immichConnected: true), isFalse);
    expect(s.albumsOffered, isFalse);
  });

  test('one already placed by hand is left where it is', () {
    final s = DashboardSettings(widgets: [tile('a', albumsWidgetType, 1)]);
    expect(offerAlbumsTile(s, immichConnected: true), isTrue);
    expect(s.widgets.length, 1);
    expect(s.albumsOffered, isTrue);
  });
}

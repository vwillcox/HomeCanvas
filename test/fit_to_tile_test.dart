import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/fit_canvas.dart';
import 'package:home_canvas/dashboard/widgets/unifi_widgets.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/unifi_models.dart';
import 'package:home_canvas/services/unifi_service.dart';

/// A console that has already answered: two devices, like the panel's.
class FakeUnifi extends UnifiService {
  FakeUnifi(this._devs) : super(ConfigService());
  final List<UnifiDevice> _devs;

  @override
  List<UnifiDevice> get devices => _devs;
  @override
  List<UnifiClient> get clients => [
        for (var i = 0; i < 29; i++)
          UnifiClient(id: '$i', name: 'c$i', type: 'WIRELESS'),
      ];
  @override
  bool get hasContent => true;
  @override
  UnifiStats get gatewayStats => const UnifiStats(
      txRateBps: 50000, rxRateBps: 54000, cpuPct: 28, memoryPct: 68);
  @override
  UnifiStats statsFor(String id) => const UnifiStats(uptimeSec: 11 * 86400);
  @override
  List<UnifiDevice> get offlineDevices => const [];
  @override
  List<UnifiDevice> get updatableDevices => const [];
}

List<UnifiDevice> devices(int n) => [
      for (var i = 0; i < n; i++)
        UnifiDevice(
          id: 'd$i',
          name: i == 0 ? 'Dream Router 7' : 'USW Flex 2.5G $i',
          model: i == 0 ? 'UDR7' : 'USW Flex 2.5G',
          state: 'ONLINE',
          firmwareVersion: '5.1.33',
        ),
    ];

/// The panel's grid: a 1900 × 1080 area, 12 × 8 cells, 10 px gaps — then
/// the tile's own padding taken off, as the dashboard does.
Size tile(int w, int h) {
  const gap = 10.0;
  final cellW = (1900 - gap * 13) / 12;
  final cellH = (1080 - gap * 9) / 8;
  return Size(w * cellW + (w - 1) * gap - 16, h * cellH + (h - 1) * gap - 16);
}

Future<void> pump(WidgetTester tester, Widget child, Size size,
    UnifiService unifi) async {
  tester.view.physicalSize = const Size(1920, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<UnifiService>.value(
    value: unifi,
    child: MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(size: size, child: child),
        ),
      ),
    ),
  ));
}

DashboardWidgetContext ctx(String type) => DashboardWidgetContext(
      theme: kBuiltInThemes.first,
      config: DashboardWidgetConfig(
          id: 't', type: type, x: 0, y: 0, width: 4, height: 2),
    );

/// How tall [text] is on screen, after every scaling on the way there.
double shownHeight(WidgetTester tester, String text) =>
    tester.getRect(find.text(text)).height;

void main() {
  group('the canvas', () {
    test('has the tile\'s own shape, so the fit is exact', () {
      final c = FitCanvas.canvasFor(const Size(600, 240));
      expect(c.height, 100);
      expect(c.width / c.height, closeTo(600 / 240, 1e-9));
    });

    test('stops growing type past its limit on a huge tile', () {
      final c = FitCanvas.canvasFor(const Size(1800, 1000), maxScale: 4);
      // 1000 px at the ×4 limit is a 250-unit canvas: the extra room is
      // shared out rather than the type growing.
      expect(c.height, 250);
    });
  });

  group('arranging entries across a tile', () {
    test('two on a wide, short strip go side by side', () {
      expect(bestGrid(2, tile(5, 1), cellAspect: 3.2),
          (columns: 2, rows: 1));
    });

    test('two on a tall, narrow tile stack', () {
      expect(bestGrid(2, tile(2, 4), cellAspect: 3.2),
          (columns: 1, rows: 2));
    });

    test('many make a grid', () {
      final g = bestGrid(6, tile(8, 3), cellAspect: 3.2);
      expect(g.columns * g.rows, greaterThanOrEqualTo(6));
      expect(g.columns, greaterThan(1));
      expect(g.rows, greaterThan(1));
    });
  });

  group('the health panel\'s shape', () {
    test('follows the tile', () {
      expect(healthLayoutFor(6), HealthLayout.strip);
      expect(healthLayoutFor(2.6), HealthLayout.stacked);
      expect(healthLayoutFor(0.6), HealthLayout.column);
    });
  });

  group('on the panel, as placed', () {
    testWidgets('network health (4 × 2) has figures you can read',
        (tester) async {
      await pump(tester, UnifiHealthWidget(w: ctx('unifi_health')),
          tile(4, 2), FakeUnifi(devices(2)));
      // Before: 26 × 0.67 = 17 px values, about 20 px of line, in a tile
      // with room for far more. Now sized from the tile: over double.
      expect(shownHeight(tester, '54 kb/s'), greaterThan(40));
      expect(shownHeight(tester, 'Network healthy'), greaterThan(28));
      expect(tester.takeException(), isNull);
    });

    testWidgets('devices (5 × 1) has names you can read', (tester) async {
      await pump(tester, UnifiDevicesWidget(w: ctx('unifi_devices')),
          tile(5, 1), FakeUnifi(devices(2)));
      // Before: 15 × 0.45 = 7 px.
      expect(shownHeight(tester, 'Dream Router 7'), greaterThan(24));
      // Side by side, not one above the other.
      final a = tester.getRect(find.text('Dream Router 7'));
      final b = tester.getRect(find.text('USW Flex 2.5G 1'));
      expect(b.left, greaterThan(a.right));
      expect(tester.takeException(), isNull);
    });
  });

  group('at every size and shape', () {
    // Every tile from 1 × 1 to 12 × 8. Overflow is reported as an exception,
    // so this is the check that nothing ever runs off its tile.
    final sizes = [
      for (var w = 1; w <= 12; w++)
        for (var h = 1; h <= 8; h++) (w, h),
    ];

    testWidgets('network health never overflows', (tester) async {
      final unifi = FakeUnifi(devices(2));
      for (final (w, h) in sizes) {
        await pump(tester, UnifiHealthWidget(w: ctx('unifi_health')),
            tile(w, h), unifi);
        expect(tester.takeException(), isNull, reason: '$w × $h');
      }
    });

    testWidgets('devices never overflow, however many there are',
        (tester) async {
      for (final n in [1, 2, 5, 12]) {
        final unifi = FakeUnifi(devices(n));
        for (final (w, h) in sizes) {
          await pump(tester, UnifiDevicesWidget(w: ctx('unifi_devices')),
              tile(w, h), unifi);
          expect(tester.takeException(), isNull, reason: '$n on $w × $h');
        }
      }
    });

    testWidgets('bigger tiles get bigger figures, up to a limit',
        (tester) async {
      final unifi = FakeUnifi(devices(2));
      await pump(tester, UnifiHealthWidget(w: ctx('unifi_health')),
          tile(4, 2), unifi);
      final small = shownHeight(tester, '54 kb/s');
      await pump(tester, UnifiHealthWidget(w: ctx('unifi_health')),
          tile(8, 4), unifi);
      final large = shownHeight(tester, '54 kb/s');
      expect(large, greaterThan(small * 1.5));
      await pump(tester, UnifiHealthWidget(w: ctx('unifi_health')),
          tile(12, 8), unifi);
      expect(shownHeight(tester, '54 kb/s'), lessThan(160),
          reason: 'a full-page tile must not get figures a hand high');
    });
  });

  test('these widgets opt out of the dashboard\'s generic shrink', () {
    for (final type in [
      unifiHealthWidgetType,
      unifiDevicesWidgetType,
      unifiThroughputWidgetType,
    ]) {
      expect(type.fitsItself, isTrue, reason: type.type);
    }
  });
}

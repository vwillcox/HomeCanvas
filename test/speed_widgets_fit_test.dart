import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:immich_kiosk_pi/dashboard/dashboard_model.dart';
import 'package:immich_kiosk_pi/dashboard/dashboard_theme.dart';
import 'package:immich_kiosk_pi/dashboard/widget_registry.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/lan_speedtest_widget.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/speed_gauge.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/speedtest_widget.dart';
import 'package:immich_kiosk_pi/services/lan_speedtest_service.dart';
import 'package:immich_kiosk_pi/services/speedtest_service.dart';

/// The panel's grid, with the tile's padding taken off, as the dashboard does.
Size tile(int w, int h) {
  const gap = 10.0;
  final cellW = (1900 - gap * 13) / 12;
  final cellH = (1080 - gap * 9) / 8;
  return Size(w * cellW + (w - 1) * gap - 16, h * cellH + (h - 1) * gap - 16);
}

DashboardWidgetContext ctx(String type, [Map<String, dynamic>? options]) =>
    DashboardWidgetContext(
      theme: kBuiltInThemes.first,
      config: DashboardWidgetConfig(
          id: 't', type: type, x: 0, y: 0, width: 5, height: 3,
          options: options),
    );

Future<void> pump(WidgetTester tester, Widget child, Size size) async {
  tester.view.physicalSize = const Size(1920, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SpeedtestService()),
      ChangeNotifierProvider(create: (_) => LanSpeedtestService()),
    ],
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

Widget internet() => DashboardSpeedtestWidget(w: ctx('speedtest'));
Widget lan() => DashboardLanSpeedtestWidget(
    w: ctx('lan_speedtest', {'server': 'http://macmini.local:3000', 'name': 'MacMini'}));

void main() {
  group('the dial stays inside its box', () {
    test('whatever the shape of the box', () {
      for (final size in [
        const Size(460, 380), // beside the readout on the panel: the bug
        const Size(900, 200),
        const Size(200, 900),
        const Size(300, 300),
        const Size(40, 1000),
      ]) {
        final reach = SpeedGauge.reachIn(size);
        final shorter = size.shortestSide;
        expect(reach, lessThanOrEqualTo(shorter / 2),
            reason: 'the dial in $size reaches $reach from its centre');
      }
    });
  });

  group('on the panel, as placed (5 × 3)', () {
    for (final (name, build) in [('internet', internet), ('LAN', lan)]) {
      testWidgets('$name: the readout is readable', (tester) async {
        await pump(tester, build(), tile(5, 3));
        // Before: 13 × 0.75 = 10 px labels.
        expect(tester.getRect(find.text('Down')).height, greaterThan(22));
        expect(tester.getRect(find.text('0.00')).height, greaterThan(60),
            reason: "the dial's own figure");
        expect(tester.takeException(), isNull);
      });

      testWidgets('$name: the dial fits inside the tile', (tester) async {
        final t = tile(5, 3);
        await pump(tester, build(), t);
        final dial = tester.getRect(find.byType(SpeedGauge));
        final paint = tester.getRect(find.descendant(
            of: find.byType(SpeedGauge), matching: find.byType(CustomPaint)).first);
        expect(dial.top, greaterThanOrEqualTo(0));
        expect(dial.bottom, lessThanOrEqualTo(t.height + 0.5));
        // The circle drawn from the centre of the paint box stays within it.
        expect(SpeedGauge.reachIn(paint.size),
            lessThanOrEqualTo(paint.size.shortestSide / 2));
      });
    }
  });

  group('at every size and shape', () {
    final sizes = [
      for (var w = 1; w <= 12; w++)
        for (var h = 1; h <= 8; h++) (w, h),
    ];
    for (final (name, build) in [('internet', internet), ('LAN', lan)]) {
      testWidgets('$name never overflows', (tester) async {
        for (final (w, h) in sizes) {
          await pump(tester, build(), tile(w, h));
          expect(tester.takeException(), isNull, reason: '$w × $h');
        }
      });

      testWidgets('$name: text grows with the tile, up to a limit',
          (tester) async {
        await pump(tester, build(), tile(3, 2));
        final small = tester.getRect(find.text('Down')).height;
        await pump(tester, build(), tile(8, 5));
        final large = tester.getRect(find.text('Down')).height;
        expect(large, greaterThan(small * 1.3));
        await pump(tester, build(), tile(12, 8));
        expect(tester.getRect(find.text('Down')).height, lessThan(60));
      });
    }
  });

  test('both opt out of the dashboard\'s generic shrink', () {
    expect(speedtestWidgetType.fitsItself, isTrue);
    expect(lanSpeedtestWidgetType.fitsItself, isTrue);
  });
}

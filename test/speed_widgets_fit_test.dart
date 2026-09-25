import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/lan_speedtest_widget.dart';
import 'package:home_canvas/dashboard/widgets/speed_gauge.dart';
import 'package:home_canvas/dashboard/widgets/speedtest_widget.dart';
import 'package:home_canvas/services/lan_speedtest_service.dart';
import 'package:home_canvas/services/speedtest_service.dart';

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
        id: 't',
        type: type,
        x: 0,
        y: 0,
        width: 5,
        height: 3,
        options: options,
      ),
    );

Future<void> pump(WidgetTester tester, Widget child, Size size) async {
  tester.view.physicalSize = const Size(1920, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
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
    ),
  );
}

Widget internet() => DashboardSpeedtestWidget(w: ctx('speedtest'));
Widget lan() => DashboardLanSpeedtestWidget(
  w: ctx('lan_speedtest', {
    'server': 'http://macmini.local:3000',
    'name': 'MacMini',
  }),
);

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
        expect(
          reach,
          lessThanOrEqualTo(shorter / 2),
          reason: 'the dial in $size reaches $reach from its centre',
        );
      }
    });
  });

  group('on the panel, as placed (5 × 3)', () {
    for (final (name, build) in [('internet', internet), ('LAN', lan)]) {
      testWidgets('$name: the readout is readable', (tester) async {
        await pump(tester, build(), tile(5, 3));
        // Before: 13 × 0.75 = 10 px labels.
        expect(tester.getRect(find.text('Down')).height, greaterThan(22));
        // The size asked for, not the size drawn: the reading is scaled down
        // to fit the ring's hole, and the test font's glyphs are a full em
        // wide — twice a real digit — so '0.00' is squeezed here as it never
        // is on the panel.
        final figure = tester.widget<Text>(find.text('0.00'));
        expect(
          figure.style!.fontSize,
          greaterThan(60),
          reason: "the dial's own figure",
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('$name: the dial fits inside the tile', (tester) async {
        final t = tile(5, 3);
        await pump(tester, build(), t);
        final dial = tester.getRect(find.byType(SpeedGauge));
        final paint = tester.getRect(
          find
              .descendant(
                of: find.byType(SpeedGauge),
                matching: find.byType(CustomPaint),
              )
              .first,
        );
        expect(dial.top, greaterThanOrEqualTo(0));
        expect(dial.bottom, lessThanOrEqualTo(t.height + 0.5));
        // The circle drawn from the centre of the paint box stays within it.
        expect(
          SpeedGauge.reachIn(paint.size),
          lessThanOrEqualTo(paint.size.shortestSide / 2),
        );
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

      testWidgets('$name: text grows with the tile, up to a limit', (
        tester,
      ) async {
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

  testWidgets('a four-figure reading stays inside the inner ring', (
    tester,
  ) async {
    // 2048 Mbps on the LAN gauge ran over the ring: the reading was only
    // limited by the width of the whole dial.
    for (final side in [120.0, 300.0, 420.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: side,
              child: const SpeedGauge(
                downloadMbps: 2048,
                uploadMbps: 1930,
                maxMbps: 2500,
                colour: Colors.blue,
                uploadColour: Colors.pink,
                trackColour: Colors.grey,
                textColour: Colors.white,
                mutedColour: Colors.grey,
              ),
            ),
          ),
        ),
      );
      final reading = tester.getSize(find.text('2048'));
      final shown = tester.getRect(
        find.ancestor(of: find.text('2048'), matching: find.byType(FittedBox)),
      );
      expect(
        shown.width,
        lessThanOrEqualTo(side * SpeedGauge.holeWidth + 0.01),
        reason: 'side $side, text ${reading.width}',
      );
    }
  });

  test('both opt out of the dashboard\'s generic shrink', () {
    expect(speedtestWidgetType.fitsItself, isTrue);
    expect(lanSpeedtestWidgetType.fitsItself, isTrue);
  });
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/tides_service.dart';
import 'package:home_canvas/services/traffic_cams_service.dart';

import 'new_widgets_fit_test.dart' show shapes, tile;

/// A semidiurnal tide — 12 h 25 min between highs, 2 m either way — every
/// quarter hour through three days from [start].
List<(DateTime, double)> _sea(DateTime start) => [
  for (var i = 0; i < 4 * 72; i++)
    (
      start.add(Duration(minutes: 15 * i)),
      2 * math.cos(2 * math.pi * (15 * i) / 745),
    ),
];

Future<void> _draw(
  WidgetTester tester,
  String type,
  Size size,
  Map<String, dynamic> options,
  List<ChangeNotifierProvider> providers,
) async {
  tester.view.physicalSize = const Size(1920, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final t = WidgetRegistry.find(type)!;
  final w = DashboardWidgetContext(
    theme: kBuiltInThemes.first,
    config: DashboardWidgetConfig(
      id: 'x',
      type: type,
      x: 0,
      y: 0,
      width: 4,
      height: 3,
      options: options,
    ),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: providers,
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: size,
              child: Builder(builder: (context) => t.build(context, w)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('tides: each high and low found, between the quarter hours', () {
    final start = DateTime(2026, 9, 29);
    final tides = TidesService.findTides(_sea(start));
    // Three days of a 12 h 25 min tide: highs and lows in turn.
    expect(tides.length, inInclusiveRange(10, 12));
    for (var i = 1; i < tides.length; i++) {
      expect(tides[i].high, isNot(tides[i - 1].high));
    }
    final firstLow = tides.firstWhere((t) => !t.high);
    // Half a period after the start: 6 h 12.5 min.
    expect(firstLow.at.difference(start).inMinutes, closeTo(372, 3));
    expect(firstLow.metres, closeTo(-2, 0.02));
  });

  test('tides: nothing where the model has no sea', () {
    expect(
      TidesService.parse({
        'minutely_15': {
          'time': [for (var i = 0; i < 20; i++) 1790000000 + i * 900],
          'sea_level_height_msl': [for (var i = 0; i < 20; i++) null],
        },
      }),
      isNull,
    );
  });

  test('cameras: parsed, and found by id or words of their name', () {
    final cams = TrafficCamsService.parse([
      {
        'id': 'JamCams_00002.00865',
        'commonName': 'A406 Billet Upass E',
        'lat': 51.6,
        'lon': -0.01,
        'additionalProperties': [
          {'key': 'available', 'value': 'true'},
          {'key': 'imageUrl', 'value': 'https://s3/x/00002.00865.jpg'},
          {'key': 'view', 'value': 'West'},
        ],
      },
      {
        'id': 'JamCams_1',
        'commonName': 'No picture',
        'additionalProperties': [],
      },
    ]);
    expect(cams, hasLength(1));
    expect(cams.single.view, 'West');
    expect(TrafficCamsService.find(cams, '00002.00865'), cams.single);
    expect(TrafficCamsService.find(cams, 'billet a406'), cams.single);
    expect(TrafficCamsService.find(cams, 'blackwall'), isNull);
  });

  testWidgets('tides and cameras fit every shape', (tester) async {
    registerBuiltInWidgets();
    final tides = TidesService(home: () => (lat: 51.85, lon: 1.27));
    addTearDown(tides.dispose);
    final points = _sea(DateTime.now().subtract(const Duration(days: 1)));
    tides.debugSet('', (
      lat: 51.85,
      lon: 1.27,
    ), TideTable(points: points, tides: TidesService.findTides(points)));
    final cams = TrafficCamsService(home: () => (lat: 51.5, lon: -0.1));
    addTearDown(cams.dispose);
    cams.debugSet([
      for (var i = 0; i < 6; i++)
        TrafficCam(
          id: 'c$i',
          name: 'Camera number $i on a long road name',
          imageUrl: 'https://example.invalid/$i.jpg',
          lat: 51.5 + i / 100,
          lon: -0.1,
          view: 'North',
        ),
    ]);
    final providers = <ChangeNotifierProvider>[
      ChangeNotifierProvider<TidesService>.value(value: tides),
      ChangeNotifierProvider<TrafficCamsService>.value(value: cams),
    ];
    for (final type in ['tides', 'traffic_cams']) {
      final t = WidgetRegistry.find(type)!;
      for (final (w, h) in shapes) {
        if (w < t.minWidth || h < t.minHeight) continue;
        await _draw(tester, type, tile(w, h), {}, providers);
        expect(tester.takeException(), isNull, reason: '$type ${w}x$h');
      }
    }
    await _draw(tester, 'tides', tile(4, 3), {}, providers);
    expect(find.textContaining(RegExp('High tide|Low tide')), findsOneWidget);
    await _draw(tester, 'traffic_cams', tile(4, 3), {'nearest': 4}, providers);
    expect(find.textContaining('Camera number'), findsNWidgets(4));
    await _draw(tester, 'traffic_cams', tile(4, 3), {
      'cameras': [
        {'camera': 'number 5'},
        {'camera': 'https://example.invalid/own.jpg', 'name': 'Our road'},
      ],
    }, providers);
    expect(find.textContaining('Camera number 5'), findsOneWidget);
    expect(find.textContaining('Our road'), findsOneWidget);
    // Nothing ticking left behind.
    await tester.pumpWidget(const SizedBox());
  });
}

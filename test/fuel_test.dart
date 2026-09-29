import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/fuel_service.dart';

import 'new_widgets_fit_test.dart' show shapes, tile;

void main() {
  test('feeds are read whatever types they write numbers in', () {
    final list = FuelService.parseFeed('''﻿{"stations": [
      {"brand": "ASDA", "address": "Abbey Park", "postcode": "CV3 4AR",
       "location": {"latitude": 52.39, "longitude": -1.48},
       "prices": {"E10": 172.9, "B7": 196.7}},
      {"brand": "Morrisons", "address": "Westside Road", "postcode": "GX11 1AA",
       "location": {"latitude": "36.14", "longitude": "-5.36"},
       "prices": {"E10": "1.506", "E5": 0, "B7": 9999}},
      {"brand": "Nowhere", "location": {}, "prices": {"E10": 140}}
    ]}''');
    expect(list, hasLength(2));
    expect(list.first.prices, {'E10': 172.9, 'B7': 196.7});
    // Pounds turned to pence; a zero and a typo dropped.
    expect(list.last.prices, {'E10': closeTo(150.6, 1e-9)});
    expect(FuelService.parseFeed('not json'), isEmpty);
  });

  test('distances as the crow flies, in miles', () {
    const s = FuelStation(
      brand: 'x',
      address: '',
      postcode: '',
      latitude: 51.5074,
      longitude: -0.1278,
      prices: {},
    );
    // London to Colchester is about 50 miles.
    expect(s.milesFrom(51.8959, 0.8919), closeTo(50, 3));
  });

  testWidgets('the tile fits every shape, cheapest first within the distance',
      (tester) async {
    registerBuiltInWidgets();
    final config = ConfigService();
    config.config.weather
      ..latitude = 51.27
      ..longitude = 0.52;
    final fuel = FuelService(config);
    addTearDown(fuel.dispose);
    for (final f in kFuelFeeds) {
      fuel.debugSet(f, const []);
    }
    fuel.debugSet(kFuelFeeds.first, [
      for (var i = 0; i < 8; i++)
        FuelStation(
          brand: i.isEven ? 'ASDA' : 'Shell',
          address: 'High Street $i',
          postcode: 'ME16 8AB',
          latitude: 51.27 + i * .005,
          longitude: 0.52,
          prices: {'E10': 150.0 - i, 'B7': 160.0 + i},
        ),
      // Far away: never shown within five miles.
      const FuelStation(
        brand: 'Far',
        address: '',
        postcode: '',
        latitude: 55,
        longitude: -3,
        prices: {'E10': 99.9},
      ),
    ]);
    Future<void> draw(Size size, [Map<String, dynamic>? options]) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = WidgetRegistry.find('fuel')!;
      final w = DashboardWidgetContext(
        theme: kBuiltInThemes.first,
        config: DashboardWidgetConfig(
          id: 'f', type: 'fuel', x: 0, y: 0, width: 3, height: 3,
          options: options,
        ),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider.value(value: fuel)],
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

    for (final (w, h) in shapes) {
      await draw(tile(w, h));
      expect(tester.takeException(), isNull, reason: '${w}x$h');
    }
    await draw(tile(4, 4));
    expect(find.text('143.0p'), findsOneWidget);
    expect(find.text('99.9p'), findsNothing);
    expect(find.text('Asda'), findsWidgets);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/planes_service.dart';

import 'new_widgets_fit_test.dart' show shapes, tile;

void main() {
  test(
    'aircraft: nearest first, in miles, the far and the unplaced left out',
    () {
      final list = PlanesService.parse({
        'ac': [
          {
            'hex': '4ca7b5',
            'flight': 'EZY82  ',
            't': 'A320',
            'r': 'G-EZAA',
            'alt_baro': 12300,
            'gs': 310.5,
            'track': 95.2,
            'baro_rate': -1200,
            'dst': 6.1,
            'dir': 44,
          },
          {
            'hex': 'a',
            'flight': 'BAW743',
            'alt_baro': 'ground',
            'dst': 2.0,
            'dir': 270,
          },
          {
            'hex': 'b',
            'flight': 'FAR1',
            'alt_baro': 30000,
            'dst': 40.0,
            'dir': 0,
          },
          {'hex': 'c', 'flight': 'NOPOS', 'alt_baro': 30000},
          {
            'hex': 'd',
            'flight': 'HELP1',
            'alt_baro': 5000,
            'squawk': '7700',
            'dst': 3,
            'dir': 1,
          },
        ],
      }, 10);
      expect(list.map((p) => p.callsign), ['BAW743', 'HELP1', 'EZY82']);
      expect(list.first.onGround, isTrue);
      expect(list[1].emergency, isTrue);
      expect(list.last.altitudeFt, 12300);
      expect(list.last.climbFpm, -1200);
      expect(list.last.miles, closeTo(7.02, 0.01));
    },
  );

  test('a route, and none when adsbdb has none', () {
    final r = PlanesService.parseRoute({
      'response': {
        'flightroute': {
          'airline': {'name': 'British Airways'},
          'origin': {'municipality': 'Heraklion', 'iata_code': 'HER'},
          'destination': {'municipality': 'London', 'iata_code': 'LHR'},
        },
      },
    })!;
    expect(
      (r.from, r.to, r.fromCode, r.airline),
      ('Heraklion', 'London', 'HER', 'British Airways'),
    );
    expect(PlanesService.parseRoute({'response': 'unknown callsign'}), isNull);
    expect(PlanesService.validCallsign('BAW743'), isTrue);
    expect(PlanesService.validCallsign('../x'), isFalse);
  });

  testWidgets('the tile fits every shape', (tester) async {
    registerBuiltInWidgets();
    final service = PlanesService(home: () => (lat: 51.5, lon: -0.1));
    addTearDown(service.dispose);
    service.debugSet(
      10,
      [
        for (var i = 0; i < 8; i++)
          Plane(
            hex: 'h$i',
            callsign: 'BAW${100 + i}',
            type: 'A320',
            registration: 'G-EUY$i',
            altitudeFt: i == 0 ? null : 3000 + i * 4000,
            climbFpm: i.isEven ? 1500 : -800,
            track: i * 40.0,
            miles: 1.0 + i,
            bearing: i * 45.0,
            emergency: i == 3,
          ),
      ],
      {
        for (var i = 0; i < 8; i++)
          'BAW${100 + i}': const FlightRoute(
            from: 'Heraklion',
            to: 'London',
            airline: 'British Airways',
          ),
      },
    );
    Future<void> draw(Size size, Map<String, dynamic> options) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = WidgetRegistry.find('planes')!;
      final w = DashboardWidgetContext(
        theme: kBuiltInThemes.first,
        config: DashboardWidgetConfig(
          id: 'p',
          type: 'planes',
          x: 0,
          y: 0,
          width: 4,
          height: 3,
          options: options,
        ),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: service,
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

    final type = WidgetRegistry.find('planes')!;
    for (final (w, h) in shapes) {
      // The editor will not make a tile smaller than the type allows.
      if (w < type.minWidth || h < type.minHeight) continue;
      await draw(tile(w, h), {});
      expect(tester.takeException(), isNull, reason: '${w}x$h');
    }
    await draw(tile(5, 4), {});
    // On the ground is left out unless asked for.
    expect(find.textContaining('BAW100'), findsNothing);
    expect(find.textContaining('Heraklion → London'), findsWidgets);
    expect(find.text('7,000 ft'), findsOneWidget);
    await draw(tile(5, 4), {'showGround': true});
    expect(find.textContaining('BAW100'), findsOneWidget);
    expect(find.text('On the ground'), findsOneWidget);
  });
}

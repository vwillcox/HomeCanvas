import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/transitous_service.dart';

import 'new_widgets_fit_test.dart' show shapes, tile;

void main() {
  test('stop times: late, cancelled, platforms and colours, soonest first', () {
    final list = TransitousService.parseStopTimes({
      'stopTimes': [
        {
          'mode': 'HIGHSPEED_RAIL',
          'displayName': 'ICE 578',
          'headsign': 'Frankfurt (Main) Hbf',
          'realTime': true,
          'routeColor': 'E32017',
          'place': {
            'scheduledDeparture': '2026-09-29T09:40:00Z',
            'departure': '2026-09-29T09:44:00Z',
            'track': '14',
          },
        },
        {
          'mode': 'REGIONAL_RAIL',
          'displayName': 'Intercity',
          'headsign': 'Alkmaar',
          'cancelled': true,
          'place': {'scheduledDeparture': '2026-09-29T09:28:00Z'},
        },
        {
          'mode': 'SUBWAY',
          'displayName': '?',
          'routeLongName': 'Red Line',
          'place': {'scheduledDeparture': '2026-09-29T09:50:00Z'},
        },
        {'mode': 'BUS', 'place': {}},
      ],
    });
    expect(list, hasLength(3));
    expect(list.last.line, 'Red Line');
    expect(list.first.line, 'Intercity');
    expect(list.first.cancelled, isTrue);
    expect(list[1].lateMinutes, 4);
    expect(list[1].track, '14');
    expect(list[1].colour, 'E32017');
    expect(list[1].rail, isTrue);
    expect(
      TransitousService.pickStop([
        {'id': 'de-DELFI_000008400058', 'name': 'Amsterdam Centraal', 'type': 'STOP'},
      ]),
      (id: 'de-DELFI_000008400058', name: 'Amsterdam Centraal'),
    );
  });

  testWidgets('the tile fits every shape, and filters by line', (tester) async {
    registerBuiltInWidgets();
    final service = TransitousService();
    addTearDown(service.dispose);
    final now = DateTime.now();
    service.debugSet(
      'Amsterdam Centraal',
      (id: 'x', name: 'Amsterdam Centraal'),
      kTransitModes['trains']!,
      [
        for (var i = 0; i < 8; i++)
          TransitDeparture(
            line: i.isEven ? 'Intercity' : 'Sprinter',
            mode: 'REGIONAL_RAIL',
            headsign: i.isEven ? 'Rotterdam Centraal' : 'Utrecht Centraal',
            scheduled: now.add(Duration(minutes: 3 + i * 4)),
            expected: now.add(Duration(minutes: 3 + i * 4 + (i == 2 ? 6 : 0))),
            track: '${i + 1}a',
            cancelled: i == 3,
            realTime: i != 5,
          ),
      ],
    );
    Future<void> draw(Size size, Map<String, dynamic> options) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = WidgetRegistry.find('transit')!;
      final w = DashboardWidgetContext(
        theme: kBuiltInThemes.first,
        config: DashboardWidgetConfig(
            id: 't', type: 'transit', x: 0, y: 0, width: 4, height: 3, options: options),
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

    for (final (w, h) in shapes) {
      await draw(tile(w, h), {'stop': 'Amsterdam Centraal'});
      expect(tester.takeException(), isNull, reason: '${w}x$h');
    }
    await draw(tile(5, 4), {'stop': 'Amsterdam Centraal', 'lines': 'sprinter'});
    expect(find.textContaining('Rotterdam Centraal'), findsNothing);
    expect(find.textContaining('Utrecht Centraal'), findsWidgets);
    await draw(tile(5, 4), {'stop': 'Amsterdam Centraal'});
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('+6 min'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/tfl_service.dart';

import 'new_widgets_fit_test.dart' show shapes, tile;

void main() {
  test('each line takes its worst status; notes count as good service', () {
    final lines = TflService.parseStatus([
      {
        'id': 'central',
        'name': 'Central',
        'modeName': 'tube',
        'lineStatuses': [
          {'statusSeverity': 9, 'statusSeverityDescription': 'Minor Delays'},
          {
            'statusSeverity': 6,
            'statusSeverityDescription': 'Severe Delays',
            'reason': 'Central Line: severe delays eastbound.',
          },
        ],
      },
      {
        'id': 'victoria',
        'name': 'Victoria',
        'modeName': 'tube',
        'lineStatuses': [
          {'statusSeverity': 19, 'statusSeverityDescription': 'Information'},
        ],
      },
    ]);
    expect(lines.first.status, 'Severe Delays');
    expect(lines.first.serious, isTrue);
    expect(lines.first.reason, contains('eastbound'));
    expect(lines.last.good, isTrue);
  });

  test('arrivals soonest first, stop names without "Underground Station"',
      () {
    final list = TflService.parseArrivals([
      {
        'lineName': 'Central',
        'lineId': 'central',
        'modeName': 'tube',
        'destinationName': 'Ealing Broadway Underground Station',
        'platformName': 'Westbound - Platform 1',
        'timeToStation': 300,
      },
      {
        'lineName': 'Victoria',
        'lineId': 'victoria',
        'modeName': 'tube',
        'destinationName': 'Brixton Underground Station',
        'platformName': 'Southbound - Platform 5',
        'timeToStation': 40,
      },
    ]);
    expect(list.map((a) => a.destination), ['Brixton', 'Ealing Broadway']);
    expect(shortStopName('Oxford Circus Station'), 'Oxford Circus');
    expect(
      TflService.pickStop({
        'matches': [
          {'id': '940GZZLUOXC', 'name': 'Oxford Circus Underground Station'},
        ],
      }),
      (id: '940GZZLUOXC', name: 'Oxford Circus'),
    );
    expect(looksLikeStopId('940GZZLUOXC'), isTrue);
    expect(looksLikeStopId('490000173RC'), isTrue);
    expect(looksLikeStopId('Oxford Circus'), isFalse);
    expect(looksLikeStopId('73241'), isFalse);
  });

  group('tiles', () {
    setUpAll(registerBuiltInWidgets);

    Future<void> draw(
      WidgetTester tester,
      String type,
      Size size,
      TflService tfl,
      Map<String, dynamic> options,
    ) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = WidgetRegistry.find(type)!;
      final w = DashboardWidgetContext(
        theme: kBuiltInThemes.first,
        config: DashboardWidgetConfig(
          id: 'l',
          type: type,
          x: 0,
          y: 0,
          width: 3,
          height: 3,
          options: options,
        ),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: tfl,
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

    const modes = ['tube', 'elizabeth-line', 'overground', 'dlr'];
    List<TflLine> lines(bool trouble) => [
      for (final (id, name) in [
        ('bakerloo', 'Bakerloo'),
        ('central', 'Central'),
        ('circle', 'Circle'),
        ('elizabeth', 'Elizabeth line'),
        ('hammersmith-city', 'Hammersmith & City'),
        ('weaver', 'Weaver'),
      ])
        TflLine(
          id: id,
          name: name,
          mode: 'tube',
          severity: trouble && id == 'central' ? 6 : 10,
          status: trouble && id == 'central' ? 'Severe Delays' : 'Good Service',
          reason: trouble && id == 'central' ? 'Signal failure' : '',
        ),
    ];

    testWidgets('London lines fit every shape, with and without trouble',
        (tester) async {
      final tfl = TflService();
      addTearDown(tfl.dispose);
      for (final trouble in [true, false]) {
        tfl.debugSetStatus(modes, lines(trouble));
        for (final only in [false, true]) {
          for (final (w, h) in shapes) {
            await draw(tester, 'tfl_lines', tile(w, h), tfl, {'onlyProblems': only});
            expect(tester.takeException(), isNull,
                reason: 'trouble $trouble only $only ${w}x$h');
          }
        }
      }
      tfl.debugSetStatus(modes, lines(false));
      await draw(tester, 'tfl_lines', tile(3, 4), tfl, {'onlyProblems': true});
      expect(find.text('Good service on every line'), findsOneWidget);
    });

    testWidgets('London arrivals fit every shape, filtered by line',
        (tester) async {
      final tfl = TflService();
      addTearDown(tfl.dispose);
      tfl.debugSetArrivals('Oxford Circus', 'any',
          (id: '940GZZLUOXC', name: 'Oxford Circus'), [
        for (var i = 0; i < 8; i++)
          TflArrival(
            line: i.isEven ? 'Victoria' : 'Central',
            lineId: i.isEven ? 'victoria' : 'central',
            mode: 'tube',
            destination: i.isEven ? 'Brixton' : 'Ealing Broadway',
            platform: 'Southbound - Platform 5',
            seconds: i * 90,
          ),
      ]);
      for (final (w, h) in shapes) {
        await draw(tester, 'tfl_arrivals', tile(w, h), tfl, {'stop': 'Oxford Circus'});
        expect(tester.takeException(), isNull, reason: '${w}x$h');
      }
      await draw(tester, 'tfl_arrivals', tile(3, 3), tfl,
          {'stop': 'Oxford Circus', 'lines': 'central'});
      expect(find.text('Brixton'), findsNothing);
      expect(find.text('Ealing Broadway'), findsWidgets);
      expect(find.text('Oxford Circus'), findsOneWidget);
    });
  });
}

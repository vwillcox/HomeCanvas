import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/ha_energy_widget.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/glowmarkt_service.dart';
import 'package:home_canvas/services/home_assistant_service.dart';

DateTime at(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 10, day, hour, minute);

void main() {
  group('a day of electricity', () {
    // Yesterday ran up to 7.9 kWh, still shown until 01:05; today's
    // readings start then, late as the meter's always are.
    final usage = [
      (at(13, 9), 2.0),
      (at(13, 20), 6.5),
      (at(14, 0, 30), 7.9),
      (at(14, 1, 5), 0.1),
      (at(14, 7, 30), 0.6),
      (at(14, 8, 15), 1.4),
      (at(14, 14, 10), 2.2),
    ];
    final cost = [
      (at(13, 23), 2.97),
      (at(14, 1, 5), 0.5),
      (at(14, 14, 10), 1.19),
    ];

    test('today is what came after the total went back to nothing', () {
      final day = EnergyDay.from(usage, cost, at(14, 14, 30));
      expect(day.today, 2.2);
      expect(day.yesterday, 7.9);
      expect(day.costToday, 1.19);
      expect(day.costYesterday, 2.97);
      expect(day.hours[1], closeTo(0.1, 1e-9));
      expect(day.hours[7], closeTo(0.5, 1e-9));
      expect(day.hours[8], closeTo(0.8, 1e-9));
      expect(day.hours[14], closeTo(0.8, 1e-9));
      expect(day.hours.fold(0.0, (a, b) => a + b), closeTo(2.2, 1e-9));
    });

    test('just after midnight, the total shown is still yesterday’s', () {
      final early = usage.where((s) => s.$1.isBefore(at(14, 1))).toList();
      final day = EnergyDay.from(early, const [], at(14, 0, 45));
      expect(day.today, 0);
      expect(day.yesterday, 7.9);
      expect(day.hours.every((h) => h == 0), isTrue);
    });

    test('kept only from part way through the day: no hour gets the lot', () {
      final day = EnergyDay.from(
        [(at(14, 15, 3), 0.27), (at(14, 15, 40), 0.5), (at(14, 16, 10), 0.9)],
        const [],
        at(14, 16, 20),
      );
      expect(day.today, 0.9);
      expect(day.hours[15], closeTo(0.23, 1e-9));
      expect(day.hours[16], closeTo(0.4, 1e-9));
    });

    test('nothing yet is nothing', () {
      final day = EnergyDay.from(const [], const [], at(14, 9));
      expect(day.today, 0);
      expect(day.yesterday, isNull);
      expect(day.costToday, isNull);
    });
  });

  group('weeks, months and years', () {
    final now = at(14, 15);
    List<(DateTime, double)> days(int from, int to, double kwh) => [
      for (var d = from; d <= to; d++) (DateTime(2026, 10, d), kwh),
    ];

    test('a week is the last seven days, against the seven before', () {
      final r = EnergyRange.week(days(1, 14, 2.0), days(1, 14, 0.8), now);
      expect(r.bars, List.filled(7, 2.0));
      expect(r.total, 14.0);
      expect(r.cost, closeTo(5.6, 1e-9));
      expect(r.before, 14.0);
      // 14 October 2026 is a Wednesday: the last bar is lettered W.
      expect(r.axis.last, (6, 'W'));
    });

    test('a day not read yet is a gap, not nothing used', () {
      final r = EnergyRange.week(days(1, 12, 3.0), null, now);
      expect(r.bars.sublist(5), [null, null]);
      expect(r.cost, isNull);
    });

    test('a month a day at a time, against last month’s total', () {
      final r = EnergyRange.month(
        days(1, 13, 5.0),
        null,
        [for (var d = 1; d <= 30; d++) (DateTime(2026, 9, d), 160.0 / 30)],
        [for (var d = 1; d <= 30; d++) (DateTime(2026, 9, d), 55.0 / 30)],
        now,
      );
      expect(r.bars.length, 31);
      expect(r.bars[12], 5.0);
      expect(r.bars[13], isNull);
      expect(r.total, 65.0);
      expect(r.before, closeTo(160.0, 1e-9));
      expect(r.costBefore, closeTo(55.0, 1e-9));
      expect(r.now, 13);
    });

    test('a year as twelve months, against the twelve before', () {
      final months = [
        for (var i = 11; i >= 0; i--) (DateTime(2026, 10 - i), 200.0),
      ];
      final r = EnergyRange.year(
        months,
        null,
        [(DateTime(2025, 1), 2000.0)],
        null,
        now,
      );
      expect(r.bars, List.filled(12, 200.0));
      expect(r.total, 2400.0);
      expect(r.before, 2000.0);
      expect(r.axis.first, (0, 'N'));
      expect(r.axis.last, (11, 'O'));
    });

    test(
      'today in half hours, where Glowmarkt has more than Home Assistant',
      () {
        final halves = [
          (at(14, 0), 0.1),
          (at(14, 0, 30), 0.1),
          (at(14, 7, 30), 0.4),
        ];
        final r = EnergyRange.day(null, halves, null, null, 2.2, 1.0, now);
        expect(r.bars.length, 48);
        expect(r.bars[15], 0.4);
        expect(r.bars[40], isNull, reason: 'still to come');
        expect(r.total, 2.2, reason: 'Home Assistant’s total is ahead');
        expect(r.axis.map((a) => a.$1), [0, 12, 24, 36]);
      },
    );
  });

  group('the widget', () {
    setUpAll(registerBuiltInWidgets);

    late ConfigService config;

    Future<void> draw(
      WidgetTester tester,
      HomeAssistantService ha,
      Size size,
      String theme,
    ) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final w = DashboardWidgetContext(
        theme: kBuiltInThemes.firstWhere((t) => t.id == theme),
        config: DashboardWidgetConfig(
          id: 'e',
          type: 'ha_energy',
          x: 0,
          y: 0,
          width: 4,
          height: 3,
        ),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: ha),
            Provider.value(value: GlowmarktService(config)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                  size: size,
                  child: Builder(
                    builder: (context) =>
                        WidgetRegistry.find('ha_energy')!.build(context, w),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('finds the Glow meter by itself, and fits every size', (
      tester,
    ) async {
      config = ConfigService();
      config.config.homeAssistant
        ..baseUrl = 'http://ha.local:8123'
        ..token = 'x';
      const m = 'sensor.dcc_sourced_smart_electricity_meter';
      final ha = HomeAssistantService(config)
        ..debugSet(const [
          HaEntity(id: '${m}_usage_today', state: '4.25'),
          HaEntity(id: '${m}_cost_today', state: '1.83'),
          HaEntity(id: '${m}_rate', state: '0.324'),
          HaEntity(id: '${m}_standing_charge', state: '0.4728'),
        ]);
      for (final theme in ['glass', 'lcars']) {
        for (final size in const [
          Size(620, 420),
          Size(300, 140),
          Size(150, 140),
          Size(1880, 1150),
        ]) {
          await draw(tester, ha, size, theme);
          expect(tester.takeException(), isNull, reason: '$size in $theme');
        }
      }
      await draw(tester, ha, const Size(620, 420), 'glass');
      expect(find.text('4.3 kWh'), findsOneWidget);
      expect(find.text('£1.83'), findsOneWidget);
      expect(find.textContaining('32.4p a kWh · 47.3p a day'), findsOneWidget);
      // Without a Bright login there is only today: no tabs to tap.
      expect(find.text('Week'), findsNothing);

      config.config.bright
        ..username = 'me@example.org'
        ..password = 'x';
      for (final theme in ['glass', 'lcars']) {
        await draw(tester, ha, const Size(620, 420), theme);
        expect(tester.takeException(), isNull, reason: theme);
      }
      expect(find.text('WEEK'), findsOneWidget);
      await draw(tester, ha, const Size(620, 420), 'glass');
      expect(find.text('Week'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      // There is no Home Assistant here: let the history request time out.
      await tester.pump(const Duration(seconds: 15));
    });
  });
}

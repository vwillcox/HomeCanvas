import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:immich_kiosk_pi/dashboard/dashboard_model.dart';
import 'package:immich_kiosk_pi/dashboard/dashboard_theme.dart';
import 'package:immich_kiosk_pi/dashboard/widget_registry.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/countdowns_widget.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/history_widget.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/immich_library_widget.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/meals_widget.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/widgets.dart';
import 'package:immich_kiosk_pi/models/immich_models.dart';
import 'package:immich_kiosk_pi/services/config_service.dart';
import 'package:immich_kiosk_pi/services/home_assistant_service.dart';
import 'package:immich_kiosk_pi/services/immich_service.dart';
import 'package:immich_kiosk_pi/services/rain_service.dart';

Size tile(int w, int h) {
  const gap = 10.0;
  final cellW = (1900 - gap * 13) / 12;
  final cellH = (1080 - gap * 9) / 8;
  return Size(w * cellW + (w - 1) * gap - 16, h * cellH + (h - 1) * gap - 16);
}

const shapes = [
  (1, 1),
  (2, 1),
  (1, 2),
  (2, 2),
  (3, 2),
  (3, 3),
  (4, 2),
  (4, 3),
  (5, 3),
  (4, 6),
  (1, 6),
  (6, 1),
  (12, 1),
  (1, 8),
  (6, 4),
  (12, 8),
];

List<RainSlot> rain(DateTime from, List<double> mm) => [
  for (var i = 0; i < mm.length; i++)
    RainSlot(from.add(Duration(minutes: 15 * i)), mm[i], null),
];

void main() {
  group('rain', () {
    final now = DateTime(2026, 9, 25, 14, 5);
    final start = DateTime(2026, 9, 25, 14);

    test('dry, coming, and already raining', () {
      expect(
        rainSummary(rain(start, List.filled(8, 0)), now).headline,
        'Dry for the next 2 hours',
      );
      final coming = rainSummary(
        rain(start, [0, 0.3, 0.5, 0.2, 0, 0, 0, 0]),
        now,
      );
      expect(coming.headline, 'Rain from 14:15');
      expect(coming.detail, 'light · until about 15:00');
      final now2 = rainSummary(rain(start, [2.5, 2, 0, 0, 0, 0, 0, 0]), now);
      expect(now2.headline, 'Raining now');
      expect(now2.detail, 'heavy · stops about 14:30');
    });

    test('reads Open-Meteo’s quarter hours', () {
      final slots = RainService.parse({
        'minutely_15': {
          'time': ['2026-09-25T14:00', '2026-09-25T14:15'],
          'precipitation': [0.0, 0.4],
          'precipitation_probability': [5, 60],
        },
      });
      expect(slots.last.rate, closeTo(1.6, 1e-9));
      expect(rainWord(slots.last.rate), 'light');
      expect(slots.last.chance, 60);
    });
  });

  group('Home Assistant', () {
    HaEntity e(String id, String state, [Map<String, dynamic> a = const {}]) =>
        HaEntity(id: id, state: state, attributes: a);

    test('says each kind of entity the way its own cards would', () {
      expect(
        e('sensor.t', '21.37', {'unit_of_measurement': '°C'}).display,
        '21.4 °C',
      );
      expect(e('sensor.h', '54', {'unit_of_measurement': '%'}).display, '54%');
      expect(
        e('binary_sensor.d', 'on', {'device_class': 'door'}).display,
        'Open',
      );
      expect(
        e('binary_sensor.m', 'off', {'device_class': 'motion'}).display,
        'Clear',
      );
      expect(e('person.v', 'home').display, 'Home');
      expect(e('device_tracker.p', 'not_home').display, 'Away');
      expect(
        e('media_player.tv', 'playing', {'media_title': 'Bluey'}).display,
        'Bluey',
      );
      expect(e('light.l', 'on', {'brightness': 128}).display, '50%');
      expect(e('sensor.x', 'unavailable').display, 'Unavailable');
    });

    test('only lights, switches and fans switch from the wall', () {
      expect(e('switch.kiosk_screen', 'on').switchable, isTrue);
      expect(e('light.strip', 'off').switchable, isTrue);
      expect(e('lock.front_door', 'locked').switchable, isFalse);
      expect(e('cover.garage', 'closed').switchable, isFalse);
    });
  });

  test('bank holidays come from gov.uk, a list per country', () {
    final all = BankHolidays.parse({
      'england-and-wales': {
        'division': 'england-and-wales',
        'events': [
          {'title': 'Christmas Day', 'date': '2026-12-25'},
          {'title': 'Boxing Day', 'date': '2026-12-28'},
        ],
      },
      'scotland': {
        'events': [
          {'title': 'St Andrew’s Day', 'date': '2026-11-30'},
        ],
      },
    });
    expect(
      [for (final c in all['england-and-wales']!) c.name],
      ['Christmas Day', 'Boxing Day'],
    );
    final list = Countdown.upcoming(
      [
        {'name': 'Holiday', 'date': '2026-10-20'},
      ],
      DateTime(2026, 9, 25),
      extra: all['england-and-wales']!,
    );
    expect(
      [for (final c in list) c.name],
      ['Holiday', 'Christmas Day', 'Boxing Day'],
    );
  });

  test('tonight becomes tomorrow after dinner', () {
    expect(tonight(DateTime(2026, 9, 25, 18), 20), DateTime(2026, 9, 25));
    expect(tonight(DateTime(2026, 9, 25, 21), 20), DateTime(2026, 9, 26));
    expect(
      mealOn({'friday': ' Fish and chips '}, DateTime(2026, 9, 25)),
      'Fish and chips',
    );
  });

  test('history comes from Wikipedia’s selected events', () {
    final events = HistoryEvent.fromWikipedia({
      'selected': [
        {
          'year': 1981,
          'text': 'Sandra Day O’Connor joined the Supreme Court.',
          'pages': [
            {
              'thumbnail': {'source': 'https://upload.example/s.jpg'},
            },
          ],
        },
        {'year': 'nope', 'text': 'skipped'},
        {'year': 1990, 'text': ''},
      ],
    });
    expect(events.single.year, 1981);
    expect(events.single.thumbnail, 'https://upload.example/s.jpg');
  });

  group('every tile size', () {
    setUpAll(registerBuiltInWidgets);

    late ConfigService config;
    late HomeAssistantService ha;

    setUp(() {
      config = ConfigService();
      config.config.homeAssistant
        ..baseUrl = 'http://ha.local:8123'
        ..token = 'x';
      ha = HomeAssistantService(config)
        ..debugSet([
          const HaEntity(
            id: 'sensor.lounge_temperature',
            state: '21.4',
            attributes: {
              'friendly_name': 'Lounge temperature',
              'unit_of_measurement': '°C',
              'device_class': 'temperature',
            },
          ),
          const HaEntity(
            id: 'person.vincent',
            state: 'home',
            attributes: {'friendly_name': 'Vincent'},
          ),
          const HaEntity(
            id: 'switch.kiosk_screen',
            state: 'on',
            attributes: {'friendly_name': 'Kiosk screen'},
          ),
          const HaEntity(
            id: 'media_player.living_room',
            state: 'playing',
            attributes: {
              'friendly_name': 'Living room',
              'media_title': 'A very long programme title indeed',
            },
          ),
        ]);
      HistoryWidget.debugEvents = [
        const HistoryEvent(
          1981,
          'Sandra Day O’Connor became the first woman to serve as a justice of the Supreme Court of the United States, sworn in by Chief Justice Warren Burger.',
        ),
        const HistoryEvent(1990, 'A shorter one.'),
      ];
      ImmichLibraryWidget.fetch = false;
      ImmichLibraryWidget.last = const LibraryStats(
        photos: 5429,
        videos: 301,
        bytes: 22526208607,
        addedRecently: 12,
        recentDays: 30,
        latest: [
          Asset(id: 'a', type: AssetType.image),
          Asset(id: 'b', type: AssetType.image),
          Asset(id: 'c', type: AssetType.image),
          Asset(id: 'd', type: AssetType.image),
        ],
      );
      BankHolidays.debugSet({
        'england-and-wales': [
          Countdown('Christmas Day', DateTime(2099, 12, 25)),
        ],
      });
    });
    tearDown(() {
      HistoryWidget.debugEvents = null;
      ImmichLibraryWidget.fetch = true;
      ImmichLibraryWidget.last = null;
    });

    Future<void> draw(
      WidgetTester tester,
      String type,
      Size size, {
      Map<String, dynamic>? options,
    }) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = WidgetRegistry.find(type)!;
      final w = DashboardWidgetContext(
        theme: kBuiltInThemes.first,
        config: DashboardWidgetConfig(
          id: 'w',
          type: type,
          x: 0,
          y: 0,
          width: 3,
          height: 2,
          options: options,
        ),
      );
      final now = DateTime.now();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: config),
            ChangeNotifierProvider.value(value: ha),
            Provider(create: (_) => ImmichService(config)),
            ChangeNotifierProvider(
              create: (_) => RainService.withSlots(
                config,
                rain(DateTime(now.year, now.month, now.day, now.hour), [
                  0,
                  0,
                  0.3,
                  0.8,
                  1.5,
                  0.4,
                  0,
                  0,
                  0,
                ]),
              ),
            ),
          ],
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
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> sweep(
      WidgetTester tester,
      String type, {
      Map<String, dynamic>? options,
    }) async {
      final t = WidgetRegistry.find(type)!;
      for (final (w, h) in shapes) {
        if (w < t.minWidth || h < t.minHeight) continue;
        await draw(tester, type, tile(w, h), options: options);
        final e = tester.takeException();
        expect(e, isNull, reason: '$type at $w × $h: $e');
      }
      await tester.pumpWidget(const SizedBox());
    }

    testWidgets('Rain soon', (t) => sweep(t, 'rain'));
    testWidgets(
      'Home Assistant',
      (t) => sweep(
        t,
        'home_assistant',
        options: {
          'entities': [
            {'entity': 'sensor.lounge_temperature', 'name': ''},
            {'entity': 'person.vincent', 'name': 'Vincent'},
            {'entity': 'switch.kiosk_screen', 'name': ''},
            {'entity': 'media_player.living_room', 'name': ''},
            {'entity': 'sensor.gone', 'name': 'Missing'},
          ],
        },
      ),
    );
    testWidgets('Immich library', (t) => sweep(t, 'immich_library'));
    testWidgets('On this day in history', (t) => sweep(t, 'history'));
    testWidgets(
      'Meal plan',
      (t) => sweep(
        t,
        'meals',
        options: {
          for (final d in [
            'monday',
            'tuesday',
            'wednesday',
            'thursday',
            'friday',
            'saturday',
            'sunday',
          ])
            d: 'Slow-cooked beef and ale pie with mash and greens',
        },
      ),
    );
    testWidgets(
      'Countdowns with bank holidays',
      (t) => sweep(
        t,
        'countdowns',
        options: {
          'events': [
            {'name': 'Holiday', 'date': '2099-10-20'},
          ],
          'bankHolidays': 'england-and-wales',
        },
      ),
    );

    testWidgets('a tap switches a Home Assistant switch', (tester) async {
      await draw(
        tester,
        'home_assistant',
        tile(4, 2),
        options: {
          'entities': [
            {'entity': 'switch.kiosk_screen', 'name': ''},
          ],
        },
      );
      expect(ha.entity('switch.kiosk_screen')!.on, isTrue);
      await tester.tap(find.text('Kiosk screen'));
      await tester.pump();
      expect(
        ha.entity('switch.kiosk_screen')!.on,
        isFalse,
        reason: 'shown at once, before Home Assistant answers',
      );
      await tester.pumpWidget(const SizedBox());
      // There is no Home Assistant here: let the request's timeout run out.
      await tester.pump(const Duration(seconds: 15));
    });
  });
}

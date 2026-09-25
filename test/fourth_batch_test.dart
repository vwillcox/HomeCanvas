import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:immich_kiosk_pi/dashboard/dashboard_model.dart';
import 'package:immich_kiosk_pi/dashboard/dashboard_theme.dart';
import 'package:immich_kiosk_pi/dashboard/schedule.dart';
import 'package:immich_kiosk_pi/dashboard/widget_registry.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/birthdays_widget.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/certs_widget.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/updates_widget.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/widgets.dart';
import 'package:immich_kiosk_pi/screens/dashboard_screen.dart';
import 'package:immich_kiosk_pi/services/cert_check.dart';
import 'package:immich_kiosk_pi/services/chores_service.dart';
import 'package:immich_kiosk_pi/services/config_service.dart';
import 'package:immich_kiosk_pi/services/dashboard_service.dart';
import 'package:immich_kiosk_pi/services/home_assistant_service.dart';
import 'package:immich_kiosk_pi/services/immich_service.dart';
import 'package:immich_kiosk_pi/services/screen_idle_service.dart';
import 'package:immich_kiosk_pi/services/unifi_service.dart';

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

/// Certificates without the network.
class FakeCerts extends CertChecker {
  const FakeCerts();
  @override
  Future<CertInfo> check(String target) async => switch (target) {
    'soon.example' => CertInfo(
      host: target,
      expires: DateTime.now().add(const Duration(days: 5)),
      issuer: 'Let’s Encrypt',
    ),
    'down.example' => CertInfo(host: target, error: 'Not answering'),
    _ => CertInfo(
      host: target,
      expires: DateTime.now().add(const Duration(days: 68)),
      issuer: 'Let’s Encrypt',
    ),
  };
}

void main() {
  group('schedules', () {
    // Friday 25 September 2026.
    DateTime at(int h, int m, [int day = 25]) => DateTime(2026, 9, day, h, m);

    test('between two times, on some days', () {
      const s = Schedule(from: '06:00', to: '09:00', days: 'weekdays');
      expect(s.activeAt(at(6, 0)), isTrue);
      expect(s.activeAt(at(8, 59)), isTrue);
      expect(s.activeAt(at(9, 0)), isFalse);
      expect(s.activeAt(at(7, 0, 27)), isFalse, reason: 'Sunday');
      expect(s.describe(), 'weekdays 06:00–09:00');
    });

    test('past midnight counts from the day it starts', () {
      const night = Schedule(from: '22:00', to: '06:30', days: 'Fri');
      expect(night.activeAt(at(23, 0, 24)), isFalse, reason: 'Thursday night');
      expect(night.activeAt(at(23, 0, 25)), isTrue, reason: 'Friday night');
      expect(
        night.activeAt(at(3, 0, 26)),
        isTrue,
        reason: 'Saturday small hours',
      );
      expect(night.activeAt(at(7, 0, 26)), isFalse);
    });

    test('days only, and nothing at all', () {
      expect(const Schedule(days: 'Mon Fri').activeAt(at(12, 0)), isTrue);
      expect(const Schedule(days: 'weekends').activeAt(at(12, 0)), isFalse);
      expect(Schedule.always.isAlways, isTrue);
      expect(const Schedule(days: 'daily').isAlways, isTrue);
    });

    test('pages out of their hours drop out; never all of them', () {
      final pages = [
        const DashboardPage(),
        const DashboardPage(
          name: 'Morning',
          schedule: Schedule(from: '06:00', to: '09:00'),
        ),
        const DashboardPage(
          name: 'Night',
          schedule: Schedule(from: '22:00', to: '06:00'),
        ),
      ];
      expect(visiblePages(3, pages, at(7, 0)), [0, 1]);
      expect(visiblePages(3, pages, at(12, 0)), [0]);
      expect(visiblePages(4, pages, at(23, 0)), [0, 2, 3]);
      expect(visiblePages(2, [pages[1], pages[1]], at(12, 0)), [
        0,
        1,
      ], reason: 'every page asleep: show them all rather than nothing');
    });

    test('pages, hours and the photo background are saved and read back', () {
      final s = DashboardSettings(
        pages: [
          const DashboardPage(
            name: 'Morning',
            schedule: Schedule(from: '06:00', to: '09:00'),
          ),
        ],
        photoBackground: true,
        photoAlbum: 'abc',
        photoDim: 0.65,
        photoSeconds: 300,
        widgets: [
          DashboardWidgetConfig(
            id: 'a',
            type: 'trains',
            x: 0,
            y: 0,
            width: 3,
            height: 2,
            schedule: const Schedule(
              from: '06:30',
              to: '09:00',
              days: 'weekdays',
            ),
          ),
        ],
      );
      final back = DashboardSettings.fromJson(s.toJson());
      expect(back.pages.single.name, 'Morning');
      expect(back.pages.single.schedule.from, '06:00');
      expect(back.photoBackground, isTrue);
      expect(back.photoAlbum, 'abc');
      expect(back.photoDim, 0.65);
      expect(back.photoSeconds, 300);
      expect(back.widgets.single.schedule.days, 'weekdays');
      expect(DashboardSettings.fromJson(const {}).photoBackground, isFalse);
    });
  });

  group('chores', () {
    test('ticks, stars and whose tick it is', () {
      var now = DateTime(2026, 9, 21, 8); // a Monday
      final s = ChoresService(clock: () => now, persist: false);
      const bed = Chore(task: 'Make bed', who: 'Sam', stars: 2);
      const fish = Chore(task: 'Feed the fish');
      s.toggle('b', bed, 'Sam');
      s.toggle('b', fish, 'Jo');
      expect(s.doneBy('b', bed), 'Sam');
      expect(s.starsThisWeek('b', 'Sam'), 2);
      expect(s.starsThisWeek('b', 'Jo'), 1);
      s.toggle('b', fish, 'Sam'); // not Sam's tick to undo
      expect(s.doneBy('b', fish), 'Jo');
      now = DateTime(2026, 9, 22, 8);
      expect(s.doneBy('b', bed), isNull, reason: 'a new day');
      s.toggle('b', bed, 'Sam');
      expect(s.starsThisWeek('b', 'Sam'), 4);
      now = DateTime(2026, 9, 28, 8); // next Monday
      expect(
        s.starsThisWeek('b', 'Sam'),
        0,
        reason: 'stars start again each week',
      );
    });

    test('which days a chore is due', () {
      final thu = DateTime(2026, 9, 24);
      expect(const Chore(task: 'x').dueOn(thu), isTrue);
      expect(const Chore(task: 'x', days: 'weekends').dueOn(thu), isFalse);
      expect(const Chore(task: 'x', days: 'Mon Thu').dueOn(thu), isTrue);
    });
  });

  test('birthdays come round, with the age turning', () {
    final today = DateTime(2026, 9, 25);
    final list = NextBirthday.upcoming([
      Person(id: '1', name: 'Sam', birthDate: DateTime(2017, 9, 26)),
      Person(id: '2', name: 'Jo', birthDate: DateTime(1985, 3, 2)),
      Person(id: '3', name: 'Leap', birthDate: DateTime(2004, 2, 29)),
      const Person(id: '4', name: 'Nobody'),
    ], today);
    expect(
      [for (final b in list) (b.person.name, b.turning)],
      [('Sam', 9), ('Leap', 23), ('Jo', 42)],
    );
    expect(list[1].day, DateTime(2027, 2, 28));
    expect(birthdayWhen(1, DateTime(2026, 9, 26)), 'Tomorrow');
  });

  test('newer versions, whatever their spelling', () {
    expect(isNewer('v3.3.0', '3.2.2'), isTrue);
    expect(isNewer('v3.2.2', '3.2.2'), isFalse);
    expect(isNewer('3.10.0', '3.9.9'), isTrue);
    expect(isNewer('v3.2.1-rc.1', '3.2.2'), isFalse);
  });

  test('the issuer’s name, from a certificate’s issuer line', () {
    expect(
      CertChecker.issuerName("/C=US/O=Let's Encrypt/CN=R11"),
      "Let's Encrypt",
    );
    expect(CertChecker.issuerName('/CN=casaos.local'), 'casaos.local');
  });

  group('every tile size', () {
    setUpAll(registerBuiltInWidgets);

    late ConfigService config;
    late ChoresService chores;
    late HomeAssistantService ha;

    setUp(() {
      config = ConfigService();
      config.config.homeAssistant
        ..baseUrl = 'http://ha.local:8123'
        ..token = 'x';
      chores = ChoresService(persist: false);
      ha = HomeAssistantService(config)
        ..debugSet([
          const HaEntity(
            id: 'update.home_assistant_core_update',
            state: 'on',
            attributes: {
              'title': 'Home Assistant Core',
              'installed_version': '2026.9.1',
              'latest_version': '2026.9.2',
            },
          ),
          const HaEntity(id: 'update.hacs_update', state: 'off'),
        ]);
      CertsWidget.debugChecker = const FakeCerts();
      UpdatesWidget.debugLatestImmich = 'v3.3.0';
      UpdatesWidget.debugRunningImmich = '3.2.2';
      BirthdaysWidget.debugPeople = [
        Person(
          id: '1',
          name: 'Sam',
          birthDate: DateTime.now()
              .add(const Duration(days: 1))
              .subtract(const Duration(days: 365 * 9)),
        ),
        Person(
          id: '2',
          name: 'Grandma Josephine Willcox',
          birthDate: DateTime(1950, 12, 1),
        ),
      ];
    });
    tearDown(() {
      CertsWidget.debugChecker = null;
      UpdatesWidget.debugLatestImmich = null;
      UpdatesWidget.debugRunningImmich = null;
      BirthdaysWidget.debugPeople = null;
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
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: config),
            ChangeNotifierProvider.value(value: chores),
            ChangeNotifierProvider.value(value: ha),
            ChangeNotifierProvider(create: (_) => UnifiService(config)),
            Provider(create: (_) => ImmichService(config)),
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

    final choreOptions = {
      'people': [
        {'name': 'Sam', 'colour': '#FF7AB6'},
        {'name': 'Jo', 'colour': '#7EE2A8'},
        {'name': 'Alexander', 'colour': '#8AB4FF'},
      ],
      'chores': [
        {
          'task': 'Make bed',
          'emoji': '🛏️',
          'who': 'Sam',
          'days': 'daily',
          'stars': 1,
        },
        {
          'task': 'Empty the dishwasher before school',
          'emoji': '🍽️',
          'who': '',
          'days': 'daily',
          'stars': 2,
        },
        {
          'task': 'Feed the fish',
          'emoji': '🐟',
          'who': 'Jo',
          'days': 'daily',
          'stars': 1,
        },
        {
          'task': 'Homework',
          'emoji': '📚',
          'who': 'Alexander',
          'days': 'daily',
          'stars': 3,
        },
      ],
      'goal': 20,
      'reward': 'Pizza night',
    };

    testWidgets(
      'Certificates',
      (t) => sweep(
        t,
        'certs',
        options: {
          'sites': [
            {'host': 'talktech.info'},
            {'host': 'soon.example'},
            {'host': 'down.example'},
          ],
        },
      ),
    );
    testWidgets('Updates', (t) => sweep(t, 'updates'));
    testWidgets('Birthdays', (t) => sweep(t, 'birthdays'));
    testWidgets('Chores', (t) => sweep(t, 'chores', options: choreOptions));

    testWidgets('Updates lists what is waiting', (tester) async {
      await draw(tester, 'updates', tile(4, 3));
      expect(find.text('Immich server'), findsOneWidget);
      expect(find.text('Home Assistant Core'), findsOneWidget);
      expect(find.textContaining('3.2.2 → 3.3.0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a chore ticks off with a tap', (tester) async {
      await draw(tester, 'chores', tile(6, 4), options: choreOptions);
      await tester.tap(find.text('Make bed'));
      await tester.pump();
      expect(chores.starsThisWeek('w', 'Sam'), 1);
      expect(find.text('1/20'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
    'the dashboard shows only pages in their hours, and widgets in theirs',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      String hm(DateTime t) =>
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      final on = Schedule(
        from: hm(now.subtract(const Duration(hours: 1))),
        to: hm(now.add(const Duration(hours: 1))),
      );
      final off = Schedule(
        from: hm(now.add(const Duration(hours: 2))),
        to: hm(now.add(const Duration(hours: 3))),
      );
      final config = ConfigService();
      DashboardWidgetConfig w(
        String id,
        int page, [
        Schedule s = Schedule.always,
      ]) => DashboardWidgetConfig(
        id: id,
        type: 'kind_$id',
        x: 0,
        y: 0,
        width: 3,
        height: 2,
        page: page,
        schedule: s,
      );
      config.config.dashboard
        ..topBar = false
        ..pages = [
          const DashboardPage(),
          DashboardPage(schedule: off),
          DashboardPage(schedule: on),
        ]
        ..widgets = [
          w('first', 0),
          DashboardWidgetConfig(
            id: 'later',
            type: 'kind_later',
            x: 4,
            y: 0,
            width: 3,
            height: 2,
            schedule: off,
          ),
          w('asleep', 1),
          w('awake', 2),
        ];
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: config),
            ChangeNotifierProvider(create: (_) => DashboardService(config)),
            Provider(create: (_) => ScreenIdleService(config, const [])),
          ],
          child: const MaterialApp(home: DashboardScreen()),
        ),
      );
      await tester.pump();
      expect(find.textContaining('kind_first'), findsOneWidget);
      expect(
        find.textContaining('kind_later'),
        findsNothing,
        reason: 'a widget out of its hours is not drawn',
      );
      // Two pages showing, so two dots: the one out of its hours is not there.
      await tester.drag(find.byType(PageView), const Offset(-1200, 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('kind_awake'), findsOneWidget);
      expect(find.textContaining('kind_asleep'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

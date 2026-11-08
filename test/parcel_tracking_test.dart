import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/parcels_widget.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/l10n/dates.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/parcel_tracking.dart';
import 'package:home_canvas/services/parcels_service.dart';
import 'package:home_canvas/services/side_browser.dart';

void main() {
  group('17TRACK', () {
    final info = {
      'code': 0,
      'data': {
        'accepted': [
          {
            'number': 'QG123456785GB',
            'carrier': 11031,
            'track_info': {
              'latest_status': {'status': 'OutForDelivery'},
              'time_metrics': {
                'estimated_delivery_date': {
                  'source': 'Official',
                  'from': '2026-11-04T10:15:00+00:00',
                  'to': '2026-11-04T11:15:00+00:00',
                },
              },
              'tracking': {
                'providers': [
                  {
                    'provider': {'key': 11031, 'name': 'Royal Mail'},
                    'events': [
                      {
                        'time_iso': '2026-11-03T18:02:00+00:00',
                        'description': 'Item received',
                        'location': 'Medway Mail Centre',
                      },
                      {
                        'time_iso': '2026-11-04T07:41:00+00:00',
                        'description': 'Out for delivery',
                        'location': 'Maidstone DO',
                      },
                    ],
                  },
                ],
              },
            },
          },
        ],
        'rejected': [],
      },
    };

    test('registers once, then reads what it has', () async {
      final api = _Api({
        '/track/v2.4/register': (
          200,
          {
            'code': 0,
            'data': {
              'accepted': [
                {'number': 'QG123456785GB'},
              ],
              'rejected': [],
            },
          },
        ),
        '/track/v2.4/gettrackinfo': (200, info),
      });
      final t = SeventeenTrack('k', dio: api.dio);
      final memo = <String, dynamic>{};
      final first = await t.check('QG123456785GB', memo: memo);
      expect(first.ready, isFalse);
      expect(memo['registered'], isTrue);
      expect(api.asked.single.headers['17token'], 'k');

      final u = await t.check('QG123456785GB', memo: memo);
      expect(api.asked.map((o) => o.uri.path), [
        '/track/v2.4/register',
        '/track/v2.4/gettrackinfo',
      ]);
      expect(u.stage, ParcelStage.out);
      expect(u.carrier, Carrier.royalMail);
      expect(u.events.first.text, 'Out for delivery');
      expect(u.events.first.location, 'Maidstone DO');
      expect(u.expected, DateTime.utc(2026, 11, 4, 10, 15).toLocal());
      expect(u.expectedTo, DateTime.utc(2026, 11, 4, 11, 15).toLocal());
    });

    test('a number registered before is read straight away', () async {
      final api = _Api({
        '/track/v2.4/register': (
          200,
          {
            'code': 0,
            'data': {
              'accepted': [],
              'rejected': [
                {
                  'number': 'QG123456785GB',
                  'error': {
                    'code': SeventeenTrack.alreadyRegistered,
                    'message': 'already registered',
                  },
                },
              ],
            },
          },
        ),
        '/track/v2.4/gettrackinfo': (200, info),
      });
      final u = await SeventeenTrack(
        'k',
        dio: api.dio,
      ).check('QG123456785GB', memo: {});
      expect(u.stage, ParcelStage.out);
    });

    test('a refused key says so', () async {
      final api = _Api({
        '/track/v2.4/register': (401, {'code': -1}),
      });
      expect(
        () => SeventeenTrack('bad', dio: api.dio).check('X', memo: {}),
        throwsA(
          isA<TrackingError>().having((e) => e.keyRefused, 'refused', true),
        ),
      );
    });
  });

  group('Ship24', () {
    Map<String, Object> tracking(String milestone) => {
      'data': {
        'trackings': [
          {
            'tracker': {
              'trackerId': 'abc-123',
              'trackingNumber': '15501234567890',
              'courierCode': ['dpd-uk'],
            },
            'shipment': {
              'statusMilestone': milestone,
              'delivery': {'estimatedDeliveryDate': '2026-11-05'},
            },
            'events': [
              {
                'status': 'Your parcel has been delivered',
                'occurrenceDatetime': '2026-11-05T13:20:00',
                'location': 'Maidstone',
                'courierCode': 'dpd-uk',
                'statusMilestone': 'delivered',
              },
              {
                'status': 'Out for delivery',
                'occurrenceDatetime': '2026-11-05T08:01:00',
                'courierCode': 'dpd-uk',
              },
            ],
          },
        ],
      },
    };

    test('makes a tracker once, then asks for its results', () async {
      final api = _Api({
        '/public/v1/trackers/track': (200, tracking('out_for_delivery')),
        '/public/v1/trackers/abc-123/results': (200, tracking('delivered')),
      });
      final t = Ship24('k', dio: api.dio);
      final memo = <String, dynamic>{};
      final first = await t.check(
        '15501234567890',
        memo: memo,
        postcode: 'me14 1aa',
      );
      expect(first.stage, ParcelStage.out);
      expect(memo['tracker'], 'abc-123');
      final sent = api.asked.single;
      expect(sent.headers['Authorization'], 'Bearer k');
      expect(sent.data, {
        'trackingNumber': '15501234567890',
        'destinationPostCode': 'ME141AA',
      });

      final u = await t.check('15501234567890', memo: memo);
      expect(api.asked.last.method, 'GET');
      expect(u.stage, ParcelStage.delivered);
      expect(u.carrier, Carrier.dpd);
      expect(u.events.first.text, 'Your parcel has been delivered');
      expect(u.expected, DateTime(2026, 11, 5));
    });
  });

  group('the list', () {
    late _Tracker tracker;
    late ParcelsService s;
    late DateTime now;
    final news = <String>[];

    setUp(() {
      now = DateTime(2026, 11, 3, 9);
      tracker = _Tracker();
      news.clear();
      s =
          ParcelsService(
              null,
              persist: false,
              clock: () => now,
              tracker: (settings) =>
                  settings.service == 'none' ? null : tracker,
            )
            ..settingsOverride = const ParcelSettings(service: 'fake', key: 'k')
            ..onNews = (p) => news.add('${p.number} ${p.stage.name}');
    });

    test('a parcel shared is looked up, and news told once seen', () async {
      tracker.stage = ParcelStage.transit;
      final p = s.add(ParcelRef.find('QG123456785GB')!, label: ' Trainers ');
      await pumpEventQueue();
      expect(p.label, 'Trainers');
      expect(p.stage, ParcelStage.transit);
      // Already on its way when it was shared: no news in that.
      expect(news, isEmpty);

      tracker.stage = ParcelStage.out;
      now = now.add(ParcelsService.every);
      await s.checkDue();
      expect(news, ['QG123456785GB out']);
      // Asked again with nothing new, nothing more is said.
      now = now.add(ParcelsService.every);
      await s.checkDue();
      expect(news, hasLength(1));
      expect(tracker.asked, 3);
    });

    test('the same parcel twice is one, renamed', () async {
      s.add(ParcelRef.find('DPD 15501234567890')!);
      s.add(
        ParcelRef.find('https://track.dpd.co.uk/parcels/15501234567890*19826')!,
        label: 'Books',
      );
      expect(s.parcels, hasLength(1));
      expect(s.parcels.single.label, 'Books');
      expect(s.parcels.single.url, contains('*19826'));
    });

    test('nearest the door first, delivered last', () async {
      tracker.stage = ParcelStage.transit;
      final a = s.add(ParcelRef.find('QG123456785GB')!);
      final b = s.add(ParcelRef.find('1Z999AA10123456784')!);
      final c = s.add(ParcelRef.find('H01HYA0012345678')!);
      await pumpEventQueue();
      s.setDelivered(a.id, true);
      c.stage = ParcelStage.out;
      expect(s.parcels.map((p) => p.id), [c.id, b.id, a.id]);
      expect(s.coming, 2);
    });

    test('a delivered parcel is cleared away after a while', () {
      final p = s.add(ParcelRef.find('QG123456785GB')!);
      s.setDelivered(p.id, true);
      now = now.add(const Duration(days: 1));
      s.add(ParcelRef.find('1Z999AA10123456784')!);
      expect(s.parcels, hasLength(2));
      now = now.add(const Duration(days: 2));
      s.add(ParcelRef.find('H01HYA0012345678')!);
      expect(s.parcels.map((p) => p.number), [
        '1Z999AA10123456784',
        'H01HYA0012345678',
      ]);
    });

    test('a refused key stops the round, and says so', () async {
      tracker.error = const TrackingError('nope', keyRefused: true);
      s.add(ParcelRef.find('QG123456785GB')!);
      s.add(ParcelRef.find('1Z999AA10123456784')!);
      await pumpEventQueue();
      expect(s.serviceError, 'nope');
      // The second waits for the next round: there is no point asking.
      expect(tracker.asked, 1);
    });

    test('with no service, nothing is looked up', () async {
      s.settingsOverride = const ParcelSettings();
      s.add(ParcelRef.find('QG123456785GB')!);
      await pumpEventQueue();
      expect(tracker.asked, 0);
      expect(s.tracking, isFalse);
    });

    group('when it is coming', () {
      final due = <String>[];
      setUp(() {
        due.clear();
        s.onDue = (p) => due.add(parcelDueNow(p));
      });

      test('a window shared with the parcel is kept, and said as it opens', () {
        // Shared at nine, for DPD's "between 10:15 and 11:15".
        final p = s.add(
          ParcelRef.find('DPD 15501234567890')!,
          due: findDeliveryWindow(
            'Your parcel will be delivered today between 10:15 and 11:15',
            now,
          ),
        );
        expect(p.expected, DateTime(2026, 11, 3, 10, 15));
        expect(p.expectedTo, DateTime(2026, 11, 3, 11, 15));
        expect(p.dueSaid, isTrue);
        s.announceDue();
        expect(due, isEmpty, reason: 'not open yet');
        now = DateTime(2026, 11, 3, 10, 16);
        s.announceDue();
        s.announceDue();
        expect(due, ['Due now, until 11:15'], reason: 'once');
      });

      test('a window already open when it is said needs no telling', () {
        final p = s.add(ParcelRef.find('QG123456785GB')!);
        s.setDue(p.id, (from: DateTime(2026, 11, 3, 8), to: null));
        s.announceDue();
        expect(due, isEmpty);
        // Moved to tomorrow, it is news again tomorrow at eight.
        s.setDue(p.id, (from: DateTime(2026, 11, 4), to: null));
        now = DateTime(2026, 11, 4, 7, 59);
        s.announceDue();
        expect(due, isEmpty);
        now = DateTime(2026, 11, 4, 8);
        s.announceDue();
        expect(due, ['Due today']);
      });

      test('a window gone by is not said late', () {
        final p = s.add(ParcelRef.find('QG123456785GB')!);
        s.setDue(p.id, (
          from: DateTime(2026, 11, 4, 9),
          to: DateTime(2026, 11, 4, 13),
        ));
        now = DateTime(2026, 11, 4, 14);
        s.announceDue();
        expect(due, isEmpty);
      });

      test('nor one for a parcel already here', () {
        final p = s.add(ParcelRef.find('QG123456785GB')!);
        s.setDue(p.id, (from: DateTime(2026, 11, 3, 10), to: null));
        s.setDelivered(p.id, true);
        now = DateTime(2026, 11, 3, 10, 30);
        s.announceDue();
        expect(due, isEmpty);
      });

      test('the service\'s day beats one said; its silence does not', () async {
        tracker.stage = ParcelStage.transit;
        final p = s.add(ParcelRef.find('QG123456785GB')!);
        await pumpEventQueue();
        s.setDue(p.id, (from: DateTime(2026, 11, 5), to: null));
        now = now.add(ParcelsService.every);
        await s.checkDue();
        expect(p.expected, DateTime(2026, 11, 5), reason: 'no day from it');
        tracker.expected = DateTime(2026, 11, 6);
        now = now.add(ParcelsService.every);
        await s.checkDue();
        expect(p.expected, DateTime(2026, 11, 6));
        expect(p.dueSaid, isFalse);
      });

      test('not known is not known', () {
        final p = s.add(ParcelRef.find('QG123456785GB')!);
        s.setDue(p.id, (from: DateTime(2026, 11, 5), to: null));
        s.setDue(p.id, null);
        expect(p.expected, isNull);
        expect(p.dueSaid, isFalse);
      });

      test('said, and kept across a restart', () async {
        final dir = Directory.systemTemp.createTempSync('parcels');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = '${dir.path}/parcels.json';
        final one = ParcelsService(null, file: file, clock: () => now)
          ..settingsOverride = const ParcelSettings();
        final p = one.add(ParcelRef.find('QG123456785GB')!);
        one.setDue(p.id, (from: DateTime(2026, 11, 3, 8), to: null));
        await one.saved;
        final two = ParcelsService(null, file: file, clock: () => now)
          ..settingsOverride = const ParcelSettings();
        await two.load();
        final back = two.parcels.single;
        expect(back.dueSaid, isTrue);
        expect(back.toldDue, isNotNull, reason: 'not said again at start');
      });
    });

    test('kept across a restart', () async {
      final dir = Directory.systemTemp.createTempSync('parcels');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = '${dir.path}/parcels.json';
      final one = ParcelsService(null, file: file, clock: () => now)
        ..settingsOverride = const ParcelSettings();
      final p = one.add(ParcelRef.find('QG123456785GB')!, label: 'Shoes');
      p
        ..stage = ParcelStage.out
        ..events = [ParcelEvent(text: 'Out', at: now, location: 'Maidstone')]
        ..memo['registered'] = true;
      one.setDelivered(p.id, false);
      await one.saved;
      final two = ParcelsService(null, file: file, clock: () => now)
        ..settingsOverride = const ParcelSettings();
      await two.load();
      final back = two.parcels.single;
      expect(back.label, 'Shoes');
      expect(back.carrier, Carrier.royalMail);
      expect(back.events.single.location, 'Maidstone');
      expect(back.memo['registered'], isTrue);
    });

    test('the tile\'s settings', () {
      final config = ConfigService();
      config.config.dashboard.widgets = [
        DashboardWidgetConfig(
          id: 'p',
          type: 'parcels',
          x: 0,
          y: 0,
          width: 4,
          height: 4,
          options: {
            'service': 'ship24',
            'apiKey': ' key ',
            'keepDays': '7',
            'tell': false,
          },
        ),
      ];
      final settings = ParcelsService(config, persist: false).settings;
      expect(settings.service, 'ship24');
      expect(settings.keep, const Duration(days: 7));
      expect(settings.tell, isFalse);
      expect(
        ParcelTracker.forService(settings.service, settings.key),
        isA<Ship24>().having((t) => t.key, 'key', 'key'),
      );
    });
  });

  group('the tile', () {
    setUpAll(registerBuiltInWidgets);

    // LCARS's own condensed letters, as the panel draws them: the test
    // font's are squares, three times as wide, and no heading fits.
    setUpAll(() async {
      final antonio = FontLoader('Antonio')
        ..addFont(rootBundle.load('assets/fonts/Antonio.ttf'));
      await antonio.load();
    });

    Future<void> draw(
      WidgetTester tester,
      ParcelsService s,
      Size size,
      DashboardTheme theme,
    ) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final w = DashboardWidgetContext(
        theme: theme,
        config: DashboardWidgetConfig(
          id: 'p',
          type: 'parcels',
          x: 0,
          y: 0,
          width: 4,
          height: 4,
        ),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: s,
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                  size: size,
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      fontFamily: theme.isLcars ? 'Antonio' : null,
                    ),
                    child: Builder(
                      builder: (context) =>
                          WidgetRegistry.find('parcels')!.build(context, w),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    ParcelsService filled(int n) {
      final s = ParcelsService(null, persist: false)
        ..settingsOverride = const ParcelSettings();
      final refs = [
        'QG123456785GB',
        'DPD 15501234567890',
        'H01HYA0012345678',
        '1Z999AA10123456784',
        'https://www.amazon.co.uk/progress-tracker/package/?orderId=1',
      ];
      for (var i = 0; i < n; i++) {
        final p = s.add(
          ParcelRef.find(refs[i % refs.length])!,
          label: i == 0 ? 'A very long name for a pair of trainers' : null,
        );
        p.stage = ParcelStage.values[i % ParcelStage.values.length];
        p.expected = DateTime.now().add(Duration(days: i));
        p.events = [ParcelEvent(text: 'Arrived at depot', at: DateTime.now())];
      }
      return s;
    }

    final themes = [
      for (final id in ['glass', 'lcars', 'paper'])
        kBuiltInThemes.firstWhere((t) => t.id == id),
    ];

    testWidgets('fits, from a small tile to a big one, in every look', (
      tester,
    ) async {
      for (final theme in themes) {
        for (final n in [0, 1, 3, 9]) {
          for (final size in const [
            Size(300, 260),
            Size(620, 300),
            Size(620, 560),
            Size(300, 900),
          ]) {
            await draw(tester, filled(n), size, theme);
            expect(
              tester.takeException(),
              isNull,
              reason: '${theme.id}, $n parcels at $size',
            );
          }
        }
      }
    });

    testWidgets('one parcel says where it is; a tap opens it', (tester) async {
      final s = filled(1)..parcels.single.stage = ParcelStage.out;
      await draw(tester, s, const Size(620, 560), themes.first);
      expect(find.text('Out for delivery'), findsWidgets);
      expect(find.text('1 out for delivery'), findsOneWidget);
      await tester.tap(find.text('A very long name for a pair of trainers'));
      await tester.pumpAndSettle();
      expect(find.byType(ParcelSheet), findsOneWidget);
      expect(find.text('Arrived at depot'), findsOneWidget);
      await tester.tap(find.text('It’s here'));
      await tester.pump();
      expect(s.parcels.single.delivered, isTrue);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(s.parcels, isEmpty);
      expect(find.byType(ParcelSheet), findsNothing);
    });

    group('a page to itself', () {
      // No labwc in a test: the frame shows the parcel's story, and its
      // page would open in a window of its own.
      setUp(() => SideBrowser.availableOverride = false);
      tearDown(() => SideBrowser.availableOverride = null);

      testWidgets('the list beside a frame, in every look', (tester) async {
        for (final theme in themes) {
          for (final n in [1, 3, 9]) {
            for (final size in const [Size(1880, 1000), Size(1100, 560)]) {
              await draw(tester, filled(n), size, theme);
              expect(
                tester.takeException(),
                isNull,
                reason: '${theme.id}, $n parcels at $size',
              );
              expect(find.byIcon(Icons.public), findsOneWidget);
            }
          }
        }
      });

      testWidgets('a touch on the list shows that parcel in the frame', (
        tester,
      ) async {
        final s = filled(3);
        await draw(tester, s, const Size(1880, 1000), themes.first);
        final second = s.parcels[1];
        expect(find.text('Arrived at depot'), findsOneWidget);
        await tester.tap(find.text(parcelName(second)).first);
        await tester.pump();
        // Its name twice now — in the list and over the frame — and no
        // sheet over everything.
        expect(find.text(parcelName(second)), findsNWidgets(2));
        expect(find.byType(ParcelSheet), findsNothing);
        await tester.tap(find.text('It’s here'));
        await tester.pump();
        expect(s.byId(second.id)!.delivered, isTrue);
      });

      Finder inPicker(String text) => find.descendant(
        of: find.byType(DuePicker),
        matching: find.text(text),
      );

      testWidgets('the week ahead, a day a row, today lit', (tester) async {
        final s = filled(3);
        final today = DateTime.now();
        s.parcels[2].expected = null;
        await draw(tester, s, const Size(1880, 1000), themes.first);
        expect(find.text('The week ahead'), findsOneWidget);
        expect(find.text('Today'), findsWidgets);
        expect(find.text('Tomorrow'), findsWidgets);
        expect(find.text('No day yet'), findsOneWidget);
        final dayAfter = DateTime(today.year, today.month, today.day + 2);
        expect(
          find.text('${weekdayShort(dayAfter)} ${dayAfter.day}'),
          findsOneWidget,
        );
      });

      testWidgets('When? sets a day and a part of it', (tester) async {
        final s = filled(1)..parcels.single.expected = null;
        await draw(tester, s, const Size(1880, 1000), themes.first);
        await tester.tap(find.text('When?'));
        await tester.pumpAndSettle();
        expect(find.byType(DuePicker), findsOneWidget);
        await tester.tap(find.text('Tomorrow').last);
        await tester.tap(find.text('Morning'));
        await tester.pump();
        expect(find.text('Due tomorrow, 08:00–12:00'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.byType(DuePicker), findsNothing);
        final p = s.parcels.single;
        final now = DateTime.now();
        expect(p.expected, DateTime(now.year, now.month, now.day + 1, 8));
        expect(p.expectedTo, DateTime(now.year, now.month, now.day + 1, 12));
        expect(p.dueSaid, isTrue);
      });

      testWidgets('a slot to the quarter hour, and taken back', (tester) async {
        final s = filled(1);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        s.setDue(s.parcels.single.id, (
          from: today.add(const Duration(hours: 14, minutes: 30)),
          to: today.add(const Duration(hours: 16, minutes: 30)),
        ));
        await draw(tester, s, const Size(1880, 1000), themes[1]);
        await tester.tap(find.text('WHEN?'));
        await tester.pumpAndSettle();
        // Opened on what it is now: today, the slot, from 14:30 for two.
        expect(inPicker('Due today, 14:30–16:30'), findsOneWidget);
        await tester.tap(find.text('09:30'));
        await tester.tap(find.text(':15'));
        await tester.tap(find.text('AN HOUR'));
        await tester.pump();
        expect(inPicker('Due today, 09:15–10:15'), findsOneWidget);
        await tester.tap(find.text('NOT KNOWN'));
        await tester.pumpAndSettle();
        expect(s.parcels.single.expected, isNull);
      });

      testWidgets('Done untouched keeps a "by" as it was', (tester) async {
        final s = filled(1);
        final now = DateTime.now();
        final by = (
          from: DateTime(now.year, now.month, now.day + 1),
          to: DateTime(now.year, now.month, now.day + 1, 22),
        );
        s.setDue(s.parcels.single.id, by);
        await draw(tester, s, const Size(1880, 1000), themes.first);
        await tester.tap(find.text('When?'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(s.parcels.single.expected, by.from);
        expect(s.parcels.single.expectedTo, by.to);
      });

      testWidgets('the picker fits, in every look', (tester) async {
        for (final theme in themes) {
          final s = filled(1);
          await draw(tester, s, const Size(1880, 1000), theme);
          await tester.tap(
            find.byWidgetPredicate(
              (w) => w is Text && w.data?.toLowerCase() == 'when?',
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(DuePicker), findsOneWidget, reason: theme.id);
          expect(tester.takeException(), isNull, reason: theme.id);
          await tester.tapAt(const Offset(4, 4));
          await tester.pumpAndSettle();
          expect(find.byType(DuePicker), findsNothing, reason: theme.id);
        }
      });
    });
  });
}

/// A tracking service that says what it is told to.
class _Tracker implements ParcelTracker {
  ParcelStage stage = ParcelStage.transit;
  TrackingError? error;
  DateTime? expected;
  int asked = 0;

  @override
  String get id => 'fake';

  @override
  Future<ParcelUpdate> check(
    String number, {
    required TrackerMemo memo,
    String? postcode,
  }) async {
    asked++;
    if (error != null) throw error!;
    return ParcelUpdate(
      stage: stage,
      expected: expected,
      events: [ParcelEvent(text: stage.name, at: DateTime(2026, 11, 3))],
    );
  }
}

/// A tracking API answering each path with a status and a body.
class _Api implements HttpClientAdapter {
  _Api(this.answers);

  final Map<String, (int, Object)> answers;
  final asked = <RequestOptions>[];

  Dio get dio => Dio()..httpClientAdapter = this;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options);
    final answer = answers[options.uri.path];
    if (answer == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'down',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(answer.$2),
      answer.$1,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

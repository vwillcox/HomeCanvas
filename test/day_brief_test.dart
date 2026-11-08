import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/day_brief.dart';
import 'package:home_canvas/dashboard/widgets/day_brief_sheet.dart';
import 'package:home_canvas/look.dart';
import 'package:home_canvas/services/article_reader.dart';
import 'package:home_canvas/services/bin_schedule.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/elevenlabs_tts.dart';
import 'package:home_canvas/services/feed_service.dart';
import 'package:home_canvas/services/parcels_service.dart';
import 'package:home_canvas/services/reminders_service.dart';
import 'package:home_canvas/services/timer_service.dart';
import 'package:home_canvas/services/weather_service.dart';
import 'package:home_canvas/theme.dart';
import 'package:home_canvas/widgets/lcars.dart';

// Tuesday 3 November 2026, a quarter to eleven.
final _now = DateTime(2026, 11, 3, 10, 46);
DateTime _at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);

Weather _weather(DateTime now, {bool rain = true}) {
  final start = DateTime(now.year, now.month, now.day);
  return Weather(
    temperature: 12.4,
    feelsLike: 10,
    tempMax: 14,
    tempMin: 7,
    weatherCode: 3,
    isDay: true,
    label: 'Maidstone',
    unit: '°C',
    humidity: 80,
    windSpeed: 12,
    windUnit: 'km/h',
    daily: [
      for (var i = 0; i < 3; i++)
        DailyForecast(
          date: DateTime(now.year, now.month, now.day + i),
          weatherCode: 61,
          tempMax: 14.0 - i,
          tempMin: 7.0 - i,
          precipitationChance: 70,
          windMax: 20,
          uvIndexMax: 1,
          sunrise: '06:58',
          sunset: '16:28',
        ),
    ],
    hourly: [
      for (var h = 0; h < 48; h++)
        HourlyForecast(
          time: start.add(Duration(hours: h)),
          temperature: 10,
          weatherCode: 3,
          // Wet from three till six this afternoon, and early tomorrow.
          precipitationChance: rain && ((h >= 15 && h < 18) || h == 27)
              ? (h == 16 ? 80 : 60)
              : 10,
          isDay: true,
        ),
    ],
  );
}

Parcel _parcel(
  String id,
  String label, {
  DateTime? from,
  DateTime? to,
  ParcelStage stage = ParcelStage.transit,
}) => Parcel(
  id: id,
  carrier: Carrier.dpd,
  url: 'https://track.dpd.co.uk/',
  added: _now,
  label: label,
  expected: from,
  expectedTo: to,
)..stage = stage;

DayBrief _brief({DateTime? now}) {
  final at = now ?? _now;
  const blue = Color(0xFF3366FF);
  return DayBrief.gather(
    now: at,
    weather: _weather(at),
    events: [
      (
        CalendarEvent(title: 'Standup', start: _at(3, 9), end: _at(3, 9, 15)),
        blue,
      ),
      (
        CalendarEvent(
          title: 'Dentist',
          start: _at(3, 14),
          end: _at(3, 14, 30),
          location: 'High Street',
        ),
        blue,
      ),
      // Started yesterday, ends Thursday: on all day today and tomorrow.
      (
        CalendarEvent(
          title: 'Half term',
          start: DateTime(2026, 11, 2),
          end: DateTime(2026, 11, 5),
          allDay: true,
        ),
        blue,
      ),
      (
        CalendarEvent(
          title: 'Parents’ evening',
          start: _at(4, 18),
          end: _at(4, 19),
        ),
        blue,
      ),
      // Last week: nothing to do with today.
      (CalendarEvent(title: 'Gone', start: _at(1, 9)), blue),
    ],
    reminders: [
      Reminder(
        id: '1',
        text: 'Call the vet',
        from: 'Jo',
        created: _now,
        due: _at(3, 17),
      ),
      Reminder(
        id: '2',
        text: 'Recycling',
        from: '',
        created: _now,
        due: DateTime(2026, 11, 4),
        allDay: true,
      ),
    ],
    parcels: [
      _parcel('a', 'Trainers', from: _at(3, 10, 15), to: _at(3, 11, 15)),
      _parcel('b', 'Coffee', from: DateTime(2026, 11, 4), to: _at(4, 12)),
      _parcel('c', 'Kettle', stage: ParcelStage.out),
      _parcel('d', 'Delivered', from: _at(3, 9), stage: ParcelStage.delivered),
    ],
    bins: [
      BinCollection(DateTime(2026, 11, 4), [
        Bin(name: 'Rubbish', colour: Colors.black, first: DateTime(2026, 1, 7)),
        Bin(name: 'Food', colour: Colors.green, first: DateTime(2026, 1, 7)),
      ], BinStage.later),
    ],
    timers: [
      KioskTimer(
        id: 1,
        label: 'Pasta',
        total: const Duration(minutes: 10),
        now: at,
      ),
    ],
  );
}

void main() {
  group('the day, put together', () {
    test('today in order: the all-day things first, then by the clock', () {
      final b = _brief();
      expect(b.today.map((i) => i.text), [
        'Half term',
        'Kettle',
        'Bins out tonight: rubbish and food',
        'Standup',
        'Trainers',
        'Pasta',
        'Dentist',
        'Rain likely',
        'Sunset',
        'Call the vet',
      ]);
      expect(b.tomorrow.map((i) => i.text), [
        'Half term',
        'Recycling',
        'Bin day: rubbish and food',
        'Coffee',
        'Parents’ evening',
      ]);
    });

    test('what is over, what is next', () {
      final b = _brief();
      expect(b.ahead.map((i) => i.text), isNot(contains('Standup')));
      expect(b.ahead.map((i) => i.text), contains('Half term'));
      // Its window is still open: the next thing, not a thing gone.
      expect(b.next?.text, 'Trainers');
      final later = _brief(now: _at(3, 11, 30));
      expect(later.next?.text, 'Pasta');
    });

    test('a parcel keeps its window, and a "by" stays a "by"', () {
      final b = _brief();
      final trainers = b.today.firstWhere((i) => i.text == 'Trainers');
      expect(trainers.at, _at(3, 10, 15));
      expect(trainers.until, _at(3, 11, 15));
      final coffee = b.tomorrow.firstWhere((i) => i.text == 'Coffee');
      expect(coffee.at, isNull);
      expect(coffee.until, _at(4, 12));
      expect(coffee.time, _at(4, 12));
    });

    test('rain: from the first likely hour to the first dry one, today', () {
      final r = DayBrief.rainWindow(_weather(_now), _now)!;
      expect(r.from, _at(3, 15));
      expect(r.to, _at(3, 18));
      expect(r.chance, 80);
      expect(
        DayBrief.rainWindow(_weather(_now, rain: false), _now),
        isNull,
        reason: 'tomorrow’s rain is not today’s',
      );
      // Once it has started, from this hour.
      expect(
        DayBrief.rainWindow(_weather(_now), _at(3, 16, 20))!.from,
        _at(3, 16),
      );
    });

    test('said out loud, in a few sentences', () {
      final said = _brief().spoken();
      expect(said.first, 'Good morning.');
      expect(said[1], contains('It’s 12 degrees and overcast.'));
      expect(said[1], contains('A high of 14, and a low of 7.'));
      expect(said[1], contains('Rain is likely between 3 pm and 6 pm.'));
      final today = said[2];
      expect(today, startsWith('Still to come today:'));
      expect(today, isNot(contains('Standup')));
      expect(today, contains('Trainers is due between 10:15 am and 11:15 am.'));
      expect(today, contains('Kettle is coming, out for delivery.'));
      expect(today, contains('The pasta timer ends at 10:56 am.'));
      expect(today, contains('At 2 pm, Dentist.'));
      expect(today, contains('At 5 pm, a reminder: Call the vet.'));
      expect(today, isNot(contains('Sunset')));
      expect(said[3], startsWith('Tomorrow:'));
      expect(said[3], contains('Coffee is due by midday.'));
      expect(said[3], contains('And 1 more.'));
    });

    test('an empty day says so', () {
      final b = DayBrief.gather(now: _now);
      expect(b.today, isEmpty);
      expect(b.spoken(), ['Good morning.', 'Nothing else is on today.']);
    });

    test('times as said', () {
      expect(saidTime(_at(3, 15)), '3 pm');
      expect(saidTime(_at(3, 10, 5)), '10:05 am');
      expect(saidTime(_at(3, 12)), 'midday');
      expect(saidTime(_at(3, 0)), 'midnight');
      expect(saidTime(_at(3, 0, 30)), '12:30 am');
    });
  });

  group('the sheet', () {
    setUpAll(() async {
      final antonio = FontLoader('Antonio')
        ..addFont(rootBundle.load('assets/fonts/Antonio.ttf'));
      await antonio.load();
    });

    final themes = [
      for (final id in ['glass', 'lcars', 'paper'])
        kBuiltInThemes.firstWhere((t) => t.id == id),
    ];

    Future<_Output> draw(
      WidgetTester tester,
      DashboardTheme theme, {
      bool full = true,
      bool read = false,
    }) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final parcels = ParcelsService(null, persist: false)
        ..settingsOverride = const ParcelSettings();
      final reminders = RemindersService(persist: false);
      if (full) {
        for (final (i, h) in [9, 11, 13, 15, 17, 19, 21].indexed) {
          final p = parcels.add(
            ParcelRef.find('https://track.dpd.co.uk/parcels/1550000000000$i')!,
            label: 'A parcel with rather a long name, number $i',
          );
          parcels.setDue(p.id, (
            from: today.add(Duration(hours: h)),
            to: today.add(Duration(hours: h + 1)),
          ));
        }
        parcels.setDue(
          parcels.add(ParcelRef.find('QG123456785GB')!, label: 'Shoes').id,
          (from: today.add(const Duration(days: 1)), to: null),
        );
      }
      final out = _Output();
      final reader = ArticleReader(output: out, volume: () => 50);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ConfigService()),
            ChangeNotifierProvider<WeatherService>(
              create: (_) => _FakeWeather(full ? _weather(now) : null),
            ),
            ChangeNotifierProvider.value(value: parcels),
            ChangeNotifierProvider<RemindersService?>.value(value: reminders),
            ChangeNotifierProvider.value(value: reader),
          ],
          child: KioskLook(
            theme: theme,
            child: MaterialApp(
              theme: buildTheme(theme),
              home: Scaffold(
                body: DefaultTextStyle.merge(
                  style: TextStyle(
                    fontFamily: theme.isLcars ? 'Antonio' : null,
                  ),
                  child: DayBriefSheet(theme: theme, read: read),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      return out;
    }

    testWidgets('fits, full or empty, in every look', (tester) async {
      for (final theme in themes) {
        for (final full in [true, false]) {
          await draw(tester, theme, full: full);
          expect(
            tester.takeException(),
            isNull,
            reason: '${theme.id}, ${full ? 'a full day' : 'nothing on'}',
          );
          expect(
            find.textContaining(RegExp('your day', caseSensitive: false)),
            findsOneWidget,
          );
        }
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the day as it is: weather, parcels, tomorrow', (tester) async {
      await draw(tester, themes.first);
      expect(find.text('12°'), findsOneWidget);
      expect(find.text('Shoes'), findsOneWidget);
      expect(find.textContaining('Tomorrow'), findsWidgets);
      expect(find.textContaining('Rain likely'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('read out at a touch, and stopped at another', (tester) async {
      final out = await draw(tester, themes.first);
      await tester.tap(find.text('Read it to me'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(out.made.first, startsWith('Good '));
      expect(find.text('Stop reading'), findsOneWidget);
      await tester.tap(find.text('Stop reading'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.text('Read it to me'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the greeting on a crowded console bar', () {
    final lcars = kBuiltInThemes.firstWhere((t) => t.id == 'lcars');

    Future<void> bar(WidgetTester tester, double width) async {
      await tester.pumpWidget(
        KioskLook(
          theme: lcars,
          child: MaterialApp(
            theme: buildTheme(lcars),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: const LcarsTextBar(
                    title: 'Good morning',
                    short: 'Morning',
                    note: 'Tuesday 3 November',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('whole where it fits, a word where it does not', (
      tester,
    ) async {
      await bar(tester, 1000);
      expect(find.text('GOOD MORNING'), findsOneWidget);
      expect(find.text('TUESDAY 3 NOVEMBER'), findsOneWidget);
      await bar(tester, 260);
      expect(find.text('MORNING'), findsOneWidget);
      expect(
        find.text('TUESDAY 3 NOVEMBER'),
        findsNothing,
        reason: 'no words in a stub of bar',
      );
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeWeather extends WeatherService {
  _FakeWeather(this.fixed) : super(ConfigService());
  final Weather? fixed;
  @override
  Weather? get weather => fixed;
}

/// Says nothing, but keeps what it was asked to say.
class _Output implements SpeechOutput {
  final made = <String>[];
  Completer<void>? _playing;

  @override
  Future<File?> synthesise(
    String text, {
    String? voice,
    double speed = 1,
    ElevenLabsVoice? cloud,
  }) async {
    made.add(text);
    return File('brief-${made.length}.wav');
  }

  @override
  Future<void> play(File file, double volume) =>
      (_playing = Completer<void>()).future;

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {
    final p = _playing;
    if (p != null && !p.isCompleted) p.complete();
  }
}

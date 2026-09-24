import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:immich_kiosk_pi/dashboard/dashboard_theme.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/weather_forecast_sheet.dart';
import 'package:immich_kiosk_pi/services/config_service.dart';
import 'package:immich_kiosk_pi/services/weather_service.dart';

/// A weather service that has already fetched [fixed], and fetches nothing.
class FakeWeather extends WeatherService {
  FakeWeather(this.fixed) : super(ConfigService());
  final Weather? fixed;
  @override
  Weather? get weather => fixed;
}

DailyForecast day(DateTime d, double lo, double hi, {int rain = 0}) =>
    DailyForecast(
      date: d,
      weatherCode: 3,
      tempMax: hi,
      tempMin: lo,
      precipitationChance: rain,
      windMax: 10,
      uvIndexMax: 4,
      sunrise: '06:52',
      sunset: '19:08',
    );

Weather sample() {
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day, today.hour);
  return Weather(
    // 16° appears nowhere else in the sample — the lows run 9–15 and the
    // highs 17–23 — so finding it means finding the reading.
    temperature: 16,
    feelsLike: 12,
    tempMax: 17,
    tempMin: 9,
    weatherCode: 3,
    isDay: true,
    label: 'Thornton-Cleveleys',
    unit: '°C',
    humidity: 81,
    windSpeed: 19,
    windUnit: 'km/h',
    daily: [
      for (var i = 0; i < 7; i++)
        day(DateTime(today.year, today.month, today.day + i), 9.0 + i,
            17.0 + i, rain: i == 2 ? 70 : 5),
    ],
    hourly: [
      for (var i = 0; i < 25; i++)
        HourlyForecast(
          time: start.add(Duration(hours: i)),
          temperature: 10 + (i % 12).toDouble(),
          weatherCode: 3,
          precipitationChance: i == 5 ? 60 : 0,
          isDay: i < 10,
        ),
    ],
  );
}

Future<FakeWeather> pumpSheet(WidgetTester tester, Weather? w,
    {Size size = const Size(1920, 1200)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = FakeWeather(w);
  await tester.pumpWidget(
    ChangeNotifierProvider<WeatherService>.value(
      value: fake,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () =>
                    showWeatherForecast(context, kBuiltInThemes.first),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return fake;
}

Future<void> finish(WidgetTester tester, FakeWeather fake) async {
  await tester.pumpWidget(const SizedBox());
  fake.dispose();
}

void main() {
  group('reading the hourly forecast', () {
    test('one entry an hour, in order', () {
      final hours = parseHourly({
        'time': ['2026-09-24T09:00', '2026-09-24T10:00'],
        'temperature_2m': [10.7, 11.2],
        'weather_code': [3, 61],
        'precipitation_probability': [0, 45],
        'is_day': [1, 1],
      });
      expect(hours, hasLength(2));
      expect(hours[1].time, DateTime(2026, 9, 24, 10));
      expect(hours[1].temperature, 11.2);
      expect(hours[1].weatherCode, 61);
      expect(hours[1].precipitationChance, 45);
    });

    test('a forecast without an hourly block is still a forecast', () {
      expect(parseHourly(null), isEmpty);
      expect(parseHourly('nonsense'), isEmpty);
    });

    test('a short column fills in rather than throwing', () {
      final hours = parseHourly({
        'time': ['2026-09-24T09:00', '2026-09-24T10:00'],
        'temperature_2m': [10.7],
      });
      expect(hours, hasLength(2));
      expect(hours[1].temperature, 0);
      expect(hours[1].isDay, isTrue);
    });
  });

  group('the week bars', () {
    test('share one scale, from the coldest low to the warmest high', () {
      final now = DateTime(2026, 9, 24);
      expect(weekRange([day(now, 8, 15), day(now, 11, 21)]), (8.0, 21.0));
    });

    test('a flat week still draws as bars', () {
      final now = DateTime(2026, 9, 24);
      final r = weekRange([day(now, 12, 12), day(now, 12, 12)]);
      expect(r.$2 - r.$1, greaterThanOrEqualTo(1));
    });

    test('a value lands where it should on the scale, and never off it', () {
      expect(rangeFraction(15, (10, 20)), 0.5);
      expect(rangeFraction(-5, (10, 20)), 0);
      expect(rangeFraction(40, (10, 20)), 1);
      expect(rangeFraction(15, (20, 20)), 0.5);
    });
  });

  group('labels', () {
    test('the first hour is "Now", the rest are on the 24-hour clock', () {
      expect(hourLabel(DateTime(2026, 9, 24, 9), first: true), 'Now');
      expect(hourLabel(DateTime(2026, 9, 24, 9)), '09:00');
      expect(hourLabel(DateTime(2026, 9, 24, 21)), '21:00');
    });

    test('days are "Today" or spelled out in full', () {
      final now = DateTime(2026, 9, 24); // a Thursday
      expect(dayName(now, now: now), 'Today');
      expect(dayName(DateTime(2026, 9, 25), now: now), 'Friday');
      expect(dayName(DateTime(2026, 9, 28), now: now), 'Monday');
    });

    test('UV follows the Met Office bands', () {
      expect(uvLabel(1), 'Low');
      expect(uvLabel(4), 'Moderate');
      expect(uvLabel(7), 'High');
      expect(uvLabel(9), 'Very high');
      expect(uvLabel(11), 'Extreme');
    });
  });

  group('"Now" in the hourly strip', () {
    test('shows the reading, not the forecast for the top of the hour', () {
      final w = sample();
      final hours = withNow(w);
      expect(hours.first.temperature, w.temperature);
      expect(hours.first.weatherCode, w.weatherCode);
      expect(hours.first.time, w.hourly.first.time);
      expect(hours.skip(1).map((h) => h.temperature),
          w.hourly.skip(1).map((h) => h.temperature));
    });

    test('no hourly forecast, no strip', () {
      final w = sample();
      expect(
          withNow(Weather(
            temperature: w.temperature,
            feelsLike: w.feelsLike,
            tempMax: w.tempMax,
            tempMin: w.tempMin,
            weatherCode: w.weatherCode,
            isDay: w.isDay,
            label: w.label,
            unit: w.unit,
          )),
          isEmpty);
    });
  });

  group('fitting the hours across', () {
    List<HourlyForecast> n(int count) => [
          for (var i = 0; i < count; i++)
            HourlyForecast(
              time: DateTime(2026, 9, 24, i % 24),
              temperature: 10,
              weatherCode: 0,
              precipitationChance: 0,
              isDay: true,
            ),
        ];

    test('every hour when there is room', () {
      expect(hoursToShow(n(25), 1800), hasLength(25));
    });

    test('every other hour when there is not, keeping the first', () {
      final shown = hoursToShow(n(25), 900);
      expect(shown, hasLength(13));
      expect(shown.first.time.hour, 0);
      expect(shown[1].time.hour, 2);
    });
  });

  group('on the panel', () {
    testWidgets('shows now, the day and the week', (tester) async {
      final fake = await pumpSheet(tester, sample());
      expect(find.text('Thornton-Cleveleys'), findsOneWidget);
      expect(find.text('16°'), findsOneWidget);
      expect(find.text('Now'), findsOneWidget, reason: 'the hourly strip');
      expect(find.text('Today'), findsOneWidget, reason: 'the week');
      expect(find.text('NEXT 7 DAYS'), findsOneWidget);
      expect(find.text('81%'), findsOneWidget, reason: 'humidity');
      expect(find.text('70%'), findsOneWidget,
          reason: 'a wet day says so; a dry one does not');
      expect(tester.takeException(), isNull);
      await finish(tester, fake);
    });

    testWidgets('the close button closes it', (tester) async {
      final fake = await pumpSheet(tester, sample());
      await tester.tap(find.bySemanticsLabel('Close the forecast').last);
      await tester.pumpAndSettle();
      expect(find.text('NEXT 7 DAYS'), findsNothing);
      await finish(tester, fake);
    });

    testWidgets('a tap outside it closes it', (tester) async {
      final fake = await pumpSheet(tester, sample());
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('NEXT 7 DAYS'), findsNothing);
      await finish(tester, fake);
    });

    testWidgets('a tap on it does not', (tester) async {
      final fake = await pumpSheet(tester, sample());
      await tester.tap(find.text('NEXT 7 DAYS'));
      await tester.pumpAndSettle();
      expect(find.text('NEXT 7 DAYS'), findsOneWidget);
      await finish(tester, fake);
    });

    testWidgets('a swipe down closes it', (tester) async {
      final fake = await pumpSheet(tester, sample());
      await tester.fling(find.text('NEXT 7 DAYS'), const Offset(0, 400), 1500);
      await tester.pumpAndSettle();
      expect(find.text('NEXT 7 DAYS'), findsNothing);
      await finish(tester, fake);
    });

    testWidgets('a small drag springs back instead', (tester) async {
      final fake = await pumpSheet(tester, sample());
      await tester.drag(find.text('NEXT 7 DAYS'), const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(find.text('NEXT 7 DAYS'), findsOneWidget);
      await finish(tester, fake);
    });

    testWidgets('it closes itself if left open', (tester) async {
      final fake = await pumpSheet(tester, sample());
      await tester.pump(const Duration(minutes: 2, seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('NEXT 7 DAYS'), findsNothing);
      await finish(tester, fake);
    });

    testWidgets('before the first forecast it says so', (tester) async {
      final fake = await pumpSheet(tester, null);
      expect(find.text('Waiting for the forecast…'), findsOneWidget);
      await finish(tester, fake);
    });

    testWidgets('fits a portrait screen without overflowing', (tester) async {
      final fake =
          await pumpSheet(tester, sample(), size: const Size(800, 1280));
      expect(tester.takeException(), isNull);
      await finish(tester, fake);
    });
  });
}

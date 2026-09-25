import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'config_service.dart';

/// Half an hour of the grid's forecast carbon intensity.
@immutable
class CarbonSlot {
  const CarbonSlot(this.from, this.grams, this.index);

  final DateTime from;

  /// Grams of CO₂ per kWh.
  final int grams;

  /// The National Grid's own word for it: "very low" to "very high".
  final String index;
}

@immutable
class CarbonForecast {
  const CarbonForecast({required this.region, required this.slots});

  /// "East England".
  final String region;
  final List<CarbonSlot> slots;

  /// The slot covering [now], or the first one if the forecast starts later.
  CarbonSlot? at(DateTime now) {
    for (final s in slots) {
      if (!now.isBefore(s.from) &&
          now.isBefore(s.from.add(const Duration(minutes: 30)))) {
        return s;
      }
    }
    return slots.isEmpty ? null : slots.first;
  }

  /// The next day's worth of slots from [now].
  List<CarbonSlot> nextDay(DateTime now) => slots
      .where(
        (s) =>
            !s.from.add(const Duration(minutes: 30)).isBefore(now) &&
            s.from.isBefore(now.add(const Duration(hours: 24))),
      )
      .toList();

  /// The cleanest [length] of the next day: where to put the washing.
  ({DateTime from, DateTime to, int average})? greenest(
    DateTime now, {
    Duration length = const Duration(hours: 3),
  }) {
    final day = nextDay(now);
    final n = length.inMinutes ~/ 30;
    if (day.length < n) return null;
    var best = -1;
    var bestSum = 1 << 30;
    for (var i = 0; i + n <= day.length; i++) {
      final sum = day.sublist(i, i + n).fold<int>(0, (a, s) => a + s.grams);
      if (sum < bestSum) {
        bestSum = sum;
        best = i;
      }
    }
    return (
      from: day[best].from,
      to: day[best + n - 1].from.add(const Duration(minutes: 30)),
      average: (bestSum / n).round(),
    );
  }

  static CarbonForecast fromApi(Map<String, dynamic> json) {
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final slots = <CarbonSlot>[];
    for (final s in (data['data'] as List? ?? const []).whereType<Map>()) {
      final from =
          DateTime.tryParse(
            '${s['from']}'.replaceFirst(RegExp(r'Z$'), ':00Z'),
          ) ??
          DateTime.tryParse('${s['from']}');
      final intensity = s['intensity'] as Map?;
      final grams = intensity?['forecast'];
      if (from == null || grams is! num) continue;
      slots.add(
        CarbonSlot(
          from.toLocal(),
          grams.round(),
          '${intensity?['index'] ?? ''}',
        ),
      );
    }
    return CarbonForecast(region: '${data['shortname'] ?? ''}', slots: slots);
  }
}

/// "CO1" from "CO1 1ZY", "ME16" from "me168ab" — the part the forecast
/// service is keyed by. Null for anything that is not a UK postcode.
String? outwardCode(String postcode) {
  final p = postcode.toUpperCase().replaceAll(RegExp(r'\s+'), '');
  final m = RegExp(r'^([A-Z]{1,2}\d[A-Z\d]?)(\d[A-Z]{2})?$').firstMatch(p);
  return m?[1];
}

/// The grid's carbon intensity for a region, from National Grid ESO's
/// Carbon Intensity service — free, no key, forecast two days ahead.
class CarbonService extends ChangeNotifier {
  CarbonService(this._config);

  final ConfigService _config;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  static const refreshEvery = Duration(minutes: 30);

  final Map<String, CarbonForecast> _forecasts = {};
  final Map<String, DateTime> _fetched = {};
  final Set<String> _busy = {};
  final Map<String, String> _errors = {};

  /// The postcode to use when a widget does not give one: the weather's
  /// location, if that is a postcode.
  String? get defaultOutcode => outwardCode(_config.config.weather.location);

  CarbonForecast? forecast(String outcode) => _forecasts[outcode];

  /// Holds [f] for [outcode] as if just fetched — for tests.
  @visibleForTesting
  void debugSet(String outcode, CarbonForecast f) {
    _forecasts[outcode] = f;
    _fetched[outcode] = DateTime.now();
    notifyListeners();
  }
  String? error(String outcode) => _errors[outcode];

  /// Fetches for [outcode] if there is nothing recent. Cheap to call often.
  Future<void> ensure(String outcode) async {
    final last = _fetched[outcode];
    if (_busy.contains(outcode) ||
        (last != null && DateTime.now().difference(last) < refreshEvery)) {
      return;
    }
    _busy.add(outcode);
    try {
      final from = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final stamp = '${from.toIso8601String().substring(0, 16)}Z';
      final r = await _dio.get(
        'https://api.carbonintensity.org.uk/regional/intensity/$stamp/fw48h/postcode/$outcode',
      );
      _forecasts[outcode] = CarbonForecast.fromApi(
        (r.data as Map).cast<String, dynamic>(),
      );
      _errors.remove(outcode);
      _fetched[outcode] = DateTime.now();
    } catch (e) {
      _errors[outcode] = 'Could not reach the grid forecast';
      // Try again in a few minutes rather than waiting the full half hour.
      _fetched[outcode] = DateTime.now().subtract(
        refreshEvery - const Duration(minutes: 3),
      );
      debugPrint('Carbon: $e');
    } finally {
      _busy.remove(outcode);
      notifyListeners();
    }
  }
}

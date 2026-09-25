import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'config_service.dart';
import 'retry_schedule.dart';

/// How much of something there is, in the words a forecast would use.
enum Level { none, low, moderate, high, veryHigh }

extension LevelWords on Level {
  String get word => switch (this) {
    Level.none => 'None',
    Level.low => 'Low',
    Level.moderate => 'Moderate',
    Level.high => 'High',
    Level.veryHigh => 'Very high',
  };

  /// Filled segments on a four-segment meter.
  int get bars => index;
}

/// Pollen of one family, in grains per cubic metre.
@immutable
class PollenReading {
  const PollenReading(this.name, this.grains, this.thresholds);

  final String name;
  final double? grains;

  /// Where low stops and moderate, high and very high begin. Differs by
  /// family: a count that is high for weeds is low for grass.
  final (double, double, double) thresholds;

  Level get level {
    final g = grains;
    if (g == null || g < 1) return Level.none;
    final (moderate, high, veryHigh) = thresholds;
    if (g >= veryHigh) return Level.veryHigh;
    if (g >= high) return Level.high;
    if (g >= moderate) return Level.moderate;
    return Level.low;
  }
}

@immutable
class AirQuality {
  const AirQuality({
    required this.aqi,
    required this.uv,
    required this.pollen,
    required this.fetched,
  });

  /// The European Air Quality Index: 0–20 good up to 100+ extremely poor.
  final int? aqi;
  final double? uv;
  final List<PollenReading> pollen;
  final DateTime fetched;

  String get aqiWord {
    final a = aqi;
    if (a == null) return 'No reading';
    if (a <= 20) return 'Good';
    if (a <= 40) return 'Fair';
    if (a <= 60) return 'Moderate';
    if (a <= 80) return 'Poor';
    if (a <= 100) return 'Very poor';
    return 'Extremely poor';
  }

  /// 0 good to 3 bad, for colouring.
  int get aqiSeverity {
    final a = aqi ?? 0;
    if (a <= 20) return 0;
    if (a <= 40) return 1;
    if (a <= 80) return 2;
    return 3;
  }

  String get uvWord {
    final u = uv;
    if (u == null) return '';
    if (u < 3) return 'low';
    if (u < 6) return 'moderate';
    if (u < 8) return 'high';
    if (u < 11) return 'very high';
    return 'extreme';
  }

  /// Built from Open-Meteo's `current` block.
  ///
  /// Pollen is grouped the way hay-fever forecasts group it — grass, trees,
  /// weeds — rather than the six species the model gives, and each group
  /// takes its worst species. Grass uses the Met Office's bands (30, 50 and
  /// 150 grains); trees and weeds use rough equivalents, since the forecasts
  /// that publish bands for them do not agree with each other.
  static AirQuality fromOpenMeteo(Map<String, dynamic> json, DateTime now) {
    final c = (json['current'] as Map?)?.cast<String, dynamic>() ?? const {};
    double? n(String k) => (c[k] as num?)?.toDouble();
    double? worst(List<String> keys) {
      final v = [for (final k in keys) ?n(k)];
      return v.isEmpty ? null : v.reduce((a, b) => a > b ? a : b);
    }

    return AirQuality(
      aqi: n('european_aqi')?.round(),
      uv: n('uv_index'),
      pollen: [
        PollenReading('Grass', n('grass_pollen'), (30, 50, 150)),
        PollenReading(
          'Trees',
          worst(['alder_pollen', 'birch_pollen', 'olive_pollen']),
          (40, 80, 200),
        ),
        PollenReading('Weeds', worst(['mugwort_pollen', 'ragweed_pollen']), (
          10,
          30,
          100,
        )),
      ],
      fetched: now,
    );
  }
}

/// Air quality, pollen and UV from Open-Meteo, for the weather's location.
///
/// The same provider the weather comes from, so no key, and the place is
/// the one already set in Settings → Weather. Created when a widget first
/// asks for it; refreshes every half hour after that.
class AirQualityService extends ChangeNotifier {
  AirQualityService(this._config) {
    _schedule(Duration.zero);
  }

  /// Holding [reading] and never fetching — for tests and previews.
  @visibleForTesting
  AirQualityService.withReading(this._config, AirQuality reading)
      : _current = reading;

  final ConfigService _config;
  final RetrySchedule _retry = RetrySchedule(
    settled: const Duration(minutes: 30),
  );
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  AirQuality? _current;
  AirQuality? get current => _current;
  String? _error;
  String? get error => _error;
  Timer? _timer;
  bool _disposed = false;

  void _schedule(Duration after) {
    _timer?.cancel();
    _timer = Timer(after, () async {
      await refresh();
      if (!_disposed) _schedule(_retry.next(hasContent: _current != null));
    });
  }

  Future<void> refresh() async {
    final w = _config.config.weather;
    // The weather service resolves the place; until it has, there is nowhere
    // to ask about. The retry schedule comes back shortly.
    if (w.latitude == null || w.longitude == null) {
      _error = 'Waiting for the weather location';
      if (!_disposed) notifyListeners();
      return;
    }
    try {
      final r = await _dio.get(
        'https://air-quality-api.open-meteo.com/v1/air-quality',
        queryParameters: {
          'latitude': w.latitude,
          'longitude': w.longitude,
          'current':
              'european_aqi,uv_index,alder_pollen,birch_pollen,'
              'grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen',
          'timezone': 'auto',
        },
      );
      _current = AirQuality.fromOpenMeteo(
        (r.data as Map).cast<String, dynamic>(),
        DateTime.now(),
      );
      _error = null;
    } catch (e) {
      _error = 'Could not reach the air-quality forecast';
      debugPrint('AirQuality: $e');
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

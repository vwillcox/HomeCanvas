import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'config_service.dart';

/// A quarter of an hour of rain forecast.
@immutable
class RainSlot {
  const RainSlot(this.from, this.mm, this.chance);

  final DateTime from;

  /// Millimetres expected in this quarter hour.
  final double mm;

  /// Percent chance of any, where the model gives one.
  final int? chance;

  /// Millimetres an hour at this rate — how forecasters grade rain.
  double get rate => mm * 4;

  bool get wet => mm >= 0.05;
}

/// "Light", "moderate", "heavy" for a rate in millimetres an hour, on the
/// Met Office's scale.
String rainWord(double mmPerHour) {
  if (mmPerHour < 0.5) return 'drizzle';
  if (mmPerHour < 2.5) return 'light';
  if (mmPerHour < 7.6) return 'moderate';
  return 'heavy';
}

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// What the next couple of hours hold, as one sentence and a few words:
/// "Rain from 14:20" / "light"; "Raining now" / "stops about 15:10";
/// "Dry for the next 2 hours".
({String headline, String detail, bool wet}) rainSummary(
  List<RainSlot> slots,
  DateTime now,
) {
  final ahead = slots
      .where((s) => s.from.add(const Duration(minutes: 15)).isAfter(now))
      .toList();
  if (ahead.isEmpty) return (headline: 'No forecast', detail: '', wet: false);
  final hours = ahead.length / 4;
  final span = hours == hours.roundToDouble()
      ? '${hours.round()} hour${hours == 1 ? '' : 's'}'
      : '${(hours * 60).round()} minutes';
  final peak = ahead.map((s) => s.rate).reduce((a, b) => a > b ? a : b);

  if (ahead.first.wet) {
    final stop = ahead.indexWhere((s) => !s.wet);
    return (
      headline: 'Raining now',
      detail: stop < 0
          ? '${rainWord(peak)} · for the next $span'
          : '${rainWord(peak)} · stops about ${_hm(ahead[stop].from)}',
      wet: true,
    );
  }
  final start = ahead.indexWhere((s) => s.wet);
  if (start < 0) {
    return (headline: 'Dry for the next $span', detail: '', wet: false);
  }
  final rest = ahead.sublist(start);
  final end = rest.indexWhere((s) => !s.wet);
  final shower = end < 0 ? rest : rest.sublist(0, end);
  final showerPeak = shower.map((s) => s.rate).reduce((a, b) => a > b ? a : b);
  return (
    headline: 'Rain from ${_hm(ahead[start].from)}',
    detail: end < 0
        ? rainWord(showerPeak)
        : '${rainWord(showerPeak)} · until about ${_hm(rest[end].from)}',
    wet: true,
  );
}

/// The next two hours of rain, fifteen minutes at a time, from Open-Meteo —
/// the weather's own provider, for the weather's own place.
class RainService extends ChangeNotifier {
  RainService(this._config) {
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => refresh());
    unawaited(refresh());
  }

  /// Holding [slots] and never fetching — for tests.
  @visibleForTesting
  RainService.withSlots(this._config, List<RainSlot> slots) : _slots = slots;

  final ConfigService _config;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
  Timer? _timer;
  List<RainSlot>? _slots;
  String? _error;

  List<RainSlot>? get slots => _slots;
  String? get error => _error;

  Future<void> refresh() async {
    final w = _config.config.weather;
    if (w.latitude == null || w.longitude == null) {
      _error = 'Waiting for the weather location';
      notifyListeners();
      return;
    }
    try {
      final r = await _dio.get(
        'https://api.open-meteo.com/v1/forecast',
        queryParameters: {
          'latitude': w.latitude,
          'longitude': w.longitude,
          'minutely_15': 'precipitation,precipitation_probability',
          'forecast_minutely_15': 8,
          'timezone': 'auto',
        },
      );
      _slots = parse((r.data as Map).cast<String, dynamic>());
      _error = null;
    } catch (e) {
      _error = 'Could not reach the rain forecast';
      debugPrint('Rain: $e');
    }
    notifyListeners();
  }

  /// Open-Meteo's `minutely_15` block. Times arrive in the place's own time
  /// without a zone, which on the panel is local time.
  static List<RainSlot> parse(Map<String, dynamic> json) {
    final m =
        (json['minutely_15'] as Map?)?.cast<String, dynamic>() ?? const {};
    final times = (m['time'] as List? ?? const []);
    final mm = (m['precipitation'] as List? ?? const []);
    final chance = (m['precipitation_probability'] as List? ?? const []);
    return [
      for (var i = 0; i < times.length; i++)
        if (DateTime.tryParse('${times[i]}') != null)
          RainSlot(
            DateTime.parse('${times[i]}'),
            i < mm.length && mm[i] is num ? (mm[i] as num).toDouble() : 0,
            i < chance.length && chance[i] is num
                ? (chance[i] as num).round()
                : null,
          ),
    ];
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';

/// A high or low tide.
@immutable
class Tide {
  const Tide({required this.at, required this.metres, required this.high});
  final DateTime at;

  /// Above or below mean sea level.
  final double metres;
  final bool high;
}

/// The sea's height through a few days at one place, and its tides.
@immutable
class TideTable {
  const TideTable({required this.points, required this.tides, this.place = ''});

  /// Every quarter of an hour.
  final List<(DateTime, double)> points;
  final List<Tide> tides;

  /// Where it is for, when looked up by name.
  final String place;

  /// The height at [t], between the quarter hours; null outside the table.
  double? heightAt(DateTime t) {
    for (var i = 1; i < points.length; i++) {
      final (a, ha) = points[i - 1];
      final (b, hb) = points[i];
      if (!t.isBefore(a) && !t.isAfter(b)) {
        final span = b.difference(a).inSeconds;
        if (span <= 0) return ha;
        return ha + (hb - ha) * t.difference(a).inSeconds / span;
      }
    }
    return null;
  }

  /// The tides still to come after [t].
  List<Tide> after(DateTime t) => [
    for (final x in tides)
      if (x.at.isAfter(t)) x,
  ];

  /// The next tide is a high one: the water is coming in.
  bool rising(DateTime t) => after(t).firstOrNull?.high ?? false;
}

/// Tides anywhere on the coast, worked out from Open-Meteo's modelled sea
/// level — free, no key. Modelled, not measured: good for a walk on the
/// beach, not for navigation.
class TidesService extends ChangeNotifier {
  TidesService({required this.home, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );

  final Dio _dio;

  /// The home location from Settings → Weather, if it has been found.
  final ({double lat, double lon})? Function() home;

  /// Places typed into a tile, looked up once: null when there's no such.
  final Map<String, ({double lat, double lon, String name})?> _places = {};
  final Map<String, TideTable?> _tables = {};
  final Map<String, DateTime> _fetched = {};
  final Map<String, String> _errors = {};
  final Set<String> _busy = {};
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  static String _placeKey(String typed) => typed.trim().toLowerCase();

  ({double lat, double lon})? _where(String typed) {
    if (typed.trim().isEmpty) return home();
    final p = _places[_placeKey(typed)];
    return p == null ? null : (lat: p.lat, lon: p.lon);
  }

  static String _tableKey(({double lat, double lon}) at) =>
      '${at.lat.toStringAsFixed(3)},${at.lon.toStringAsFixed(3)}';

  bool placeUnknown(String typed) =>
      _places.containsKey(_placeKey(typed)) &&
      _places[_placeKey(typed)] == null;

  /// The table for [typed] (empty for home). Null while it's being asked
  /// for, or when [noSea] says there's no sea there.
  TideTable? table(String typed) {
    final at = _where(typed);
    return at == null ? null : _tables[_tableKey(at)];
  }

  /// Open-Meteo has no sea at this place — inland.
  bool noSea(String typed) {
    final at = _where(typed);
    return at != null &&
        _tables.containsKey(_tableKey(at)) &&
        _tables[_tableKey(at)] == null;
  }

  String? error(String typed) {
    final placeError = _errors['place|${_placeKey(typed)}'];
    if (placeError != null) return placeError;
    final at = _where(typed);
    return at == null ? null : _errors[_tableKey(at)];
  }

  String? placeName(String typed) => _places[_placeKey(typed)]?.name;

  @visibleForTesting
  void debugSet(String typed, ({double lat, double lon}) at, TideTable? t) {
    if (typed.trim().isNotEmpty) {
      _places[_placeKey(typed)] = (lat: at.lat, lon: at.lon, name: typed);
    }
    _tables[_tableKey(at)] = t;
    _fetched[_tableKey(at)] = DateTime.now();
    _changed();
  }

  Future<void> ensure(String typed) async {
    final key = _placeKey(typed);
    if (key.isNotEmpty && !_places.containsKey(key)) {
      if (_busy.contains('place|$key')) return;
      final last = _fetched['place|$key'];
      if (last != null &&
          DateTime.now().difference(last) < const Duration(minutes: 5)) {
        return;
      }
      _busy.add('place|$key');
      try {
        final r = await _dio.get<Map<String, dynamic>>(
          'https://geocoding-api.open-meteo.com/v1/search',
          queryParameters: {'name': typed.trim(), 'count': 1},
        );
        final res = (r.data?['results'] as List?)?.whereType<Map>().firstOrNull;
        _places[key] = res == null
            ? null
            : (
                lat: (res['latitude'] as num).toDouble(),
                lon: (res['longitude'] as num).toDouble(),
                name: '${res['name'] ?? typed}',
              );
        _errors.remove('place|$key');
      } catch (e) {
        debugPrint('Tides: finding $typed: $e');
        _errors['place|$key'] = tr(
          'widget.tides.unreachable',
          'Could not reach Open-Meteo',
        );
      } finally {
        _fetched['place|$key'] = DateTime.now();
        _busy.remove('place|$key');
        _changed();
      }
    }
    final at = _where(typed);
    if (at == null) return;
    final tk = _tableKey(at);
    final last = _fetched[tk];
    // The model runs a few times a day; a table lasts three days.
    if (_busy.contains(tk) ||
        (last != null &&
            DateTime.now().difference(last) <
                (_errors.containsKey(tk)
                    ? const Duration(minutes: 5)
                    : const Duration(hours: 6)))) {
      return;
    }
    _busy.add(tk);
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        'https://marine-api.open-meteo.com/v1/marine',
        queryParameters: {
          'latitude': at.lat.toStringAsFixed(4),
          'longitude': at.lon.toStringAsFixed(4),
          'minutely_15': 'sea_level_height_msl',
          'past_days': 1,
          'forecast_days': 3,
          'timeformat': 'unixtime',
          'cell_selection': 'sea',
        },
      );
      _tables[tk] = parse(r.data ?? const {});
      _errors.remove(tk);
    } catch (e) {
      debugPrint('Tides: $e');
      _errors[tk] = tr(
        'widget.tides.unreachable',
        'Could not reach Open-Meteo',
      );
    } finally {
      _fetched[tk] = DateTime.now();
      _busy.remove(tk);
      _changed();
    }
  }

  /// The table from Open-Meteo's answer, or null when it has no sea level
  /// there.
  @visibleForTesting
  static TideTable? parse(Map<String, dynamic> json) {
    final m = json['minutely_15'] as Map? ?? const {};
    final times = m['time'] as List? ?? const [];
    final heights = m['sea_level_height_msl'] as List? ?? const [];
    final points = <(DateTime, double)>[
      for (var i = 0; i < times.length && i < heights.length; i++)
        if (times[i] is num && heights[i] is num)
          (
            DateTime.fromMillisecondsSinceEpoch(
              (times[i] as num).toInt() * 1000,
            ),
            (heights[i] as num).toDouble(),
          ),
    ];
    if (points.length < 8) return null;
    return TideTable(points: points, tides: findTides(points));
  }

  /// The turning points of the sea's height: each high and low, placed
  /// between the quarter hours by fitting a curve through the three
  /// readings around it.
  @visibleForTesting
  static List<Tide> findTides(List<(DateTime, double)> points) {
    final out = <Tide>[];
    for (var i = 1; i < points.length - 1; i++) {
      final a = points[i - 1].$2, b = points[i].$2, c = points[i + 1].$2;
      final high = b >= a && b > c;
      final low = b <= a && b < c;
      if (!high && !low) continue;
      final bend = a - 2 * b + c;
      final offset = bend == 0 ? 0.0 : (0.5 * (a - c) / bend).clamp(-1.0, 1.0);
      final step = points[i + 1].$1.difference(points[i].$1);
      final at = points[i].$1.add(step * offset);
      final metres = b - 0.25 * (a - c) * offset;
      final tide = Tide(at: at, metres: metres, high: high);
      // A wobble on the slack water isn't a tide of its own: the same kind
      // within a couple of hours keeps the more extreme one, and a turn
      // back within one is dropped with its partner.
      final prev = out.lastOrNull;
      if (prev != null && at.difference(prev.at) < const Duration(hours: 2)) {
        if (prev.high == high) {
          if (high ? metres > prev.metres : metres < prev.metres) {
            out[out.length - 1] = tide;
          }
        } else if (at.difference(prev.at) < const Duration(hours: 1)) {
          out.removeLast();
        } else {
          out.add(tide);
        }
        continue;
      }
      out.add(tide);
    }
    return out;
  }
}

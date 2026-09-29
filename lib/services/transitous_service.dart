import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';

/// One departure from a stop.
@immutable
class TransitDeparture {
  const TransitDeparture({
    required this.line,
    required this.mode,
    required this.headsign,
    required this.scheduled,
    required this.expected,
    this.track = '',
    this.cancelled = false,
    this.realTime = false,
    this.colour,
    this.textColour,
    this.operator = '',
  });

  /// "Intercity", "ICE 578", "S3", "17".
  final String line;

  /// Transitous's: HIGHSPEED_RAIL, REGIONAL_RAIL, SUBWAY, TRAM, BUS…
  final String mode;
  final String headsign;
  final DateTime scheduled;
  final DateTime expected;
  final String track;
  final bool cancelled;

  /// Times from the operator's live feed rather than the timetable.
  final bool realTime;

  /// The line's own colours, where the timetable gives them: "E32017".
  final String? colour;
  final String? textColour;
  final String operator;

  int get lateMinutes => expected.difference(scheduled).inMinutes;

  bool get rail => const {
    'HIGHSPEED_RAIL',
    'LONG_DISTANCE',
    'REGIONAL_RAIL',
    'REGIONAL_FAST_RAIL',
    'NIGHT_RAIL',
    'SUBURBAN',
    'RAIL',
  }.contains(mode);
}

/// Which kinds of transport a tile asks for.
const kTransitModes = {
  'trains':
      'HIGHSPEED_RAIL,LONG_DISTANCE,REGIONAL_FAST_RAIL,REGIONAL_RAIL,NIGHT_RAIL,SUBURBAN',
  'local': 'SUBWAY,TRAM,BUS,FERRY,SUBURBAN',
  'all': '',
};

/// Departures across Europe and beyond from Transitous, the community-run
/// open journey planner built on public timetables and live feeds — no
/// key, asked kindly: once a minute a stop at most, stops looked up once.
class TransitousService extends ChangeNotifier {
  TransitousService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              // Transitous asks its users to say who they are.
              headers: const {
                'User-Agent': 'HomeCanvas/1.0 (home dashboard panel)',
              },
            ),
          );

  final Dio _dio;
  static const _base = 'https://api.transitous.org/api/v1';

  final Map<String, ({String id, String name})?> _stops = {};
  final Map<String, List<TransitDeparture>> _departures = {};
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

  static String _stopKey(String typed) => typed.trim().toLowerCase();
  static String _depKey(String id, String modes) => '$id|$modes';

  ({String id, String name})? stop(String typed) => _stops[_stopKey(typed)];
  bool stopUnknown(String typed) =>
      _stops.containsKey(_stopKey(typed)) && _stops[_stopKey(typed)] == null;
  String? stopError(String typed) => _errors['stop|${_stopKey(typed)}'];

  List<TransitDeparture>? departures(String id, String modes) =>
      _departures[_depKey(id, modes)];
  String? departuresError(String id, String modes) =>
      _errors[_depKey(id, modes)];

  @visibleForTesting
  void debugSet(
    String typed,
    ({String id, String name}) stop,
    String modes,
    List<TransitDeparture> list,
  ) {
    _stops[_stopKey(typed)] = stop;
    _departures[_depKey(stop.id, modes)] = list;
    _fetched[_depKey(stop.id, modes)] = DateTime.now();
    _changed();
  }

  /// Finds [typed] — a stop's name, or a Transitous stop id — then fetches
  /// its departures of [modes] if more than a minute old.
  Future<void> ensure(String typed, String modes) async {
    final key = _stopKey(typed);
    if (key.isEmpty) return;
    var found = _stops[key];
    if (found == null) {
      if (_stops.containsKey(key) || _busy.contains('stop|$key')) return;
      final lastTry = _fetched['stop|$key'];
      if (lastTry != null &&
          DateTime.now().difference(lastTry) < const Duration(minutes: 5)) {
        return;
      }
      _busy.add('stop|$key');
      try {
        found = await _find(typed.trim());
        _stops[key] = found;
        _errors.remove('stop|$key');
      } catch (e) {
        debugPrint('Transitous stop $typed: $e');
        _errors['stop|$key'] = tr(
          'widget.transit.unreachable',
          'Could not reach Transitous',
        );
        _fetched['stop|$key'] = DateTime.now();
      } finally {
        _busy.remove('stop|$key');
        _changed();
      }
      if (found == null) return;
    }
    final dk = _depKey(found.id, modes);
    final last = _fetched[dk];
    if (_busy.contains(dk) ||
        (last != null &&
            DateTime.now().difference(last) < const Duration(minutes: 1))) {
      return;
    }
    _busy.add(dk);
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '$_base/stoptimes',
        queryParameters: {
          'stopId': found.id,
          'n': 30,
          if (modes.isNotEmpty) 'mode': modes,
        },
      );
      _departures[dk] = parseStopTimes(r.data ?? const {});
      _errors.remove(dk);
      _fetched[dk] = DateTime.now();
    } catch (e) {
      debugPrint('Transitous ${found.id}: $e');
      _errors[dk] = tr('widget.transit.unreachable', 'Could not reach Transitous');
      // Tried again in a minute, like a success.
      _fetched[dk] = DateTime.now();
    } finally {
      _busy.remove(dk);
      _changed();
    }
  }

  Future<({String id, String name})?> _find(String typed) async {
    // An id as copied from Transitous: a feed prefix, an underscore, no spaces.
    if (RegExp(r'^[a-z]{2}-[\w.-]+_\S+$').hasMatch(typed)) {
      return (id: typed, name: typed);
    }
    final r = await _dio.get<List<dynamic>>(
      '$_base/geocode',
      queryParameters: {'text': typed, 'type': 'STOP'},
    );
    return pickStop(r.data ?? const []);
  }

  @visibleForTesting
  static ({String id, String name})? pickStop(List<dynamic> json) {
    for (final m in json.whereType<Map>()) {
      final id = '${m['id'] ?? ''}';
      if (id.isEmpty || (m['type'] != null && m['type'] != 'STOP')) continue;
      return (id: id, name: '${m['name'] ?? id}');
    }
    return null;
  }

  /// "ICE 578", "S3", "Red Line" — the first name the feed gives that is
  /// one; some write "?" for a line they don't name.
  static String _lineName(Map s) {
    for (final k in ['displayName', 'routeShortName', 'routeLongName']) {
      final v = '${s[k] ?? ''}'.trim();
      if (v.isNotEmpty && v != '?') return v;
    }
    return '';
  }

  @visibleForTesting
  static List<TransitDeparture> parseStopTimes(Map<String, dynamic> json) {
    final out = <TransitDeparture>[];
    for (final s in (json['stopTimes'] as List? ?? const []).whereType<Map>()) {
      final place = s['place'] as Map? ?? const {};
      final scheduled = DateTime.tryParse(
        '${place['scheduledDeparture'] ?? place['scheduledArrival'] ?? ''}',
      );
      if (scheduled == null) continue;
      final expected =
          DateTime.tryParse('${place['departure'] ?? place['arrival'] ?? ''}') ??
          scheduled;
      String? colour(Object? v) {
        final c = '${v ?? ''}'.replaceAll('#', '');
        return RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(c) ? c : null;
      }

      out.add(
        TransitDeparture(
          line: _lineName(s),
          mode: '${s['mode'] ?? ''}',
          headsign: '${s['headsign'] ?? (s['tripTo'] as Map?)?['name'] ?? ''}'
              .trim(),
          scheduled: scheduled.toLocal(),
          expected: expected.toLocal(),
          track: '${place['track'] ?? place['scheduledTrack'] ?? ''}'.trim(),
          cancelled: s['cancelled'] == true || s['tripCancelled'] == true,
          realTime: s['realTime'] == true,
          colour: colour(s['routeColor']),
          textColour: colour(s['routeTextColor']),
          operator: '${s['agencyName'] ?? ''}'.trim(),
        ),
      );
    }
    out.sort((a, b) => a.expected.compareTo(b.expected));
    return out;
  }
}

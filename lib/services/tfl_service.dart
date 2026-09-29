import 'dart:async';
import 'dart:ui' show Color;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';

/// One line's state, as TfL reports it.
@immutable
class TflLine {
  const TflLine({
    required this.id,
    required this.name,
    required this.mode,
    required this.severity,
    required this.status,
    this.reason = '',
  });

  /// "central", "elizabeth", "weaver".
  final String id;
  final String name;

  /// "tube", "elizabeth-line", "overground", "dlr", "tram".
  final String mode;

  /// TfL's scale: 10 is good service, lower is worse; 18 and 19 are notes
  /// (step-free access, information) rather than trouble.
  final int severity;

  /// "Good Service", "Severe Delays"…
  final String status;

  /// Why, in TfL's words; empty when all is well.
  final String reason;

  bool get good => severity == 10 || severity == 18 || severity == 19;

  /// Worse than minor: severe delays, closures, suspensions.
  bool get serious => !good && severity != 9;

  /// TfL's own colour for the line, for the stripe beside it.
  Color get colour => tflColour(id, mode);
}

/// A train or bus on its way to a stop.
@immutable
class TflArrival {
  const TflArrival({
    required this.line,
    required this.lineId,
    required this.mode,
    required this.destination,
    required this.platform,
    required this.seconds,
  });

  final String line;
  final String lineId;
  final String mode;

  /// Where it is going, without TfL's "Underground Station" on the end.
  final String destination;

  /// "Northbound - Platform 6"; for a bus, its stop letter.
  final String platform;

  /// How long until it arrives.
  final int seconds;
}

/// TfL's colours for its lines, and for the modes a line of which has none
/// of its own.
Color tflColour(String id, String mode) {
  const lines = {
    'bakerloo': 0xFFB36305,
    'central': 0xFFE32017,
    'circle': 0xFFFFD300,
    'district': 0xFF00782A,
    'hammersmith-city': 0xFFF3A9BB,
    'jubilee': 0xFFA0A5A9,
    'metropolitan': 0xFF9B0056,
    'northern': 0xFF1C1C1C,
    'piccadilly': 0xFF003688,
    'victoria': 0xFF0098D4,
    'waterloo-city': 0xFF95CDBA,
    'elizabeth': 0xFF6950A1,
    'liberty': 0xFF5D6061,
    'lioness': 0xFFFAA61A,
    'mildmay': 0xFF0077AD,
    'suffragette': 0xFF5BBD72,
    'weaver': 0xFF823A62,
    'windrush': 0xFFED1B00,
    'dlr': 0xFF00A4A7,
    'tram': 0xFF84B817,
  };
  const modes = {
    'bus': 0xFFDC241F,
    'overground': 0xFFEE7C0E,
    'dlr': 0xFF00A4A7,
    'tram': 0xFF84B817,
    'elizabeth-line': 0xFF6950A1,
    'river-bus': 0xFF0099CC,
  };
  return Color(lines[id] ?? modes[mode] ?? 0xFF808080);
}

/// Whether [text] is already a TfL stop id — 940GZZLUOXC for a station,
/// 490000173RC for a bus stop — rather than something to search for.
bool looksLikeStopId(String text) =>
    RegExp(r'^(940G|910G|490|HUB|9400ZZ)[A-Z0-9]+$').hasMatch(text.trim());

/// Line status and arrivals from TfL's open API — no key needed at the
/// rate a few tiles ask. Everything is cached and shared between tiles.
class TflService extends ChangeNotifier {
  TflService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );

  final Dio _dio;
  static const _base = 'https://api.tfl.gov.uk';

  final Map<String, List<TflLine>> _status = {};
  final Map<String, List<TflArrival>> _arrivals = {};
  final Map<String, ({String id, String name})?> _stops = {};
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

  static String _modesKey(List<String> modes) =>
      'status|${(modes.toList()..sort()).join(',')}';

  List<TflLine>? status(List<String> modes) => _status[_modesKey(modes)];
  String? statusError(List<String> modes) => _errors[_modesKey(modes)];

  List<TflArrival>? arrivals(String stopId) => _arrivals['arr|$stopId'];
  String? arrivalsError(String stopId) => _errors['arr|$stopId'];

  /// The stop [typed] was taken to mean, once looked up.
  ({String id, String name})? stop(String typed, String mode) =>
      _stops['$mode|${typed.trim().toLowerCase()}'];
  String? stopError(String typed, String mode) =>
      _errors['stop|$mode|${typed.trim().toLowerCase()}'];

  /// Holds [lines] as if just fetched — for tests.
  @visibleForTesting
  void debugSetStatus(List<String> modes, List<TflLine> lines) {
    _status[_modesKey(modes)] = lines;
    _fetched[_modesKey(modes)] = DateTime.now();
    _changed();
  }

  @visibleForTesting
  void debugSetArrivals(
    String typed,
    String mode,
    ({String id, String name}) stop,
    List<TflArrival> list,
  ) {
    _stops['$mode|${typed.trim().toLowerCase()}'] = stop;
    _arrivals['arr|${stop.id}'] = list;
    _fetched['arr|${stop.id}'] = DateTime.now();
    _changed();
  }

  bool _due(String key, Duration maxAge) {
    if (_busy.contains(key)) return false;
    final last = _fetched[key];
    return last == null || DateTime.now().difference(last) > maxAge;
  }

  /// A failure is tried again in a minute rather than a whole [maxAge].
  void _failed(String key, String message, Duration maxAge) {
    _errors[key] = message;
    const retry = Duration(minutes: 1);
    _fetched[key] = maxAge <= retry
        ? DateTime.now()
        : DateTime.now().subtract(maxAge - retry);
  }

  String _why(Object e) {
    if (e is DioException && e.response?.statusCode == 429) {
      return tr('widget.tfl.busy', 'TfL is busy — trying again shortly');
    }
    return tr('widget.tfl.unreachable', 'Could not reach TfL');
  }

  /// Fetches the status of every line of [modes] if older than [maxAge].
  Future<void> ensureStatus(
    List<String> modes, {
    Duration maxAge = const Duration(minutes: 2),
  }) async {
    final key = _modesKey(modes);
    if (modes.isEmpty || !_due(key, maxAge)) return;
    _busy.add(key);
    try {
      final r = await _dio.get<List<dynamic>>(
        '$_base/Line/Mode/${modes.join(',')}/Status',
      );
      _status[key] = parseStatus(r.data ?? const []);
      _errors.remove(key);
      _fetched[key] = DateTime.now();
    } catch (e) {
      debugPrint('TfL status: $e');
      _failed(key, _why(e), maxAge);
    } finally {
      _busy.remove(key);
      _changed();
    }
  }

  /// Finds the stop [typed] means — a TfL stop id as it is, a name or a
  /// bus stop's five-digit code by searching — then fetches what is on its
  /// way there if older than [maxAge].
  Future<void> ensureArrivals(
    String typed,
    String mode, {
    Duration maxAge = const Duration(seconds: 30),
  }) async {
    final text = typed.trim();
    if (text.isEmpty) return;
    final stopKey = '$mode|${text.toLowerCase()}';
    var found = _stops[stopKey];
    if (found == null) {
      if (_busy.contains('stop|$stopKey') ||
          (_errors.containsKey('stop|$stopKey') &&
              !_due('stop|$stopKey', const Duration(minutes: 10)))) {
        return;
      }
      _busy.add('stop|$stopKey');
      try {
        found = await _findStop(text, mode);
        if (found == null) {
          _failed(
            'stop|$stopKey',
            tr('widget.tfl.noSuchStop', 'TfL has no stop called “{stop}”', {
              'stop': text,
            }),
            const Duration(minutes: 10),
          );
          _changed();
          return;
        }
        _stops[stopKey] = found;
        _errors.remove('stop|$stopKey');
      } catch (e) {
        debugPrint('TfL stop $text: $e');
        _failed('stop|$stopKey', _why(e), const Duration(minutes: 10));
        _changed();
        return;
      } finally {
        _busy.remove('stop|$stopKey');
      }
    }
    final key = 'arr|${found.id}';
    if (!_due(key, maxAge)) return;
    _busy.add(key);
    try {
      final r = await _dio.get<List<dynamic>>(
        '$_base/StopPoint/${Uri.encodeComponent(found.id)}/Arrivals',
      );
      _arrivals[key] = parseArrivals(r.data ?? const []);
      _errors.remove(key);
      _fetched[key] = DateTime.now();
    } catch (e) {
      debugPrint('TfL arrivals ${found.id}: $e');
      _failed(key, _why(e), maxAge);
    } finally {
      _busy.remove(key);
      _changed();
    }
  }

  Future<({String id, String name})?> _findStop(String text, String mode) async {
    if (looksLikeStopId(text)) return (id: text.toUpperCase(), name: text);
    final modes = switch (mode) {
      'bus' => 'bus',
      'rail' => 'tube,elizabeth-line,overground,dlr,tram,national-rail',
      _ => 'tube,elizabeth-line,overground,dlr,tram,bus',
    };
    final r = await _dio.get<Map<String, dynamic>>(
      '$_base/StopPoint/Search/${Uri.encodeComponent(text)}',
      queryParameters: {'modes': modes, 'maxResults': 5},
    );
    return pickStop(r.data ?? const {});
  }

  /// The first match of a stop search, by id and a short name.
  @visibleForTesting
  static ({String id, String name})? pickStop(Map<String, dynamic> json) {
    final matches = (json['matches'] as List? ?? const []).whereType<Map>();
    for (final m in matches) {
      final id = '${m['id'] ?? ''}';
      if (id.isEmpty) continue;
      return (id: id, name: shortStopName('${m['name'] ?? id}'));
    }
    return null;
  }

  @visibleForTesting
  static List<TflLine> parseStatus(List<dynamic> json) {
    final out = <TflLine>[];
    for (final l in json.whereType<Map>()) {
      final statuses = (l['lineStatuses'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      // The worst it reports; a line can have several at once — severe
      // delays one way, minor the other.
      statuses.sort((a, b) {
        int rank(Map s) {
          final v = (s['statusSeverity'] as num?)?.toInt() ?? 10;
          return v >= 18 ? 10 : v; // notes rank with good service
        }
        return rank(a).compareTo(rank(b));
      });
      final worst = statuses.isEmpty ? null : statuses.first;
      out.add(
        TflLine(
          id: '${l['id'] ?? ''}',
          name: '${l['name'] ?? l['id'] ?? ''}',
          mode: '${l['modeName'] ?? ''}',
          severity: (worst?['statusSeverity'] as num?)?.toInt() ?? 10,
          status: '${worst?['statusSeverityDescription'] ?? 'Good Service'}',
          reason: '${worst?['reason'] ?? ''}'.trim(),
        ),
      );
    }
    return out;
  }

  @visibleForTesting
  static List<TflArrival> parseArrivals(List<dynamic> json) {
    final out = [
      for (final a in json.whereType<Map>())
        TflArrival(
          line: '${a['lineName'] ?? ''}',
          lineId: '${a['lineId'] ?? ''}',
          mode: '${a['modeName'] ?? ''}',
          destination: shortStopName(
            '${a['destinationName'] ?? a['towards'] ?? ''}',
          ),
          platform: '${a['platformName'] ?? ''}',
          seconds: (a['timeToStation'] as num?)?.toInt() ?? 0,
        ),
    ];
    out.sort((a, b) => a.seconds.compareTo(b.seconds));
    return out;
  }
}

/// "Brixton" from "Brixton Underground Station" — the kind of stop is
/// already clear from the line.
String shortStopName(String name) => name
    .replaceFirst(
      RegExp(
        r' (Underground|DLR|Rail|Tram|Overground|Elizabeth line) Station$| Station$| \(London\)$',
        caseSensitive: false,
      ),
      '',
    )
    .trim();

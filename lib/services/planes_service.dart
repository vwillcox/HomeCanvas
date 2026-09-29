import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';

/// One aircraft in the sky near home.
@immutable
class Plane {
  const Plane({
    required this.hex,
    required this.callsign,
    required this.miles,
    required this.bearing,
    this.registration = '',
    this.type = '',
    this.altitudeFt,
    this.knots,
    this.track,
    this.climbFpm,
    this.emergency = false,
  });

  /// The transponder's own id: "4ca7b5".
  final String hex;

  /// "BAW743"; empty when the plane isn't sending one.
  final String callsign;
  final String registration;

  /// Its ICAO type code: "A320", "B738".
  final String type;

  /// Null on the ground.
  final int? altitudeFt;
  final double? knots;

  /// Which way it's heading, degrees from north.
  final double? track;

  /// Feet a minute, up or down.
  final int? climbFpm;

  /// Distance from home, and which way to look (degrees from north).
  final double miles;
  final double bearing;

  /// Squawking 7500, 7600 or 7700.
  final bool emergency;

  bool get onGround => altitudeFt == null;
}

/// Where a flight is from and going to.
@immutable
class FlightRoute {
  const FlightRoute({
    required this.from,
    required this.to,
    this.fromCode = '',
    this.toCode = '',
    this.airline = '',
  });

  /// Towns: "Heraklion", "London".
  final String from;
  final String to;

  /// IATA codes: "HER", "LHR".
  final String fromCode;
  final String toCode;
  final String airline;
}

/// Aircraft overhead from adsb.lol, the community's open ADS-B network, and
/// where each is flying from adsbdb — both free, and neither needs a key.
///
/// The sky is asked for at most every 20 seconds, and a flight's route once
/// a day: routes don't change, and adsbdb is run by one person.
class PlanesService extends ChangeNotifier {
  PlanesService({required this.home, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: const {
                'User-Agent': 'HomeCanvas/1.0 (home dashboard panel)',
              },
            ),
          );

  final Dio _dio;

  /// The home location from Settings → Weather, if it has been found.
  final ({double lat, double lon})? Function() home;

  static const _sky = 'https://api.adsb.lol/v2/point';
  static const _routes = 'https://api.adsbdb.com/v0/callsign';

  final Map<int, List<Plane>> _planes = {};
  final Map<int, DateTime> _fetched = {};
  final Set<int> _busy = {};
  String? _error;

  /// Null for a flight known to have no route on file.
  final Map<String, FlightRoute?> _routeOf = {};
  final Map<String, DateTime> _routeAsked = {};
  final Set<String> _routeBusy = {};
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Every plane within [radiusMiles] of home, nearest first; null until
  /// the sky has been asked.
  List<Plane>? planes(int radiusMiles) => _planes[radiusMiles];
  String? get error => _error;

  /// The route [callsign] flies, once looked up.
  FlightRoute? route(String callsign) => _routeOf[callsign];

  @visibleForTesting
  void debugSet(
    int radiusMiles,
    List<Plane> list, [
    Map<String, FlightRoute> routes = const {},
  ]) {
    _planes[radiusMiles] = list;
    _fetched[radiusMiles] = DateTime.now();
    _routeOf.addAll(routes);
    for (final c in routes.keys) {
      _routeAsked[c] = DateTime.now();
    }
    _changed();
  }

  Future<void> ensure(int radiusMiles) async {
    final at = home();
    if (at == null) return;
    final last = _fetched[radiusMiles];
    if (_busy.contains(radiusMiles) ||
        (last != null &&
            DateTime.now().difference(last) < const Duration(seconds: 20))) {
      return;
    }
    _busy.add(radiusMiles);
    try {
      // adsb.lol takes the radius in nautical miles, up to 250.
      final nm = (radiusMiles / 1.15078).ceil().clamp(1, 250);
      final r = await _dio.get<Map<String, dynamic>>(
        '$_sky/${at.lat.toStringAsFixed(4)}/${at.lon.toStringAsFixed(4)}/$nm',
      );
      _planes[radiusMiles] = parse(r.data ?? const {}, radiusMiles);
      _error = null;
    } catch (e) {
      debugPrint('Planes: $e');
      _error = tr('widget.planes.unreachable', 'Could not reach adsb.lol');
    } finally {
      _fetched[radiusMiles] = DateTime.now();
      _busy.remove(radiusMiles);
      _changed();
    }
  }

  /// Looks up the routes of [callsigns] not already known — a few at a
  /// time, so a busy sky doesn't mean a burst of requests.
  Future<void> ensureRoutes(Iterable<String> callsigns) async {
    final now = DateTime.now();
    final wanted = [
      for (final c in callsigns)
        if (validCallsign(c) &&
            !_routeBusy.contains(c) &&
            (_routeAsked[c] == null ||
                now.difference(_routeAsked[c]!) > const Duration(hours: 24)))
          c,
    ].take(4);
    for (final c in wanted) {
      _routeBusy.add(c);
      try {
        final r = await _dio.get<Map<String, dynamic>>(
          '$_routes/$c',
          options: Options(validateStatus: (s) => s == 200 || s == 404),
        );
        _routeOf[c] = parseRoute(r.data ?? const {});
        _routeAsked[c] = DateTime.now();
      } catch (e) {
        debugPrint('Planes: route of $c: $e');
        // Tried again in an hour rather than the next refresh.
        _routeAsked[c] = DateTime.now().subtract(const Duration(hours: 23));
      } finally {
        _routeBusy.remove(c);
        _changed();
      }
    }
  }

  /// Letters and digits only, as a callsign is: nothing that could climb
  /// out of the URL's path.
  static bool validCallsign(String c) => RegExp(r'^[A-Z0-9]{3,8}$').hasMatch(c);

  @visibleForTesting
  static List<Plane> parse(Map<String, dynamic> json, int radiusMiles) {
    final out = <Plane>[];
    for (final a in (json['ac'] as List? ?? const []).whereType<Map>()) {
      final nm = (a['dst'] as num?)?.toDouble();
      final dir = (a['dir'] as num?)?.toDouble();
      if (nm == null || dir == null) continue;
      final miles = nm * 1.15078;
      if (miles > radiusMiles) continue;
      final alt = a['alt_baro'];
      final squawk = '${a['squawk'] ?? ''}';
      out.add(
        Plane(
          hex: '${a['hex'] ?? ''}',
          callsign: '${a['flight'] ?? ''}'.trim().toUpperCase(),
          registration: '${a['r'] ?? ''}'.trim(),
          type: '${a['t'] ?? ''}'.trim(),
          altitudeFt: alt is num ? alt.round() : null,
          knots: (a['gs'] as num?)?.toDouble(),
          track: (a['track'] as num? ?? a['true_heading'] as num?)?.toDouble(),
          climbFpm: (a['baro_rate'] as num? ?? a['geom_rate'] as num?)?.round(),
          miles: miles,
          bearing: dir,
          emergency:
              const {'7500', '7600', '7700'}.contains(squawk) ||
              (a['emergency'] != null && a['emergency'] != 'none'),
        ),
      );
    }
    out.sort((a, b) => a.miles.compareTo(b.miles));
    return out;
  }

  @visibleForTesting
  static FlightRoute? parseRoute(Map<String, dynamic> json) {
    final r = (json['response'] is Map
        ? json['response'] as Map
        : null)?['flightroute'];
    if (r is! Map) return null;
    final o = r['origin'] is Map ? r['origin'] as Map : const {};
    final d = r['destination'] is Map ? r['destination'] as Map : const {};
    String town(Map a) => '${a['municipality'] ?? a['name'] ?? ''}'.trim();
    if (town(o).isEmpty || town(d).isEmpty) return null;
    return FlightRoute(
      from: town(o),
      to: town(d),
      fromCode: '${o['iata_code'] ?? ''}',
      toCode: '${d['iata_code'] ?? ''}',
      airline: '${(r['airline'] is Map ? r['airline']['name'] : null) ?? ''}',
    );
  }
}

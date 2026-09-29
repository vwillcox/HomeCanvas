import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';
import 'config_service.dart';

/// The retailers' own price files, published under the UK's open fuel
/// price scheme — no key. Those that turn automated requests away (BP,
/// Tesco) or have stopped publishing aren't listed; a tile can add more.
const kFuelFeeds = [
  'https://storelocator.asda.com/fuel_prices_data.json',
  'https://applegreenstores.com/fuel-prices/data.json',
  'https://jetlocal.co.uk/fuel_prices_data.json',
  'https://fuel.motorfuelgroup.com/fuel_prices_data.json',
  'https://www.morrisons.com/fuel-prices/fuel.json',
  'https://moto-way.com/fuel-price/fuel_prices.json',
  'https://www.rontec-servicestations.co.uk/fuel-prices/data/fuel_prices_data.json',
  'https://www.sgnretail.uk/files/data/SGN_daily_fuel_prices.json',
  'https://www.shell.co.uk/fuel-prices-data.html',
];

/// One forecourt and what it charges, in pence a litre.
@immutable
class FuelStation {
  const FuelStation({
    required this.brand,
    required this.address,
    required this.postcode,
    required this.latitude,
    required this.longitude,
    required this.prices,
  });

  final String brand;
  final String address;
  final String postcode;
  final double latitude;
  final double longitude;

  /// By fuel: E10, E5, B7, SDV.
  final Map<String, double> prices;

  /// Miles from [lat], [lon], as the crow flies.
  double milesFrom(double lat, double lon) {
    const r = 3958.8;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(latitude - lat), dLon = rad(longitude - lon);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat)) * math.cos(rad(latitude)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.sqrt(a));
  }
}

/// Every station from every feed, refreshed hourly — the retailers update
/// once or a few times a day — and shared between tiles.
class FuelService extends ChangeNotifier {
  FuelService(this._config, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              headers: const {'User-Agent': 'Mozilla/5.0 HomeCanvas/1.0'},
            ),
          );

  final ConfigService _config;
  final Dio _dio;

  final Map<String, List<FuelStation>> _byFeed = {};
  final Map<String, DateTime> _fetched = {};
  final Set<String> _busy = {};
  final Map<String, ({double lat, double lon})?> _places = {};
  String? _error;
  bool _disposed = false;

  static const refreshEvery = Duration(hours: 1);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// The home location from Settings → Weather, if it has been found.
  ({double lat, double lon})? get home {
    final w = _config.config.weather;
    final lat = w.latitude, lon = w.longitude;
    return lat == null || lon == null ? null : (lat: lat, lon: lon);
  }

  /// Where [postcode] is, once looked up; null until then, or if it isn't
  /// one.
  ({double lat, double lon})? place(String postcode) =>
      _places[_postcodeKey(postcode)];
  bool placeUnknown(String postcode) =>
      _places.containsKey(_postcodeKey(postcode)) &&
      _places[_postcodeKey(postcode)] == null;

  static String _postcodeKey(String p) =>
      p.toUpperCase().replaceAll(RegExp(r'\s+'), '');

  /// Every station from [feeds] that has answered, or null while none has.
  List<FuelStation>? stations(List<String> feeds) {
    final got = [for (final f in feeds) ?_byFeed[f]];
    if (got.isEmpty) return null;
    return [for (final list in got) ...list];
  }

  /// Why nothing could be fetched, if nothing could.
  String? get error => _error;

  /// Holds [list] as feed [feed]'s, as if just fetched — for tests.
  @visibleForTesting
  void debugSet(String feed, List<FuelStation> list) {
    _byFeed[feed] = list;
    _fetched[feed] = DateTime.now();
    _changed();
  }

  @visibleForTesting
  void debugPlace(String postcode, ({double lat, double lon})? at) {
    _places[_postcodeKey(postcode)] = at;
    _changed();
  }

  /// Fetches whichever of [feeds] are older than an hour, and looks up
  /// [postcode] if one is given and not yet known.
  Future<void> ensure(List<String> feeds, {String postcode = ''}) async {
    final jobs = <Future<void>>[
      for (final f in feeds)
        if (!_busy.contains(f) &&
            (_fetched[f] == null ||
                DateTime.now().difference(_fetched[f]!) > refreshEvery))
          _fetch(f),
      if (postcode.trim().isNotEmpty &&
          !_places.containsKey(_postcodeKey(postcode)))
        _lookUp(postcode),
    ];
    if (jobs.isEmpty) return;
    await Future.wait(jobs);
    _error = feeds.any(_byFeed.containsKey)
        ? null
        : tr('widget.fuel.unreachable', 'Could not reach the fuel price feeds');
    _changed();
  }

  Future<void> _fetch(String feed) async {
    // Only ever a web address someone chose to fetch prices from.
    final uri = Uri.tryParse(feed);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      return;
    }
    _busy.add(feed);
    try {
      final r = await _dio.get<Object?>(
        feed,
        options: Options(responseType: ResponseType.plain),
      );
      final body = '${r.data ?? ''}';
      // A few megabytes of JSON between them: parsed away from the frames.
      _byFeed[feed] = await compute(parseFeed, body);
      _fetched[feed] = DateTime.now();
    } catch (e) {
      debugPrint('Fuel $feed: $e');
      // Tried again in ten minutes rather than an hour.
      _fetched[feed] = DateTime.now().subtract(
        refreshEvery - const Duration(minutes: 10),
      );
    } finally {
      _busy.remove(feed);
    }
  }

  Future<void> _lookUp(String postcode) async {
    final key = _postcodeKey(postcode);
    // A whole postcode, or just its first half (ME16).
    final full = RegExp(r'^[A-Z]{1,2}\d[A-Z\d]?\d[A-Z]{2}$').hasMatch(key);
    final out = RegExp(r'^[A-Z]{1,2}\d[A-Z\d]?$').hasMatch(key);
    if (!full && !out) {
      _places[key] = null;
      return;
    }
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        'https://api.postcodes.io/${full ? 'postcodes' : 'outcodes'}/$key',
      );
      final result = r.data?['result'] as Map?;
      final lat = result?['latitude'], lon = result?['longitude'];
      _places[key] = lat is num && lon is num
          ? (lat: lat.toDouble(), lon: lon.toDouble())
          : null;
    } on DioException catch (e) {
      // Not found is an answer; anything else is asked again next time.
      if (e.response?.statusCode == 404) _places[key] = null;
    } catch (_) {}
  }

  /// A retailer's price file. They share a shape — {stations: [{brand,
  /// address, postcode, location: {latitude, longitude}, prices: {E10…}}]}
  /// — but not their types: some write coordinates and prices as strings.
  @visibleForTesting
  static List<FuelStation> parseFeed(String body) {
    final Object? json;
    try {
      // Some files start with a byte-order mark.
      json = jsonDecode(body.replaceFirst('\uFEFF', ''));
    } catch (_) {
      return const [];
    }
    final list = json is Map ? json['stations'] : null;
    if (list is! List) return const [];
    double? num_(Object? v) =>
        v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.trim());
    final out = <FuelStation>[];
    for (final s in list.whereType<Map>()) {
      final loc = s['location'];
      final lat = num_(loc is Map ? loc['latitude'] : null);
      final lon = num_(loc is Map ? loc['longitude'] : null);
      if (lat == null || lon == null) continue;
      final prices = <String, double>{};
      final raw = s['prices'];
      if (raw is Map) {
        for (final e in raw.entries) {
          var p = num_(e.value);
          if (p == null || p <= 0) continue;
          // A few write pounds (1.429) where the rest write pence.
          if (p < 10) p *= 100;
          // Nothing sells for under 50p or over £5 a litre: a typo.
          if (p < 50 || p > 500) continue;
          prices['${e.key}'.toUpperCase()] = p;
        }
      }
      if (prices.isEmpty) continue;
      out.add(
        FuelStation(
          brand: '${s['brand'] ?? ''}'.trim(),
          address: '${s['address'] ?? ''}'.trim(),
          postcode: '${s['postcode'] ?? ''}'.trim(),
          latitude: lat,
          longitude: lon,
          prices: prices,
        ),
      );
    }
    return out;
  }
}

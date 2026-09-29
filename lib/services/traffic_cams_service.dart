import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';

/// One roadside camera.
@immutable
class TrafficCam {
  const TrafficCam({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.lat,
    this.lon,
    this.view = '',
    this.available = true,
  });

  final String id;

  /// "A406 Billet Upass E".
  final String name;
  final String imageUrl;
  final double? lat;
  final double? lon;

  /// Which way it looks: "West".
  final String view;

  /// TfL marks cameras that are switched off or being mended.
  final bool available;

  double milesFrom(double lat2, double lon2) {
    if (lat == null || lon == null) return double.infinity;
    const r = 3958.8;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat!), dLon = rad(lon2 - lon!);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat!)) *
            math.cos(rad(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.sqrt(a));
  }
}

/// London's 900-odd traffic cameras from TfL's open data — no key — looked
/// up by name, id or nearness to home. The list is fetched once a day; the
/// pictures themselves are stills TfL renews every few minutes.
class TrafficCamsService extends ChangeNotifier {
  TrafficCamsService({required this.home, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              headers: const {
                'User-Agent': 'HomeCanvas/1.0 (home dashboard panel)',
              },
            ),
          );

  final Dio _dio;

  /// The home location from Settings → Weather, if it has been found.
  final ({double lat, double lon})? Function() home;

  List<TrafficCam>? _cams;
  DateTime? _fetched;
  bool _busy = false;
  String? _error;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Every TfL camera, or null until the list has arrived.
  List<TrafficCam>? get cams => _cams;
  String? get error => _error;

  @visibleForTesting
  void debugSet(List<TrafficCam> list) {
    _cams = list;
    _fetched = DateTime.now();
    _changed();
  }

  Future<void> ensure() async {
    final last = _fetched;
    if (_busy ||
        (last != null &&
            DateTime.now().difference(last) <
                (_cams == null
                    ? const Duration(minutes: 5)
                    : const Duration(hours: 24)))) {
      return;
    }
    _busy = true;
    try {
      final r = await _dio.get<List<dynamic>>(
        'https://api.tfl.gov.uk/Place/Type/JamCam',
      );
      _cams = parse(r.data ?? const []);
      _error = null;
    } catch (e) {
      debugPrint('JamCams: $e');
      _error = tr('widget.cams.unreachable', 'Could not reach TfL');
    } finally {
      _fetched = DateTime.now();
      _busy = false;
      _changed();
    }
  }

  @visibleForTesting
  static List<TrafficCam> parse(List<dynamic> json) {
    final out = <TrafficCam>[];
    for (final p in json.whereType<Map>()) {
      final props = {
        for (final a
            in (p['additionalProperties'] as List? ?? const [])
                .whereType<Map>())
          '${a['key']}': '${a['value'] ?? ''}',
      };
      final image = props['imageUrl'] ?? '';
      if (!image.startsWith('https://')) continue;
      out.add(
        TrafficCam(
          id: '${p['id'] ?? ''}',
          name: '${p['commonName'] ?? ''}'.trim(),
          imageUrl: image,
          lat: (p['lat'] as num?)?.toDouble(),
          lon: (p['lon'] as num?)?.toDouble(),
          view: props['view'] ?? '',
          available: props['available'] != 'false',
        ),
      );
    }
    return out;
  }

  /// The camera [typed] names: a TfL id ("JamCams_00001.07450" or just
  /// "00001.07450"), else the first whose name has every word typed —
  /// "billet a406" finds "A406 Billet Upass E".
  static TrafficCam? find(List<TrafficCam> cams, String typed) {
    final q = typed.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final c in cams) {
      final id = c.id.toLowerCase();
      if (id == q || id == 'jamcams_$q') return c;
    }
    final words = q.split(RegExp(r'[\s,/]+')).where((w) => w.isNotEmpty);
    for (final c in cams) {
      final name = c.name.toLowerCase();
      if (words.every(name.contains)) return c;
    }
    return null;
  }

  /// The [n] working cameras nearest home.
  List<TrafficCam> nearest(int n) {
    final at = home();
    final all = _cams;
    if (at == null || all == null) return const [];
    final working =
        [
          for (final c in all)
            if (c.available && c.lat != null) c,
        ]..sort(
          (a, b) => a
              .milesFrom(at.lat, at.lon)
              .compareTo(b.milesFrom(at.lat, at.lon)),
        );
    return working.take(n).toList();
  }
}

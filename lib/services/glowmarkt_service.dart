import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'config_service.dart';
import 'http_client.dart';

/// How finely a smart meter's history is asked for. Glowmarkt's own names.
enum GlowPeriod {
  halfHour('PT30M'),
  day('P1D'),
  month('P1M');

  const GlowPeriod(this.code);
  final String code;
}

/// A smart meter's history, from Glowmarkt — Hildebrand's service behind
/// the Bright app — with the Bright login in Settings.
///
/// The meter's readings reach it through the DCC hours late, so the last
/// few half hours are usually missing: [readings] leaves out what has not
/// arrived rather than calling it nothing used.
///
/// Answers are kept for half an hour; Glowmarkt has nothing newer sooner.
class GlowmarktService {
  GlowmarktService(this._config, {Dio? dio})
    : _dio =
          dio ??
          httpClient(
            baseUrl: 'https://api.glowmarkt.com/api/v0-1/',
            // Its totals over months can take half a minute to add up.
            receive: const Duration(seconds: 60),
            // The Bright app's own: Glowmarkt wants one, and this is what
            // every Bright client sends.
            headers: {'applicationId': 'b0f1b774-a586-4f72-9edd-27ead8aa7a8d'},
          );

  final ConfigService _config;
  final Dio _dio;

  String? _token;
  DateTime? _tokenExpires;
  String? _tokenFor;

  /// Resource ids by Glowmarkt's classifier: `electricity.consumption`,
  /// `electricity.consumption.cost`.
  Map<String, String>? _resources;

  final Map<String, (DateTime, List<(DateTime, double)>)> _cache = {};

  bool get configured => _config.config.bright.isConfigured;

  Future<String> _signIn() async {
    final bright = _config.config.bright;
    // A changed login is a new sign-in, and maybe a different meter.
    if (_tokenFor != bright.username) {
      _token = null;
      _resources = null;
      _cache.clear();
    }
    final token = _token;
    if (token != null &&
        _tokenExpires != null &&
        DateTime.now().isBefore(
          _tokenExpires!.subtract(const Duration(days: 1)),
        )) {
      return token;
    }
    final r = await _dio.post(
      'auth',
      data: {'username': bright.username, 'password': bright.password},
    );
    final data = r.data as Map;
    if (data['valid'] != true || data['token'] is! String) {
      throw StateError('Bright did not accept the login');
    }
    _tokenFor = bright.username;
    _tokenExpires = DateTime.fromMillisecondsSinceEpoch(
      ((data['exp'] as num?) ?? 0).toInt() * 1000,
    );
    return _token = data['token'] as String;
  }

  Future<String?> _resource(String classifier, String token) async {
    _resources ??= {
      for (final r
          in ((await _dio.get(
                'resource',
                options: Options(headers: {'token': token}),
              )).data
              as List))
        if (r is Map) '${r['classifier']}': '${r['resourceId']}',
    };
    return _resources![classifier];
  }

  /// Electricity used, in kWh — or, with [cost], what it cost in pounds —
  /// in each [period] from [from] to [to], oldest first. Each is stamped
  /// with when it began, in local time. Null when it could not be asked.
  ///
  /// Glowmarkt limits how far one question reaches: ten days of half
  /// hours, 31 of days, 365 of months. Ask within them.
  Future<List<(DateTime, double)>?> readings(
    GlowPeriod period,
    DateTime from,
    DateTime to, {
    bool cost = false,
  }) async {
    if (!configured) return null;
    final key =
        '${period.code} $cost ${from.toIso8601String()} ${to.toIso8601String()}';
    final kept = _cache[key];
    if (kept != null &&
        DateTime.now().difference(kept.$1) < const Duration(minutes: 30)) {
      return kept.$2;
    }
    try {
      final token = await _signIn();
      final id = await _resource(
        cost ? 'electricity.consumption.cost' : 'electricity.consumption',
        token,
      );
      if (id == null) return null;
      String utc(DateTime t) => t.toUtc().toIso8601String().substring(0, 19);
      Future<Response<dynamic>> ask() => _dio.get(
        'resource/$id/readings',
        queryParameters: {
          'from': utc(from),
          'to': utc(to),
          'period': period.code,
          // In UTC, and turned into local time here, summer time and all.
          'offset': 0,
          'function': 'sum',
          // Missing as missing, not as nothing used.
          'nulls': 1,
        },
        options: Options(headers: {'token': token}),
      );
      // It drops a question now and then and answers the same one again.
      Response<dynamic> r;
      try {
        r = await ask();
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) rethrow;
        r = await ask();
      }
      final pence = (r.data as Map)['units'] == 'pence';
      final out = parse((r.data as Map)['data'], pence: pence);
      _cache[key] = (DateTime.now(), out);
      return out;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) _token = null;
      debugPrint('Glowmarkt: ${e.response?.data ?? e.message}');
      return null;
    } catch (e) {
      debugPrint('Glowmarkt: $e');
      return null;
    }
  }

  /// Glowmarkt's `[[seconds, value], …]`, the missing left out, pence made
  /// pounds.
  @visibleForTesting
  static List<(DateTime, double)> parse(Object? data, {bool pence = false}) => [
    for (final row in (data as List? ?? const []))
      if (row is List && row.length >= 2 && row[1] is num)
        (
          DateTime.fromMillisecondsSinceEpoch(
            (row[0] as num).toInt() * 1000,
            isUtc: true,
          ).toLocal(),
          (row[1] as num).toDouble() / (pence ? 100 : 1),
        ),
  ];
}

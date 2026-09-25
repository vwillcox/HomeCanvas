import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// One departure from the station, as a station board shows it.
@immutable
class Departure {
  const Departure({
    required this.scheduled,
    required this.destination,
    this.expected,
    this.platform,
    this.cancelled = false,
    this.lateMinutes,
    this.operator,
    this.bus = false,
    this.reason,
    this.atPlatform = false,
  });

  final DateTime scheduled;
  final String destination;

  /// When it is now expected to leave (or did), if that is known.
  final DateTime? expected;
  final String? platform;
  final bool cancelled;
  final int? lateMinutes;
  final String? operator;

  /// A replacement bus rather than a train.
  final bool bus;

  /// Why it is late or cancelled, in a few words, when the railway says.
  final String? reason;

  /// Standing at the platform now.
  final bool atPlatform;

  bool get late => !cancelled && (lateMinutes ?? 0) >= 2;

  /// The time it will actually go, for sorting and hiding ones already gone.
  DateTime get leaves => expected ?? scheduled;
}

@immutable
class Board {
  const Board({required this.station, required this.departures});

  /// "Maidstone East".
  final String station;
  final List<Departure> departures;
}

/// Parses the next-generation Realtime Trains API's location line-up.
Board parseBoard(Map<String, dynamic> json) {
  DateTime? time(Object? v) =>
      v == null ? null : DateTime.tryParse('$v')?.toLocal();
  Map<String, dynamic> map(Object? v) =>
      v is Map ? v.cast<String, dynamic>() : const {};

  final query = map(json['query']);
  final station = '${map(query['location'])['description'] ?? ''}';
  final out = <Departure>[];
  for (final s in (json['services'] as List? ?? const []).whereType<Map>()) {
    final svc = s.cast<String, dynamic>();
    final meta = map(svc['scheduleMetadata']);
    if (meta['inPassengerService'] == false) continue;
    final temporal = map(svc['temporalData']);
    final display = '${temporal['displayAs'] ?? ''}';
    // Passing through, or ending here: nothing to catch.
    if (display == 'PASS' || display == 'TERMINATES') continue;
    final dep = map(temporal['departure']);
    final scheduled =
        time(dep['scheduleAdvertised']) ?? time(dep['scheduleInternal']);
    if (scheduled == null) continue;

    final platform = map(map(svc['locationMetadata'])['platform']);
    final destinations = [
      for (final d
          in (svc['destination'] as List? ?? const []).whereType<Map>())
        '${map(d['location'])['description'] ?? ''}'.trim(),
    ].where((d) => d.isNotEmpty).toList();
    final reasons = [
      for (final r in (svc['reasons'] as List? ?? const []).whereType<Map>())
        '${r['shortText'] ?? ''}'.trim(),
    ].where((r) => r.isNotEmpty).toList();
    final mode = '${meta['modeType'] ?? ''}';

    out.add(
      Departure(
        scheduled: scheduled,
        destination: destinations.isEmpty ? '—' : destinations.join(' & '),
        expected:
            time(dep['realtimeActual']) ??
            time(dep['realtimeEstimate']) ??
            time(dep['realtimeForecast']),
        platform:
            '${platform['actual'] ?? platform['planned'] ?? ''}'.trim().isEmpty
            ? null
            : '${platform['actual'] ?? platform['planned']}',
        cancelled: dep['isCancelled'] == true || display == 'CANCELLED',
        lateMinutes: (dep['realtimeAdvertisedLateness'] as num?)?.toInt(),
        operator: map(meta['operator'])['name'] as String?,
        bus: mode.contains('BUS'),
        reason: reasons.isEmpty ? null : reasons.first,
        atPlatform:
            temporal['status'] == 'AT_PLATFORM' ||
            temporal['status'] == 'DEPART_READY' ||
            temporal['status'] == 'DEPART_PREPARING',
      ),
    );
  }
  out.sort((a, b) => a.scheduled.compareTo(b.scheduled));
  return Board(station: station, departures: out);
}

/// Why a board could not be had, in words for the tile.
class TrainsError implements Exception {
  const TrainsError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to the Realtime Trains API (the next-generation one at data.rtt.io;
/// the old api.rtt.io is switched off at the end of September 2026).
///
/// Takes either kind of token the portal issues. A long-life access token is
/// used as it is. A refresh token is swapped for an access token, which is
/// kept until shortly before it expires. Which one it has been given, it
/// works out from how the API answers.
class TrainsClient {
  TrainsClient({Dio? dio, this.base = 'https://data.rtt.io'})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
            ),
          );

  final Dio _dio;
  final String base;

  /// Access tokens swapped for refresh tokens, by refresh token.
  static final Map<String, ({String token, DateTime until})> _access = {};

  Future<Board> board({
    required String token,
    required String from,
    String to = '',
    int windowMinutes = 120,
  }) async {
    if (token.trim().isEmpty) {
      throw const TrainsError(
        'Add your Realtime Trains token in the widget settings',
      );
    }
    final params = {
      'code': from.trim().toUpperCase(),
      if (to.trim().isNotEmpty) 'filterTo': to.trim().toUpperCase(),
      'timeWindow': windowMinutes,
    };
    final swapped = _access[token];
    final usable =
        swapped != null &&
        swapped.until.isAfter(DateTime.now().add(const Duration(minutes: 2)));
    try {
      return await _get(usable ? swapped.token : token, params);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 401 && code != 403) throw _explain(e);
      // Not accepted as an access token: try it as a refresh token.
      final access = await _swap(token);
      try {
        return await _get(access, params);
      } on DioException catch (e2) {
        throw _explain(e2);
      }
    }
  }

  Future<Board> _get(String bearer, Map<String, Object> params) async {
    final r = await _dio.get(
      '$base/gb-nr/location',
      queryParameters: params,
      options: Options(headers: {'Authorization': 'Bearer $bearer'}),
    );
    final data = r.data;
    if (data is! Map) {
      throw const TrainsError('Unexpected answer from Realtime Trains');
    }
    return parseBoard(data.cast<String, dynamic>());
  }

  Future<String> _swap(String refresh) async {
    try {
      final r = await _dio.get(
        '$base/api/get_access_token',
        options: Options(headers: {'Authorization': 'Bearer $refresh'}),
      );
      final data = r.data as Map;
      final token = '${data['token'] ?? ''}';
      final until =
          DateTime.tryParse('${data['validUntil'] ?? ''}') ??
          DateTime.now().add(const Duration(minutes: 30));
      if (token.isEmpty) {
        throw const TrainsError('Realtime Trains gave no access token');
      }
      _access[refresh] = (token: token, until: until);
      return token;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw const TrainsError('Realtime Trains did not accept the token');
      }
      throw _explain(e);
    }
  }

  TrainsError _explain(DioException e) {
    switch (e.response?.statusCode) {
      case 401 || 403:
        return const TrainsError('Realtime Trains did not accept the token');
      case 404 || 400:
        return const TrainsError(
          'Check the station codes — three letters, like MDE',
        );
      case 429:
        return const TrainsError(
          'Asked Realtime Trains too often; trying again shortly',
        );
    }
    return const TrainsError('Could not reach Realtime Trains');
  }

  @visibleForTesting
  static void forgetTokens() => _access.clear();
}

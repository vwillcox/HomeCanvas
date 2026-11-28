import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart' show ArtMatrixSettings;
import 'http_client.dart';
import 'local_network.dart';

/// What became of a request to the Art Matrix.
enum ArtMatrixResult {
  /// It answered, and the display is as asked.
  done,

  /// Nothing answered at its address, or its name could not be looked up.
  unreachable,

  /// Something answered, but not with the display as asked: a value it
  /// would not take, or not an Art Matrix at all.
  refused,

  /// Its address is not on the home network, so nothing was sent.
  notLocal,

  /// There is no Art Matrix in Settings.
  notSetUp,
}

/// Switches an Art Matrix LED display on and off, and sets its brightness,
/// over the small HTTP API it has on the home network:
///
///     POST /display?on=1                 on; on=0 is off
///     POST /display?brightness=40&on=1   kept by the display, and on
///
/// Each is answered with the display as it now is: `{"on": true,
/// "brightness": 40}`. Off darkens the panel and its lights and pauses the
/// animations, but it stays on Wi-Fi, so it can be put on again from here.
///
/// The name is looked up each time — `arty.local` by mDNS, so a new address
/// from the router is followed — and only used when every address it stands
/// for is on the home network. The request goes to the address found.
class ArtMatrixService {
  ArtMatrixService(
    this._settings, {
    Dio? dio,
    Future<List<InternetAddress>> Function(String host)? lookup,
  }) : _dio =
           dio ??
           httpClient(
             // On the same network, it answers at once or not at all.
             connect: const Duration(seconds: 3),
             receive: const Duration(seconds: 5),
             followRedirects: false,
           ),
       _lookup = lookup ?? _lookupV4;

  final ArtMatrixSettings Function() _settings;
  final Dio _dio;
  final Future<List<InternetAddress>> Function(String host) _lookup;

  /// IPv4 only: a name found by mDNS can also stand for an IPv6 link-local
  /// address, which [isLocalAddress] does not count as home.
  static Future<List<InternetAddress>> _lookupV4(String host) =>
      InternetAddress.lookup(
        host,
        type: InternetAddressType.IPv4,
      ).timeout(const Duration(seconds: 3));

  /// Puts the display on, or off.
  Future<ArtMatrixResult> setPower(bool on) =>
      _display({'on': on ? '1' : '0'}, on: on);

  /// Sets the display to [level] percent, 1 to 100, which the Art Matrix
  /// keeps, and puts it on.
  Future<ArtMatrixResult> setBrightness(int level) =>
      _display({'brightness': '${level.clamp(1, 100)}', 'on': '1'}, on: true);

  Future<ArtMatrixResult> _display(
    Map<String, String> query, {
    required bool on,
  }) async {
    final s = _settings();
    if (!s.isConfigured) return ArtMatrixResult.notSetUp;
    final at = Uri.tryParse('http://${s.host}');
    if (at == null || at.host.isEmpty) return ArtMatrixResult.unreachable;
    final InternetAddress address;
    try {
      final literal = InternetAddress.tryParse(at.host);
      final found = literal != null ? [literal] : await _lookup(at.host);
      if (found.isEmpty) return ArtMatrixResult.unreachable;
      if (!found.every(isLocalAddress)) {
        debugPrint('Art Matrix: ${at.host} is $found, not on the home network');
        return ArtMatrixResult.notLocal;
      }
      address = found.first;
    } catch (e) {
      debugPrint('Art Matrix: looking up ${at.host}: $e');
      return ArtMatrixResult.unreachable;
    }
    final uri = Uri(
      scheme: 'http',
      host: address.address,
      port: at.port,
      path: '/display',
      queryParameters: query,
    );
    try {
      final response = await _dio.postUri<Object?>(uri);
      if (_onIn(response.data) == on) return ArtMatrixResult.done;
      debugPrint('Art Matrix: asked $query, answered ${response.data}');
      return ArtMatrixResult.refused;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse) {
        debugPrint(
          'Art Matrix: $query refused: '
          '${e.response?.statusCode} ${e.response?.data}',
        );
        return ArtMatrixResult.refused;
      }
      debugPrint('Art Matrix: $query: ${e.type.name} ${e.message ?? ''}');
      return ArtMatrixResult.unreachable;
    } catch (e) {
      debugPrint('Art Matrix: $query: $e');
      return ArtMatrixResult.unreachable;
    }
  }

  /// Whether the display says it is on, in an answer as Dio has it: read
  /// already, or still text if it came without a JSON content type.
  static bool? _onIn(Object? data) {
    if (data is String) {
      try {
        data = jsonDecode(data);
      } on FormatException {
        return null;
      }
    }
    return data is Map && data['on'] is bool ? data['on'] as bool : null;
  }
}

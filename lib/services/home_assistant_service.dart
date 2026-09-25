import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'config_service.dart';

/// One Home Assistant entity, as the widget shows it.
@immutable
class HaEntity {
  const HaEntity({
    required this.id,
    required this.state,
    this.attributes = const {},
  });

  final String id;
  final String state;
  final Map<String, dynamic> attributes;

  String get domain => id.split('.').first;
  String get name => '${attributes['friendly_name'] ?? id}';
  bool get unavailable => state == 'unavailable' || state == 'unknown';

  /// Things a tap can switch. Locks, alarms and covers are left out on
  /// purpose: a wall panel anyone walks past should not open the front door.
  bool get switchable =>
      const {'light', 'switch', 'fan', 'input_boolean'}.contains(domain);

  bool get on => state == 'on';

  /// The reading, in words, as Home Assistant's own cards would put it.
  String get display {
    if (unavailable) return 'Unavailable';
    final a = attributes;
    switch (domain) {
      case 'sensor':
        final unit = '${a['unit_of_measurement'] ?? ''}';
        final n = double.tryParse(state);
        final value = n == null
            ? _title(state)
            : (n == n.roundToDouble() || n.abs() >= 100
                  ? n.round().toString()
                  : n.toStringAsFixed(1));
        return unit.isEmpty
            ? value
            : (unit == '%' ? '$value%' : '$value $unit');
      case 'binary_sensor':
        final on = state == 'on';
        return switch ('${a['device_class'] ?? ''}') {
          'door' ||
          'window' ||
          'opening' ||
          'garage_door' => on ? 'Open' : 'Closed',
          'motion' || 'occupancy' || 'presence' => on ? 'Detected' : 'Clear',
          'moisture' => on ? 'Wet' : 'Dry',
          'battery' => on ? 'Low' : 'OK',
          'connectivity' => on ? 'Connected' : 'Disconnected',
          'problem' => on ? 'Problem' : 'OK',
          _ => on ? 'On' : 'Off',
        };
      case 'person' || 'device_tracker':
        return state == 'home'
            ? 'Home'
            : state == 'not_home'
            ? 'Away'
            : _title(state);
      case 'media_player':
        final title = '${a['media_title'] ?? ''}'.trim();
        return state == 'playing' && title.isNotEmpty ? title : _title(state);
      case 'climate':
        final t = a['current_temperature'];
        return t == null ? _title(state) : '$t°';
      case 'weather':
        final t = a['temperature'];
        return t == null
            ? _title(state)
            : '${_title(state.replaceAll('-', ' '))} · $t°';
      case 'light':
        final b = a['brightness'];
        return state == 'on' && b is num
            ? '${(b / 255 * 100).round()}%'
            : _title(state);
    }
    return _title(state);
  }

  static String _title(String s) {
    final words = s.replaceAll('_', ' ');
    return words.isEmpty
        ? words
        : '${words[0].toUpperCase()}${words.substring(1)}';
  }

  static HaEntity? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = '${j['entity_id'] ?? ''}';
    if (!id.contains('.')) return null;
    return HaEntity(
      id: id,
      state: '${j['state'] ?? ''}',
      attributes:
          (j['attributes'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

/// Reads and switches Home Assistant entities for the dashboard, using the
/// connection set up in Settings for the indoor temperature.
class HomeAssistantService extends ChangeNotifier {
  HomeAssistantService(this._config, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );

  final ConfigService _config;
  final Dio _dio;
  Map<String, HaEntity> _states = {};
  String? _error;
  DateTime? _fetched;
  Future<void>? _inFlight;

  String get _base =>
      _config.config.homeAssistant.baseUrl.replaceAll(RegExp(r'/+$'), '');
  String get _token => _config.config.homeAssistant.token;
  bool get configured => _base.isNotEmpty && _token.isNotEmpty;

  HaEntity? entity(String id) => _states[id];
  String? get error => _error;
  Iterable<HaEntity> get all => _states.values;

  Options get _auth => Options(headers: {'Authorization': 'Bearer $_token'});

  /// Everything's state, in one request. Shared by every widget that asks
  /// within a few seconds of another.
  Future<void> refresh() {
    if (!configured) {
      _error = 'Set up Home Assistant in Settings first';
      notifyListeners();
      return Future.value();
    }
    if (_fetched != null &&
        DateTime.now().difference(_fetched!) < const Duration(seconds: 5)) {
      return Future.value();
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<void> _fetch() async {
    try {
      final r = await _dio.get('$_base/api/states', options: _auth);
      _states = {
        for (final e in (r.data as List? ?? const []))
          if (HaEntity.fromJson(e) case final HaEntity h) h.id: h,
      };
      _fetched = DateTime.now();
      _error = null;
    } on DioException catch (e) {
      _error = e.response?.statusCode == 401
          ? 'Home Assistant did not accept the token'
          : 'Could not reach Home Assistant';
    } catch (e) {
      _error = 'Unexpected answer from Home Assistant';
    }
    notifyListeners();
  }

  /// Switches [e], showing the change at once and putting it back if Home
  /// Assistant says no.
  Future<void> toggle(HaEntity e) async {
    if (!e.switchable) return;
    final flipped = HaEntity(
      id: e.id,
      state: e.on ? 'off' : 'on',
      attributes: e.attributes,
    );
    _states[e.id] = flipped;
    notifyListeners();
    try {
      await _dio.post(
        '$_base/api/services/${e.domain}/toggle',
        data: {'entity_id': e.id},
        options: _auth,
      );
      _fetched = null; // the next refresh reads the real state
    } catch (_) {
      _states[e.id] = e;
      _error = 'Home Assistant did not take the change';
      notifyListeners();
    }
  }

  /// For the editor's entity picker: id → "Friendly name (id)", grouped by
  /// kind, the plumbing left out.
  Future<Map<String, String>> choices() async {
    _fetched = null;
    await refresh();
    const skip = {
      'update',
      'button',
      'conversation',
      'stt',
      'tts',
      'event',
      'zone',
      'automation',
    };
    final list = _states.values.where((e) => !skip.contains(e.domain)).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return {for (final e in list) e.id: '${e.name} (${e.id})'};
  }

  @visibleForTesting
  void debugSet(List<HaEntity> entities) {
    _states = {for (final e in entities) e.id: e};
    _fetched = DateTime.now();
    notifyListeners();
  }
}

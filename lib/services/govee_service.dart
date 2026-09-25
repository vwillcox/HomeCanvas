import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

/// A Govee light or plug, and what it is doing.
class GoveeDevice {
  GoveeDevice({
    required this.id,
    required this.sku,
    required this.name,
    this.ip,
    this.cloud = false,
    this.canDim = true,
    this.canColour = true,
  });

  /// Govee's device id, a MAC-like string; the same whichever way it is
  /// reached, which is how a device found both ways is told apart.
  final String id;
  final String sku;
  String name;

  /// Where it answers on the home network, when local control is on.
  String? ip;

  /// Reachable through Govee's cloud with the API key.
  bool cloud;

  bool canDim;
  bool canColour;

  bool? on;
  int? brightness; // 1–100
  Color? colour;
  bool online = true;

  bool get local => ip != null;
}

/// Govee lights and plugs, for the Lights widget.
///
/// Two ways in. Local control needs no account: devices with "LAN Control"
/// switched on in the Govee app answer a broadcast on the home network and
/// take commands directly. Govee's cloud API reaches every device on the
/// account, with a key from the Govee app. Where a device can be reached
/// both ways, the local way is used — faster, and it does not count against
/// the cloud's daily allowance.
class GoveeService extends ChangeNotifier {
  GoveeService({Dio? dio, this.listen = true})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );

  static const _multicast = '239.255.255.250';
  static const _scanPort = 4001;
  static const _replyPort = 4002;
  static const _commandPort = 4003;
  static const _cloud = 'https://openapi.api.govee.com/router/api/v1';

  /// Off keeps it off the home network entirely — for tests.
  final bool listen;

  final Dio _dio;
  final Map<String, GoveeDevice> _devices = {};
  final _rng = Random();
  RawDatagramSocket? _socket;
  String? _error;
  DateTime? _cloudListed;

  /// Everything found, by name.
  List<GoveeDevice> get devices =>
      _devices.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  String? get error => _error;

  /// Looks for devices and reads what each is doing. Called by the widget
  /// while it is on screen.
  Future<void> refresh({String apiKey = ''}) async {
    await _scanLocal();
    if (apiKey.trim().isNotEmpty) await _refreshCloud(apiKey.trim());
    notifyListeners();
  }

  // ---------- local ----------

  Future<void> _ensureSocket() async {
    if (_socket != null) return;
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _replyPort,
        reuseAddress: true,
      );
      _socket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final d = _socket?.receive();
        if (d == null) return;
        handleLocalReply(
          utf8.decode(d.data, allowMalformed: true),
          d.address.address,
        );
      });
    } catch (e) {
      debugPrint('Govee: cannot listen on $_replyPort: $e');
    }
  }

  Future<void> _scanLocal() async {
    if (!listen) return;
    await _ensureSocket();
    final s = _socket;
    if (s == null) return;
    s.send(
      utf8.encode(
        jsonEncode({
          'msg': {
            'cmd': 'scan',
            'data': {'account_topic': 'reserve'},
          },
        }),
      ),
      InternetAddress(_multicast),
      _scanPort,
    );
    // Ask every device already known what it is doing; the answers arrive on
    // the same socket.
    for (final d in _devices.values.where((d) => d.local)) {
      _sendLocal(d, 'devStatus', const {});
    }
    // Give the replies a moment before the widget redraws.
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  /// A message from a device on the home network: its answer to the
  /// broadcast, or its status.
  @visibleForTesting
  void handleLocalReply(String text, String fromIp) {
    Map? msg;
    try {
      msg = (jsonDecode(text) as Map)['msg'] as Map?;
    } catch (_) {
      return;
    }
    if (msg == null) return;
    final data = (msg['data'] as Map?) ?? const {};
    switch (msg['cmd']) {
      case 'scan':
        final id = '${data['device'] ?? ''}';
        if (id.isEmpty) return;
        final d = _devices.putIfAbsent(
          id,
          () => GoveeDevice(
            id: id,
            sku: '${data['sku'] ?? ''}',
            name: '${data['sku'] ?? 'Govee light'}',
          ),
        );
        d.ip = '${data['ip'] ?? fromIp}';
        _sendLocal(d, 'devStatus', const {});
      case 'devStatus':
        final d = _devices.values.where((x) => x.ip == fromIp).firstOrNull;
        if (d == null) return;
        d.on = data['onOff'] == 1;
        d.brightness = (data['brightness'] as num?)?.toInt();
        final c = data['color'];
        if (c is Map) {
          d.colour = Color.fromARGB(
            255,
            (c['r'] as num? ?? 0).toInt(),
            (c['g'] as num? ?? 0).toInt(),
            (c['b'] as num? ?? 0).toInt(),
          );
        }
        d.online = true;
        notifyListeners();
    }
  }

  void _sendLocal(GoveeDevice d, String cmd, Map<String, Object> data) {
    final s = _socket;
    if (s == null || d.ip == null) return;
    s.send(
      utf8.encode(
        jsonEncode({
          'msg': {'cmd': cmd, 'data': data},
        }),
      ),
      InternetAddress(d.ip!),
      _commandPort,
    );
  }

  // ---------- cloud ----------

  Map<String, String> _headers(String key) => {
    'Govee-API-Key': key,
    'Content-Type': 'application/json',
  };

  String _requestId() =>
      List.generate(16, (_) => _rng.nextInt(16).toRadixString(16)).join();

  Future<void> _refreshCloud(String key) async {
    try {
      // The device list changes rarely; the allowance is per day.
      if (_cloudListed == null ||
          DateTime.now().difference(_cloudListed!) >
              const Duration(minutes: 30)) {
        final r = await _dio.get(
          '$_cloud/user/devices',
          options: Options(headers: _headers(key)),
        );
        mergeCloudDevices(r.data);
        _cloudListed = DateTime.now();
      }
      for (final d in _devices.values.where((d) => d.cloud && !d.local)) {
        final r = await _dio.post(
          '$_cloud/device/state',
          options: Options(headers: _headers(key)),
          data: {
            'requestId': _requestId(),
            'payload': {'sku': d.sku, 'device': d.id},
          },
        );
        applyCloudState(d, r.data);
      }
      _error = null;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      _error = code == 401 || code == 403
          ? 'Govee did not accept the API key'
          : code == 429
          ? 'Govee’s daily allowance is used up'
          : 'Could not reach Govee';
    } catch (e) {
      _error = 'Unexpected answer from Govee';
      debugPrint('Govee: $e');
    }
  }

  /// Govee's device list, merged into what the home network found.
  @visibleForTesting
  void mergeCloudDevices(Object? body) {
    final list = body is Map ? body['data'] : null;
    if (list is! List) return;
    for (final raw in list.whereType<Map>()) {
      final id = '${raw['device'] ?? ''}';
      if (id.isEmpty) continue;
      final caps = [
        for (final c
            in (raw['capabilities'] as List? ?? const []).whereType<Map>())
          '${c['type']}:${c['instance']}',
      ];
      final d = _devices.putIfAbsent(
        id,
        () => GoveeDevice(id: id, sku: '${raw['sku'] ?? ''}', name: id),
      );
      d.cloud = true;
      final name = '${raw['deviceName'] ?? ''}'.trim();
      if (name.isNotEmpty) d.name = name;
      d.canDim = caps.contains('devices.capabilities.range:brightness');
      d.canColour = caps.contains(
        'devices.capabilities.color_setting:colorRgb',
      );
    }
  }

  @visibleForTesting
  void applyCloudState(GoveeDevice d, Object? body) {
    final payload = body is Map ? body['payload'] : null;
    final caps = payload is Map ? payload['capabilities'] : null;
    if (caps is! List) return;
    for (final c in caps.whereType<Map>()) {
      final value = (c['state'] as Map?)?['value'];
      switch ('${c['type']}:${c['instance']}') {
        case 'devices.capabilities.online:online':
          d.online = value == true;
        case 'devices.capabilities.on_off:powerSwitch':
          d.on = value == 1 || value == true;
        case 'devices.capabilities.range:brightness':
          if (value is num) d.brightness = value.toInt();
        case 'devices.capabilities.color_setting:colorRgb':
          if (value is num) d.colour = Color(0xFF000000 | value.toInt());
      }
    }
  }

  Future<void> _control(
    GoveeDevice d,
    String key,
    String type,
    String instance,
    Object value,
  ) async {
    await _dio.post(
      '$_cloud/device/control',
      options: Options(headers: _headers(key)),
      data: {
        'requestId': _requestId(),
        'payload': {
          'sku': d.sku,
          'device': d.id,
          'capability': {'type': type, 'instance': instance, 'value': value},
        },
      },
    );
  }

  // ---------- control ----------

  /// Each of these shows the change straight away and puts it back if the
  /// device could not be told.
  Future<void> setPower(GoveeDevice d, bool on, {String apiKey = ''}) =>
      _change(
        d,
        apiKey,
        () => d.on = on,
        () => _sendLocal(d, 'turn', {'value': on ? 1 : 0}),
        () => _control(
          d,
          apiKey,
          'devices.capabilities.on_off',
          'powerSwitch',
          on ? 1 : 0,
        ),
      );

  Future<void> setBrightness(GoveeDevice d, int level, {String apiKey = ''}) {
    final v = level.clamp(1, 100);
    return _change(
      d,
      apiKey,
      () {
        d.brightness = v;
        d.on = true;
      },
      () => _sendLocal(d, 'brightness', {'value': v}),
      () => _control(d, apiKey, 'devices.capabilities.range', 'brightness', v),
    );
  }

  Future<void> setColour(GoveeDevice d, Color c, {String apiKey = ''}) {
    final r = (c.r * 255).round(),
        g = (c.g * 255).round(),
        b = (c.b * 255).round();
    return _change(
      d,
      apiKey,
      () {
        d.colour = c;
        d.on = true;
      },
      () => _sendLocal(d, 'colorwc', {
        'color': {'r': r, 'g': g, 'b': b},
        'colorTemInKelvin': 0,
      }),
      () => _control(
        d,
        apiKey,
        'devices.capabilities.color_setting',
        'colorRgb',
        (r << 16) | (g << 8) | b,
      ),
    );
  }

  Future<void> _change(
    GoveeDevice d,
    String key,
    void Function() apply,
    void Function() viaLan,
    Future<void> Function() viaCloud,
  ) async {
    final wasOn = d.on, wasLevel = d.brightness, wasColour = d.colour;
    apply();
    notifyListeners();
    if (d.local) {
      viaLan();
      return;
    }
    if (!d.cloud || key.trim().isEmpty) return;
    try {
      await viaCloud();
      _error = null;
    } catch (e) {
      d
        ..on = wasOn
        ..brightness = wasLevel
        ..colour = wasColour;
      _error = 'Govee did not take the change';
      notifyListeners();
    }
  }

  @visibleForTesting
  void debugAdd(GoveeDevice d) {
    _devices[d.id] = d;
    notifyListeners();
  }

  @override
  void dispose() {
    _socket?.close();
    super.dispose();
  }
}

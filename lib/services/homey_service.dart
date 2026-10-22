import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';
import 'config_service.dart';
import 'local_network.dart';
import 'socket_io.dart';
import 'http_client.dart';

/// One thing a Homey device measures or can be set to: `onoff`, `dim`,
/// `measure_temperature`.
@immutable
class HomeyCapability {
  const HomeyCapability({
    required this.id,
    this.value,
    this.units = '',
    this.setable = false,
    this.decimals,
    this.min,
    this.max,
  });

  final String id;
  final Object? value;
  final String units;
  final bool setable;
  final int? decimals;
  final double? min;
  final double? max;

  HomeyCapability withValue(Object? value) => HomeyCapability(
    id: id,
    value: value,
    units: units,
    setable: setable,
    decimals: decimals,
    min: min,
    max: max,
  );

  static HomeyCapability? fromJson(String id, Object? j) {
    if (j is! Map) return null;
    final units = j['units'];
    final decimals = j['decimals'];
    return HomeyCapability(
      id: id,
      value: j['value'],
      units: units is String ? units : '',
      setable: j['setable'] == true,
      decimals: decimals is num ? decimals.toInt() : null,
      min: (j['min'] as Object?) is num ? (j['min'] as num).toDouble() : null,
      max: (j['max'] as Object?) is num ? (j['max'] as num).toDouble() : null,
    );
  }
}

/// One Homey device, as the widget shows it.
@immutable
class HomeyDevice {
  const HomeyDevice({
    required this.id,
    required this.name,
    this.kind = 'other',
    this.zone = '',
    this.available = true,
    this.capabilities = const {},
  });

  final String id;
  final String name;

  /// Homey's class for it — `light`, `socket`, `sensor` — or the one its
  /// owner said to treat it as.
  final String kind;

  /// The id of the zone it is in.
  final String zone;
  final bool available;
  final Map<String, HomeyCapability> capabilities;

  /// Things a tap can switch. Locks, garage doors and alarms are left out on
  /// purpose: a wall panel anyone walks past should not open the front door.
  bool get switchable =>
      available &&
      (capabilities['onoff']?.setable ?? false) &&
      const {
        'light',
        'socket',
        'fan',
        'heater',
        'kettle',
        'coffeemachine',
        'amplifier',
        'speaker',
        'tv',
      }.contains(kind);

  bool get on => capabilities['onoff']?.value == true;

  /// Whether its brightness can be set from the panel.
  bool get dimmable => switchable && (capabilities['dim']?.setable ?? false);

  /// How bright it is, from nothing to one — nothing while it is off.
  double get brightness {
    final v = capabilities['dim']?.value;
    return !on ? 0 : (v is num ? v.toDouble().clamp(0.0, 1.0) : 1);
  }

  /// A reading as a number, or null when it has none.
  double? number(String capability) {
    final v = capabilities[capability]?.value;
    return v is num ? v.toDouble() : null;
  }

  bool has(String capability) => capabilities.containsKey(capability);

  /// What the panel may set, and on what. Never a lock, a door, a blind or
  /// an alarm; and of the rest, only how it is lit, blown or heated.
  bool settable(String capability) =>
      available &&
      !const {
        'lock',
        'garagedoor',
        'homealarm',
        'doorbell',
        'windowcoverings',
        'curtain',
        'blinds',
        'sunshade',
      }.contains(kind) &&
      const {
        'onoff',
        'dim',
        'light_hue',
        'light_saturation',
        'light_temperature',
        'light_mode',
        'oscillating',
        'fan_speed',
        'target_temperature',
      }.contains(capability.split('.').first) &&
      (capabilities[capability]?.setable ?? false);

  /// What a card shows first, when its owner has not said.
  static const _preferred = [
    'locked',
    'measure_temperature',
    'target_temperature',
    'alarm_contact',
    'alarm_motion',
    'alarm_water',
    'alarm_smoke',
    'measure_power',
    'measure_humidity',
    'measure_co2',
    'measure_luminance',
    'meter_power',
    'onoff',
    'measure_battery',
  ];

  /// The capability to show: [wanted] when the device has it, otherwise its
  /// switch if a tap can work it, otherwise the most telling reading.
  String? reading([String wanted = '']) {
    if (capabilities.containsKey(wanted)) return wanted;
    if (switchable) return 'onoff';
    for (final c in _preferred) {
      if (capabilities.containsKey(c)) return c;
    }
    return capabilities.keys.firstOrNull;
  }

  /// The reading, in words, as Homey's own app would put it.
  String display(String? capability) {
    if (!available) return tr('widget.homey.unavailable', 'Unavailable');
    final c = capabilities[capability];
    if (c == null) return tr('widget.homey.noReading', 'No reading');
    final v = c.value;
    // "measure_temperature.outside" is a temperature like any other.
    final what = c.id.split('.').first;
    if (what == 'onoff') {
      final dim = capabilities['dim']?.value;
      return v != true
          ? tr('widget.homey.off', 'Off')
          : dim is num
          ? '${(dim * 100).round()}%'
          : tr('widget.homey.on', 'On');
    }
    if (v is bool) {
      return switch (what) {
        'alarm_contact' =>
          v
              ? tr('widget.homey.open', 'Open')
              : tr('widget.homey.closed', 'Closed'),
        'alarm_motion' =>
          v
              ? tr('widget.homey.detected', 'Detected')
              : tr('widget.homey.clear', 'Clear'),
        'alarm_water' =>
          v ? tr('widget.homey.wet', 'Wet') : tr('widget.homey.dry', 'Dry'),
        'alarm_battery' =>
          v ? tr('widget.homey.low', 'Low') : tr('widget.homey.ok', 'OK'),
        'locked' =>
          v
              ? tr('widget.homey.locked', 'Locked')
              : tr('widget.homey.unlocked', 'Unlocked'),
        _ when what.startsWith('alarm_') =>
          v ? tr('widget.homey.alarm', 'Alarm') : tr('widget.homey.ok', 'OK'),
        _ => v ? tr('widget.homey.on', 'On') : tr('widget.homey.off', 'Off'),
      };
    }
    if (v is num) {
      // Homey keeps these as a fraction of one, and calls the unit %.
      if (const {'dim', 'volume_set', 'windowcoverings_set'}.contains(what)) {
        return '${(v * 100).round()}%';
      }
      final decimals = c.decimals;
      final value = decimals != null
          ? v.toStringAsFixed(decimals)
          : (v == v.roundToDouble() || v.abs() >= 100
                ? v.round().toString()
                : v.toStringAsFixed(1));
      return c.units.isEmpty
          ? value
          : (c.units == '%' ? '$value%' : '$value ${c.units}');
    }
    if (v == null) return '—';
    final words = '$v'.replaceAll('_', ' ');
    return words.isEmpty
        ? words
        : '${words[0].toUpperCase()}${words.substring(1)}';
  }

  HomeyDevice withValue(String capability, Object? value) {
    final had = capabilities[capability];
    if (had == null) return this;
    return HomeyDevice(
      id: id,
      name: name,
      kind: kind,
      zone: zone,
      available: available,
      capabilities: {...capabilities, capability: had.withValue(value)},
    );
  }

  static HomeyDevice? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = '${j['id'] ?? ''}';
    if (id.isEmpty) return null;
    final caps = j['capabilitiesObj'];
    return HomeyDevice(
      id: id,
      name: '${j['name'] ?? id}',
      kind: '${j['virtualClass'] ?? j['class'] ?? 'other'}',
      zone: '${j['zone'] ?? ''}',
      available: j['available'] != false,
      capabilities: {
        if (caps is Map)
          for (final e in caps.entries)
            if (HomeyCapability.fromJson('${e.key}', e.value)
                case final HomeyCapability c)
              c.id: c,
      },
    );
  }
}

/// A room, or the house it is in.
@immutable
class HomeyZone {
  const HomeyZone({required this.id, required this.name, this.parent});

  final String id;
  final String name;

  /// The zone this one is inside, if any.
  final String? parent;
}

/// Something set up in Homey to be started: a flow, or an advanced flow,
/// which is started at a different address.
@immutable
class HomeyFlow {
  const HomeyFlow({
    required this.id,
    required this.name,
    this.advanced = false,
  });

  final String id;
  final String name;
  final bool advanced;
}

/// Reads and switches the devices of a Homey Pro on the home network, with
/// an API key made in Homey's own app. Where it is and the key are in
/// Settings, once, for every Homey tile on the dashboard.
///
/// Two ways in, as Homey's Web API has them. HTTP for the whole picture —
/// every device and what it reads — and to switch one. Socket.IO for what
/// changes: once connected, each device a tile shows is subscribed to, and
/// a light switched in the hall is on the panel as it happens. While that
/// connection is up the whole picture is only asked for now and then; while
/// it is not, every few seconds, as if there were no socket at all.
class HomeyService extends ChangeNotifier {
  HomeyService(
    this._config, {
    Dio? dio,
    SocketIoOpener? socket,
    Future<List<InternetAddress>> Function(String host)? lookup,
  }) : _lookup = lookup ?? InternetAddress.lookup,
       _dio =
           dio ??
           httpClient(
             connect: const Duration(seconds: 5),
             receive: const Duration(seconds: 10),
             // Wherever a Homey might send the panel on to, the key does
             // not follow.
             followRedirects: false,
           ),
       _open = socket;

  final ConfigService _config;
  final Dio _dio;
  final SocketIoOpener? _open;
  final Future<List<InternetAddress>> Function(String host) _lookup;

  /// Whether the address is on the home network — null until looked up.
  /// The key is sent nowhere else.
  bool? _local;

  String _base = '';
  String _key = '';

  /// Where the Homey answered: [_base], or [_base] at the port a Homey
  /// that is a program on somebody's server listens on instead of 80.
  String _root = '';
  static const _selfHostedPort = 4859;

  /// What the Homey calls itself. The socket's handshake asks for it.
  String? _homeyId;
  Map<String, HomeyDevice> _devices = {};
  Map<String, HomeyZone> _zones = {};
  Map<String, HomeyFlow> _flows = {};
  String? _error;
  DateTime? _fetched;
  Future<void>? _inFlight;

  /// What the Homey last said to a plain question — its moods, who is
  /// home, a log's readings — by the path asked, and when.
  final Map<String, (DateTime, Object?)> _answers = {};
  final Set<String> _asking = {};

  SocketIoClient? _socket;
  StreamSubscription<SocketIoEvent>? _events;
  String _namespace = '/api';
  final Set<String> _watched = {};
  final Set<String> _subscribed = {};
  bool _disposed = false;

  bool get configured => _config.config.homey.isConfigured;

  /// Whether changes are arriving as they happen.
  bool get live => _socket != null;
  String? get error => _error;
  HomeyDevice? device(String id) => _devices[id];
  Iterable<HomeyDevice> get all => _devices.values;
  HomeyZone? zone(String id) => _zones[id];
  Iterable<HomeyZone> get zones => _zones.values;
  HomeyFlow? flow(String id) => _flows[id];

  /// Every light, by name.
  List<HomeyDevice> get lights =>
      _devices.values.where((d) => d.kind == 'light').toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  /// The devices in the zone [id] — and, with [below], in the rooms inside
  /// it — by name.
  List<HomeyDevice> devicesIn(String id, {bool below = true}) {
    bool inside(String? zone) {
      // A zone is never its own ancestor, but nothing here depends on it.
      for (var hops = 0; zone != null && hops < 16; hops++) {
        if (zone == id) return true;
        if (!below) return false;
        zone = _zones[zone]?.parent;
      }
      return false;
    }

    return _devices.values.where((d) => inside(d.zone)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Options get _auth => Options(headers: {'Authorization': 'Bearer $_key'});

  @override
  void dispose() {
    _disposed = true;
    _hangUp();
    _dio.close();
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// "192.168.1.50" as much as "http://192.168.1.50/".
  static String baseOf(String address) {
    final a = address.trim().replaceAll(RegExp(r'/+$'), '');
    return a.isEmpty || a.contains('://') ? a : 'http://$a';
  }

  /// The Homey in Settings, if it is not the one already in use.
  void _use(String address, String key) {
    final base = baseOf(address);
    key = key.trim();
    if (base == _base && key == _key) return;
    _base = base;
    _root = base;
    _key = key;
    _local = null;
    _homeyId = null;
    _devices = {};
    _zones = {};
    _flows = {};
    _answers.clear();
    _error = null;
    _fetched = null;
    _hangUp();
  }

  /// The devices whose changes are wanted as they happen.
  void watch(Iterable<String> ids) => _watched.addAll(ids);

  /// Brings the picture up to date if it is old, and the socket up if it is
  /// down. Shared by every tile that asks at once.
  Future<void> ensure() {
    final settings = _config.config.homey;
    _use(settings.address, settings.apiKey);
    if (_base.isEmpty || _key.isEmpty) return Future.value();
    return _inFlight ??= _ensure().whenComplete(() => _inFlight = null);
  }

  Future<void> _ensure() async {
    if (!await _onHomeNetwork()) return;
    final last = _fetched;
    final keep = live
        ? const Duration(minutes: 5)
        : const Duration(seconds: 10);
    if (last == null || DateTime.now().difference(last) >= keep) {
      await _fetch();
    }
    await _listen();
  }

  /// Whether every address the Homey's name stands for is on the home
  /// network. A name that cannot be looked up yet is asked about again.
  Future<bool> _onHomeNetwork() async {
    if (_local case final bool known) return known;
    final base = _base;
    final host = Uri.tryParse(base)?.host ?? '';
    String? error;
    bool? local;
    try {
      final literal = InternetAddress.tryParse(host);
      final found = literal != null ? [literal] : await _lookup(host);
      local = found.isNotEmpty && found.every(isLocalAddress);
      if (!local) {
        error = tr(
          'widget.homey.notLocal',
          'That address is not on your home network. The API key is only '
              'sent to a Homey that is.',
        );
      }
    } catch (_) {
      error = tr('widget.homey.unreachable', 'Could not reach Homey');
    }
    if (base != _base) return false;
    _local = local;
    if (error != null) {
      _error = error;
      _changed();
    }
    return local ?? false;
  }

  Future<void> _fetch() async {
    final base = _base;
    try {
      _homeyId ??= await _find(base);
      if (base != _base) return;
      final root = _root;
      final r = await _dio.get(
        '$root/api/manager/devices/device',
        options: _auth,
      );
      // A key without the zones or flows permission still shows its devices.
      var zones = _zones;
      try {
        final z = await _dio.get(
          '$root/api/manager/zones/zone',
          options: _auth,
        );
        zones = {
          for (final e in (z.data as Map? ?? const {}).entries)
            if (e.value case {'name': final String name})
              '${e.key}': HomeyZone(
                id: '${e.key}',
                name: name,
                parent: (e.value as Map)['parent'] as String?,
              ),
        };
      } on DioException catch (_) {}
      final flows = <String, HomeyFlow>{};
      for (final advanced in const [false, true]) {
        try {
          final f = await _dio.get(
            '$root/api/manager/flow/${advanced ? 'advancedflow' : 'flow'}',
            options: _auth,
          );
          for (final e in (f.data as Map? ?? const {}).entries) {
            if (e.value case {'name': final String name}) {
              flows['${e.key}'] = HomeyFlow(
                id: '${e.key}',
                name: name,
                advanced: advanced,
              );
            }
          }
        } on DioException catch (_) {
          flows.addAll({
            for (final f in _flows.values)
              if (f.advanced == advanced) f.id: f,
          });
        }
      }
      if (base != _base) return;
      _devices = {
        for (final d in (r.data as Map? ?? const {}).values)
          if (HomeyDevice.fromJson(d) case final HomeyDevice h) h.id: h,
      };
      _zones = zones;
      _flows = flows;
      _fetched = DateTime.now();
      _error = null;
    } on DioException catch (e) {
      if (base != _base) return;
      final status = e.response?.statusCode;
      _error = status == 401 || status == 403
          ? tr(
              'widget.homey.keyNotAccepted',
              'Homey did not accept the API key',
            )
          : tr('widget.homey.unreachable', 'Could not reach Homey');
    } catch (e) {
      if (base != _base) return;
      debugPrint('Homey: $e');
      _error = tr('widget.homey.unexpected', 'Unexpected answer from Homey');
    }
    _changed();
  }

  /// Asks the Homey at [base] what it calls itself — and, if nothing is
  /// listening there and no port was given, at the self-hosted port, which
  /// is then where everything else is asked for.
  Future<String?> _find(String base) async {
    Future<String?> ping(String at) async => (await _dio.get(
      '$at/api/manager/system/ping',
    )).headers.value('x-homey-id');
    try {
      return await ping(base);
    } on DioException catch (e) {
      if (e.response != null || (Uri.tryParse(base)?.hasPort ?? true)) rethrow;
      final other = '$base:$_selfHostedPort';
      final id = await ping(other);
      if (base == _base) _root = other;
      return id;
    }
  }

  /// Connects the socket if it is not, and subscribes to whatever is watched
  /// and not yet subscribed to. Quiet when it fails: the tiles carry on with
  /// what HTTP tells them, and the next [ensure] tries again.
  Future<void> _listen() async {
    final id = _homeyId;
    if (id == null || _watched.isEmpty || _disposed) return;
    var socket = _socket;
    final fresh = socket == null;
    try {
      if (socket == null) {
        final base = _base;
        final opened = await SocketIoClient.connect(
          Uri.parse(_root),
          open: _open,
        );
        try {
          final answer = await opened.emit('handshakeClient', [
            {'token': _key, 'homeyId': id},
          ]);
          if (answer.firstOrNull != null) {
            throw StateError('handshake refused: ${answer.first}');
          }
          final said = answer.length > 1 ? answer[1] : null;
          final namespace = said is Map && said['namespace'] is String
              ? said['namespace'] as String
              : '/api';
          await opened.join(namespace);
          if (base != _base || _disposed) throw const SocketIoClosed();
          _namespace = namespace;
        } catch (_) {
          opened.close();
          rethrow;
        }
        socket = _socket = opened;
        _subscribed.clear();
        _events = opened.events.listen(_onEvent);
        unawaited(opened.done.then((_) => _dropped(opened)));
      }
      for (final d in _watched.difference(_subscribed)) {
        final answer = await socket.emit('subscribe', [
          'homey:device:$d',
        ], namespace: _namespace);
        if (answer.firstOrNull == null) _subscribed.add(d);
      }
      // Whatever changed between the last picture and the first subscription.
      if (fresh) await _fetch();
    } catch (e) {
      debugPrint('Homey socket: $e');
    }
  }

  void _onEvent(SocketIoEvent e) {
    // Nobody is showing a Homey tile any more.
    if (!hasListeners) {
      _hangUp();
      return;
    }
    const prefix = 'homey:device:';
    if (e.namespace != _namespace || !e.name.startsWith(prefix)) return;
    final device = _devices[e.name.substring(prefix.length)];
    final what = e.args.firstOrNull;
    final data = e.args.length > 1 ? e.args[1] : null;
    if (what == 'capability' && device != null && data is Map) {
      _devices[device.id] = device.withValue(
        '${data['capabilityId']}',
        data['value'],
      );
      _changed();
    } else {
      // Renamed, moved, gone off line, deleted: the next picture has it.
      _fetched = null;
    }
  }

  void _dropped(SocketIoClient socket) {
    if (!identical(socket, _socket)) return;
    _socket = null;
    unawaited(_events?.cancel());
    _events = null;
    _subscribed.clear();
  }

  void _hangUp() {
    final socket = _socket;
    if (socket == null) return;
    _dropped(socket);
    socket.close();
  }

  /// What the Homey last answered to `GET /api/manager/[path]`, if it has
  /// been asked: see [ask].
  Object? answer(String path) => _answers[path]?.$2;

  /// Asks the Homey for [path] — `users/user`, `system/memory` — unless it
  /// was asked within [keep], and tells listeners when the answer is in. A
  /// question that fails keeps the last answer, and is not asked again
  /// until [keep] has passed.
  Future<void> ask(
    String path, {
    Duration keep = const Duration(minutes: 1),
  }) async {
    await ensure();
    if (_homeyId == null) return;
    final had = _answers[path];
    if (had != null && DateTime.now().difference(had.$1) < keep) return;
    if (!_asking.add(path)) return;
    final root = _root;
    try {
      final r = await _dio.get('$root/api/manager/$path', options: _auth);
      if (root != _root) return;
      _answers[path] = (DateTime.now(), r.data);
      _changed();
    } catch (_) {
      if (root == _root) _answers[path] = (DateTime.now(), had?.$2);
    } finally {
      _asking.remove(path);
    }
  }

  /// Sets the mood [id]: a room's lights as they were saved.
  Future<bool> setMood(String id) =>
      _send('POST', 'moods/mood/${Uri.encodeComponent(id)}/set');

  /// Gives the logic variable [id] a new value.
  Future<bool> setVariable(String id, Object value) async {
    final ok = await _send(
      'PUT',
      'logic/variable/${Uri.encodeComponent(id)}',
      data: {
        'variable': {'value': value},
      },
    );
    if (ok) {
      // Asked again, so the tile shows what Homey now has.
      _answers.remove('logic/variable');
      unawaited(ask('logic/variable'));
    }
    return ok;
  }

  Future<bool> _send(String method, String path, {Object? data}) async {
    if (_homeyId == null) return false;
    try {
      await _dio.request(
        '$_root/api/manager/$path',
        data: data,
        options: Options(method: method, headers: _auth.headers),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// For the editor's pickers: what [path] lists, id to [label].
  Future<Map<String, String>> listChoices(
    String path,
    String? Function(Map<dynamic, dynamic> item) label,
  ) async {
    await ask(path, keep: const Duration(seconds: 5));
    final data = answer(path);
    final items = data is Map ? data.values : (data is List ? data : const []);
    final found = <String, String>{
      for (final i in items)
        if (i is Map && i['id'] is String)
          if (label(i) case final String name) i['id'] as String: name,
    };
    final ids = found.keys.toList()
      ..sort((a, b) => found[a]!.compareTo(found[b]!));
    return {for (final id in ids) id: found[id]!};
  }

  /// Switches [d], showing the change at once and putting it back if Homey
  /// says no.
  Future<void> toggle(HomeyDevice d) async {
    if (d.switchable) await _set(d, 'onoff', !d.on);
  }

  /// Sets one of the things the panel may set — see [HomeyDevice.settable].
  Future<void> set(HomeyDevice d, String capability, Object value) =>
      _set(d, capability, value);

  /// A colour, by its place round the wheel from nought to one.
  Future<void> colour(HomeyDevice d, double hue) async {
    if (!d.settable('light_hue')) return;
    await _set(d, 'light_mode', 'color');
    await _set(_devices[d.id] ?? d, 'light_hue', hue);
    await _set(_devices[d.id] ?? d, 'light_saturation', 1);
    await _comeOn(d);
  }

  /// White, from cool at nought to warm at one.
  Future<void> warmth(HomeyDevice d, double warm) async {
    if (!d.settable('light_temperature')) return;
    await _set(d, 'light_mode', 'temperature');
    await _set(_devices[d.id] ?? d, 'light_temperature', warm.clamp(0.0, 1.0));
    await _comeOn(d);
  }

  Future<void> _comeOn(HomeyDevice d) async {
    final now = _devices[d.id];
    if (now != null && now.switchable && !now.on) {
      await _set(now, 'onoff', true);
    }
  }

  /// Switches every one of [devices] that a tap can switch.
  Future<void> switchAll(Iterable<HomeyDevice> devices, bool on) =>
      Future.wait([
        for (final d in devices)
          if (d.switchable && d.on != on) _set(d, 'onoff', on),
      ]);

  /// How bright [d] is, from nothing to one. A light that is off comes on.
  Future<void> dim(HomeyDevice d, double level) async {
    if (!d.dimmable) return;
    await _set(d, 'dim', level.clamp(0.01, 1.0));
    await _comeOn(d);
  }

  Future<void> _set(HomeyDevice d, String capability, Object value) async {
    if (!d.settable(capability)) return;
    _devices[d.id] = d.withValue(capability, value);
    _changed();
    try {
      await _dio.put(
        '$_root/api/manager/devices/device/${d.id}/capability/$capability',
        data: {'value': value},
        options: _auth,
      );
      // Without the socket to say so, the next picture confirms it.
      if (!live) _fetched = null;
    } catch (_) {
      final now = _devices[d.id];
      if (now != null) {
        _devices[d.id] = now.withValue(
          capability,
          d.capabilities[capability]?.value,
        );
      }
      _error = tr('widget.homey.didNotTake', 'Homey did not take the change');
      _changed();
    }
  }

  /// Starts the flow [id]. Whether Homey took it.
  Future<bool> start(String id) async {
    final flow = _flows[id];
    if (flow == null) return false;
    try {
      await _dio.post(
        '$_root/api/manager/flow/'
        '${flow.advanced ? 'advancedflow' : 'flow'}/$id/trigger',
        options: _auth,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// How things stand with the Homey in Settings, asked afresh: for the
  /// editor, after the address or key has been changed there.
  Future<Map<String, dynamic>> status() async {
    _fetched = null;
    await ensure();
    return {'devices': _devices.length, 'live': live, 'error': _error};
  }

  String _label(HomeyDevice d) {
    final zone = _zones[d.zone];
    return zone == null ? d.name : '${zone.name} · ${d.name}';
  }

  Future<Map<String, String>> _picker(
    Iterable<HomeyDevice> Function() of,
  ) async {
    await ensure();
    final list = of().toList()..sort((a, b) => _label(a).compareTo(_label(b)));
    return {for (final d in list) d.id: _label(d)};
  }

  /// For the editor's pickers: id → "Zone · Name". Empty until Settings has
  /// the address and key.
  Future<Map<String, String>> choices() {
    // The editor asks for this list first; the others share its picture.
    _fetched = null;
    return _picker(() => _devices.values);
  }

  Future<Map<String, String>> lightChoices() => _picker(() => lights);

  /// Rooms, each under the zone it is in: "Home › Lounge".
  Future<Map<String, String>> zoneChoices() async {
    await ensure();
    String path(HomeyZone z) {
      final names = [z.name];
      for (var up = _zones[z.parent]; up != null && names.length < 8;) {
        names.insert(0, up.name);
        up = _zones[up.parent];
      }
      return names.join(' › ');
    }

    final list = _zones.values.toList()
      ..sort((a, b) => path(a).compareTo(path(b)));
    return {for (final z in list) z.id: path(z)};
  }

  Future<Map<String, String>> flowChoices() async {
    await ensure();
    final list = _flows.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return {for (final f in list) f.id: f.name};
  }

  @visibleForTesting
  void debugAnswer(String path, Object? data) {
    _answers[path] = (DateTime.now().add(const Duration(days: 1)), data);
    _changed();
  }

  @visibleForTesting
  void debugSet(
    List<HomeyDevice> devices, {
    List<HomeyZone> zones = const [],
    List<HomeyFlow> flows = const [],
  }) {
    final settings = _config.config.homey;
    _use(settings.address, settings.apiKey);
    _devices = {for (final d in devices) d.id: d};
    _zones = {for (final z in zones) z.id: z};
    _flows = {for (final f in flows) f.id: f};
    _answers.clear();
    // Not asked for again, and so no socket either.
    _fetched = DateTime.now().add(const Duration(days: 1));
    _changed();
  }
}

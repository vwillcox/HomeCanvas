import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/homey_extras.dart';
import 'package:home_canvas/services/homey_service.dart';
import 'package:home_canvas/services/socket_io.dart';

import 'new_widgets_fit_test.dart' show shapes, tile;

/// What `GET /api/manager/devices/device` answers with, cut down.
Map<String, dynamic> _devices({bool lampOn = false}) => {
  'lamp': {
    'id': 'lamp',
    'name': 'Hall lamp',
    'class': 'light',
    'zone': 'hall',
    'available': true,
    'capabilitiesObj': {
      'onoff': {'value': lampOn, 'setable': true},
      'dim': {'value': 0.62, 'units': '%', 'setable': true},
    },
  },
  'door': {
    'id': 'door',
    'name': 'Front door',
    'class': 'sensor',
    'zone': 'hall',
    'available': true,
    'capabilitiesObj': {
      'alarm_contact': {'value': false},
      'measure_temperature': {'value': 18.46, 'units': '°C', 'decimals': 1},
    },
  },
  'lock': {
    'id': 'lock',
    'name': 'Back door lock',
    'class': 'lock',
    'zone': 'kitchen',
    'available': true,
    'capabilitiesObj': {
      'locked': {'value': true, 'setable': true},
      'onoff': {'value': true, 'setable': true},
    },
  },
};

/// A fuller house, for the tiles that want more than a lamp and a door.
List<HomeyDevice> _house() => [
  for (final d in <Map<String, dynamic>>[
    {
      'id': 'strip',
      'name': 'Strip',
      'class': 'light',
      'zone': 'hall',
      'capabilitiesObj': {
        'onoff': {'value': true, 'setable': true},
        'dim': {'value': 0.4, 'setable': true},
        'light_hue': {'value': 0.67, 'setable': true},
        'light_saturation': {'value': 1, 'setable': true},
        'light_temperature': {'value': 0.5, 'setable': true},
        'light_mode': {'value': 'color', 'setable': true},
      },
    },
    {
      'id': 'fan',
      'name': 'Fan',
      'class': 'fan',
      'zone': 'kitchen',
      'capabilitiesObj': {
        'onoff': {'value': true, 'setable': true},
        'oscillating': {'value': false, 'setable': true},
        'fan_speed': {'value': 0.5, 'setable': true},
        'workMode.fan': {'value': 'Sleep', 'setable': true},
      },
    },
    {
      'id': 'stat',
      'name': 'Thermostat',
      'class': 'thermostat',
      'zone': 'hall',
      'capabilitiesObj': {
        'measure_temperature': {'value': 19.5, 'units': '°C', 'decimals': 1},
        'measure_humidity': {'value': 54, 'units': '%'},
        'target_temperature': {
          'value': 21,
          'units': '°C',
          'setable': true,
          'min': 5,
          'max': 21.2,
        },
      },
    },
    {
      'id': 'kettle',
      'name': 'Kettle',
      'class': 'socket',
      'zone': 'kitchen',
      'capabilitiesObj': {
        'onoff': {'value': true, 'setable': true},
        'measure_power': {'value': 1840.0, 'units': 'W'},
      },
    },
    {
      'id': 'window',
      'name': 'Window',
      'class': 'sensor',
      'zone': 'kitchen',
      'capabilitiesObj': {
        'alarm_contact': {'value': true},
        'measure_battery': {'value': 12, 'units': '%'},
      },
    },
    {
      'id': 'lost',
      'name': 'Shed sensor',
      'class': 'sensor',
      'zone': 'kitchen',
      'available': false,
      'capabilitiesObj': {
        'alarm_motion': {'value': true},
      },
    },
    {
      'id': 'lock',
      'name': 'Back door lock',
      'class': 'lock',
      'zone': 'kitchen',
      'capabilitiesObj': {
        'locked': {'value': true, 'setable': true},
        'onoff': {'value': true, 'setable': true},
        'dim': {'value': 1, 'setable': true},
      },
    },
  ])
    HomeyDevice.fromJson(d)!,
];

/// The Homey's HTTP side, as far as the service asks of it.
class _Http implements HttpClientAdapter {
  final List<String> asked = [];
  var lampOn = false;
  double? dim;
  var guests = false;

  /// What was set on anything but the lamp: "strip light_hue 0.5".
  final List<String> sets = [];
  var key = 'secret';
  var refusePut = false;

  /// The only port anything is listening on, when it is not all of them.
  int? port;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    asked.add('${options.method} $path');
    if (port != null && options.uri.port != port) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connection refused',
      );
    }
    ResponseBody json(Object body, {int status = 200}) =>
        ResponseBody.fromString(
          jsonEncode(body),
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
            'x-homey-id': ['abc123'],
          },
        );
    if (path == '/api/manager/system/ping') return json('pong');
    if (options.headers['Authorization'] != 'Bearer $key') {
      return json({'error': 'unauthorized'}, status: 401);
    }
    if (path == '/api/manager/devices/device') {
      return json(_devices(lampOn: lampOn));
    }
    if (path == '/api/manager/zones/zone') {
      return json({
        'home': {'id': 'home', 'name': 'Home', 'parent': null},
        'hall': {'id': 'hall', 'name': 'Hall', 'parent': 'home'},
        'kitchen': {'id': 'kitchen', 'name': 'Kitchen', 'parent': 'home'},
      });
    }
    if (path == '/api/manager/flow/flow') {
      return json({
        'night': {'id': 'night', 'name': 'Goodnight'},
      });
    }
    if (path == '/api/manager/flow/advancedflow') {
      return json({
        'film': {'id': 'film', 'name': 'Movie time'},
      });
    }
    if (options.method == 'POST' &&
        (path.endsWith('/trigger') || path.endsWith('/set'))) {
      return json({});
    }
    if (path == '/api/manager/users/user') {
      return json({
        'u': {'id': 'u', 'name': 'Vincent Willcox', 'present': true},
      });
    }
    if (path == '/api/manager/logic/variable') {
      return json({
        'v': {'id': 'v', 'name': 'Guests staying', 'value': guests},
      });
    }
    if (options.method == 'PUT' && path == '/api/manager/logic/variable/v') {
      guests = ((options.data as Map)['variable'] as Map)['value'] == true;
      return json({});
    }
    final put = RegExp(
      r'^/api/manager/devices/device/(\w+)/capability/([\w.]+)$',
    ).firstMatch(path);
    if (options.method == 'PUT' &&
        put != null &&
        !(put[1] == 'lamp' && (put[2] == 'onoff' || put[2] == 'dim'))) {
      sets.add('${put[1]} ${put[2]} ${(options.data as Map)['value']}');
      return json({});
    }
    if (options.method == 'PUT' &&
        path == '/api/manager/devices/device/lamp/capability/onoff') {
      if (refusePut) return json({'error': 'no'}, status: 500);
      lampOn = (options.data as Map)['value'] == true;
      return json({});
    }
    if (options.method == 'PUT' &&
        path == '/api/manager/devices/device/lamp/capability/dim') {
      dim = ((options.data as Map)['value'] as num).toDouble();
      return json({});
    }
    return json({'error': 'not found'}, status: 404);
  }

  @override
  void close({bool force = false}) {}
}

/// The Homey's Socket.IO side: says hello, takes the handshake, lets the
/// namespace it named be joined, and acknowledges subscriptions.
class _Socket {
  final List<Uri> opened = [];
  final List<String> sent = [];
  final List<String> subscribed = [];
  Object? handshake;
  var refuse = false;
  StreamController<String>? _in;

  bool get open => !(_in?.isClosed ?? true);

  Future<SocketIoWire> connect(Uri uri) async {
    opened.add(uri);
    final wire = _in = StreamController<String>();
    scheduleMicrotask(() {
      wire.add('0{"sid":"s","pingInterval":25000,"pingTimeout":5000}');
      wire.add('40');
    });
    return SocketIoWire(
      incoming: wire.stream,
      send: _got,
      close: () => unawaited(wire.close()),
    );
  }

  void _got(String m) {
    sent.add(m);
    if (!m.startsWith('4')) return;
    final p = SocketIoPacket.parse(m.substring(1))!;
    void answer(List<Object?> with_) => _in!.add(
      '4${SocketIoPacket(SocketIoPacket.ack, namespace: p.namespace, id: p.id, data: with_).encode()}',
    );
    if (p.type == SocketIoPacket.connect) _in!.add('40${p.namespace},');
    if (p.type != SocketIoPacket.event) return;
    final data = p.data as List;
    switch (data.first) {
      case 'handshakeClient':
        handshake = data[1];
        answer(
          refuse
              ? [
                  {'code': 401, 'message': 'invalid token'},
                ]
              : [
                  null,
                  {'namespace': '/api'},
                ],
        );
      case 'subscribe':
        subscribed.add('${data[1]}');
        answer([null]);
    }
  }

  /// A device saying one of its capabilities has changed.
  void push(String device, String capability, Object? value) => _in!.add(
    '42/api,${jsonEncode([
      'homey:device:$device',
      'capability',
      {'capabilityId': capability, 'value': value},
    ])}',
  );

  void drop() => unawaited(_in!.close());
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('Socket.IO packets', () {
    test('are written as a 2.x server reads them', () {
      expect(
        const SocketIoPacket(
          SocketIoPacket.event,
          id: 3,
          data: [
            'handshakeClient',
            {'token': 't'},
          ],
        ).encode(),
        '23["handshakeClient",{"token":"t"}]',
      );
      expect(
        const SocketIoPacket(
          SocketIoPacket.connect,
          namespace: '/api',
        ).encode(),
        '0/api,',
      );
      expect(
        const SocketIoPacket(
          SocketIoPacket.event,
          namespace: '/api',
          id: 12,
          data: ['subscribe', 'homey:device:x'],
        ).encode(),
        '2/api,12["subscribe","homey:device:x"]',
      );
    });

    test('are read back: namespace, answer number and what was said', () {
      final e = SocketIoPacket.parse(
        '2/api,["homey:device:x","capability",{"value":true}]',
      )!;
      expect(e.type, SocketIoPacket.event);
      expect(e.namespace, '/api');
      expect(e.id, isNull);
      expect((e.data as List).first, 'homey:device:x');

      final a = SocketIoPacket.parse('3/api,12[null]')!;
      expect((a.type, a.namespace, a.id), (SocketIoPacket.ack, '/api', 12));
      expect(a.data, [null]);

      final root = SocketIoPacket.parse('37[null,{"namespace":"/api"}]')!;
      expect((root.namespace, root.id), ('/', 7));

      expect(SocketIoPacket.parse('0')!.namespace, '/');
      expect(SocketIoPacket.parse('0/api?x=1,')!.namespace, '/api');
      expect(
        SocketIoPacket.parse('4/api,"Invalid namespace"')!.data,
        'Invalid namespace',
      );
      expect(SocketIoPacket.parse(''), isNull);
      expect(SocketIoPacket.parse('51-["x"]'), isNull);
      expect(SocketIoPacket.parse('2[broken'), isNull);
    });
  });

  group('Socket.IO client', () {
    test('asks for Engine.IO 3 over a WebSocket, and is answered', () async {
      final server = _Socket();
      final client = await SocketIoClient.connect(
        Uri.parse('http://192.168.1.50'),
        open: server.connect,
      );
      addTearDown(client.close);
      expect(
        '${server.opened.single}',
        'ws://192.168.1.50/socket.io/?EIO=3&transport=websocket',
      );
      final answer = await client.emit('handshakeClient', [
        {'token': 't', 'homeyId': 'h'},
      ]);
      expect(answer, [
        null,
        {'namespace': '/api'},
      ]);
      await client.join('/api');
      expect(
        await client.emit('subscribe', ['homey:device:x'], namespace: '/api'),
        [null],
      );
      final heard = client.events.first;
      server.push('x', 'onoff', true);
      final e = await heard;
      expect(
        (e.namespace, e.name, e.args.first),
        ('/api', 'homey:device:x', 'capability'),
      );
    });

    test('a server that goes away fails what was waiting on it', () async {
      final server = _Socket();
      final client = await SocketIoClient.connect(
        Uri.parse('https://homey.example'),
        open: server.connect,
      );
      expect(server.opened.single.scheme, 'wss');
      final waiting = client.emit('never answered', const []);
      server.drop();
      await expectLater(waiting, throwsA(isA<SocketIoClosed>()));
      await client.done;
      expect(client.closed, isTrue);
      expect(client.emit('too late', const []), throwsA(isA<SocketIoClosed>()));
    });
  });

  group('Homey devices', () {
    final devices = {
      for (final d in _devices(lampOn: true).values)
        if (HomeyDevice.fromJson(d) case final HomeyDevice h) h.id: h,
    };

    test('say what they read as Homey would', () {
      final lamp = devices['lamp']!;
      expect(lamp.reading(), 'onoff');
      expect(lamp.display('onoff'), '62%');
      expect(lamp.withValue('onoff', false).display('onoff'), 'Off');

      final door = devices['door']!;
      expect(door.reading(), 'measure_temperature');
      expect(door.display('measure_temperature'), '18.5 °C');
      expect(door.reading('alarm_contact'), 'alarm_contact');
      expect(door.display('alarm_contact'), 'Closed');
      expect(
        door.withValue('alarm_contact', true).display('alarm_contact'),
        'Open',
      );
      // A capability it has not got falls back to its main one.
      expect(door.reading('measure_power'), 'measure_temperature');
    });

    test('only lights, sockets and the like switch with a tap', () {
      expect(devices['lamp']!.switchable, isTrue);
      expect(devices['door']!.switchable, isFalse);
      // It has an on/off, and is still a lock.
      expect(devices['lock']!.switchable, isFalse);
    });
  });

  group('what else Homey says', () {
    test('alerts: alarms first, then what is off line, then batteries', () {
      final alerts = homeyAlerts(_house());
      expect(
        [for (final a in alerts) '${a.device.name}: ${a.text}'],
        ['Window: Open', 'Shed sensor: Off line', 'Window: Battery 12%'],
      );
      expect(homeyAlerts(_house(), battery: 10, offline: false).length, 1);
    });

    test('the timeline is newest first, without Homey\'s asterisks', () {
      final notes = homeyTimeline({
        'a': {
          'excerpt': '**Front door** opened',
          'ownerName': 'Hall',
          'dateCreated': '2026-10-04T08:00:00.000Z',
        },
        'b': {
          'excerpt': 'Welcome home!',
          'ownerName': 'Timeline',
          'dateCreated': '2026-10-04T09:00:00.000Z',
        },
        'c': 'not a note',
      });
      expect(
        [for (final n in notes) n.text],
        ['Welcome home!', 'Front door opened'],
      );
    });

    test('a log is asked for by its owner, and its gaps are left out', () {
      expect(
        homeyLogPath('homey:manager:weather:temperature', 'last24Hours'),
        'insights/log/homey%3Amanager%3Aweather/'
        'homey%3Amanager%3Aweather%3Atemperature/entry?resolution=last24Hours',
      );
      final points = homeyEntries({
        'values': [
          {'t': '2026-10-04T08:00:00.000Z', 'v': null},
          {'t': '2026-10-04T08:05:00.000Z', 'v': 18.5},
          {'t': '2026-10-04T08:10:00.000Z', 'v': true},
        ],
      });
      expect([for (final p in points) p.value], [18.5, 1.0]);
      expect(homeyEntries(null), isEmpty);
    });

    test('people, uptime, fullness and power, in words', () {
      final people = homeyPeople({
        'a': {'name': 'Vincent Willcox', 'present': true, 'asleep': true},
        'b': {'name': 'Sam', 'present': false},
        'c': {'name': 'Old guest', 'enabled': false},
      });
      expect(
        [for (final p in people) '${p.name} ${p.state}'],
        ['Sam Away', 'Vincent Asleep'],
      );
      expect(homeyUptime(8542), '2 h 22 min');
      expect(homeyUptime(3 * 86400 + 4 * 3600), '3 d 4 h');
      expect(homeyUptime(125), '2 min');
      expect(homeyUsed(4000, 3000), '25%');
      expect(homeyUsed(null, 1), '—');
      expect(homeyWatts(850), '850 W');
      expect(homeyWatts(2400), '2.4 kW');
    });
  });

  group('Homey service', () {
    late _Http http;
    late _Socket socket;
    late HomeyService homey;
    late ConfigService config;

    /// As Settings would: where the Homey is, and the key to it.
    void use(String address, String key) => config.config.homey
      ..address = address
      ..apiKey = key;

    setUp(() {
      http = _Http();
      socket = _Socket();
      config = ConfigService();
      homey = HomeyService(
        config,
        dio: Dio()..httpClientAdapter = http,
        socket: socket.connect,
      );
    });
    tearDown(() => homey.dispose());

    test('an address needs no http:// in front', () {
      expect(HomeyService.baseOf(' 192.168.1.50/ '), 'http://192.168.1.50');
      expect(
        HomeyService.baseOf('https://192-168-1-50.homey.homeylocal.com'),
        'https://192-168-1-50.homey.homeylocal.com',
      );
      expect(HomeyService.baseOf(''), '');
    });

    test('reads the devices over HTTP, then listens on the socket', () async {
      use('192.168.1.50', 'secret');
      homey
        ..addListener(() {})
        ..watch(['lamp', 'door']);
      await homey.ensure();

      expect(homey.error, isNull);
      expect(homey.device('lamp')!.on, isFalse);
      expect(homey.live, isTrue);
      expect(socket.handshake, {'token': 'secret', 'homeyId': 'abc123'});
      expect(socket.subscribed, ['homey:device:lamp', 'homey:device:door']);

      // Switched at the wall: nothing is asked for, and the panel has it.
      final asked = http.asked.length;
      socket.push('lamp', 'onoff', true);
      await _settle();
      expect(homey.device('lamp')!.on, isTrue);
      expect(http.asked.length, asked);

      // A device picked later joins the same connection.
      homey.watch(['lock']);
      await homey.ensure();
      expect(socket.opened.length, 1);
      expect(socket.subscribed.last, 'homey:device:lock');
      expect(http.asked.length, asked);
    });

    test(
      'a tap switches over HTTP, and is put back if Homey says no',
      () async {
        use('192.168.1.50', 'secret');
        homey.watch(['lamp']);
        await homey.ensure();

        await homey.toggle(homey.device('lamp')!);
        expect(
          http.asked,
          contains('PUT /api/manager/devices/device/lamp/capability/onoff'),
        );
        expect(http.lampOn, isTrue);
        expect(homey.device('lamp')!.on, isTrue);

        http.refusePut = true;
        await homey.toggle(homey.device('lamp')!);
        expect(homey.device('lamp')!.on, isTrue);
        expect(homey.error, 'Homey did not take the change');

        // And a lock is never asked to.
        final asked = http.asked.length;
        await homey.toggle(homey.device('lock')!);
        expect(http.asked.length, asked);
      },
    );

    test('a socket that drops is connected again the next time', () async {
      use('192.168.1.50', 'secret');
      homey
        ..addListener(() {})
        ..watch(['lamp']);
      await homey.ensure();
      socket.drop();
      await _settle();
      expect(homey.live, isFalse);

      // Switched while nobody was listening.
      http.lampOn = true;
      await homey.ensure();
      expect(homey.live, isTrue);
      expect(socket.opened.length, 2);
      expect(socket.subscribed, ['homey:device:lamp', 'homey:device:lamp']);
      expect(homey.device('lamp')!.on, isTrue);
    });

    test('a socket that will not have the key leaves HTTP working', () async {
      socket.refuse = true;
      use('192.168.1.50', 'secret');
      homey.watch(['lamp']);
      await homey.ensure();
      expect(homey.live, isFalse);
      expect(socket.open, isFalse);
      expect(homey.device('lamp'), isNotNull);
      expect(homey.error, isNull);
    });

    test('a key Homey does not know is said so', () async {
      use('192.168.1.50', 'wrong');
      homey.watch(['lamp']);
      await homey.ensure();
      expect(homey.all, isEmpty);
      expect(homey.error, 'Homey did not accept the API key');
    });

    test('a self-hosted Homey is found on its own port', () async {
      http.port = 4859;
      use('10.0.0.178', 'secret');
      homey.watch(['lamp']);
      await homey.ensure();
      expect(homey.error, isNull);
      expect(homey.device('lamp'), isNotNull);
      expect(
        '${socket.opened.single}',
        'ws://10.0.0.178:4859/socket.io/?EIO=3&transport=websocket',
      );

      // A port that was given is the only one tried.
      http.asked.clear();
      use('10.0.0.178:8123', 'secret');
      await homey.ensure();
      expect(http.asked, ['GET /api/manager/system/ping']);
      expect(homey.error, 'Could not reach Homey');
    });

    test('rooms, brightness and flows', () async {
      use('192.168.1.50', 'secret');
      await homey.ensure();
      // The house has what its rooms have; a room only its own.
      expect(homey.devicesIn('home').map((d) => d.id), [
        'lock',
        'door',
        'lamp',
      ]);
      expect(homey.devicesIn('home', below: false), isEmpty);
      expect(homey.devicesIn('hall').map((d) => d.id), ['door', 'lamp']);

      // Dragged up from off: as bright as asked, and on.
      await homey.dim(homey.device('lamp')!, 0.4);
      expect(http.dim, 0.4);
      expect(http.lampOn, isTrue);
      expect(homey.device('lamp')!.display('onoff'), '40%');
      // A lock is not for dimming either.
      final asked = http.asked.length;
      await homey.dim(homey.device('lock')!, 0.4);
      expect(http.asked.length, asked);

      await homey.switchAll(homey.devicesIn('home'), false);
      expect(http.lampOn, isFalse);
      expect(homey.device('lock')!.on, isTrue);

      expect(await homey.start('night'), isTrue);
      expect(await homey.start('film'), isTrue);
      expect(await homey.start('nothing'), isFalse);
      expect(
        http.asked,
        containsAll([
          'POST /api/manager/flow/flow/night/trigger',
          'POST /api/manager/flow/advancedflow/film/trigger',
        ]),
      );
    });

    test(
      'questions are asked once, kept, and asked again when stale',
      () async {
        use('192.168.1.50', 'secret');
        await homey.ask('users/user');
        expect(homeyPeople(homey.answer('users/user')).single.name, 'Vincent');
        final asked = http.asked.length;
        await homey.ask('users/user');
        expect(http.asked.length, asked);
        await homey.ask('users/user', keep: Duration.zero);
        expect(http.asked.length, asked + 1);

        // Something it has not got is not asked for over and over either.
        await homey.ask('nothing/here');
        final after = http.asked.length;
        await homey.ask('nothing/here');
        expect(http.asked.length, after);
        expect(homey.answer('nothing/here'), isNull);

        expect(
          await homey.listChoices(
            'logic/variable',
            (v) => v['name'] as String?,
          ),
          {'v': 'Guests staying'},
        );
        expect(await homey.setVariable('v', true), isTrue);
        expect(http.guests, isTrue);
        expect(await homey.setMood('evening'), isTrue);
        expect(
          http.asked,
          contains('POST /api/manager/moods/mood/evening/set'),
        );
      },
    );

    test('colour, warmth and heat are set; a lock is never touched', () async {
      use('192.168.1.50', 'secret');
      homey.debugSet(_house());
      await homey.status();
      homey.debugSet(_house());
      http.sets.clear();
      await homey.colour(homey.device('strip')!, 0.33);
      expect(http.sets, [
        'strip light_mode color',
        'strip light_hue 0.33',
        'strip light_saturation 1',
      ]);
      http.sets.clear();
      await homey.warmth(homey.device('strip')!, 0.8);
      expect(http.sets, [
        'strip light_mode temperature',
        'strip light_temperature 0.8',
      ]);
      expect(
        homey.device('strip')!.capabilities['light_mode']!.value,
        'temperature',
      );

      http.sets.clear();
      final lock = homey.device('lock')!;
      expect(lock.settable('onoff'), isFalse);
      await homey.set(lock, 'onoff', false);
      await homey.set(lock, 'dim', 0.2);
      await homey.set(lock, 'locked', false);
      // And nothing but how a thing is lit, blown or heated, on anything.
      await homey.set(homey.device('fan')!, 'workMode.fan', 'Turbo');
      expect(http.sets, isEmpty);
      await homey.set(homey.device('fan')!, 'oscillating', true);
      await homey.set(homey.device('stat')!, 'target_temperature', 21.5);
      expect(http.sets, [
        'fan oscillating true',
        'stat target_temperature 21.5',
      ]);
    });

    test('the key goes nowhere but the home network', () async {
      use('https://203.0.113.9', 'secret');
      homey.watch(['lamp']);
      await homey.ensure();
      expect(homey.error, startsWith('That address is not on your home'));
      expect(http.asked, isEmpty);
      expect(socket.opened, isEmpty);

      // A name counts for what it stands for: all of it at home, or not.
      final named = HomeyService(
        config,
        dio: Dio()..httpClientAdapter = http,
        socket: socket.connect,
        lookup: (host) async => [
          InternetAddress('192.168.1.50'),
          if (host == 'homey.example') InternetAddress('203.0.113.9'),
        ],
      );
      addTearDown(named.dispose);
      use('homey.example', 'secret');
      await named.ensure();
      expect(http.asked, isEmpty);
      use('homey.local', 'secret');
      await named.ensure();
      expect(named.error, isNull);
      expect(named.device('lamp'), isNotNull);
    });

    test('the editor is offered every device, by zone', () async {
      expect(await homey.choices(), isEmpty);
      use('192.168.1.50', 'secret');
      expect(await homey.choices(), {
        'door': 'Hall · Front door',
        'lamp': 'Hall · Hall lamp',
        'lock': 'Kitchen · Back door lock',
      });
      expect(await homey.lightChoices(), {'lamp': 'Hall · Hall lamp'});
      expect(await homey.zoneChoices(), {
        'home': 'Home',
        'hall': 'Home › Hall',
        'kitchen': 'Home › Kitchen',
      });
      expect(await homey.flowChoices(), {
        'night': 'Goodnight',
        'film': 'Movie time',
      });
      // Nothing is watched, so there is nothing to listen for.
      expect(socket.opened, isEmpty);
    });
  });

  group('the tiles', () {
    setUpAll(registerBuiltInWidgets);

    late _Http http;
    late HomeyService homey;

    Future<void> draw(
      WidgetTester tester,
      String type,
      Size size,
      Map<String, dynamic> options,
    ) {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final w = DashboardWidgetContext(
        theme: kBuiltInThemes.first,
        config: DashboardWidgetConfig(
          id: 'w',
          type: type,
          x: 0,
          y: 0,
          width: 4,
          height: 2,
          options: options,
        ),
      );
      return tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: homey,
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                  size: size,
                  child: Builder(
                    builder: (context) =>
                        WidgetRegistry.find(type)!.build(context, w),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    /// Draws [type] at every size a tile can be, then at four by two.
    Future<void> sweep(
      WidgetTester tester,
      String type,
      Map<String, dynamic> options, {
      List<HomeyDevice>? devices,
      Map<String, Object?> answers = const {},
    }) async {
      final config = ConfigService();
      config.config.homey
        ..address = '192.168.1.50'
        ..apiKey = 'secret';
      http = _Http();
      homey = HomeyService(config, dio: Dio()..httpClientAdapter = http)
        ..debugSet(
          devices ??
              [for (final d in _devices().values) HomeyDevice.fromJson(d)!],
          zones: const [
            HomeyZone(id: 'home', name: 'Home'),
            HomeyZone(id: 'hall', name: 'Hall', parent: 'home'),
            HomeyZone(id: 'kitchen', name: 'Kitchen', parent: 'home'),
          ],
          flows: const [HomeyFlow(id: 'night', name: 'Goodnight')],
        );
      addTearDown(homey.dispose);
      answers.forEach(homey.debugAnswer);
      final t = WidgetRegistry.find(type)!;
      for (final (cols, rows) in shapes) {
        if (cols < t.minWidth || rows < t.minHeight) continue;
        await draw(tester, type, tile(cols, rows), options);
        await tester.pump(const Duration(milliseconds: 50));
        final e = tester.takeException();
        expect(e, isNull, reason: '$type at $cols × $rows: $e');
      }
      await draw(tester, type, tile(4, 2), options);
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> tap(WidgetTester tester, Finder what) async {
      await tester.runAsync(() async {
        // The bar's filled part is found by its box, which is not what is hit.
        await tester.tap(what, warnIfMissed: false);
        // Until the Homey has heard nothing new for a while: dimming is two
        // requests in turn, and a fixed wait missed the second when the
        // machine running the tests was busy.
        var heard = -1;
        final until = DateTime.now().add(const Duration(seconds: 2));
        while (heard != http.asked.length && DateTime.now().isBefore(until)) {
          heard = http.asked.length;
          await _settle();
        }
      });
      await tester.pump(const Duration(milliseconds: 250));
    }

    testWidgets('devices: fits at every size, and a tap switches the lamp', (
      tester,
    ) async {
      await sweep(tester, 'homey', {
        'devices': [
          {'device': 'lamp', 'capability': '', 'name': ''},
          {'device': 'door', 'capability': 'alarm_contact', 'name': 'Door'},
          {'device': 'lock', 'capability': '', 'name': ''},
          {'device': 'gone', 'capability': '', 'name': 'Missing'},
        ],
      });
      expect(find.text('Hall lamp'), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('Not found'), findsOneWidget);

      await tap(tester, find.text('Hall lamp'));
      expect(http.lampOn, isTrue);
      expect(find.text('62%'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a room: everything in it, and a card that switches the lot', (
      tester,
    ) async {
      await sweep(tester, 'homey_room', {'zone': 'home'});
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('All off'), findsOneWidget);
      expect(find.text('Front door'), findsOneWidget);
      expect(find.text('Back door lock'), findsOneWidget);

      // One room of it, only its lights, and no card for the room.
      await draw(tester, 'homey_room', tile(4, 2), {
        'zone': 'hall',
        'show': 'lights',
        'master': false,
      });
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Hall lamp'), findsOneWidget);
      expect(find.text('Front door'), findsNothing);
      expect(find.text('Hall'), findsNothing);

      await draw(tester, 'homey_room', tile(4, 2), {'zone': 'home'});
      await tester.pump(const Duration(milliseconds: 50));
      await tap(tester, find.text('Home'));
      expect(http.lampOn, isTrue);
      expect(find.text('1 on'), findsOneWidget);
      // The lock was not asked to do anything.
      expect(http.asked.where((a) => a.startsWith('PUT')).length, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('lights: every one when none is picked, dimmed with a touch', (
      tester,
    ) async {
      await sweep(tester, 'homey_lights', {});
      expect(find.text('Hall lamp'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);

      // The middle of the bar is half.
      await tap(tester, find.byType(FractionallySizedBox));
      expect(http.dim, closeTo(0.5, 0.05));
      expect(http.lampOn, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('flows: a button each, started with a tap', (tester) async {
      await sweep(tester, 'homey_flows', {
        'flows': [
          {'flow': 'night', 'name': ''},
          {'flow': 'gone', 'name': 'Old one'},
        ],
      });
      expect(find.text('Goodnight'), findsOneWidget);
      expect(find.text('Not found'), findsOneWidget);

      await tap(tester, find.text('Goodnight'));
      expect(http.asked, contains('POST /api/manager/flow/flow/night/trigger'));
      expect(find.text('Started'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('colour, fans and climate: a card each, at every size', (
      tester,
    ) async {
      await sweep(tester, 'homey_colour', {}, devices: _house());
      expect(find.text('Strip'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);

      await sweep(tester, 'homey_fan', {}, devices: _house());
      expect(find.text('Fan'), findsOneWidget);
      expect(find.text('On · Sleep'), findsOneWidget);

      await sweep(tester, 'homey_climate', {}, devices: _house());
      expect(find.text('Thermostat · 54%'), findsOneWidget);
      expect(find.text('19.5 °C'), findsOneWidget);
      expect(find.text('21.0°'), findsOneWidget);
      // A step up stops at the most the thermostat takes.
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('21.2°'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the house, alerts and energy: at every size', (tester) async {
      await sweep(tester, 'homey_house', {}, devices: _house());
      expect(find.text('Everything'), findsOneWidget);
      // The strip, the fan and the kettle; never the lock.
      expect(find.text('3 on'), findsOneWidget);
      expect(find.text('Kitchen'), findsOneWidget);
      expect(find.text('2 on'), findsOneWidget);

      await sweep(tester, 'homey_alerts', {}, devices: _house());
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Battery 12%'), findsOneWidget);
      expect(find.text('Off line'), findsOneWidget);
      await sweep(tester, 'homey_alerts', {});
      expect(find.text('All quiet'), findsOneWidget);

      await sweep(tester, 'homey_energy', {}, devices: _house());
      expect(find.text('Drawing now'), findsOneWidget);
      expect(find.text('1.8 kW'), findsNWidgets(2));
      await sweep(tester, 'homey_energy', {});
      expect(find.textContaining('reports the power'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('moods, variables, people, timeline, history, the Homey', (
      tester,
    ) async {
      await sweep(
        tester,
        'homey_moods',
        {},
        answers: {
          'moods/mood': {
            'm': {'id': 'm', 'name': 'Evening', 'zone': 'hall'},
          },
        },
      );
      expect(find.text('Hall'), findsOneWidget);
      expect(find.text('Evening'), findsOneWidget);
      await sweep(tester, 'homey_moods', {}, answers: {'moods/mood': {}});
      expect(find.textContaining('No moods yet'), findsOneWidget);

      await sweep(
        tester,
        'homey_variables',
        {},
        answers: {
          'logic/variable': {
            'v': {'id': 'v', 'name': 'Guests staying', 'value': true},
            'n': {'id': 'n', 'name': 'Bin week', 'value': 2},
          },
        },
      );
      expect(find.text('Guests staying'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await sweep(
        tester,
        'homey_presence',
        {},
        answers: {
          'users/user': {
            'u': {'id': 'u', 'name': 'Vincent Willcox', 'present': true},
          },
        },
      );
      expect(find.text('Vincent'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);

      await sweep(
        tester,
        'homey_timeline',
        {},
        answers: {
          'notifications/notification': {
            'n': {
              'excerpt': 'Welcome home!',
              'ownerName': 'Timeline',
              'dateCreated': '2026-10-04T08:55:06.471Z',
            },
          },
        },
      );
      expect(find.text('Welcome home!'), findsOneWidget);

      const log = 'homey:manager:weather:temperature';
      await sweep(
        tester,
        'homey_history',
        {'log': log},
        answers: {
          'insights/log': [
            {
              'id': log,
              'ownerName': 'Weather',
              'title': 'Temperature',
              'units': '°C',
              'decimals': 2,
            },
          ],
          homeyLogPath(log, 'last24Hours'): {
            'values': [
              for (var i = 0; i < 12; i++)
                {'t': '2026-10-04T${10 + i}:00:00.000Z', 'v': 14 + i * 0.5},
            ],
          },
        },
      );
      expect(find.text('Weather · Temperature'), findsOneWidget);
      expect(find.text('19.50 °C'), findsOneWidget);
      await sweep(tester, 'homey_history', {});
      expect(find.textContaining('Pick what to chart'), findsOneWidget);

      await sweep(
        tester,
        'homey_system',
        {},
        answers: {
          'system/': {
            'homeyModelName': 'Homey Self-Hosted Server',
            'homeyVersion': '13.5.1',
            'uptime': 8542.26,
          },
          'system/memory': {'total': 4000, 'free': 3000},
          'system/storage': {'total': 1000, 'free': 100},
        },
      );
      expect(find.text('13.5.1'), findsOneWidget);
      expect(find.text('2 h 22 min'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('90%'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('without an address and key, every tile says where they go', (
      tester,
    ) async {
      homey = HomeyService(ConfigService());
      addTearDown(homey.dispose);
      final types = [
        for (final t in WidgetRegistry.all)
          if (t.type.startsWith('homey')) t.type,
      ];
      expect(types.length, 16);
      for (final type in types) {
        await draw(tester, type, tile(4, 2), const {});
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.textContaining('Settings → Home → Homey'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:immich_kiosk_pi/dashboard/widgets/countdowns_widget.dart';
import 'package:immich_kiosk_pi/services/carbon_service.dart';
import 'package:immich_kiosk_pi/services/govee_service.dart';
import 'package:immich_kiosk_pi/services/shopping_service.dart';
import 'package:immich_kiosk_pi/services/trains_service.dart';

void main() {
  group('countdowns', () {
    final today = DateTime(2026, 9, 25, 10);

    test('a day and month comes round every year', () {
      final xmas = Countdown.fromRow({
        'name': 'Christmas',
        'date': '25/12',
      }, today)!;
      expect(xmas.day, DateTime(2026, 12, 25));
      expect(xmas.yearly, isTrue);
      final gone = Countdown.fromRow({'name': 'Spring', 'date': '1/3'}, today)!;
      expect(gone.day, DateTime(2027, 3, 1));
    });

    test('a leap-day birthday falls on the 28th in other years', () {
      final c = Countdown.fromRow({'name': 'Leap', 'date': '29/02'}, today)!;
      expect(c.day, DateTime(2027, 2, 28));
    });

    test('one-offs drop off once past; the soonest comes first', () {
      final list = Countdown.upcoming([
        {'name': 'Christmas', 'date': '25/12'},
        {'name': 'Holiday', 'date': '2026-10-20'},
        {'name': 'Last week', 'date': '18/09/2026'},
        {'name': 'Today', 'date': '25/09/2026'},
        {'name': '', 'date': '1/1'},
        {'name': 'Nonsense', 'date': 'soon'},
      ], today);
      expect([for (final c in list) c.name], ['Today', 'Holiday', 'Christmas']);
    });
  });

  group('shopping', () {
    test('adds once, ticks, and clears ticked things after a while', () {
      var now = DateTime(2026, 9, 25, 9);
      final s = ShoppingService(clock: () => now, persist: false);
      final milk = s.add('  Milk ')!;
      s.add('Bread');
      s.add('milk'); // already there
      expect([for (final i in s.items) i.text], ['Milk', 'Bread']);
      expect(s.toGet, 2);
      s.toggle(milk.id);
      expect(
        [for (final i in s.items) (i.text, i.done)],
        [('Bread', false), ('Milk', true)],
      );
      // Adding it again puts it back on the list.
      s.add('Milk');
      expect(s.toGet, 2);
      s.toggle(milk.id);
      now = now.add(ShoppingService.keepTicked + const Duration(minutes: 1));
      s.add('Eggs');
      expect([for (final i in s.items) i.text], ['Bread', 'Eggs']);
      s.dispose();
    });

    test('keeps it across a restart', () async {
      final dir = Directory.systemTemp.createTempSync('shop');
      addTearDown(() => dir.deleteSync(recursive: true));
      final a = ShoppingService(file: '${dir.path}/s.json');
      a.add('Coffee beans');
      await a.saved;
      final b = ShoppingService(file: '${dir.path}/s.json');
      await b.load();
      expect(b.items.single.text, 'Coffee beans');
      a.dispose();
      b.dispose();
    });
  });

  group('grid carbon', () {
    test('finds the postcode district', () {
      expect(outwardCode('CO1 1ZY'), 'CO1');
      expect(outwardCode('me168ab'), 'ME16');
      expect(outwardCode('SW1A 1AA'), 'SW1A');
      expect(outwardCode('ME16'), 'ME16');
      expect(outwardCode('Colchester'), isNull);
    });

    test('reads the forecast and picks the greenest three hours', () {
      final start = DateTime.utc(2026, 9, 25, 7);
      final grams = [
        248,
        240,
        230,
        200,
        150,
        120,
        110,
        100,
        105,
        130,
        170,
        210,
      ];
      final f = CarbonForecast.fromApi({
        'data': {
          'shortname': 'East England',
          'data': [
            for (var i = 0; i < grams.length; i++)
              {
                'from': start
                    .add(Duration(minutes: 30 * i))
                    .toIso8601String()
                    .replaceFirst(':00.000Z', 'Z'),
                'intensity': {
                  'forecast': grams[i],
                  'index': grams[i] > 200 ? 'high' : 'low',
                },
              },
          ],
        },
      });
      expect(f.region, 'East England');
      expect(f.slots, hasLength(12));
      final now = start.add(const Duration(minutes: 10)).toLocal();
      expect(f.at(now)!.grams, 248);
      final best = f.greenest(now)!;
      // 150 120 110 100 105 130 — the six lowest in a row, from 09:00 UTC.
      expect(best.from, start.add(const Duration(hours: 2)).toLocal());
      expect(best.average, 119);
    });
  });

  group('trains', () {
    Map<String, dynamic> service(
      String time, {
      String? expected,
      bool cancelled = false,
      String display = 'CALL',
      String platform = '2',
      int? late,
    }) => {
      'temporalData': {
        'departure': {
          'scheduleAdvertised': time,
          'realtimeForecast': ?expected,
          'isCancelled': cancelled,
          'realtimeAdvertisedLateness': ?late,
        },
        'displayAs': display,
      },
      'locationMetadata': {
        'platform': {'planned': platform},
      },
      'destination': [
        {
          'location': {'description': 'London Victoria'},
        },
      ],
      'scheduleMetadata': {
        'inPassengerService': true,
        'modeType': 'TRAIN',
        'operator': {'name': 'Southeastern'},
      },
      'reasons': cancelled
          ? [
              {'type': 'CANCEL', 'shortText': 'a fault with the signalling'},
            ]
          : [],
    };

    final board = {
      'query': {
        'location': {'description': 'Maidstone East'},
      },
      'services': [
        service(
          '2026-09-25T08:12:00+01:00',
          expected: '2026-09-25T08:19:00+01:00',
          late: 7,
        ),
        service('2026-09-25T07:48:00+01:00'),
        service('2026-09-25T08:48:00+01:00', cancelled: true),
        service('2026-09-25T08:30:00+01:00', display: 'PASS'),
      ],
    };

    test('reads a station board', () {
      final b = parseBoard(board);
      expect(b.station, 'Maidstone East');
      expect(b.departures, hasLength(3));
      final first = b.departures.first;
      expect(first.scheduled.toUtc(), DateTime.utc(2026, 9, 25, 6, 48));
      expect(first.platform, '2');
      expect(first.late, isFalse);
      expect(b.departures[1].late, isTrue);
      expect(
        b.departures[1].expected!.toUtc(),
        DateTime.utc(2026, 9, 25, 7, 19),
      );
      expect(b.departures[2].cancelled, isTrue);
      expect(b.departures[2].reason, 'a fault with the signalling');
    });

    test('swaps a refresh token for an access token, and keeps it', () async {
      TrainsClient.forgetTokens();
      var swaps = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) {
        final auth = req.headers.value('authorization');
        final res = req.response..headers.contentType = ContentType.json;
        if (req.uri.path == '/api/get_access_token' &&
            auth == 'Bearer REFRESH') {
          swaps++;
          res.write(
            jsonEncode({
              'token': 'ACCESS',
              'validUntil': DateTime.now()
                  .add(const Duration(hours: 1))
                  .toUtc()
                  .toIso8601String(),
            }),
          );
        } else if (req.uri.path == '/gb-nr/location' &&
            auth == 'Bearer ACCESS') {
          expect(req.uri.queryParameters['code'], 'MDE');
          expect(req.uri.queryParameters['filterTo'], 'VIC');
          res.write(jsonEncode(board));
        } else {
          res.statusCode = 401;
        }
        res.close();
      });
      final client = TrainsClient(base: 'http://127.0.0.1:${server.port}');
      final b = await client.board(token: 'REFRESH', from: 'mde', to: 'vic');
      expect(b.departures, hasLength(3));
      await client.board(token: 'REFRESH', from: 'mde', to: 'vic');
      expect(swaps, 1, reason: 'the access token is reused until it expires');

      // A long-life access token is used as it is.
      final direct = await client.board(
        token: 'ACCESS',
        from: 'MDE',
        to: 'VIC',
      );
      expect(direct.station, 'Maidstone East');

      // And a token that is neither says so.
      expect(
        () => client.board(token: 'WRONG', from: 'MDE'),
        throwsA(
          isA<TrainsError>().having(
            (e) => e.message,
            'message',
            contains('token'),
          ),
        ),
      );
    });
  });

  group('lights', () {
    test('finds devices on the home network and reads their state', () {
      final g = GoveeService(listen: false);
      g.handleLocalReply(
        jsonEncode({
          'msg': {
            'cmd': 'scan',
            'data': {'ip': '10.0.0.40', 'device': 'AA:BB', 'sku': 'H61E1'},
          },
        }),
        '10.0.0.40',
      );
      g.handleLocalReply(
        jsonEncode({
          'msg': {
            'cmd': 'devStatus',
            'data': {
              'onOff': 1,
              'brightness': 70,
              'color': {'r': 255, 'g': 122, 'b': 182},
            },
          },
        }),
        '10.0.0.40',
      );
      final d = g.devices.single;
      expect(d.local, isTrue);
      expect(d.on, isTrue);
      expect(d.brightness, 70);
      expect(d.colour, const Color(0xFFFF7AB6));
      g.handleLocalReply('not json', '10.0.0.40');
      g.dispose();
    });

    test('merges Govee’s own list, and reads state from it', () {
      final g = GoveeService(listen: false);
      g.handleLocalReply(
        jsonEncode({
          'msg': {
            'cmd': 'scan',
            'data': {'ip': '10.0.0.40', 'device': 'AA:BB', 'sku': 'H61E1'},
          },
        }),
        '10.0.0.40',
      );
      g.mergeCloudDevices({
        'data': [
          {
            'device': 'AA:BB',
            'sku': 'H61E1',
            'deviceName': 'LED strip',
            'capabilities': [
              {
                'type': 'devices.capabilities.on_off',
                'instance': 'powerSwitch',
              },
              {'type': 'devices.capabilities.range', 'instance': 'brightness'},
              {
                'type': 'devices.capabilities.color_setting',
                'instance': 'colorRgb',
              },
            ],
          },
          {
            'device': 'CC:DD',
            'sku': 'H5082',
            'deviceName': 'Lamp plug',
            'capabilities': [
              {
                'type': 'devices.capabilities.on_off',
                'instance': 'powerSwitch',
              },
            ],
          },
        ],
      });
      expect([for (final d in g.devices) d.name], ['Lamp plug', 'LED strip']);
      final strip = g.devices.last;
      expect(strip.local && strip.cloud, isTrue);
      final plug = g.devices.first;
      expect(plug.canDim || plug.canColour, isFalse);
      g.applyCloudState(plug, {
        'payload': {
          'capabilities': [
            {
              'type': 'devices.capabilities.online',
              'instance': 'online',
              'state': {'value': true},
            },
            {
              'type': 'devices.capabilities.on_off',
              'instance': 'powerSwitch',
              'state': {'value': 0},
            },
          ],
        },
      });
      expect(plug.on, isFalse);
      expect(plug.online, isTrue);
      g.dispose();
    });
  });
}

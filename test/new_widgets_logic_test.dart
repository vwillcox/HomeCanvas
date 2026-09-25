import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/services/air_quality_service.dart';
import 'package:home_canvas/services/bin_schedule.dart';
import 'package:home_canvas/services/bins_service.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/dashboard_service.dart';
import 'package:home_canvas/services/notes_service.dart';
import 'package:home_canvas/services/service_checks.dart';
import 'package:home_canvas/services/sun_moon.dart';
import 'package:home_canvas/services/system_stats.dart';
import 'package:home_canvas/services/timer_service.dart';

void main() {
  group('sun', () {
    // London, midsummer 2026: sunrise 03:43 UTC, sunset 20:21 UTC.
    test('rises and sets when the almanac says', () {
      final d = SunMoon.sun(DateTime(2026, 6, 21), 51.5074, -0.1278);
      final rise = d.sunrise!.toUtc(), set = d.sunset!.toUtc();
      expect(
        rise.difference(DateTime.utc(2026, 6, 21, 3, 43)).inMinutes.abs(),
        lessThanOrEqualTo(3),
      );
      expect(
        set.difference(DateTime.utc(2026, 6, 21, 20, 21)).inMinutes.abs(),
        lessThanOrEqualTo(3),
      );
    });

    test('in late September the days shorten by a few minutes a day', () {
      final today = SunMoon.sun(DateTime(2026, 9, 24), 51.27, 0.52);
      final before = SunMoon.sun(DateTime(2026, 9, 23), 51.27, 0.52);
      final change = today.dayLength - before.dayLength;
      expect(change.inSeconds, inInclusiveRange(-5 * 60, -3 * 60));
      expect(today.dayLength.inHours, 12);
    });

    test('a polar winter has no sunrise, and says so', () {
      final d = SunMoon.sun(DateTime(2026, 12, 21), 69.65, 18.96); // Tromsø
      expect(d.sunrise, isNull);
      expect(d.polar, isFalse);
      expect(d.dayLength, Duration.zero);
    });

    test('progress runs from 0 at sunrise to 1 at sunset', () {
      final d = SunMoon.sun(DateTime(2026, 9, 24), 51.27, 0.52);
      expect(d.progress(d.sunrise!), closeTo(0, 0.001));
      expect(d.progress(d.sunset!), closeTo(1, 0.001));
      expect(d.progress(d.solarNoon), closeTo(0.5, 0.02));
    });
  });

  group('moon', () {
    test('knows a full moon and a new moon', () {
      // 23 April 2024 23:49 UTC full; 8 April 2024 18:21 UTC new (the eclipse).
      expect(
        SunMoon.moonPhase(DateTime.utc(2024, 4, 23, 23, 49)),
        closeTo(0.5, 0.03),
      );
      final newMoon = SunMoon.moonPhase(DateTime.utc(2024, 4, 8, 18, 21));
      expect(newMoon < 0.03 || newMoon > 0.97, isTrue);
      expect(SunMoon.phaseName(0.5), 'Full moon');
      expect(SunMoon.phaseName(0.1), 'Waxing crescent');
      expect(SunMoon.phaseName(0.62), 'Waning gibbous');
      expect(SunMoon.illumination(0.5), closeTo(1, 1e-9));
    });

    test('the next full moon is less than a month away', () {
      final from = DateTime.utc(2026, 9, 24);
      final next = SunMoon.next(0.5, from);
      expect(next.isAfter(from), isTrue);
      expect(next.difference(from).inDays, lessThan(30));
      expect(SunMoon.moonPhase(next), closeTo(0.5, 0.001));
    });
  });

  group('bins', () {
    final rubbish = Bin(
      name: 'Rubbish',
      colour: Colors.grey,
      first: DateTime(2026, 10, 1),
      everyWeeks: 2,
    );
    final recycling = Bin(
      name: 'Recycling',
      colour: Colors.blue,
      first: DateTime(2026, 9, 24),
      everyWeeks: 2,
    );
    final food = Bin(
      name: 'Food',
      colour: Colors.green,
      first: DateTime(2026, 9, 3),
      everyWeeks: 1,
    );
    final all = [rubbish, recycling, food];

    test('the evening before, it is time to put them out', () {
      final c = BinCollection.next(all, DateTime(2026, 9, 30, 18))!;
      expect(c.day, DateTime(2026, 10, 1));
      expect(c.stage, BinStage.tonight);
      expect(c.names, 'rubbish and food');
    });

    test('earlier that day, it is only coming up', () {
      final c = BinCollection.next(all, DateTime(2026, 9, 30, 9))!;
      expect(c.stage, BinStage.later);
    });

    test('on the morning it is today; after the lorry, the next one', () {
      expect(
        BinCollection.next(all, DateTime(2026, 10, 1, 8))!.stage,
        BinStage.today,
      );
      final after = BinCollection.next(all, DateTime(2026, 10, 1, 13))!;
      expect(after.day, DateTime(2026, 10, 8));
      expect(after.names, 'recycling and food');
    });

    test('a week is seven days across the clocks going back', () {
      final weekly = Bin(
        name: 'Food',
        colour: Colors.green,
        first: DateTime(2026, 10, 22),
      );
      expect(
        weekly.nextOnOrAfter(DateTime(2026, 10, 26)),
        DateTime(2026, 10, 29),
      );
    });

    test('reads dates the way councils write them', () {
      expect(Bin.parseDay('2026-10-01'), DateTime(2026, 10, 1));
      expect(Bin.parseDay('1/10/2026'), DateTime(2026, 10, 1));
      expect(Bin.parseDay('01-10-2026'), DateTime(2026, 10, 1));
      expect(Bin.parseDay('31/02/2026'), isNull);
      expect(Bin.fromRow({'name': 'Rubbish', 'first': ''}), isNull);
      expect(
        Bin.fromRow({
          'name': 'Rubbish',
          'first': '2026-10-01',
          'everyWeeks': '2',
          'colour': '#3A3E47',
        })!.colour,
        const Color(0xFF3A3E47),
      );
    });

    test('says it once, at the time asked, the night before', () {
      var now = DateTime(2026, 9, 30, 19, 0, 10);
      final said = <String>[];
      final config = ConfigService();
      config.config.dashboard.widgets = [
        DashboardWidgetConfig(
          id: 'b',
          type: 'bins',
          x: 0,
          y: 0,
          width: 3,
          height: 2,
          options: {
            'speakAt': '19:00',
            'bins': [
              {'name': 'Rubbish', 'first': '2026-10-01', 'everyWeeks': 2},
            ],
          },
        ),
      ];
      final service = BinsService(
        config,
        speak: (t) async => said.add(t),
        clock: () => now,
      );
      service.check();
      service.check();
      expect(said, [
        'Tomorrow is bin day: rubbish. Remember to put it out tonight.',
      ]);

      // Not a word if they are already out.
      final quiet = <String>[];
      final second = BinsService(
        config,
        speak: (t) async => quiet.add(t),
        clock: () => now,
      )..toggleOut('b', DateTime(2026, 10, 1));
      second.check();
      expect(quiet, isEmpty);

      // And nothing at other times.
      now = DateTime(2026, 9, 30, 18, 0);
      final early = <String>[];
      BinsService(
        config,
        speak: (t) async => early.add(t),
        clock: () => now,
      ).check();
      expect(early, isEmpty);
    });
  });

  group('timers', () {
    test('run down, finish, and say so until dismissed', () {
      var now = DateTime(2026, 9, 24, 12);
      final said = <String>[];
      var woke = 0;
      final s = TimerService(
        speak: (t) async => said.add(t),
        onFinished: () async => woke++,
        clock: () => now,
      );
      final t = s.start(const Duration(minutes: 5));
      expect(t.label, '5 minutes');
      now = now.add(const Duration(minutes: 2));
      s.tick();
      expect(t.remaining(now), const Duration(minutes: 3));
      now = now.add(const Duration(minutes: 3));
      s.tick();
      expect(t.finished, isTrue);
      expect(woke, 1);
      expect(said, ['Your 5 minute timer is done.']);
      now = now.add(TimerService.repeatEvery);
      s.tick();
      expect(said, hasLength(2));
      for (var i = 0; i < 10; i++) {
        now = now.add(TimerService.repeatEvery);
        s.tick();
      }
      expect(said, hasLength(TimerService.maxAnnouncements));
      s.remove(t.id);
      expect(s.timers, isEmpty);
      s.dispose();
    });

    test('pause holds the time; resuming carries on from it', () {
      var now = DateTime(2026, 9, 24, 12);
      final s = TimerService(clock: () => now);
      final t = s.start(const Duration(minutes: 10), label: 'Pasta');
      now = now.add(const Duration(minutes: 4));
      s.togglePause(t.id);
      now = now.add(const Duration(minutes: 30));
      s.tick();
      expect(t.remaining(now), const Duration(minutes: 6));
      s.togglePause(t.id);
      s.addTime(t.id, const Duration(minutes: 1));
      expect(t.remaining(now), const Duration(minutes: 7));
      expect(TimerService.announcement(t), 'The pasta timer is done.');
      s.dispose();
    });

    test('presets read names, minutes, seconds and hours', () {
      final p = TimerPreset.parse('Eggs=7, Pasta=11, 5, 90s, 1h, nonsense, =');
      expect(
        [for (final x in p) x.chip],
        ['Eggs', 'Pasta', '5 min', '90s', '1h'],
      );
      expect(p[3].length, const Duration(seconds: 90));
      expect(p[4].length, const Duration(hours: 1));
    });
  });

  group('notes', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('notes'));
    tearDown(() => dir.deleteSync(recursive: true));

    test(
      'newest first, kept across a restart, and taken down on request',
      () async {
        final file = '${dir.path}/notes.json';
        var now = DateTime(2026, 9, 24, 8);
        final a = NotesService(file: file, clock: () => now);
        final first = a.add('Dentist moved to Thursday 4pm', from: 'Vincent')!;
        now = now.add(const Duration(minutes: 5));
        a.add('Parcel is in the shed');
        expect(a.add('   '), isNull);
        await a.saved;

        final b = NotesService(file: file, clock: () => now);
        await b.load();
        expect(
          [for (final n in b.notes) n.text],
          ['Parcel is in the shed', 'Dentist moved to Thursday 4pm'],
        );
        expect(b.notes.last.from, 'Vincent');
        expect(b.remove(first.id), isTrue);
        expect(b.notes, hasLength(1));
        await b.saved;
      },
    );

    test('old notes clear themselves, and long ones are cut', () async {
      var now = DateTime(2026, 9, 1);
      final s = NotesService(file: '${dir.path}/n.json', clock: () => now);
      s.add('Old news');
      now = now.add(NotesService.keepFor + const Duration(days: 1));
      final long = s.add('x' * 500)!;
      expect(long.text.length, NotesService.maxLength);
      expect([for (final n in s.notes) n.text], [long.text]);
      await s.saved;
    });
  });

  group('air quality', () {
    test('bands the index and the pollen the way forecasts do', () {
      final air = AirQuality.fromOpenMeteo({
        'current': {
          'european_aqi': 26,
          'uv_index': 1.45,
          'grass_pollen': 62.0,
          'birch_pollen': 0.0,
          'alder_pollen': 0.0,
          'olive_pollen': null,
          'mugwort_pollen': 0.8,
          'ragweed_pollen': 0.0,
        },
      }, DateTime(2026, 9, 24));
      expect(air.aqiWord, 'Fair');
      expect(air.uvWord, 'low');
      expect(
        [for (final p in air.pollen) p.level],
        [Level.high, Level.none, Level.none],
      );
    });
  });

  group('home lab', () {
    test('reads this machine from the kernel', () {
      expect(
        LocalStats.parseCpu('cpu  100 0 50 800 50 0 0 0 0 0\ncpu0 1 2 3 4'),
        (1000, 850),
      );
      expect(
        LocalStats.parseMemory(
          'MemTotal: 8000 kB\nMemFree: 1000 kB\nMemAvailable: 2000 kB\n',
        ),
        75,
      );
      expect(
        LocalStats.parseDf(
          'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/root 100 38 62 38% /\n',
        ),
        38,
      );
      final c = LocalStats.parseDocker('homeassistant\trunning\nold\texited\n');
      expect(
        [for (final x in c) (x.name, x.running)],
        [('homeassistant', true), ('old', false)],
      );
    });

    test('reads another machine through Glances', () {
      final m = GlancesClient.fromGlances(
        'casaos',
        quicklook: {'cpu': 8.2, 'mem': 44.1},
        fs: [
          {'mnt_point': '/boot', 'percent': 90},
          {'mnt_point': '/', 'percent': 71.3},
        ],
        sensors: [
          {'label': 'cpu', 'type': 'temperature_core', 'value': 41},
          {'label': 'fan', 'type': 'fan_speed', 'value': 1200},
        ],
        uptime: '99 days, 1:02:03',
        containers: [
          {'name': 'immich', 'status': 'running'},
          {'name': 'backup', 'status': 'exited'},
        ],
      );
      expect(m.cpu, 8.2);
      expect(m.disk, 71.3);
      expect(m.temperature, 41);
      expect(m.uptime!.inDays, 99);
      expect(m.running, 1);
      expect(m.stopped, 1);
      expect(shortUptime(m.uptime!), '99 d');
    });

    test('reads a Glances 3 machine, as apt installs it', () async {
      // Answers only on /api/3, and lists containers under "docker".
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final routes = <String, Object>{
        '/api/3/quicklook': {'cpu': 12.5, 'mem': 40.0},
        '/api/3/fs': [
          {'mnt_point': '/', 'percent': 55.0},
        ],
        '/api/3/sensors': [
          {'label': 'Package id 0', 'type': 'temperature_core', 'value': 47},
        ],
        '/api/3/uptime': '4 days, 1:02:03',
        '/api/3/docker': {
          'containers': [
            {'name': 'blog', 'Status': 'running'},
            {'name': 'audiobookshelf', 'Status': 'running'},
          ],
        },
      };
      server.listen((req) {
        final body = routes[req.uri.path];
        req.response.statusCode = body == null ? 404 : 200;
        req.response.headers.contentType = ContentType.json;
        if (body != null) req.response.write(jsonEncode(body));
        req.response.close();
      });
      final m = await GlancesClient('127.0.0.1:${server.port}').read('casaos');
      expect(m.reachable, isTrue);
      expect(m.cpu, 12.5);
      expect(m.disk, 55);
      expect(m.temperature, 47);
      expect(m.uptime!.inDays, 4);
      expect(m.running, 2);
    });

    test('shows the data disks, with SMART health beside them', () {
      final m = GlancesClient.fromGlances(
        'NAS',
        quicklook: {'cpu': 4.4, 'mem': 32.9},
        fs: [
          {
            'device_name': '/dev/sdb2',
            'fs_type': 'ext4',
            'mnt_point': '/',
            'size': 29654900736,
            'used': 12063862784,
            'percent': 42.5,
          },
          {
            'device_name': '/dev/sdb1',
            'fs_type': 'vfat',
            'mnt_point': '/boot/firmware',
            'size': 535805952,
            'used': 1,
            'percent': 12,
          },
          {
            'device_name': '/dev/sda2',
            'fs_type': 'fuseblk',
            'mnt_point': '/mnt/sata',
            'size': 8001545039872,
            'used': 6594209906688,
            'percent': 82.4,
          },
          {
            'device_name': 'overlay',
            'fs_type': 'overlay',
            'mnt_point': '/var/lib/docker/overlay2/x/merged',
            'size': 29654900736,
            'used': 1,
            'percent': 42.5,
          },
        ],
        smart: [
          {
            'DeviceName': 'sda ST8000DM004-2U9188',
            '5': {
              'name': 'Reallocated_Sector_Ct',
              'raw': '0',
              'value': 100,
              'threshold': 10,
              'when_failed': '-',
            },
            '9': {
              'name': 'Power_On_Hours',
              'raw': '12011',
              'value': 87,
              'threshold': 0,
              'when_failed': '-',
            },
            '194': {
              'name': 'Temperature_Celsius',
              'raw': '34 (0 18 0 0 0)',
              'value': 34,
              'threshold': 0,
              'when_failed': '-',
            },
            '197': {
              'name': 'Current_Pending_Sector',
              'raw': '8',
              'value': 100,
              'threshold': 0,
              'when_failed': '-',
            },
          },
          {
            'DeviceName': 'sdb Samsung SSD',
            '5': {
              'name': 'Reallocated_Sector_Ct',
              'raw': '0',
              'value': 100,
              'threshold': 10,
              'when_failed': '',
            },
          },
        ],
      );
      expect([for (final d in m.disks) d.label], ['System', 'sata']);
      final sata = m.disks[1];
      expect(sata.device, 'sda');
      expect(shortSize(sata.size), '8 TB');
      expect(shortSize(sata.used), '6.6 TB');
      expect(sata.health!.state, DiskState.warning);
      expect(sata.health!.temperature, 34);
      expect(sata.health!.powerOnHours, 12011);
      expect(sata.health!.concern, '8 pending');
      expect(m.disks[0].health!.state, DiskState.healthy);
      expect(m.worstDisk, DiskState.warning);
    });

    test('reads SMART as this Glances sends it: values as padded text', () {
      // The NAS's own drive, as Glances 4.3.1 reported it.
      final h = DiskHealth.fromGlances([
        {
          'DeviceName': 'sda ST8000DM004-2U9188',
          '1': {
            'name': 'Raw_Read_Error_Rate',
            'raw': '23369400',
            'value': '074',
            'worst': 64,
            'threshold': 6,
            'when_failed': '-',
          },
          '5': {
            'name': 'Reallocated_Sector_Ct',
            'raw': '0',
            'value': '100',
            'threshold': 10,
            'when_failed': '-',
          },
          '9': {
            'name': 'Power_On_Hours',
            'raw': '23152h+02m+54.791s',
            'value': '074',
            'threshold': 0,
            'when_failed': '-',
          },
          '190': {
            'name': 'Airflow_Temperature_Cel',
            'raw': '40 (Min/Max 32/47)',
            'value': '060',
            'threshold': 40,
            'when_failed': '-',
          },
          '194': {
            'name': 'Temperature_Celsius',
            'raw': '40 (0 21 0 0 0)',
            'value': '040',
            'threshold': 0,
            'when_failed': '-',
          },
          '197': {
            'name': 'Current_Pending_Sector',
            'raw': '0',
            'value': '100',
            'threshold': 0,
            'when_failed': '-',
          },
        },
      ]).single;
      expect(h.device, 'sda');
      expect(h.model, 'ST8000DM004-2U9188');
      expect(h.state, DiskState.healthy);
      expect(h.temperature, 40);
      expect(h.powerOnHours, 23152);
    });

    test('a drive past its SMART threshold is failing', () {
      final h = DiskHealth.fromGlances([
        {
          'DeviceName': 'sda Old disk',
          '5': {
            'name': 'Reallocated_Sector_Ct',
            'raw': '2000',
            'value': 5,
            'threshold': 10,
            'when_failed': 'FAILING_NOW',
          },
        },
      ]);
      expect(h.single.state, DiskState.failing);
      expect(h.single.concern, 'failing · 2000 reallocated');
    });

    test('names drives the way the kernel does', () {
      expect(baseDevice('/dev/sda2'), 'sda');
      expect(baseDevice('/dev/nvme0n1p2'), 'nvme0n1');
      expect(baseDevice('/dev/mmcblk0p2'), 'mmcblk0');
      expect(baseDevice('sdb'), 'sdb');
      final local = LocalStats.parseDfAll(
        'Filesystem Type 1B-blocks Used Available Use% Mounted on\n'
        '/dev/mmcblk0p2 ext4 62000000000 20000000000 40000000000 33% /\n'
        '/dev/mmcblk0p1 vfat 536000000 60000000 476000000 12% /boot/firmware\n'
        'tmpfs tmpfs 800000000 0 800000000 0% /run\n'
        '/dev/sda1 ext4 1000000000000 250000000000 750000000000 25% /mnt/backup drive\n',
      );
      expect(
        [for (final d in local) (d.label, d.percent)],
        [('System', 33), ('backup drive', 25)],
      );
    });

    test('services say how they are checked', () {
      final web = ServiceTarget.fromRow({
        'name': 'Immich',
        'target': 'https://immich.lan',
      })!;
      expect(web.isWeb, isTrue);
      final port = ServiceTarget.fromRow({'target': '10.0.0.76:445'})!;
      expect(port.hostPort, ('10.0.0.76', 445));
      expect(port.name, '10.0.0.76:445');
      final ping = ServiceTarget.fromRow({
        'target': 'macmini.local',
        'mac': 'AA:BB:CC:DD:EE:FF',
      })!;
      expect(ping.hostPort, isNull);
      expect(ping.mac, 'aabbccddeeff');
      expect(ServiceTarget.fromRow({'target': ' '}), isNull);
      expect(
        ServiceChecker.parsePing(
          '64 bytes from 10.0.0.1: icmp_seq=1 ttl=64 time=2.31 ms',
        ),
        2.31,
      );
      expect(formatLatency(const Duration(milliseconds: 38)), '38 ms');
      expect(formatLatency(const Duration(milliseconds: 1240)), '1.2 s');
    });

    test('a machine that is listening answers a port check', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final r = await const ServiceChecker().check(
        ServiceTarget(name: 'x', target: '127.0.0.1:${server.port}'),
      );
      expect(r.state, CheckState.up);
      await server.close();
      final down = await const ServiceChecker().check(
        ServiceTarget(name: 'x', target: '127.0.0.1:${server.port}'),
      );
      expect(down.state, CheckState.down);
    });
  });

  test('notes are only posted from the notes page itself', () {
    expect(DashboardService.sameOrigin(null, '192.168.1.57:8090'), isTrue);
    expect(
      DashboardService.sameOrigin(
        'http://192.168.1.57:8090',
        '192.168.1.57:8090',
      ),
      isTrue,
    );
    expect(
      DashboardService.sameOrigin('https://evil.example', '192.168.1.57:8090'),
      isFalse,
    );
    expect(
      DashboardService.sameOrigin(
        'http://192.168.1.57:9999',
        '192.168.1.57:8090',
      ),
      isFalse,
    );
  });
}

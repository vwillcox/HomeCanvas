import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/config/app_config.dart';
import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/schedule.dart';
import 'package:home_canvas/services/art_matrix_service.dart';
import 'package:home_canvas/services/home_control.dart';
import 'package:home_canvas/services/routines.dart';
import 'package:home_canvas/services/tv_service.dart';
import 'package:home_canvas/services/vidaa_client.dart';
import 'package:home_canvas/services/voice_commands.dart';
import 'package:home_canvas/services/wake_on_lan.dart';

VoiceCommands _panel({List<HomeRoutine>? routines}) => VoiceCommands(
  pageCount: 2,
  pages: const [
    DashboardPage(name: 'Main'),
    DashboardPage(name: 'Media'),
  ],
  widgets: [
    for (final (i, t) in ['clock', 'tv', 'news'].indexed)
      DashboardWidgetConfig(
        id: '$t-$i',
        type: t,
        x: 0,
        y: 0,
        width: 3,
        height: 2,
        page: 0,
      ),
  ],
  nameOf: (type) =>
      const {'clock': 'Clock', 'tv': 'TV remote', 'news': 'News feed'}[type],
  routines: routines ?? HomeRoutine.defaults(),
);

/// What [heard] switches, as "tv lights off", or null for no switching.
String? _switched(String heard) {
  final a = _panel().resolve(heard);
  if (a is! VoiceSwitch) return null;
  return [
    for (final t in HomeThing.values)
      if (a.things.contains(t)) t.name,
    a.on ? 'on' : 'off',
  ].join(' ');
}

String? _routine(String heard, {List<HomeRoutine>? routines}) {
  final a = _panel(routines: routines).resolve(heard);
  return a is VoiceRoutine ? a.routine.name : null;
}

void main() {
  group('the TV and the lights, switched by voice', () {
    test('the TV, said however', () {
      for (final said in [
        'hey canvas turn the tv on',
        'Hey Canvas, turn on the TV.',
        'hey canvas switch the television on',
        'hey canvas power on the telly',
        'hey canvas tv on',
        'hey canvas put the tv on',
      ]) {
        expect(_switched(said), 'tv on', reason: said);
      }
      for (final said in [
        'hey canvas turn the tv off',
        'hey canvas, turn off the TV',
        'hey canvas switch off the telly please',
        'hey canvas tv off',
        'hey canvas power the television off',
        'hey canvas shut the tv off',
        // Said after a pause, without the wake words.
        'turn the tv off',
      ]) {
        expect(_switched(said), 'tv off', reason: said);
      }
    });

    test('the lights: every one of them, when no room is said', () {
      for (final said in [
        'hey canvas turn off the lights',
        'hey canvas turn the lights off',
        'hey canvas lights off',
        'hey canvas turn off all the lights',
        'hey canvas lights out',
        'hey canvas kill the lights',
        'hey canvas switch all the lights off in the house',
      ]) {
        expect(_switched(said), 'lights off', reason: said);
      }
      expect(_switched('hey canvas turn the lights on'), 'lights on');
      expect(_switched('hey canvas lights on'), 'lights on');
    });

    test('both at once', () {
      expect(
        _switched('hey canvas turn the tv and the lights off'),
        'tv lights off',
      );
      expect(
        _switched('hey canvas turn off the lights and the telly'),
        'tv lights off',
      );
    });

    test('a room or a name with them is left to Home Assistant', () {
      for (final said in [
        'hey canvas turn off the bedroom lights',
        'hey canvas turn the lounge lights off',
        'hey canvas turn the bedroom tv off',
        // After a pause, with no wake words to show where it begins — and
        // still not "tv off", which is the other television.
        'bedroom tv off',
        'hey canvas turn lounge one off',
        'hey canvas turn the lamp on',
        'hey canvas turn it off',
      ]) {
        expect(_panel().resolve(said), isNull, reason: said);
      }
    });

    test('what is not switching is what it was', () {
      expect(_switched('hey canvas turn the tv volume up'), isNull);
      expect(
        _panel().resolve('hey canvas open the tv remote'),
        isA<VoiceGo>().having((g) => g.place, 'place', VoicePlace.remote),
      );
      expect(
        _panel().resolve('hey canvas turn on the tv remote'),
        isA<VoiceGo>(),
      );
      expect(
        _panel().resolve('hey canvas show the telly'),
        isA<VoiceShowPage>(),
      );
      // "On and off" is no answer.
      expect(_switched('hey canvas turn the lights on and off'), isNull);
    });
  });

  group('a routine, by what sets it off', () {
    test('bedtime, said however', () {
      for (final said in [
        "hey canvas I'm going to bed",
        'Hey Canvas, I’m going to bed.',
        'hey canvas I am going to bed now',
        "hey canvas I'm off to bed",
        'hey canvas goodnight',
        'hey canvas good night',
        'hey canvas good night everyone',
        'hey canvas night night',
        'hey canvas bedtime',
        'hey canvas bed time',
        'hey canvas time for bed',
        "I'm going to bed",
      ]) {
        expect(_routine(said), 'Bedtime', reason: said);
      }
    });

    test('the whole of what was said, not part of it', () {
      for (final said in [
        'hey canvas turn off the bed light',
        'hey canvas when is bedtime',
        'hey canvas show the news',
      ]) {
        expect(_routine(said), isNull, reason: said);
      }
    });

    test(
      'one of the panel’s own phrases, taken for a routine, is the routine',
      () {
        final morning = HomeRoutine(name: 'Morning', phrases: ['good morning']);
        expect(
          _routine('hey canvas good morning', routines: [morning]),
          'Morning',
        );
        // Without it, "good morning" is the day at a glance, as it was.
        expect(
          _panel(routines: const []).resolve('hey canvas good morning'),
          isA<VoiceGo>().having((g) => g.place, 'place', VoicePlace.today),
        );
      },
    );

    test('with none set up, nothing is a routine', () {
      expect(_routine('hey canvas goodnight', routines: const []), isNull);
    });
  });

  group('routines in the config', () {
    test('a config without them starts with Bedtime', () {
      final routines = AppConfig.fromJson(const {}).routines;
      expect(routines.map((r) => r.name), ['Bedtime']);
      expect(routines.single.steps, {
        RoutineStep.lightsOff,
        RoutineStep.tvOff,
        RoutineStep.artMatrixOff,
        RoutineStep.musicOff,
        RoutineStep.screenOff,
      });
    });

    test('one that has deleted them all keeps none', () {
      expect(AppConfig.fromJson(const {'routines': []}).routines, isEmpty);
    });

    test('saved and read back the same', () {
      final r = HomeRoutine(
        name: 'Film night',
        phrases: ['film night', 'movie time'],
        steps: {RoutineStep.tvOn, RoutineStep.lightsOff},
        ask: ['turn on the lamp'],
        reply: 'Enjoy the film',
      );
      final config = AppConfig.fromJson(
        AppConfig(routines: [r]).toJson().cast<String, dynamic>(),
      );
      final back = config.routines.single;
      expect(back.name, 'Film night');
      expect(back.phrases, ['film night', 'movie time']);
      expect(back.steps, {RoutineStep.tvOn, RoutineStep.lightsOff});
      expect(back.ask, ['turn on the lamp']);
      expect(back.reply, 'Enjoy the film');
    });

    test('a step it does not know is passed over', () {
      final r = HomeRoutine.fromJson(const {
        'name': 'Odd',
        'steps': ['tvOff', 'makeTea'],
      });
      expect(r.steps, {RoutineStep.tvOff});
    });

    test('the TV keeps the address it wakes by', () {
      final tv = TvSettings.fromJson(
        TvSettings(mac: 'dc:9a:7d:00:11:22').toJson(),
      );
      expect(tv.mac, 'dc:9a:7d:00:11:22');
      expect(TvSettings.fromJson(const {}).mac, '');
    });
  });

  group('speech, quieter at night', () {
    DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 17, h, m);

    test('from ten at night until six in the morning', () {
      final s = ShareInboxSettings();
      expect(s.speechOutAt(at(21, 59)), 45);
      expect(s.speechOutAt(at(22)), 30);
      expect(s.speechOutAt(at(23, 30)), 30);
      expect(s.speechOutAt(at(0)), 30);
      expect(s.speechOutAt(at(5, 59)), 30);
      expect(s.speechOutAt(at(6)), 45);
      expect(s.speechOutAt(at(12)), 45);
    });

    test('never louder than by day; nothing at all with Do Not Disturb', () {
      final s = ShareInboxSettings(speechVolume: 20);
      expect(s.speechOutAt(at(23)), 20);
      s.dndMuted = true;
      expect(s.speechOutAt(at(23)), 0);
      expect(s.speechOutAt(at(12)), 0);
    });

    test('switched off, or hours that do not cross midnight', () {
      final s = ShareInboxSettings()..quietNights = false;
      expect(s.speechOutAt(at(23)), 45);
      s
        ..quietNights = true
        ..nightFrom = 1
        ..nightUntil = 7;
      expect(s.speechOutAt(at(23)), 45);
      expect(s.speechOutAt(at(3)), 30);
      s.nightUntil = 1;
      expect(s.isNight(at(1)), isFalse);
    });

    test('kept, and a config without them is quiet at night', () {
      final s = ShareInboxSettings.fromJson(const {});
      expect(
        (s.quietNights, s.nightSpeechVolume, s.nightFrom, s.nightUntil),
        (true, 30.0, 22, 6),
      );
      final back = ShareInboxSettings.fromJson(
        (ShareInboxSettings()
              ..quietNights = false
              ..nightSpeechVolume = 15
              ..nightFrom = 23
              ..nightUntil = 7)
            .toJson(),
      );
      expect(
        (
          back.quietNights,
          back.nightSpeechVolume,
          back.nightFrom,
          back.nightUntil,
        ),
        (false, 15.0, 23, 7),
      );
    });
  });

  group('the television’s power', () {
    test('standby and use, as the set says them', () {
      final s = TvState();
      expect(s.powerKnown, isFalse);
      s.notePower('fake_sleep_0');
      expect((s.powerOn, s.powerKnown), (false, true));
      // Waking.
      s.notePower('fake_sleep_1');
      expect(s.powerOn, isTrue);
      s.notePower('fake_sleep_0');
      s.notePower('sourceswitch');
      expect(s.powerOn, isTrue);
      s.notePower('app');
      expect(s.powerOn, isTrue);
      // A broadcast without one says nothing about it.
      s.notePower('fake_sleep_0');
      s.notePower(null);
      expect(s.powerOn, isFalse);
    });

    test('the Wake-on-LAN packet', () {
      final p = WakeOnLan.magicPacket('dc:9a:7d:ec:5c:b3')!;
      expect(p.length, 6 + 16 * 6);
      expect(p.take(6), everyElement(0xff));
      expect(p.sublist(6, 12), [0xdc, 0x9a, 0x7d, 0xec, 0x5c, 0xb3]);
      expect(p.sublist(96), [0xdc, 0x9a, 0x7d, 0xec, 0x5c, 0xb3]);
      expect(WakeOnLan.magicPacket('DC-9A-7D-EC-5C-B3'), p);
      expect(WakeOnLan.magicPacket(''), isNull);
      expect(WakeOnLan.magicPacket('dc:9a:7d:ec:5c'), isNull);
      expect(WakeOnLan.magicPacket('dc:9a:7d:ec:5c:zz'), isNull);
    });

    test('its address, from the neighbour table', () {
      const arp =
          'IP address       HW type     Flags       HW address            Mask     Device\n'
          '192.168.1.1      0x1         0x2         24:5a:4c:00:00:01     *        eth1\n'
          '192.168.1.156    0x1         0x2         DC:9A:7D:EC:5C:B3     *        eth1\n'
          '192.168.1.200    0x1         0x0         00:00:00:00:00:00     *        eth1\n';
      expect(TvService.macIn(arp, '192.168.1.156'), 'dc:9a:7d:ec:5c:b3');
      // Asked for and never answered.
      expect(TvService.macIn(arp, '192.168.1.200'), isNull);
      expect(TvService.macIn(arp, '192.168.1.15'), isNull);
    });
  });

  group('carried out', () {
    late List<String> did;
    late List<String> said;
    late TvSwitch tvAnswer;
    late String? assistAnswer;
    late bool tvReady, assistReady;

    HomeControl control() => HomeControl(
      tvReady: () => tvReady,
      tv: (on) async {
        did.add('tv ${on ? 'on' : 'off'}');
        return tvAnswer;
      },
      assistReady: () => assistReady,
      assist: (text) async {
        did.add('assist: $text');
        return assistAnswer;
      },
      stopPlaying: () async => did.add('stop playing'),
      screenOff: () async => did.add('screen off'),
      say: said.add,
      screenDelay: Duration.zero,
    );

    setUp(() {
      did = [];
      said = [];
      tvAnswer = TvSwitch.done;
      assistAnswer = 'Turned off the lights';
      tvReady = assistReady = true;
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('the TV and the lights, said at once and done after', () async {
      final shown = control().switchThings({
        HomeThing.tv,
        HomeThing.lights,
      }, on: false);
      expect(shown, 'TV and lights off');
      await settle();
      expect(did, ['tv off', 'assist: turn off all the lights']);
      expect(said, isEmpty);
    });

    test('only what is set up; nothing, and Home Assistant is asked', () async {
      tvReady = false;
      expect(
        control().switchThings({HomeThing.tv, HomeThing.lights}, on: true),
        'lights on',
      );
      assistReady = false;
      expect(control().switchThings({HomeThing.tv}, on: true), isNull);
    });

    test('what went wrong is said', () async {
      tvAnswer = TvSwitch.unreachable;
      assistAnswer = null;
      control().switchThings({HomeThing.tv, HomeThing.lights}, on: true);
      await settle();
      expect(said, [
        "The TV isn't answering.",
        "Home Assistant couldn't switch the lights.",
      ]);
    });

    test(
      'bedtime: playing stopped, the reply, the house, then the screen',
      () async {
        final shown = control().runRoutine(HomeRoutine.bedtime());
        expect(shown, 'Goodnight');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(did.first, 'stop playing');
        expect(
          did.sublist(1, 3),
          unorderedEquals(['tv off', 'assist: turn off all the lights']),
        );
        expect(did.last, 'screen off');
        expect(said, ['Goodnight']);
      },
    );

    test(
      'a TV not answering at bedtime is very likely off: not said',
      () async {
        tvAnswer = TvSwitch.unreachable;
        control().runRoutine(HomeRoutine.bedtime());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(said, ['Goodnight']);
      },
    );

    test('its own requests go to Home Assistant, in order', () async {
      final r = HomeRoutine(
        name: 'Film',
        steps: {RoutineStep.tvOn},
        ask: ['activate PC mode', 'turn off the purifier'],
      );
      expect(control().runRoutine(r), 'Film');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(did, [
        'tv on',
        'assist: activate PC mode',
        'assist: turn off the purifier',
      ]);
    });
  });

  group('the Art Matrix, by voice', () {
    int? level(String heard) {
      final a = _panel().resolve(heard);
      return a is VoiceArtMatrixBrightness ? a.level : null;
    }

    test('on and off, said however', () {
      for (final said in [
        'hey canvas turn the art matrix off',
        'Hey Canvas, turn off the Art Matrix.',
        'hey canvas switch off the art matrix',
        'hey canvas art matrix off',
        'hey canvas power the art-matrix off',
        'hey canvas turn arty off',
        'hey canvas turn off Artie',
        // Said after a pause, without the wake words.
        'turn the art matrix off',
      ]) {
        expect(_switched(said), 'artMatrix off', reason: said);
      }
      for (final said in [
        'hey canvas art matrix on',
        'hey canvas turn the art matrix on',
        'hey canvas switch on the art matrix please',
        'hey canvas arty on',
      ]) {
        expect(_switched(said), 'artMatrix on', reason: said);
      }
    });

    test('with the TV and the lights', () {
      expect(
        _switched('hey canvas turn off the tv and the art matrix'),
        'tv artMatrix off',
      );
      expect(
        _switched('hey canvas turn the lights and arty on'),
        'lights artMatrix on',
      );
      expect(
        _switched('hey canvas turn the tv the lights and the art matrix off'),
        'tv lights artMatrix off',
      );
    });

    test('"art" or "matrix" on its own is not it, nor is "party"', () {
      for (final said in [
        'hey canvas turn the art off',
        'hey canvas turn the matrix on',
        'hey canvas art on',
        'hey canvas matrix off',
        'hey canvas turn the party lights on',
        'hey canvas party on',
        'hey canvas turn the bedroom art matrix off',
        'hey canvas turn the art matrix on and off',
      ]) {
        expect(_panel().resolve(said), isNull, reason: said);
      }
    });

    test('the TV and the lights are as they were', () {
      expect(_switched('hey canvas turn the tv off'), 'tv off');
      expect(_switched('hey canvas lights out'), 'lights off');
      expect(
        _switched('hey canvas turn the tv and the lights off'),
        'tv lights off',
      );
      // A number with them is still Home Assistant's, and "volume up" the
      // music's.
      for (final said in [
        'hey canvas set the lights to 40 percent',
        'hey canvas turn the tv to 40',
        'hey canvas turn the bedroom lights off',
      ]) {
        expect(_panel().resolve(said), isNull, reason: said);
      }
      expect(
        _panel().resolve('hey canvas turn the tv volume up'),
        isA<VoiceMusic>(),
      );
    });

    test('its brightness, in figures or in words', () {
      for (final (said, want) in [
        ('hey canvas art matrix brightness 40', 40),
        ('hey canvas set the art matrix to 40 percent', 40),
        ('hey canvas art matrix to forty percent', 40),
        ('Hey Canvas, set the Art Matrix to 40%.', 40),
        ('hey canvas set the art matrix brightness to forty five per cent', 45),
        ('hey canvas turn the art matrix to 75', 75),
        ('hey canvas dim the art matrix to ten percent', 10),
        ('hey canvas arty brightness one hundred', 100),
        ('hey canvas set arty to a hundred percent', 100),
        ('hey canvas turn the art matrix on at 30 percent', 30),
        ("hey canvas set the art matrix's brightness to 60", 60),
        ('set the art matrix to 20 percent', 20),
      ]) {
        expect(level(said), want, reason: said);
      }
    });

    test('a brightness is kept to 1 to 100', () {
      expect(level('hey canvas art matrix brightness 150'), 100);
      expect(level('hey canvas art matrix brightness 0'), 1);
      expect(level('hey canvas set the art matrix to 1000 percent'), 100);
    });

    test('not a brightness: no level asked, two numbers, or more said', () {
      for (final said in [
        // A number, but nothing to say it is the brightness.
        'hey canvas art matrix 40',
        'hey canvas art matrix brightness two forty',
        'hey canvas set the art matrix to 40 percent and the tv off',
        'hey canvas turn the art matrix off at 40 percent',
        'hey canvas set the art matrix to 20 or 30 percent',
        'hey canvas set the matrix to 40 percent',
        'hey canvas art brightness 40',
      ]) {
        expect(level(said), isNull, reason: said);
        expect(_switched(said), isNull, reason: said);
      }
      // No number: on, as asked.
      expect(level('hey canvas turn the art matrix on'), isNull);
    });
  });

  group('the Art Matrix in the config and in routines', () {
    test('nothing set up to begin with', () {
      final s = AppConfig.fromJson(const {}).artMatrix;
      expect((s.enabled, s.host, s.isConfigured), (false, '', false));
      expect(ArtMatrixSettings(enabled: true).isConfigured, isFalse);
    });

    test('saved and read back the same; an address as typed is tidied', () {
      final config = AppConfig.fromJson(
        AppConfig(
          artMatrix: ArtMatrixSettings(enabled: true, host: 'arty.local'),
        ).toJson().cast<String, dynamic>(),
      );
      expect(config.artMatrix.enabled, isTrue);
      expect(config.artMatrix.host, 'arty.local');
      expect(config.artMatrix.isConfigured, isTrue);
      expect(ArtMatrixSettings.hostOf(' http://arty.local/ '), 'arty.local');
      expect(
        ArtMatrixSettings.fromJson(const {
          'host': 'http://10.1.2.3:8080/',
        }).host,
        '10.1.2.3:8080',
      );
    });

    test('its steps saved and read back by name', () {
      final r = HomeRoutine(
        name: 'Art',
        steps: {RoutineStep.artMatrixOn, RoutineStep.tvOff},
      );
      final json = r.toJson();
      expect(json['steps'], ['tvOff', 'artMatrixOn']);
      final back = HomeRoutine.fromJson(
        (jsonDecode(jsonEncode(json)) as Map).cast<String, dynamic>(),
      );
      expect(back.steps, {RoutineStep.artMatrixOn, RoutineStep.tvOff});
      expect(
        HomeRoutine.fromJson(const {
          'name': 'Off',
          'steps': ['artMatrixOff'],
        }).steps,
        {RoutineStep.artMatrixOff},
      );
    });

    test('a Bedtime saved before keeps its own steps, without it', () {
      final saved = AppConfig.fromJson(const {
        'routines': [
          {
            'name': 'Bedtime',
            'steps': ['lightsOff', 'tvOff', 'musicOff', 'screenOff'],
          },
        ],
      });
      expect(
        saved.routines.single.steps,
        isNot(contains(RoutineStep.artMatrixOff)),
      );
    });
  });

  group('the Art Matrix, carried out', () {
    late List<String> did;
    late List<String> said;
    late ArtMatrixResult answer;
    late bool ready;

    HomeControl control() => HomeControl(
      tvReady: () => true,
      tv: (on) async {
        did.add('tv ${on ? 'on' : 'off'}');
        return TvSwitch.done;
      },
      assistReady: () => false,
      assist: (text) async => null,
      stopPlaying: () async => did.add('stop playing'),
      screenOff: () async => did.add('screen off'),
      say: said.add,
      artMatrixReady: () => ready,
      artMatrix: (on) async {
        did.add('art matrix ${on ? 'on' : 'off'}');
        return answer;
      },
      artMatrixBrightness: (level) async {
        did.add('art matrix $level%');
        return answer;
      },
      screenDelay: Duration.zero,
    );

    setUp(() {
      did = [];
      said = [];
      answer = ArtMatrixResult.done;
      ready = true;
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('switched with the TV, shown at once and done after', () async {
      final shown = control().switchThings({
        HomeThing.tv,
        HomeThing.artMatrix,
      }, on: false);
      expect(shown, 'TV and Art Matrix off');
      await settle();
      expect(did, ['tv off', 'art matrix off']);
      expect(said, isEmpty);
    });

    test('from what was said to what was done', () async {
      final home = control();
      final off =
          _panel().resolve('hey canvas turn the art matrix off') as VoiceSwitch;
      expect(home.switchThings(off.things, on: off.on), 'Art Matrix off');
      final dim =
          _panel().resolve('hey canvas art matrix to forty percent')
              as VoiceArtMatrixBrightness;
      expect(home.setArtMatrixBrightness(dim.level), 'Art Matrix 40%');
      await settle();
      expect(did, ['art matrix off', 'art matrix 40%']);
      expect(said, isEmpty);
    });

    test('a brightness asked of it is kept to 1 to 100', () async {
      expect(control().setArtMatrixBrightness(0), 'Art Matrix 1%');
      expect(control().setArtMatrixBrightness(250), 'Art Matrix 100%');
      await settle();
      expect(did, ['art matrix 1%', 'art matrix 100%']);
    });

    test('not set up: nothing done, and Home Assistant is asked', () async {
      ready = false;
      expect(control().switchThings({HomeThing.artMatrix}, on: true), isNull);
      expect(control().setArtMatrixBrightness(40), isNull);
      // With the TV, only the TV.
      expect(
        control().switchThings({HomeThing.tv, HomeThing.artMatrix}, on: true),
        'TV on',
      );
      await settle();
      expect(did, ['tv on']);
    });

    test('what went wrong is said', () async {
      answer = ArtMatrixResult.unreachable;
      control().switchThings({HomeThing.artMatrix}, on: true);
      await settle();
      answer = ArtMatrixResult.refused;
      control().setArtMatrixBrightness(40);
      await settle();
      answer = ArtMatrixResult.notLocal;
      control().switchThings({HomeThing.artMatrix}, on: false);
      await settle();
      expect(said, [
        "The Art Matrix isn't answering.",
        "The Art Matrix didn't take that.",
        "The Art Matrix's address isn't on your home network.",
      ]);
    });

    test('bedtime puts it off; not answering then is not said', () async {
      answer = ArtMatrixResult.unreachable;
      control().runRoutine(HomeRoutine.bedtime());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(did, contains('art matrix off'));
      expect(did.last, 'screen off');
      expect(said, ['Goodnight']);
    });

    test('a routine can put it on; not answering then is said', () async {
      answer = ArtMatrixResult.unreachable;
      control().runRoutine(
        HomeRoutine(name: 'Morning', steps: {RoutineStep.artMatrixOn}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(did, ['art matrix on']);
      expect(said, ["The Art Matrix isn't answering."]);
    });
  });
}

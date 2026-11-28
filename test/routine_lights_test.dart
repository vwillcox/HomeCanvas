import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/home_control.dart';
import 'package:home_canvas/services/routines.dart';
import 'package:home_canvas/services/tv_service.dart';
import 'package:home_canvas/services/voice_commands.dart';

/// "Work mode": the lounge to 80% warm white, the rest off, and the heater
/// asked about.
HomeRoutine _workMode() => HomeRoutine(
  name: 'Work mode',
  phrases: ['Work mode'],
  lights: [
    RoutineLights(
      targets: ['light.lounge_1', 'light.lounge_2', 'area:office'],
      brightness: 80,
      white: LightWhite.warm,
    ),
  ],
  otherLightsOff: true,
  questions: [
    RoutineQuestion(
      prompt: 'Do you want the heater on or off?',
      entity: 'climate.heater',
      name: 'heater',
    ),
  ],
);

void main() {
  group('kept in the config', () {
    test('lights, the rest off, and questions, as they were', () {
      final back = HomeRoutine.fromJson(_workMode().toJson());
      expect(back.lights.single.targets, [
        'light.lounge_1',
        'light.lounge_2',
        'area:office',
      ]);
      expect(back.lights.single.brightness, 80);
      expect(back.lights.single.white, LightWhite.warm);
      expect(back.otherLightsOff, isTrue);
      expect(back.questions.single.prompt, 'Do you want the heater on or off?');
      expect(back.questions.single.entity, 'climate.heater');
      expect(back.questions.single.name, 'heater');
    });

    test('a routine without them writes none of them', () {
      final j = HomeRoutine.bedtime().toJson();
      expect(j.containsKey('lights'), isFalse);
      expect(j.containsKey('otherLightsOff'), isFalse);
      expect(j.containsKey('questions'), isFalse);
    });

    test('what makes no sense is dropped, not kept broken', () {
      final r = HomeRoutine.fromJson({
        'name': 'Odd',
        'lights': [
          {'targets': []},
          {
            'targets': ['light.a'],
            'brightness': 250,
            'white': 'purple',
          },
          'not a map',
        ],
        'questions': [
          {'prompt': '', 'entity': 'fan.fan'},
          {'prompt': 'Fan?', 'entity': 'not an entity'},
          {'prompt': 'Fan on?', 'entity': 'fan.fan'},
        ],
      });
      expect(r.lights.single.targets, ['light.a']);
      expect(r.lights.single.brightness, 100);
      expect(r.lights.single.white, isNull);
      expect(r.questions.single.prompt, 'Fan on?');
    });

    test('what Home Assistant is given for them', () {
      expect(_workMode().lights.single.serviceData, {
        'entity_id': ['light.lounge_1', 'light.lounge_2'],
        'area_id': ['office'],
        'brightness_pct': 80,
        'color_temp_kelvin': 2700,
      });
      // As they were, but on.
      expect(RoutineLights(targets: ['light.a']).serviceData, {
        'entity_id': ['light.a'],
      });
    });
  });

  group('an answer', () {
    bool? answer(String said) =>
        RoutineQuestion.answer(VoiceCommands.words(said));

    test('on, or off', () {
      for (final on in ['On.', 'on please', 'yes', 'yeah go on', 'OK']) {
        expect(answer(on), isTrue, reason: on);
      }
      for (final off in ['Off.', 'no', 'no thanks', 'leave it off', 'nope']) {
        expect(answer(off), isFalse, reason: off);
      }
    });

    test('neither, or both: left as it is', () {
      for (final none in [
        'leave it',
        '',
        // The question itself, heard back: not an answer.
        'Do you want the heater on or off?',
        'yes no',
      ]) {
        expect(answer(none), isNull, reason: none);
      }
    });
  });

  group('carried out', () {
    late List<String> did;
    late List<String> said;
    late bool? reply;
    late List<String>? lightsOn;
    late bool serviceWorks;

    HomeControl control() => HomeControl(
      tvReady: () => false,
      tv: (on) async => TvSwitch.notSetUp,
      assistReady: () => true,
      assist: (text) async {
        // Slower than a service call, as Assist is: what is asked after it
        // must still land after it.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        did.add('assist: $text');
        return 'Done';
      },
      stopPlaying: () async {},
      screenOff: () async {},
      say: said.add,
      screenDelay: Duration.zero,
      service: (domain, service, data) async {
        did.add('$domain.$service $data');
        return serviceWorks;
      },
      lightsOnBesides: (keep) async {
        did.add('on besides $keep');
        return lightsOn;
      },
      question: (q) async {
        did.add('asked: ${q.prompt}');
        return reply;
      },
    );

    setUp(() {
      did = [];
      said = [];
      reply = true;
      lightsOn = ['light.hallway', 'light.lamp'];
      serviceWorks = true;
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('the lights set, the rest put off, then the question', () async {
      control().runRoutine(_workMode());
      await settle();
      expect(did, [
        // Which are on is known before any is switched.
        'on besides [light.lounge_1, light.lounge_2, area:office]',
        'light.turn_on {entity_id: [light.lounge_1, light.lounge_2], '
            'area_id: [office], brightness_pct: 80, color_temp_kelvin: 2700}',
        'light.turn_off {entity_id: [light.hallway, light.lamp]}',
        'asked: Do you want the heater on or off?',
        'homeassistant.turn_on {entity_id: climate.heater}',
      ]);
      expect(said, ['Heater on.']);
    });

    test('off, as answered', () async {
      reply = false;
      control().runRoutine(_workMode());
      await settle();
      expect(did.last, 'homeassistant.turn_off {entity_id: climate.heater}');
      expect(said, ['Heater off.']);
    });

    test('no answer: the heater is left, and that is said', () async {
      reply = null;
      control().runRoutine(_workMode());
      await settle();
      expect(did.where((d) => d.startsWith('homeassistant.')), isEmpty);
      expect(said, ['Leaving the heater as it is.']);
    });

    test('all the lights off, and one lamp set: the lamp last', () async {
      control().runRoutine(
        HomeRoutine(
          name: 'Bedtime',
          steps: {RoutineStep.lightsOff},
          lights: [
            RoutineLights(targets: ['light.bedside'], brightness: 10),
          ],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(did.first, 'assist: turn off all the lights');
      expect(did.last, startsWith('light.turn_on {entity_id: [light.bedside]'));
    });

    test('nothing else on: nothing put off', () async {
      lightsOn = [];
      control().runRoutine(_workMode());
      await settle();
      expect(did.where((d) => d.startsWith('light.turn_off')), isEmpty);
    });

    test('Home Assistant refusing is said, before the question', () async {
      serviceWorks = false;
      control().runRoutine(_workMode());
      await settle();
      expect(said, [
        "Home Assistant couldn't set all the lights.",
        "Home Assistant couldn't turn the heater on.",
      ]);
    });

    test('not knowing which lights are on is a problem too', () async {
      lightsOn = null;
      control().runRoutine(_workMode());
      await settle();
      expect(said.first, "Home Assistant couldn't set all the lights.");
      expect(did.where((d) => d.startsWith('light.turn_off')), isEmpty);
    });
  });
}

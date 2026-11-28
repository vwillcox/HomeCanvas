import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/config_service.dart';

import 'package:home_canvas/services/home_assistant_service.dart';
import 'package:home_canvas/services/spoken_names.dart';

/// What the switchable things in a house are called, as Home Assistant
/// has them: numbered bulbs, rooms, a lamp in fifteen segments, sockets.
final _house = SpokenNames(
  [
    for (final n in [1, 2, 3, 4]) ...['Lounge $n', 'Lounge $n Music mode'],
    for (final n in [1, 2, 3, 4]) 'Bedroom $n',
    for (final n in [1, 2, 3]) 'Socket $n',
    for (final n in List.generate(15, (i) => i + 1)) 'lamp Segment $n',
    'lamp', 'Hallway', 'Doorway', 'Fan', 'Purifier', 'Power strip', //
    'Bedroom TV', 'Bedroom Google TV', 'Sync box', 'using the PC',
  ],
  areas: ['Living Room', 'Bedroom'],
);

void main() {
  group('a misheard name, put right', () {
    test('the bulbs, as recognisers have heard them', () {
      for (final (heard, meant) in [
        ('turn around you one on.', 'turn on lounge one'),
        ('turn on lunch one', 'turn on lounge one'),
        ('turn launch two off', 'turn off lounge two'),
        ('turn lounge won on', 'turn on lounge one'),
        ('turn lounch for off', 'turn off lounge four'),
        ('turn lands one on', 'turn on lounge one'),
        ('turn bed room three off', 'turn off bedroom three'),
        ('switch socket to on', 'turn on socket two'),
        ('turn off the lump', 'turn off lamp'),
        ('turn the van on', 'turn on fan'),
        ('turn off the bedroom teevee', 'turn off bedroom tv'),
        ('turn the living rum lights off', 'turn off living room lights'),
        // A light by its name needs no "light" after it.
        ('turn the lunch one light on', 'turn on lounge one'),
        // Digits, said as the name has them in words.
        ('lounge 1 off', 'turn off lounge one'),
      ]) {
        expect(_house.correct(heard), meant, reason: heard);
      }
    });

    test('nothing for what names nothing in the house', () {
      for (final heard in [
        'turn on the kettle',
        // No fifth: never guessed to be the fourth.
        'turn lounge five on',
        'turn around you on',
        // Not a switching at all.
        'what is the temperature in the lounge',
        'set lounge one to fifty percent',
        'turn off all the lights',
      ]) {
        expect(_house.correct(heard), isNull, reason: heard);
      }
    });

    test('never to more than was said', () {
      final house = SpokenNames(['Front door lock', 'Hallway', 'Kettle']);
      expect(house.correct('turn off the front door'), isNull);
      // As said, it is still put right.
      expect(house.correct('turn off the front door lok'), isNotNull);
    });

    test('never to a lock, a door, or a script', () {
      final ha = HomeAssistantService(ConfigService())
        ..debugSet(const [
          HaEntity(
            id: 'light.lounge_1',
            state: 'on',
            attributes: {'friendly_name': 'Lounge 1'},
          ),
          HaEntity(
            id: 'lock.front_door',
            state: 'locked',
            attributes: {'friendly_name': 'Front door'},
          ),
          HaEntity(
            id: 'cover.garage_door',
            state: 'closed',
            attributes: {'friendly_name': 'Garage door'},
          ),
          HaEntity(
            id: 'script.away',
            state: 'off',
            attributes: {'friendly_name': 'Away'},
          ),
        ]);
      expect(ha.spokenNames, ['Lounge 1']);
      ha.dispose();
    });

    test('a name it has already is left as it is', () {
      expect(_house.correct('turn on lounge one'), isNull);
      expect(_house.correct('turn the hallway off'), isNull);
      expect(_house.correct('turn hall way off'), 'turn off hallway');
    });

    test('nearest only when clearly nearest', () {
      // "Around june" is somewhat like the lounge and somewhat like the
      // bedroom: not enough between them to choose.
      expect(_house.nearest(['around', 'june', 'one']), isNull);
      expect(_house.nearest(['around', 'you', 'one']), 'lounge one');
    });

    test('how alike', () {
      // "Around you" and "lounge" both come out with the j sound in them.
      expect(SpokenNames.sound(['lounge']), 'lanja');
      expect(SpokenNames.sound(['around', 'you']), 'aranja');
      expect(SpokenNames.alike(['hall', 'way'], ['hallway']), 1.0);
      expect(
        SpokenNames.alike(['around', 'you'], ['lounge']),
        greaterThan(0.7),
      );
      expect(SpokenNames.alike(['kettle'], ['lamp']), lessThan(0.5));
    });
  });

  group('asking Home Assistant with every hearing', () {
    late List<String> asked;
    late int namesAsked;

    /// An Assist that knows only Lounge 1, by its proper name.
    Future<AssistReply?> assist(String request) async {
      asked.add(request);
      if (request.contains('lounge one')) {
        return const AssistReply('Turned on the light', done: true);
      }
      if (request.startsWith('turn')) {
        return const AssistReply(
          'Sorry, I am not aware of any device called that',
          done: false,
        );
      }
      return null;
    }

    Future<VoiceAnswerLike?> run(List<String> heard) async {
      final r = await askAssist(
        heard,
        request: (h) => h.replaceFirst('hey canvas ', ''),
        ask: assist,
        names: () async {
          namesAsked++;
          return _house;
        },
      );
      return r == null ? null : (r.heard, r.answer);
    }

    setUp(() {
      asked = [];
      namesAsked = 0;
    });

    test('a hearing that names it properly beats a refusal', () async {
      expect(
        await run([
          'hey canvas turn around you one on',
          'hey canvas turn lounge one on',
        ]),
        ('hey canvas turn lounge one on', 'Turned on the light'),
      );
      expect(asked, ['turn around you one on', 'turn lounge one on']);
      // Done before any name needed putting right.
      expect(namesAsked, 0);
    });

    test('failing every hearing, the name put right', () async {
      expect(
        await run([
          'hey canvas turn around you one on',
          'hey canvas turn round one on',
        ]),
        ('turn on lounge one', 'Turned on the light'),
      );
      expect(asked.last, 'turn on lounge one');
      expect(namesAsked, 1);
    });

    test('nothing to put right: the refusal, which says why', () async {
      expect(await run(['hey canvas turn on the kettle']), (
        'hey canvas turn on the kettle',
        'Sorry, I am not aware of any device called that',
      ));
    });

    test('nothing understood at all', () async {
      expect(await run(['hey canvas make the tea']), isNull);
    });
  });
}

typedef VoiceAnswerLike = (String, String);

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:home_canvas/config/app_config.dart';
import 'package:home_canvas/deck/deck_link.dart';
import 'package:home_canvas/deck/deck_model.dart';
import 'package:home_canvas/services/computer_power.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/home_assistant_service.dart';
import 'package:home_canvas/services/routines.dart';
import 'package:home_canvas/services/share_inbox_service.dart';

/// A deck as StreamerDeck sends one: two profiles, the first with two
/// pages, a folder, a key the computer runs and two the panel does.
Map<String, Object?> deckJson() => {
  't': 'deck',
  'v': 1,
  'active': 'main',
  'profiles': [
    {
      'id': 'main',
      'name': 'Default',
      'cols': 5,
      'rows': 3,
      'pages': [
        {
          'id': 'p1',
          'name': '',
          'keys': [
            {
              'id': 'save',
              'pos': [0, 0],
              'action': 'deck.hotkey',
              'runs': 'pc',
              'state': 0,
              'looks': [
                {
                  'img': 'abc.png',
                  'color': '#ff000080',
                  'title': 'Save',
                  'size': 14,
                  'style': 'Bold Italic',
                },
              ],
            },
            {
              'id': 'games',
              'pos': [1, 0],
              'action': 'deck.folder',
              'runs': 'nav',
              'looks': [
                {'title': 'Games'},
              ],
              'pages': [
                {
                  'id': 'f1',
                  'keys': [
                    {
                      'id': 'steam',
                      'pos': [1, 0],
                      'action': 'deck.open',
                      'runs': 'pc',
                      'looks': [
                        {'img': 'steam.png'},
                      ],
                    },
                  ],
                },
              ],
            },
            {
              'id': 'bed',
              'pos': [2, 0],
              'action': 'hc.routine',
              'runs': 'panel',
              'settings': {'routine': 'bedtime'},
              'looks': [{}],
            },
            {
              'id': 'wake',
              'pos': [3, 0],
              'action': 'hc.pc',
              'runs': 'panel',
              'settings': {'do': 'on'},
              'looks': [{}],
            },
            {
              'id': 'two',
              'pos': [4, 0],
              'action': 'deck.page.goto',
              'runs': 'nav',
              'settings': {'page': 2},
              'looks': [{}],
            },
            {
              'id': 'films',
              'pos': [0, 1],
              'action': 'deck.profile',
              'runs': 'nav',
              'settings': {'profile': 'films'},
              'looks': [{}],
            },
          ],
        },
        {'id': 'p2', 'name': '', 'keys': []},
      ],
    },
    {
      'id': 'films',
      'name': 'Films',
      'cols': 3,
      'rows': 2,
      'pages': [
        {'id': 'q1', 'keys': []},
      ],
    },
  ],
};

void main() {
  late Directory dir;
  late DeckLink link;
  late List<String> routinesRun;
  late List<bool> computerAsked;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('deck_test');
    routinesRun = [];
    computerAsked = [];
    link = DeckLink(
      home: HomeAssistantService(ConfigService()),
      routines: () => [
        HomeRoutine(name: 'Bedtime', phrases: ['goodnight']),
      ],
      runRoutine: (r) {
        routinesRun.add(r.name);
        return 'ok';
      },
      computer: (on) async {
        computerAsked.add(on);
        return PcSwitch.done;
      },
      folder: dir.path,
      cacheFolder: dir.path,
    );
  });

  tearDown(() async {
    link.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  Future<void> loadDeck() async {
    await File('${dir.path}/deck.json').writeAsString(jsonEncode(deckJson()));
    await link.load();
  }

  test('the deck is read as it is drawn', () {
    final s = DeckSnapshot.fromJson(deckJson())!;
    expect(s.profiles.map((p) => p.name), ['Default', 'Films']);
    final save = s.profile('main').pages.first.at(0, 0)!;
    expect(save.runs, DeckRuns.pc);
    expect(save.look(0).color, const Color(0x80FF0000));
    expect(save.look(0).bold && save.look(0).italic, isTrue);
    // Past its last state, a key shows its last.
    expect(save.look(3).title, 'Save');
    expect(s.key('steam')!.action, 'deck.open');
    expect(s.images, {'abc.png', 'steam.png'});
    expect(s.profile('gone').id, 'main');
    expect(parseColour('#12345'), isNull);
  });

  test('pages, folders and profiles are moved between here', () async {
    await loadDeck();
    expect(link.profile!.id, 'main');
    expect(link.pageIndex, 0);
    link.previousPage();
    expect(link.pageIndex, 1, reason: 'turning back from the first goes round');
    link.nextPage();
    expect(link.pageIndex, 0);

    link.press(link.page!.at(1, 0)!);
    expect(link.inFolder, isTrue);
    expect(link.page!.at(1, 0)!.id, 'steam');
    link.back();
    expect(link.inFolder, isFalse);

    link.press(link.page!.at(4, 0)!);
    expect(link.pageIndex, 1);
    link.showPage(0);
    link.press(link.page!.at(0, 1)!);
    expect(link.profile!.name, 'Films');
  });

  test('the panel runs its own keys, and says on them how it went', () async {
    await loadDeck();
    link.press(link.page!.at(2, 0)!);
    await until(() => routinesRun.isNotEmpty);
    expect(routinesRun, ['Bedtime']);
    expect(link.fxOf(link.page!.at(2, 0)!), DeckFx.ok);

    link.press(link.page!.at(3, 0)!);
    await until(() => computerAsked.isNotEmpty);
    expect(computerAsked, [true]);
  });

  test('a computer key with no computer there warns at once', () async {
    await loadDeck();
    final save = link.page!.at(0, 0)!;
    link.press(save);
    expect(link.fxOf(save), DeckFx.alert);
  });

  group('the computer, through the Share Inbox', () {
    late HttpServer server;

    setUp(() async {
      final config = ConfigService();
      config.config.shareInbox.senderTokens = [
        SenderToken(name: 'Desk', token: 'desk-token'),
        SenderToken(name: 'Phone', token: 'phone-token'),
      ];
      final inbox = ShareInboxService(config)..onDeck = link.accept;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(inbox.handle);
    });

    tearDown(() => server.close(force: true));

    Future<(WebSocket, List<Object?>)> connect(
      String token, {
      Map<String, String> extra = const {},
    }) async {
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/deck',
        headers: {
          'authorization': 'Bearer $token',
          'x-deck-name': 'Desk%20PC',
          ...extra,
        },
      );
      final heard = <Object?>[];
      ws.listen((m) => heard.add(m is String ? jsonDecode(m) : m));
      return (ws, heard);
    }

    Iterable<Map> said(List<Object?> heard, String t) =>
        heard.whereType<Map>().where((m) => m['t'] == t);

    test('sends its deck and images, and hears the keys it runs', () async {
      final (ws, heard) = await connect('desk-token');
      await until(() => said(heard, 'hello').isNotEmpty);
      expect(link.pcName, 'Desk PC');
      expect(link.owner, 'Desk');

      ws.add(jsonEncode(deckJson()));
      await until(
        () => link.snapshot != null && said(heard, 'need').isNotEmpty,
      );
      expect((said(heard, 'need').single['ids'] as List).toSet(), {
        'abc.png',
        'steam.png',
      });

      final name = utf8.encode('abc.png');
      ws.add([name.length, ...name, 1, 2, 3]);
      await until(() => link.imageFile('abc.png') != null);
      expect(await link.imageFile('abc.png')!.readAsBytes(), [1, 2, 3]);
      expect(link.imageFile('../abc.png'), isNull);

      link.open();
      link.press(link.page!.at(0, 0)!);
      await until(() => said(heard, 'up').isNotEmpty);
      expect(said(heard, 'down').single['id'], 'save');
      expect(said(heard, 'open').single['profile'], 'main');

      ws.add(jsonEncode({'t': 'ask', 'id': 7, 'what': 'routines'}));
      await until(() => said(heard, 'answer').isNotEmpty);
      expect(said(heard, 'answer').single, {
        't': 'answer',
        'id': 7,
        'data': [
          {'name': 'Bedtime', 'says': '“goodnight”'},
        ],
      });

      link.close();
      await until(() => said(heard, 'close').isNotEmpty);
      await ws.close();
      await until(() => !link.connected);
      // Kept for the next time the deck opens, computer or not.
      expect(File('${dir.path}/deck.json').existsSync(), isTrue);
    });

    test(
      'is turned away without a token, through a proxy, or from another sender',
      () async {
        await expectLater(connect('wrong'), throwsA(isA<WebSocketException>()));
        await expectLater(
          connect('desk-token', extra: {'x-forwarded-for': '203.0.113.9'}),
          throwsA(isA<WebSocketException>()),
        );
        expect(link.owner, isNull);

        final (desk, _) = await connect('desk-token');
        await until(() => link.connected);
        await expectLater(
          connect('phone-token'),
          throwsA(isA<WebSocketException>()),
        );
        await desk.close();

        await link.forgetOwner();
        final (phone, _) = await connect('phone-token');
        await until(() => link.owner == 'Phone');
        await phone.close();
      },
    );
  });
}

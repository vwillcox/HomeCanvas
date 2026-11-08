import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/kiosk_browser.dart';
import 'package:home_canvas/services/side_browser.dart';

/// The page shown inside a tile. In a file of its own, away from any widget
/// test: those answer every real connection with a 400, and the remote
/// control's tests below talk to a server of their own.
void main() {
  group('the window rule', () {
    const at = Rect.fromLTWH(760, 200, 1100, 900);
    const rc = '''<?xml version="1.0"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <touch deviceName="11-0041 ili_v3" mapToOutput="DSI-2" mouseEmulation="no"/>
  <windowRules>
    <windowRule identifier="firefox" serverDecoration="no"/>
  </windowRules>
</openbox_config>
''';

    test('goes in with the other rules, which stay as they were', () {
      final out = SideBrowser.withRule(rc, at)!;
      expect(out, contains('<windowRule identifier="firefox" '));
      expect(out, contains('<touch deviceName="11-0041 ili_v3"'));
      expect(out, contains('<action name="MoveTo" x="760" y="200"/>'));
      expect(
        out,
        contains('<action name="ResizeTo" width="1100" height="900"/>'),
      );
      expect(out, contains('<action name="ToggleAlwaysOnTop"/>'));
      final rule = out.indexOf('identifier="homecanvas-side"');
      expect(rule, greaterThan(out.indexOf('<windowRules>')));
      expect(rule, lessThan(out.indexOf('</windowRules>')));
    });

    test('replaces itself rather than piling up', () {
      final once = SideBrowser.withRule(rc, at)!;
      expect(SideBrowser.withRule(once, at), once, reason: 'nothing moved');
      final moved = SideBrowser.withRule(
        once,
        const Rect.fromLTWH(10, 20, 300, 400),
      )!;
      expect('identifier="homecanvas-side"'.allMatches(moved), hasLength(1));
      expect(moved, contains('x="10" y="20"'));
      expect(moved, isNot(contains('x="760"')));
      expect(
        SideBrowser.withRule(moved, at),
        once,
        reason: 'and back again, to the letter',
      );
    });

    test('takes out a rule for the same window written by hand', () {
      final hand = rc.replaceFirst('  </windowRules>', '''
    <windowRule identifier="homecanvas-side" serverDecoration="no">
      <action name="SnapToEdge" direction="right"/>
    </windowRule>
    <windowRule identifier="homecanvas-side" fixedPosition="yes"/>
  </windowRules>''');
      final out = SideBrowser.withRule(hand, at)!;
      expect(out, isNot(contains('SnapToEdge')));
      expect(out, isNot(contains('fixedPosition')));
      expect('identifier="homecanvas-side"'.allMatches(out), hasLength(1));
      expect(out, contains('<windowRule identifier="firefox" '));
    });

    test('adds a rules section to a file without one', () {
      const bare =
          '<?xml version="1.0"?>\n'
          '<openbox_config xmlns="http://openbox.org/3.4/rc">\n'
          '  <theme><name>Default</name></theme>\n'
          '</openbox_config>\n';
      final out = SideBrowser.withRule(bare, at)!;
      expect(out, contains('<windowRules>'));
      expect(out, contains('<theme><name>Default</name></theme>'));
      expect(
        out.indexOf('</windowRules>'),
        lessThan(out.indexOf('</openbox_config>')),
      );
    });

    test('leaves alone a file it does not understand', () {
      expect(SideBrowser.withRule('<something-else/>', at), isNull);
    });

    test('whole pixels, never poking out of the hole', () {
      expect(
        SideBrowser.snap(const Rect.fromLTRB(10.2, 20.7, 300.9, 400.1)),
        const Rect.fromLTRB(11, 21, 300, 400),
      );
    });
  });

  test('every page is asked for its dark look', () {
    expect(
      KioskBrowser.prefs,
      contains('"layout.css.prefers-color-scheme.content-override", 0'),
    );
    expect(KioskBrowser.prefs, contains('"ui.systemUsesDarkTheme", 1'));
  });

  test('a page in a tile keeps new windows in the one there is', () {
    expect(SideBrowser.prefs, contains('"browser.link.open_newwindow", 1'));
    expect(SideBrowser.prefs, contains('"remote.prefs.recommended", false'));
  });

  test('the toolbars leave no line behind', () {
    expect(KioskBrowser.userChrome, contains('#navigator-toolbox'));
  });

  group('the remote control', () {
    late HttpServer server;
    late List<Map<String, dynamic>> heard;
    WebSocket? firefox;

    setUp(() async {
      heard = [];
      firefox = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.uri.path != '/session') {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        final ws = await WebSocketTransformer.upgrade(request);
        firefox = ws;
        ws.listen((data) {
          final m = (jsonDecode(data as String) as Map).cast<String, dynamic>();
          heard.add(m);
          ws.add(jsonEncode(_answer(m)));
        });
      });
    });
    tearDown(() => server.close(force: true));

    Future<BidiClient> connect({
      void Function(String, Map<String, dynamic>)? onEvent,
    }) async {
      final client = await BidiClient.connect(
        'ws://127.0.0.1:${server.port}',
        onEvent: onEvent,
      );
      expect(client, isNotNull);
      addTearDown(client!.dispose);
      return client;
    }

    test('opens a session on the page', () async {
      final client = await connect();
      expect(client.context, 'top');
      expect(heard.map((m) => m['method']), [
        'session.new',
        'browsingContext.getTree',
        'session.subscribe',
      ]);
    });

    test('steers the page, and says when it could not', () async {
      final client = await connect();
      expect(await client.navigate('https://track.dpd.co.uk/'), isTrue);
      expect(heard.last['params'], {
        'context': 'top',
        'url': 'https://track.dpd.co.uk/',
        'wait': 'none',
      });
      expect(await client.navigate('https://bad.example/'), isFalse);
      expect(await client.traverse(-1), isTrue);
      expect(heard.last['params']['delta'], -1);
      expect(await client.reload(), isTrue);
    });

    test('asks the page itself whether it is still loading', () async {
      final client = await connect();
      expect(await client.stillLoading(), isTrue);
      expect(heard.last['params']['target'], {
        'context': 'top',
        'sandbox': 'homecanvas',
      });
    });

    test('hears about the page, not the frames inside it', () async {
      final events = <String>[];
      await connect(onEvent: (method, params) => events.add(params['url']));
      for (final (context, url) in [
        ('advert', 'https://ads.example/'),
        ('top', 'https://www.royalmail.com/track-your-item'),
      ]) {
        firefox!.add(
          jsonEncode({
            'type': 'event',
            'method': 'browsingContext.load',
            'params': {'context': context, 'url': url},
          }),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events, ['https://www.royalmail.com/track-your-item']);
    });

    test('nothing to connect to is no remote control, not a crash', () async {
      final port = server.port;
      await server.close(force: true);
      expect(await BidiClient.connect('ws://127.0.0.1:$port'), isNull);
    });
  });
}

/// What Firefox says to each command, near enough.
Map<String, Object?> _answer(Map<String, dynamic> m) {
  final id = m['id'];
  final params = (m['params'] as Map).cast<String, dynamic>();
  Map<String, Object?> ok(Map<String, Object?> result) => {
    'type': 'success',
    'id': id,
    'result': result,
  };
  return switch (m['method']) {
    'session.new' => ok({'sessionId': 's', 'capabilities': {}}),
    'browsingContext.getTree' => ok({
      'contexts': [
        {'context': 'top', 'children': [], 'url': 'about:blank'},
      ],
    }),
    'session.subscribe' => ok({'subscription': 'q'}),
    'browsingContext.navigate' when '${params['url']}'.contains('bad') => {
      'type': 'error',
      'id': id,
      'error': 'unknown error',
      'message': 'no',
    },
    'browsingContext.navigate' => ok({'navigation': 'n', 'url': params['url']}),
    'script.evaluate' => ok({
      'type': 'success',
      'realm': 'r',
      'result': {'type': 'string', 'value': 'interactive'},
    }),
    _ => ok({}),
  };
}

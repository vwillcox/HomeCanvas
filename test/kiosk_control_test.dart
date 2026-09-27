import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/kiosk_control_service.dart';

void main() {
  late KioskControlService control;
  late List<KioskCommand> ran;
  late bool dnd;
  late List<String> played;
  late List<bool> lit;
  final client = HttpClient();

  setUp(() async {
    ran = [];
    dnd = false;
    played = [];
    lit = [];
    control = KioskControlService(
      port: 0,
      state: () => KioskState(
        dashboard: true,
        lockedFolder: true,
        camera: false,
        cameraOpen: false,
        dnd: dnd,
      ),
      run: ran.add,
      setDnd: (m) => dnd = m,
      playVideo: (url) {
        if (!url.contains('youtu')) return false;
        played.add(url);
        return true;
      },
      screenLit: lit.add,
    );
    await control.start();
  });

  tearDown(() => control.stop());

  Future<(int, Map<String, dynamic>)> call(String method, String path) async {
    final req = await client.openUrl(
        method, Uri.parse('http://127.0.0.1:${control.boundPort}$path'));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return (res.statusCode, jsonDecode(body) as Map<String, dynamic>);
  }

  test('listens on the loopback address only', () async {
    // Asking on any other address of this machine must not reach it.
    final addresses = await NetworkInterface.list(
        includeLoopback: false, type: InternetAddressType.IPv4);
    for (final a in addresses.expand((i) => i.addresses)) {
      await expectLater(
        Socket.connect(a, control.boundPort!,
            timeout: const Duration(seconds: 1)),
        throwsA(isA<SocketException>()),
        reason: 'reachable on ${a.address}',
      );
    }
  });

  test('says what the control bar should show', () async {
    final (code, body) = await call('GET', '/state');
    expect(code, 200);
    expect(body, {
      'dashboard': true,
      'lockedFolder': true,
      'camera': false,
      'cameraOpen': false,
      'dnd': false,
    });
  });

  test('plays a YouTube link, and refuses anything else', () async {
    final link = Uri.encodeQueryComponent('https://youtu.be/aqz-KE-bpKQ');
    expect((await call('POST', '/youtube?url=$link')).$1, 200);
    expect((await call('POST', '/youtube?url=https%3A%2F%2Fbbc.co.uk')).$1, 400);
    expect(played, ['https://youtu.be/aqz-KE-bpKQ']);
  });

  test('opens each place the kiosk has', () async {
    for (final place in ['photos', 'dashboard', 'settings', 'locked-folder']) {
      final (code, _) = await call('POST', '/open/$place');
      expect(code, 200, reason: place);
    }
    expect(ran, [
      KioskCommand.photos,
      KioskCommand.dashboard,
      KioskCommand.settings,
      KioskCommand.lockedFolder,
    ]);
  });

  test('toggles the camera', () async {
    await call('POST', '/camera');
    expect(ran, [KioskCommand.camera]);
  });

  test('sets the notifications switch, and reports it', () async {
    final (_, body) = await call('POST', '/dnd?muted=true');
    expect(dnd, isTrue);
    expect(body['dnd'], isTrue);
  });

  test('is told when the screen goes dark and lights again', () async {
    expect((await call('POST', '/screen?lit=false')).$1, 200);
    expect((await call('POST', '/screen?lit=true')).$1, 200);
    expect((await call('POST', '/screen?lit=dim')).$1, 400);
    expect(lit, [false, true]);
  });

  test('refuses what it does not understand, and does nothing', () async {
    expect((await call('POST', '/open/somewhere')).$1, 404);
    expect((await call('GET', '/open/dashboard')).$1, 405);
    expect((await call('POST', '/dnd?muted=maybe')).$1, 400);
    expect((await call('POST', '/format-disk')).$1, 404);
    expect(ran, isEmpty);
    expect(dnd, isFalse);
  });
}

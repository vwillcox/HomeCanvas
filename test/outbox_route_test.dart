import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_canvas/config/app_config.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/link_outbox.dart';
import 'package:home_canvas/services/share_inbox_service.dart';

void main() {
  late HttpServer server;
  late LinkOutbox outbox;
  late String key;

  setUp(() async {
    final config = ConfigService();
    config.config.shareInbox.senderTokens = [
      SenderToken(name: 'Vinny', token: 'right'),
    ];
    outbox = LinkOutbox(
      senders: () => config.config.shareInbox.senderTokens.map((t) => t.name),
      persist: false,
    );
    final inbox = ShareInboxService(config)..outbox = outbox;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(inbox.handle);
    final pair = await X25519().newKeyPair();
    key = base64Encode((await pair.extractPublicKey()).bytes);
  });

  tearDown(() => server.close(force: true));

  Future<(int, String)> get(
    String query, {
    String token = 'right',
    String? deviceKey,
    String name = 'Jo%E2%80%99s%20phone',
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/outbox$query'),
      );
      request.headers
        ..set('authorization', 'Bearer $token')
        ..set('x-device-key', deviceKey ?? key)
        ..set('x-device-name', name);
      final response = await request.close();
      return (response.statusCode, await utf8.decodeStream(response));
    } finally {
      client.close();
    }
  }

  test('a device with a token is listed, by the name it gave', () async {
    final (status, body) = await get('');
    expect(status, 200);
    final kid = LinkOutbox.keyId(base64Decode(key));
    expect(jsonDecode(body), {'kid': kid, 'items': []});
    expect(outbox.devices.single.name, 'Jo’s phone');
    expect(outbox.devices.single.sender, 'Vinny');
  });

  test('a link sent is collected, sealed', () async {
    await get('');
    await outbox.send(outbox.devices.single, url: 'https://example.com/');
    final (status, body) = await get('?after=0');
    expect(status, 200);
    final items = (jsonDecode(body) as Map)['items'] as List;
    expect(items.single['sealed']['kid'], outbox.devices.single.kid);
    expect(body, isNot(contains('example.com')));
  });

  test('a wrong token, or no key, is turned away', () async {
    expect((await get('', token: 'wrong')).$1, HttpStatus.unauthorized);
    expect((await get('', deviceKey: 'short')).$1, HttpStatus.badRequest);
    expect(outbox.devices, isEmpty);
  });
}

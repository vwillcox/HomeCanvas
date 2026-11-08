import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_share/link_receiver.dart';

void main() {
  // Sealed by the kiosk's LinkOutbox.sealLink to the key below. If this
  // stops opening, the two have stopped agreeing on the format.
  const seed = 'sEVFFS7CdzWikRQVatNG0ORKlIwNGuzZnKaWGCdCK1I=';
  const sealed = {
    'v': 1,
    'kid': '35abe38a253415a6',
    'epk': 'sajsVk8mq2NAmufeatmYLSZ40r5ZLSYAbMqDcpQKqzg=',
    'salt': 'Zb7WQd9vTTMVGzEKjD9olQ==',
    'box':
        'lHzslyoMOhARjg/ZqEufLdwjhtaWqW6R5zurHuWKqgj55kF7QGaPqkx3VeRslkNfrZdPkS90e8P3WpJlMDWaIAQ=',
  };

  test('opens a link the kiosk sealed', () async {
    final pair = await X25519().newKeyPairFromSeed(base64Decode(seed));
    expect(await LinkReceiver.keyId(pair), '35abe38a253415a6');
    final link = await LinkReceiver.open(pair, sealed);
    expect(link['url'], 'https://example.com/ü');
    expect(link['title'], 'Héllo');
  });

  test('another phone cannot open it', () async {
    final other = await X25519().newKeyPair();
    await expectLater(
      LinkReceiver.open(other, sealed),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}

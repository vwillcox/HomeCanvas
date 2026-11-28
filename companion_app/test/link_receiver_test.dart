import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
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

  group('a panel at home', () {
    test('is one at a private address or a home name', () {
      for (final a in [
        'http://192.168.1.57:8081',
        'http://10.0.0.5:8081',
        'http://172.20.1.2',
        'http://100.101.102.103:8081',
        'http://[fd12:3456::1]:8081',
        'http://homecanvas.local:8081',
        'http://panel.lan',
        'http://panel.home.arpa',
        'http://homecanvas:8081',
      ]) {
        expect(LinkReceiver.atHome(a), isTrue, reason: a);
      }
    });

    test('is not one reached by a public name or address', () {
      for (final a in [
        'https://share.example.com',
        'http://80.0.57.213:8081',
        'http://172.32.0.1',
        '',
      ]) {
        expect(LinkReceiver.atHome(a), isFalse, reason: a);
      }
    });
  });

  group('the panel is asked', () {
    const home = 'http://192.168.1.57:8081';
    const away = 'https://share.example.com';
    const wifi = [ConnectivityResult.wifi];
    const mobile = [ConnectivityResult.mobile];
    const vpn = [ConnectivityResult.vpn, ConnectivityResult.mobile];
    const none = [ConnectivityResult.none];

    test('at home over Wi-Fi or a VPN, not over mobile data', () {
      expect(LinkReceiver.worthAsking(home, wifi), isTrue);
      expect(LinkReceiver.worthAsking(home, vpn), isTrue);
      expect(LinkReceiver.worthAsking(home, mobile), isFalse);
    });

    test('by a public name over anything', () {
      expect(LinkReceiver.worthAsking(away, mobile), isTrue);
      expect(LinkReceiver.worthAsking(away, wifi), isTrue);
    });

    test('never with no network', () {
      expect(LinkReceiver.worthAsking(home, none), isFalse);
      expect(LinkReceiver.worthAsking(away, none), isFalse);
      expect(LinkReceiver.worthAsking(away, const []), isFalse);
    });
  });

  test('a proxy giving up on a long hold means asking for less', () {
    expect(LinkReceiver.cutShort(504, LinkReceiver.longWait), isTrue);
    expect(LinkReceiver.cutShort(524, LinkReceiver.longWait), isTrue);
    expect(LinkReceiver.cutShort(502, LinkReceiver.longWait), isTrue);
    // Already asking for what a proxy allows: a real fault, not this.
    expect(LinkReceiver.cutShort(504, LinkReceiver.proxyWait), isFalse);
    expect(LinkReceiver.cutShort(500, LinkReceiver.longWait), isFalse);
    expect(LinkReceiver.cutShort(401, LinkReceiver.longWait), isFalse);
  });
}

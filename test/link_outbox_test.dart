import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_canvas/services/link_outbox.dart';

void main() {
  late SimpleKeyPair phone;
  late List<int> phonePublic;
  var senders = <String>['Vinny'];
  var now = DateTime(2026, 10, 30, 12);

  LinkOutbox outbox() =>
      LinkOutbox(senders: () => senders, clock: () => now, persist: false);

  setUp(() async {
    phone = await X25519().newKeyPair();
    phonePublic = (await phone.extractPublicKey()).bytes;
    senders = ['Vinny'];
    now = DateTime(2026, 10, 30, 12);
  });

  Future<OutboxPoll> ask(
    LinkOutbox o, {
    List<int>? key,
    String sender = 'Vinny',
    String name = 'Pixel',
    int after = 0,
    Duration wait = Duration.zero,
  }) => o.poll(
    sender: sender,
    publicKey: key ?? phonePublic,
    name: name,
    kind: 'phone',
    after: after,
    wait: wait,
  );

  Future<Map<String, dynamic>> open(
    OutboxItem item, [
    SimpleKeyPair? as,
  ]) async =>
      jsonDecode(
            utf8.decode(await LinkOutbox.openLink(as ?? phone, item.sealed)),
          )
          as Map<String, dynamic>;

  group('sealing', () {
    test('the device opens what was sealed to it', () async {
      final sealed = await LinkOutbox.sealLink(
        publicKey: phonePublic,
        kid: LinkOutbox.keyId(phonePublic),
        plaintext: utf8.encode('{"url":"https://example.com/"}'),
      );
      expect(sealed['kid'], LinkOutbox.keyId(phonePublic));
      expect(sealed.toString(), isNot(contains('example.com')));
      expect(
        utf8.decode(await LinkOutbox.openLink(phone, sealed)),
        '{"url":"https://example.com/"}',
      );
    });

    test('another device cannot open it, nor a changed one', () async {
      final sealed = await LinkOutbox.sealLink(
        publicKey: phonePublic,
        kid: LinkOutbox.keyId(phonePublic),
        plaintext: utf8.encode('secret'),
      );
      final other = await X25519().newKeyPair();
      await expectLater(
        LinkOutbox.openLink(other, sealed),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      final box = base64Decode(sealed['box'] as String)..[0] ^= 1;
      await expectLater(
        LinkOutbox.openLink(phone, {...sealed, 'box': base64Encode(box)}),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('collecting', () {
    test(
      'a device is offered once it has asked, and gets what is sent',
      () async {
        final o = outbox();
        expect(o.devices, isEmpty);
        final first = await ask(o);
        expect(first.kid, LinkOutbox.keyId(phonePublic));
        expect(first.items, isEmpty);
        expect(o.devices.single.name, 'Pixel');

        await o.send(
          o.devices.single,
          url: 'https://bsky.app/profile/a/post/b',
          title: 'Alice: hello',
          from: 'Bluesky',
        );
        final got = await ask(o);
        final link = await open(got.items.single);
        expect(link['url'], 'https://bsky.app/profile/a/post/b');
        expect(link['title'], 'Alice: hello');
        expect(link['from'], 'Bluesky');
      },
    );

    test('what a device has handled is not sent again', () async {
      final o = outbox();
      await ask(o);
      final d = o.devices.single;
      await o.send(d, url: 'https://a.example/');
      await o.send(d, url: 'https://b.example/');
      final both = await ask(o);
      expect(both.items, hasLength(2));
      final rest = await ask(o, after: both.items.first.id);
      expect(rest.items.single.id, both.items.last.id);
      expect((await ask(o, after: both.items.last.id)).items, isEmpty);
    });

    test('a waiting device is answered as soon as a link is sent', () async {
      final o = outbox();
      await ask(o);
      final waiting = ask(o, wait: const Duration(seconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await o.send(o.devices.single, url: 'https://now.example/');
      final got = await waiting.timeout(const Duration(seconds: 2));
      expect((await open(got.items.single))['url'], 'https://now.example/');
    });

    test('a link is only for the device it was sent to', () async {
      final o = outbox();
      final pc = await X25519().newKeyPair();
      final pcPublic = (await pc.extractPublicKey()).bytes;
      await ask(o);
      await ask(o, key: pcPublic, name: 'archbox');
      final phoneDevice = o.devices.firstWhere((d) => d.name == 'Pixel');
      await o.send(phoneDevice, url: 'https://phone.example/');
      expect((await ask(o, key: pcPublic, name: 'archbox')).items, isEmpty);
      expect((await ask(o)).items, hasLength(1));
    });
  });

  group('the devices offered', () {
    test('not once their sender has been removed', () async {
      final o = outbox();
      await ask(o);
      senders = ['Jo'];
      expect(o.devices, isEmpty);
    });

    test('not once they have not asked for a month', () async {
      final o = outbox();
      await ask(o);
      now = now.add(const Duration(days: 31));
      expect(o.devices, isEmpty);
    });

    test('the same device with a new key replaces the old', () async {
      final o = outbox();
      await ask(o);
      await o.send(o.devices.single, url: 'https://old.example/');
      final fresh = await X25519().newKeyPair();
      final freshPublic = (await fresh.extractPublicKey()).bytes;
      final got = await ask(o, key: freshPublic);
      expect(o.devices.single.kid, LinkOutbox.keyId(freshPublic));
      expect(got.items, isEmpty);
    });

    test('a sender has only so many', () async {
      final o = outbox();
      for (var i = 0; i < LinkOutbox.maxPerSender + 3; i++) {
        final pair = await X25519().newKeyPair();
        now = now.add(const Duration(minutes: 1));
        await ask(o, key: (await pair.extractPublicKey()).bytes, name: 'd$i');
      }
      expect(o.devices, hasLength(LinkOutbox.maxPerSender));
      expect(o.devices.last.name, 'd3');
    });

    test('a forgotten device is offered no more', () async {
      final o = outbox();
      await ask(o);
      o.forget(o.devices.single.kid);
      expect(o.devices, isEmpty);
    });
  });
}

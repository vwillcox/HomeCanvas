import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/services/computer_power.dart';
import 'package:home_canvas/services/link_outbox.dart';
import 'package:home_canvas/services/voice_commands.dart';
import 'package:home_canvas/services/wake_on_lan.dart';

void main() {
  late SimpleKeyPair pc;
  late List<int> pcPublic;
  late DateTime now;
  late LinkOutbox outbox;
  late List<(String, String)> woken;

  setUp(() async {
    pc = await X25519().newKeyPair();
    pcPublic = (await pc.extractPublicKey()).bytes;
    now = DateTime(2026, 11, 17, 23);
    outbox = LinkOutbox(
      senders: () => ['PC'],
      clock: () => now,
      persist: false,
    );
    woken = [];
  });

  /// The receiver on the computer asking, from [from] with [mac].
  Future<OutboxPoll> ask({
    String from = '10.0.0.239',
    String? mac = '0c:ef:15:80:d7:47',
    int after = 0,
  }) => outbox.poll(
    sender: 'PC',
    publicKey: pcPublic,
    name: 'omarchy',
    kind: 'computer',
    after: after,
    address: InternetAddress(from),
    wakeMac: mac,
  );

  ComputerPower power({Duration wakeWait = const Duration(minutes: 3)}) =>
      ComputerPower(
        outbox,
        wake: (mac, host) async {
          woken.add((mac, host));
          return true;
        },
        wakeWait: wakeWait,
      );

  group('where a computer is, and what it wakes on', () {
    test('kept from its asking, on the home network', () async {
      await ask();
      final d = outbox.devices.single;
      expect((d.address, d.wakeMac), ('10.0.0.239', '0c:ef:15:80:d7:47'));
      // And written down with it.
      final back = OutboxDevice.fromJson(d.toJson())!;
      expect((back.address, back.wakeMac), ('10.0.0.239', '0c:ef:15:80:d7:47'));
    });

    test(
      'not an address from outside the house, nor a MAC that is none',
      () async {
        await ask(from: '203.0.113.9', mac: 'not-a-mac');
        final d = outbox.devices.single;
        expect((d.address, d.wakeMac), (null, null));
        await ask(from: '192.168.1.20');
        expect(outbox.devices.single.address, '192.168.1.20');
        // An address from outside later leaves the home one as it was.
        await ask(from: '198.51.100.4');
        expect(outbox.devices.single.address, '192.168.1.20');
      },
    );

    test('home networks, and the rest', () {
      for (final a in [
        '10.0.0.239',
        '172.16.4.1',
        '172.31.0.9',
        '192.168.1.57',
      ]) {
        expect(LinkOutbox.isHomeAddress(InternetAddress(a)), isTrue, reason: a);
      }
      for (final a in ['172.32.0.1', '8.8.8.8', '192.169.0.1', '::1']) {
        expect(
          LinkOutbox.isHomeAddress(InternetAddress(a)),
          isFalse,
          reason: a,
        );
      }
    });

    test('here while it asks, gone a little after it stops', () async {
      await ask();
      final d = outbox.devices.single;
      expect(outbox.isHere(d), isTrue);
      now = now.add(const Duration(seconds: 65));
      expect(outbox.isHere(d), isTrue);
      now = now.add(const Duration(seconds: 10));
      expect(outbox.isHere(d), isFalse);
    });
  });

  group('switching it', () {
    test('off: a command sealed to it, which it alone can read', () async {
      await ask();
      expect(await power().setPower(false), PcSwitch.done);
      final poll = await ask();
      final said = jsonDecode(
        utf8.decode(await LinkOutbox.openLink(pc, poll.items.single.sealed)),
      );
      expect(said['do'], 'power');
      expect(said['state'], 'off');
      expect(said['at'], isNotNull);
      expect(woken, isEmpty);
    });

    test('off, when it is not asking: off already', () async {
      await ask();
      now = now.add(const Duration(minutes: 5));
      expect(await power().setPower(false), PcSwitch.already);
      now = now.add(const Duration(seconds: 1));
      expect((await ask()).items, isEmpty);
    });

    test('on, when it is asking: on already', () async {
      await ask();
      expect(await power().setPower(true), PcSwitch.already);
      expect(woken, isEmpty);
    });

    test('on: woken where it was, and done once it asks again', () async {
      await ask();
      now = now.add(const Duration(hours: 8));
      final switching = power().setPower(true);
      await Future<void>.delayed(Duration.zero);
      expect(woken, [('0c:ef:15:80:d7:47', '10.0.0.239')]);
      now = now.add(const Duration(seconds: 40));
      await ask();
      expect(await switching, PcSwitch.done);
    });

    test('on, and it never comes', () async {
      await ask();
      now = now.add(const Duration(hours: 8));
      final p = ComputerPower(
        outbox,
        wake: (mac, host) async => true,
        wakeWait: Duration.zero,
      );
      expect(await p.setPower(true), PcSwitch.notWoken);
    });

    test('on, with nothing to wake it by', () async {
      await ask(mac: null);
      now = now.add(const Duration(hours: 8));
      expect(await power().setPower(true), PcSwitch.cannotWake);
    });

    test('no computer at all', () async {
      expect(await power().setPower(true), PcSwitch.none);
      expect(power().any, isFalse);
    });

    test('by name, or the one most recently heard from', () async {
      await ask();
      expect(power().names, ['omarchy']);
      expect(power().find('Omarchy')?.name, 'omarchy');
      expect(power().find()?.name, 'omarchy');
    });

    test('a name not found is none, not another computer', () async {
      await ask();
      // Heard as the voice would say it: no hyphen.
      await outbox.poll(
        sender: 'PC',
        publicKey: List<int>.filled(32, 7),
        name: 'vince-laptop',
        kind: 'computer',
      );
      expect(power().find('vince laptop')?.name, 'vince-laptop');
      expect(power().find('kids laptop'), isNull);
      expect(
        await power().setPower(false, named: 'kids laptop'),
        PcSwitch.none,
      );
    });
  });

  group('the Wake-on-LAN packet, across the router', () {
    test('to everywhere here, to the machine, and to everywhere there', () {
      expect(
        [for (final a in WakeOnLan.targets('10.0.0.239')) a.address],
        ['255.255.255.255', '10.0.0.239', '10.0.0.255'],
      );
      expect(
        [for (final a in WakeOnLan.targets('a-name')) a.address],
        ['255.255.255.255'],
      );
    });
  });

  group('said', () {
    VoiceCommands panel({List<String> computers = const ['omarchy']}) =>
        VoiceCommands(
          pageCount: 1,
          pages: const [],
          widgets: const <DashboardWidgetConfig>[],
          nameOf: (_) => null,
          computers: computers,
        );

    (bool, String?)? pc(String heard, {List<String>? computers}) {
      final a = panel(computers: computers ?? const ['omarchy']).resolve(heard);
      if (a is! VoiceSwitch || !a.things.contains(HomeThing.computer)) {
        return null;
      }
      return (a.on, a.computer);
    }

    test('the PC, the computer, or its name', () {
      expect(pc('hey canvas turn the pc off'), (false, null));
      expect(pc('hey canvas turn off the computer'), (false, null));
      expect(pc('hey canvas switch the PC on'), (true, null));
      expect(pc('hey canvas p c on'), (true, null));
      expect(pc('hey canvas turn the omarchy pc off'), (false, 'omarchy'));
      expect(pc('hey canvas turn omarchy on'), (true, 'omarchy'));
    });

    test('of two, the one whose name was said', () {
      const two = ['vince-laptop', 'kids-laptop'];
      expect(pc('hey canvas turn off the kids laptop', computers: two), (
        false,
        'kids laptop',
      ));
      expect(pc('hey canvas turn the vince laptop off', computers: two), (
        false,
        'vince laptop',
      ));
      // Either of them: neither, rather than a guess.
      expect(pc('hey canvas turn off the laptop', computers: two), isNull);
    });

    test('a scene with "PC" in its name is Home Assistant’s still', () {
      expect(panel().resolve('hey canvas turn on pc mode'), isNull);
    });

    test('a computer’s name with the lights is a room, not the computer', () {
      expect(
        pc('hey canvas turn the office lights off', computers: ['office']),
        isNull,
      );
      expect(
        panel(
          computers: ['office'],
        ).resolve('hey canvas turn the office lights off'),
        isNull,
      );
      // With "PC", both.
      expect(pc('hey canvas turn the pc and the lights off'), (false, null));
    });
  });
}

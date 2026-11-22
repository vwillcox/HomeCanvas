import 'dart:io';

import 'package:flutter/foundation.dart';

/// Wake-on-LAN: the packet a network card listens for while the machine it
/// is in is switched off, and wakes it on.
///
/// For the television, on the panel's own network, and for a computer on
/// another network behind the router — which a broadcast does not cross.
/// So it goes to the address the machine was last at, and to that
/// network's broadcast, as well as to this one's: the router passes on the
/// first while it still remembers whose address it is, and the second if it
/// has been set to.
class WakeOnLan {
  /// The packet for [mac]: six 0xff bytes, then the address sixteen times.
  /// Null for anything that is not an address.
  static List<int>? magicPacket(String mac) {
    final parts = mac.trim().split(RegExp('[:-]'));
    if (parts.length != 6) return null;
    final hw = <int>[];
    for (final part in parts) {
      final b = part.length == 2 ? int.tryParse(part, radix: 16) : null;
      if (b == null) return null;
      hw.add(b);
    }
    return [
      for (var i = 0; i < 6; i++) 0xff,
      for (var i = 0; i < 16; i++) ...hw,
    ];
  }

  /// Where to send it, for a machine last at [host]: everywhere on this
  /// network, the machine itself, and everywhere on its network — taken to
  /// be a /24, as home networks are.
  static List<InternetAddress> targets(String host) {
    final at = InternetAddress.tryParse(host);
    return [
      InternetAddress('255.255.255.255'),
      if (at != null && at.type == InternetAddressType.IPv4) ...[
        at,
        InternetAddress('${host.substring(0, host.lastIndexOf('.'))}.255'),
      ],
    ];
  }

  /// Sends the packet for [mac] to [targets] of [host], on both the ports
  /// cards listen on, [rounds] times. Whether the machine wakes is up to it
  /// — and to the router, for one on another network: false only when
  /// nothing could be sent.
  ///
  /// More than once because a router forwarding to a machine that has gone
  /// quiet still sends to the address it remembers, while it checks
  /// whether that is still so: a few more packets get through in that time.
  static Future<bool> send(
    String mac,
    String host, {
    int rounds = 3,
    Duration apart = const Duration(milliseconds: 500),
  }) async {
    final packet = magicPacket(mac);
    if (packet == null) return false;
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      var sent = false;
      for (var round = 0; round < rounds; round++) {
        if (round > 0) await Future<void>.delayed(apart);
        for (final to in targets(host)) {
          for (final port in const [9, 7]) {
            try {
              sent = socket.send(packet, to, port) > 0 || sent;
            } on SocketException catch (e) {
              // One way not open — a broadcast refused — is not all of them.
              debugPrint('Wake-on-LAN: not to $to:$port: $e');
            }
          }
        }
      }
      socket.close();
      return sent;
    } catch (e) {
      debugPrint('Wake-on-LAN: not sent: $e');
      return false;
    }
  }
}

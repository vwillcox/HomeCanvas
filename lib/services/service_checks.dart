import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// What a check found.
enum CheckState { up, slow, down, unknown }

@immutable
class CheckResult {
  const CheckResult(this.state, {this.latency, this.detail});

  final CheckState state;
  final Duration? latency;

  /// Said instead of a time: "HTTP 503", "no reply".
  final String? detail;
}

/// One thing that should be up, as entered in the widget's settings.
///
/// The target says how to check it:
///   https://immich.lan   — a web request; up unless the server errors
///   10.0.0.76:445        — a connection to that port
///   macmini.local        — a ping
@immutable
class ServiceTarget {
  const ServiceTarget({required this.name, required this.target, this.mac});

  final String name;
  final String target;

  /// For Wake-on-LAN, when the thing is a computer that sleeps.
  final String? mac;

  static ServiceTarget? fromRow(Map<String, dynamic> row) {
    final target = '${row['target'] ?? ''}'.trim();
    if (target.isEmpty) return null;
    final name = '${row['name'] ?? ''}'.trim();
    final mac = '${row['mac'] ?? ''}'.trim();
    return ServiceTarget(
      name: name.isEmpty ? target : name,
      target: target,
      mac: normaliseMac(mac),
    );
  }

  bool get isWeb =>
      target.startsWith('http://') || target.startsWith('https://');

  /// (host, port) for a host:port target; null for anything else.
  (String, int)? get hostPort {
    if (isWeb) return null;
    final m = RegExp(r'^(.+):(\d{1,5})$').firstMatch(target);
    if (m == null) return null;
    return (m[1]!, int.parse(m[2]!));
  }

  static String? normaliseMac(String s) {
    final hex = s.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    return hex.length == 12 ? hex.toLowerCase() : null;
  }
}

/// Runs the checks. Stateless apart from the clock; the widget holds the
/// results and decides how often to ask.
class ServiceChecker {
  const ServiceChecker({this.slowAfter = const Duration(milliseconds: 800)});

  /// A reply slower than this is still up, but shown amber.
  final Duration slowAfter;

  static const _timeout = Duration(seconds: 5);

  Future<CheckResult> check(ServiceTarget t) async {
    try {
      if (t.isWeb) return await _web(t.target);
      final hp = t.hostPort;
      if (hp != null) return await _tcp(hp.$1, hp.$2);
      return await _ping(t.target);
    } catch (e) {
      return const CheckResult(CheckState.down, detail: 'no reply');
    }
  }

  CheckResult _timed(Stopwatch sw, {String? detail}) {
    final latency = sw.elapsed;
    return CheckResult(
      latency > slowAfter ? CheckState.slow : CheckState.up,
      latency: latency,
      detail: detail,
    );
  }

  Future<CheckResult> _web(String url) async {
    final client = HttpClient()
      ..connectionTimeout = _timeout
      // Home servers commonly have self-signed certificates. This only asks
      // whether something answers — nothing is sent and nothing is trusted.
      ..badCertificateCallback = (_, _, _) => true;
    final sw = Stopwatch()..start();
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      req.followRedirects = false;
      final res = await req.close().timeout(_timeout);
      await res.drain<void>().catchError((_) {});
      sw.stop();
      if (res.statusCode >= 500) {
        return CheckResult(CheckState.down, detail: 'HTTP ${res.statusCode}');
      }
      return _timed(sw);
    } finally {
      client.close(force: true);
    }
  }

  Future<CheckResult> _tcp(String host, int port) async {
    final sw = Stopwatch()..start();
    final socket = await Socket.connect(host, port, timeout: _timeout);
    sw.stop();
    socket.destroy();
    return _timed(sw);
  }

  Future<CheckResult> _ping(String host) async {
    final r = await Process.run('ping', [
      '-c',
      '1',
      '-W',
      '2',
      host,
    ]).timeout(_timeout);
    if (r.exitCode != 0) {
      return const CheckResult(CheckState.down, detail: 'no reply');
    }
    final ms = parsePing('${r.stdout}');
    final latency = ms == null
        ? null
        : Duration(microseconds: (ms * 1000).round());
    return CheckResult(
      latency != null && latency > slowAfter ? CheckState.slow : CheckState.up,
      latency: latency,
    );
  }

  static double? parsePing(String out) {
    final m = RegExp(r'time[=<]([\d.]+)\s*ms').firstMatch(out);
    return m == null ? null : double.tryParse(m[1]!);
  }

  /// Wakes a sleeping computer: the magic packet, broadcast on the LAN.
  static Future<void> wake(String mac) async {
    final bytes = <int>[
      ...List.filled(6, 0xff),
      for (var i = 0; i < 16; i++)
        for (var j = 0; j < 12; j += 2)
          int.parse(mac.substring(j, j + 2), radix: 16),
    ];
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.broadcastEnabled = true;
      for (final port in [9, 7]) {
        socket.send(bytes, InternetAddress('255.255.255.255'), port);
      }
    } finally {
      socket.close();
    }
  }
}

/// "38 ms", "1.2 s".
String formatLatency(Duration d) => d.inMilliseconds < 1000
    ? '${d.inMilliseconds} ms'
    : '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// What a site's certificate says about itself.
@immutable
class CertInfo {
  const CertInfo({
    required this.host,
    this.expires,
    this.issuer,
    this.error,
    this.trusted = true,
  });

  final String host;
  final DateTime? expires;

  /// "Let's Encrypt", from the issuer's organisation.
  final String? issuer;

  /// Why it could not be read, when it could not.
  final String? error;

  /// Whether the device trusts it — false for a self-signed or broken chain,
  /// which a browser would warn about.
  final bool trusted;

  int? daysLeft(DateTime now) => expires?.difference(now).inDays;
}

/// Reads the certificate a site presents on port 443 (or the port given, as
/// host:port). Nothing is sent but the handshake, and nothing is trusted
/// because of it: an untrusted certificate is read and reported, not used.
class CertChecker {
  const CertChecker({this.timeout = const Duration(seconds: 8)});

  final Duration timeout;

  Future<CertInfo> check(String target) async {
    final t = target
        .trim()
        .replaceFirst(RegExp(r'^https?://'), '')
        .split('/')
        .first;
    final m = RegExp(r'^(.+?)(?::(\d+))?$').firstMatch(t);
    final host = m?[1] ?? t;
    final port = int.tryParse(m?[2] ?? '') ?? 443;
    var trusted = true;
    try {
      final socket = await SecureSocket.connect(
        host,
        port,
        timeout: timeout,
        onBadCertificate: (_) {
          trusted = false;
          return true; // read it anyway, to say what is wrong with it
        },
      );
      final cert = socket.peerCertificate;
      socket.destroy();
      if (cert == null) return CertInfo(host: t, error: 'No certificate');
      return CertInfo(
        host: t,
        expires: cert.endValidity,
        issuer: issuerName(cert.issuer),
        trusted: trusted,
      );
    } on SocketException {
      return CertInfo(host: t, error: 'Not answering');
    } on HandshakeException {
      return CertInfo(host: t, error: 'No HTTPS');
    } on TimeoutException {
      return CertInfo(host: t, error: 'Not answering');
    } catch (_) {
      return CertInfo(host: t, error: 'Could not check');
    }
  }

  /// The organisation from an issuer like "/C=US/O=Let's Encrypt/CN=R11".
  static String? issuerName(String issuer) {
    final o = RegExp(r'O=([^/,]+)').firstMatch(issuer);
    if (o != null) return o[1]!.trim();
    final cn = RegExp(r'CN=([^/,]+)').firstMatch(issuer);
    return cn?[1]?.trim();
  }
}

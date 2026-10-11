import 'dart:io';

/// Whether [address] is this machine or on a home network: loopback, the
/// private IPv4 ranges, link-local, and IPv6's unique-local.
bool isLocalAddress(InternetAddress? address) {
  if (address == null) return false;
  if (address.isLoopback) return true;
  final a = address.address;
  if (a.startsWith('192.168.') || a.startsWith('10.')) return true;
  // 172.16.0.0 - 172.31.255.255
  final m = RegExp(r'^172\.(\d{1,2})\.').firstMatch(a);
  if (m != null) {
    final second = int.parse(m.group(1)!);
    if (second >= 16 && second <= 31) return true;
  }
  // Link-local, and IPv6 unique-local / loopback.
  return a.startsWith('169.254.') || a.startsWith('fd') || a == '::1';
}

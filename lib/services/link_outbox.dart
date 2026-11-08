import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as legacy show sha256;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import 'private_file.dart';

/// A phone or computer that collects links from the panel: the companion
/// app with "Receive links" on, or the receiver on a computer.
class OutboxDevice {
  OutboxDevice({
    required this.kid,
    required this.publicKey,
    required this.name,
    required this.kind,
    required this.sender,
    required this.seen,
  });

  /// First eight bytes of SHA-256 over [publicKey], as hex — worked out
  /// here, not taken from the device.
  final String kid;

  /// The device's own X25519 key. Links are sealed to it, so only that
  /// device can read them, whatever they pass through on the way.
  final List<int> publicKey;

  /// What the device calls itself: "Pixel 8", a computer's host name.
  final String name;

  /// `phone` or `computer`, for the icon.
  final String kind;

  /// Whose token it collects with — a name from the Share Inbox's senders.
  final String sender;

  DateTime seen;

  static OutboxDevice? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    try {
      return OutboxDevice(
        kid: '${j['kid']}',
        publicKey: base64Decode('${j['key']}'),
        name: '${j['name'] ?? ''}',
        kind: '${j['kind'] ?? 'phone'}',
        sender: '${j['sender'] ?? ''}',
        seen:
            DateTime.tryParse('${j['seen']}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'kid': kid,
    'key': base64Encode(publicKey),
    'name': name,
    'kind': kind,
    'sender': sender,
    'seen': seen.toIso8601String(),
  };
}

/// Links waiting for a device to collect them.
///
/// The panel cannot reach a phone, so a phone comes to it: the companion
/// app and the computer receiver each hold a request open on the Share
/// Inbox's port (`GET /outbox`), answered the moment a link is sent to them
/// or after [ShareInboxService.outboxWait] with nothing. A device that is
/// off or asleep collects what is waiting when it is next back, for up to
/// [keepFor].
///
/// Each link is sealed to the device's own key as it is queued — a fresh
/// X25519 key per link, as shares from the phone are — so it is only ever
/// stored and sent here in a form the one device can open.
class LinkOutbox extends ChangeNotifier {
  LinkOutbox({
    required this.senders,
    String? file,
    DateTime Function()? clock,
    this.persist = true,
  }) : _file = File(file ?? p.join(AppPaths.config, 'outbox.json')),
       _clock = clock ?? DateTime.now;

  /// The names of the Share Inbox's senders as they are now. A device whose
  /// sender has been removed is no longer offered.
  final Iterable<String> Function() senders;

  /// Off keeps everything in memory only — for tests.
  final bool persist;

  final File _file;
  final DateTime Function() _clock;

  /// A link not collected in this time is dropped.
  static const keepFor = Duration(days: 7);

  /// A device not heard from in this time is no longer offered, and after
  /// [forgetAfter] it is forgotten.
  static const offerFor = Duration(days: 30);
  static const forgetAfter = Duration(days: 60);

  /// At most this many links wait for one device; the oldest go first.
  static const maxWaiting = 50;

  /// At most this many devices for one sender — a token could otherwise list
  /// them without end. The one longest unheard from goes first.
  static const maxPerSender = 8;

  final Map<String, OutboxDevice> _devices = {};
  final Map<String, List<OutboxItem>> _waiting = {};
  final Map<String, List<Completer<void>>> _listeners = {};
  int _lastId = 0;

  /// The devices to offer, the most recently heard from first.
  List<OutboxDevice> get devices {
    final allowed = senders().toSet();
    final since = _clock().subtract(offerFor);
    return [
      for (final d in _devices.values)
        if (allowed.contains(d.sender) && d.seen.isAfter(since)) d,
    ]..sort((a, b) => b.seen.compareTo(a.seen));
  }

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final j = jsonDecode(await _file.readAsString());
      if (j is! Map<String, dynamic>) return;
      for (final d in (j['devices'] as List? ?? const [])) {
        final device = OutboxDevice.fromJson(d);
        if (device != null) _devices[device.kid] = device;
      }
      final waiting = j['waiting'];
      if (waiting is Map<String, dynamic>) {
        waiting.forEach((kid, items) {
          if (items is! List) return;
          _waiting[kid] = [for (final i in items) ?OutboxItem.fromJson(i)];
        });
      }
      _lastId = _waiting.values
          .expand((l) => l)
          .fold(_lastId, (m, i) => max(m, i.id));
      _prune();
      notifyListeners();
    } catch (e) {
      debugPrint('Outbox: could not read ${_file.path}: $e');
    }
  }

  /// Seals [url] to [device] and leaves it for it to collect.
  Future<void> send(
    OutboxDevice device, {
    required String url,
    String? title,
    String? from,
  }) async {
    final now = _clock();
    final sealed = await sealLink(
      publicKey: device.publicKey,
      kid: device.kid,
      plaintext: utf8.encode(
        jsonEncode({
          'url': url,
          'title': ?title,
          'from': ?from,
          'at': now.toUtc().toIso8601String(),
        }),
      ),
    );
    final list = _waiting.putIfAbsent(device.kid, () => []);
    list.add(OutboxItem(id: _nextId(now), at: now, sealed: sealed));
    if (list.length > maxWaiting) list.removeRange(0, list.length - maxWaiting);
    debugPrint('Outbox: a link for ${device.name} (${device.kid})');
    _wake(device.kid);
    unawaited(_save());
  }

  /// The links waiting for the device holding [publicKey] that are newer
  /// than [after], once there are any or [wait] has passed.
  ///
  /// [after] is the newest id the device has already handled: what it has
  /// is dropped here, so a reply lost on the way is sent again rather than
  /// lost with it.
  Future<OutboxPoll> poll({
    required String sender,
    required List<int> publicKey,
    required String name,
    required String kind,
    int after = 0,
    Duration wait = Duration.zero,
  }) async {
    final device = _register(sender, publicKey, name, kind);
    final list = _waiting[device.kid];
    if (list != null && after > 0) {
      final before = list.length;
      list.removeWhere((i) => i.id <= after);
      if (list.length != before) unawaited(_save());
    }
    var ready = _newer(device.kid, after);
    if (ready.isEmpty && wait > Duration.zero) {
      final heard = Completer<void>();
      _listeners.putIfAbsent(device.kid, () => []).add(heard);
      await heard.future.timeout(wait, onTimeout: () {});
      _listeners[device.kid]?.remove(heard);
      ready = _newer(device.kid, after);
    }
    return OutboxPoll(kid: device.kid, items: ready);
  }

  /// Stops offering [kid] and drops what was waiting for it.
  void forget(String kid) {
    if (_devices.remove(kid) == null) return;
    _waiting.remove(kid);
    notifyListeners();
    unawaited(_save());
  }

  OutboxDevice _register(
    String sender,
    List<int> publicKey,
    String name,
    String kind,
  ) {
    final kid = keyId(publicKey);
    final now = _clock();
    final known = _devices[kid];
    if (known != null) {
      // Written down at most hourly: a device asks every minute, and an SD
      // card is not worth wearing out over when it was last seen.
      final stale = now.difference(known.seen) > const Duration(hours: 1);
      known.seen = now;
      if (stale) unawaited(_save());
      return known;
    }
    // The same device with a new key — the app reinstalled — replaces the
    // old entry rather than appearing twice. What waited for the old key
    // was sealed to it and cannot be opened now.
    final replaced = [
      for (final d in _devices.values)
        if (d.sender == sender && d.name == name) d.kid,
    ];
    final theirs = _devices.values.where((d) => d.sender == sender).toList()
      ..sort((a, b) => a.seen.compareTo(b.seen));
    for (final d in theirs.take(max(0, theirs.length - maxPerSender + 1))) {
      replaced.add(d.kid);
    }
    for (final old in replaced) {
      _devices.remove(old);
      _waiting.remove(old);
    }
    final device = OutboxDevice(
      kid: kid,
      publicKey: List.unmodifiable(publicKey),
      name: name,
      kind: kind,
      sender: sender,
      seen: now,
    );
    _devices[kid] = device;
    debugPrint('Outbox: $sender\'s $name ($kid) collects links');
    notifyListeners();
    unawaited(_save());
    return device;
  }

  List<OutboxItem> _newer(String kid, int after) => [
    for (final i in _waiting[kid] ?? const <OutboxItem>[])
      if (i.id > after) i,
  ];

  void _wake(String kid) {
    for (final l in _listeners.remove(kid) ?? const <Completer<void>>[]) {
      if (!l.isCompleted) l.complete();
    }
  }

  /// Ids are microseconds since the epoch, always increasing: a device's
  /// "after" then still means the same thing if this file is lost.
  int _nextId(DateTime now) =>
      _lastId = max(_lastId + 1, now.microsecondsSinceEpoch);

  void _prune() {
    final now = _clock();
    _devices.removeWhere((_, d) => now.difference(d.seen) > forgetAfter);
    _waiting.removeWhere((kid, list) {
      list.removeWhere((i) => now.difference(i.at) > keepFor);
      return list.isEmpty || !_devices.containsKey(kid);
    });
  }

  Future<void> _saving = Future.value();

  /// Resolves once everything asked for so far is on disk.
  Future<void> get saved => _saving;

  Future<void> _save() =>
      persist ? _saving = _saving.then((_) => _write()) : _saving;

  Future<void> _write() async {
    _prune();
    try {
      await writePrivateFile(
        _file.path,
        jsonEncode({
          'devices': [for (final d in _devices.values) d.toJson()],
          'waiting': {
            for (final e in _waiting.entries)
              e.key: [for (final i in e.value) i.toJson()],
          },
        }),
      );
    } catch (e) {
      debugPrint('Outbox: could not save ${_file.path}: $e');
    }
  }

  /// [keyId] for a device's public key.
  static String keyId(List<int> publicKey) {
    final digest = legacy.sha256.convert(publicKey).bytes.take(8);
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Bound into the key and the seal, so a link can never be taken for a
  /// share going the other way, nor a share for a link.
  static const String label = 'homecanvas/link/v1';

  static final _x25519 = X25519();
  static final _aead = Chacha20.poly1305Aead();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// [plaintext] sealed to the device with [publicKey]:
  ///
  /// `{"v":1,"kid":…,"epk":…,"salt":…,"box":…}` — the key from X25519
  /// between a one-link key pair and the device's key, through HKDF-SHA256
  /// with [salt] and `label|kid|epk`; the box ChaCha20-Poly1305 under that
  /// key with a zero nonce (the key is never used again) and [label] as
  /// associated data, ciphertext then tag. The companion app's
  /// `link_receiver.dart` and `companion_pc/homecanvas-links` open it.
  static Future<Map<String, dynamic>> sealLink({
    required List<int> publicKey,
    required String kid,
    required List<int> plaintext,
  }) async {
    final ephemeral = await _x25519.newKeyPair();
    final epk = (await ephemeral.extractPublicKey()).bytes;
    final salt = SecretKeyData.random(length: 16).bytes;
    final shared = await _x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
    );
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(await shared.extractBytes()),
      nonce: salt,
      info: utf8.encode('$label|$kid|${base64Encode(epk)}'),
    );
    final box = await _aead.encrypt(
      plaintext,
      secretKey: key,
      nonce: List.filled(12, 0),
      aad: utf8.encode(label),
    );
    return {
      'v': 1,
      'kid': kid,
      'epk': base64Encode(epk),
      'salt': base64Encode(salt),
      'box': base64Encode([...box.cipherText, ...box.mac.bytes]),
    };
  }

  /// Opens what [sealLink] made — what a device does, here for the tests.
  @visibleForTesting
  static Future<List<int>> openLink(
    SimpleKeyPair device,
    Map<String, dynamic> sealed,
  ) async {
    final epk = base64Decode('${sealed['epk']}');
    final shared = await _x25519.sharedSecretKey(
      keyPair: device,
      remotePublicKey: SimplePublicKey(epk, type: KeyPairType.x25519),
    );
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(await shared.extractBytes()),
      nonce: base64Decode('${sealed['salt']}'),
      info: utf8.encode('$label|${sealed['kid']}|${sealed['epk']}'),
    );
    final box = base64Decode('${sealed['box']}');
    return _aead.decrypt(
      SecretBox(
        box.sublist(0, box.length - 16),
        nonce: List.filled(12, 0),
        mac: Mac(box.sublist(box.length - 16)),
      ),
      secretKey: key,
      aad: utf8.encode(label),
    );
  }
}

/// One link, sealed, waiting to be collected.
class OutboxItem {
  OutboxItem({required this.id, required this.at, required this.sealed});

  final int id;
  final DateTime at;
  final Map<String, dynamic> sealed;

  static OutboxItem? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final id = j['id'], sealed = j['sealed'];
    final at = DateTime.tryParse('${j['at']}');
    if (id is! int || sealed is! Map<String, dynamic> || at == null) {
      return null;
    }
    return OutboxItem(id: id, at: at, sealed: sealed);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'sealed': sealed,
  };
}

/// What a device is answered with: its key id, which it can show to be
/// compared with the panel's list, and the links.
class OutboxPoll {
  OutboxPoll({required this.kid, required this.items});

  final String kid;
  final List<OutboxItem> items;

  Map<String, dynamic> toJson() => {
    'kid': kid,
    'items': [
      for (final i in items) {'id': i.id, 'sealed': i.sealed},
    ],
  };
}

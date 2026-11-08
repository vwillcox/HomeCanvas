import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Links sent from the panel to this phone: "Send to…" on a post or a
/// story there, and a notification here that opens it.
///
/// The panel cannot reach a phone, so the phone asks it — a request held
/// open on the Share Inbox's port and answered the moment a link is sent,
/// or after 50 seconds with nothing — from a foreground service, so it
/// carries on with the app closed and the screen off. The notification
/// that says so can be hidden in Android's settings for the app.
///
/// Each link is sealed on the panel to this phone's own key, made here and
/// never sent anywhere, so the reverse proxy in between sees only bytes —
/// the mirror of what [SealedSender] does going the other way. The format
/// is `LinkOutbox.sealLink` in the kiosk's `lib/services/link_outbox.dart`.
class LinkReceiver {
  LinkReceiver._();

  static const _seedKey = 'deviceKeySeed';
  static const _onKey = 'receiveLinks';
  static const _afterKey = 'linksAfter';

  /// Bound into the key and the seal on the panel: `LinkOutbox.label`.
  static const String label = 'homecanvas/link/v1';

  static const int _wait = 50;

  static final _x25519 = X25519();
  static final _aead = Chacha20.poly1305Aead();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static Future<bool> get wanted async =>
      (await SharedPreferences.getInstance()).getBool(_onKey) ?? false;

  /// This phone's key, made the first time it is asked for.
  static Future<SimpleKeyPair> deviceKey() async {
    final prefs = await SharedPreferences.getInstance();
    final seed = prefs.getString(_seedKey);
    if (seed != null) {
      return _x25519.newKeyPairFromSeed(base64Decode(seed));
    }
    final pair = await _x25519.newKeyPair();
    await prefs.setString(
      _seedKey,
      base64Encode(await pair.extractPrivateKeyBytes()),
    );
    return pair;
  }

  /// First eight bytes of SHA-256 over the public key, as hex: what the
  /// panel lists this phone as, in Settings → Share Inbox.
  static Future<String> keyId(SimpleKeyPair pair) async {
    final public = (await pair.extractPublicKey()).bytes;
    final digest = (await Sha256().hash(public)).bytes.take(8);
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// The link inside [sealed], which was sealed to [pair].
  @visibleForTesting
  static Future<Map<String, dynamic>> open(
    SimpleKeyPair pair,
    Map<String, dynamic> sealed,
  ) async {
    if (sealed['v'] != 1) {
      throw FormatException('sealed with version ${sealed['v']}');
    }
    final epk = base64Decode('${sealed['epk']}');
    final shared = await _x25519.sharedSecretKey(
      keyPair: pair,
      remotePublicKey: SimplePublicKey(epk, type: KeyPairType.x25519),
    );
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(await shared.extractBytes()),
      nonce: base64Decode('${sealed['salt']}'),
      info: utf8.encode('$label|${sealed['kid']}|${sealed['epk']}'),
    );
    final box = base64Decode('${sealed['box']}');
    final plain = await _aead.decrypt(
      SecretBox(
        box.sublist(0, box.length - 16),
        nonce: List.filled(12, 0),
        mac: Mac(box.sublist(box.length - 16)),
      ),
      secretKey: key,
      aad: utf8.encode(label),
    );
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }

  /// Sets the service up. Call before [start], once per run of the app.
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'collecting',
        channelName: 'Collecting links',
        channelDescription:
            'Shown while the app is waiting for links from the panel. '
            'Turn this one off to hide it; links still arrive.',
        channelImportance: NotificationChannelImportance.MIN,
        priority: NotificationPriority.MIN,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Asks for what it needs and starts collecting. False if Android said
  /// no to showing notifications, without which a link could not be shown.
  static Future<bool> start() async {
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      if (await FlutterForegroundTask.requestNotificationPermission() !=
          NotificationPermission.granted) {
        return false;
      }
    }
    // Left out of battery optimisation, or Android stops the phone asking
    // once it has been still for a while.
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    await (await SharedPreferences.getInstance()).setBool(_onKey, true);
    await deviceKey();
    await restart();
    return true;
  }

  /// Starts it again, to pick up a changed address, token or name.
  static Future<void> restart() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    await FlutterForegroundTask.startService(
      serviceId: 7,
      serviceTypes: [ForegroundServiceTypes.remoteMessaging],
      notificationTitle: 'Ready for links from the panel',
      notificationText: 'Send one from a post or a story there',
      callback: startLinkReceiver,
    );
  }

  static Future<void> stop() async {
    await (await SharedPreferences.getInstance()).setBool(_onKey, false);
    await FlutterForegroundTask.stopService();
  }

  static final notifications = FlutterLocalNotificationsPlugin();

  static Future<void> initNotifications({
    void Function(NotificationResponse)? onTap,
  }) => notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: onTap,
  );

  /// Opens the page a link notification was for, in the browser.
  static Future<void> openPayload(String? payload) async {
    final uri = Uri.tryParse(payload ?? '');
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

@pragma('vm:entry-point')
void startLinkReceiver() {
  FlutterForegroundTask.setTaskHandler(_Collector());
}

/// Asks the panel for links, over and over, until the service stops.
class _Collector extends TaskHandler {
  http.Client? _client;
  bool _stopped = false;

  /// Whether the service's notification is saying something is wrong.
  bool _failing = false;

  void _status(String? problem) {
    if (problem == null && !_failing) return;
    _failing = problem != null;
    unawaited(
      FlutterForegroundTask.updateService(
        notificationTitle: problem == null
            ? 'Ready for links from the panel'
            : 'Not collecting links',
        notificationText: problem ?? 'Send one from a post or a story there',
      ),
    );
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await LinkReceiver.initNotifications();
    unawaited(_run());
  }

  Future<void> _run() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString('kioskAddress') ?? '';
    final token = prefs.getString('kioskToken') ?? '';
    final name = prefs.getString('deviceName') ?? '';
    if (address.isEmpty || token.isEmpty) return;
    final pair = await LinkReceiver.deviceKey();
    final public = base64Encode((await pair.extractPublicKey()).bytes);
    var after = prefs.getInt(LinkReceiver._afterKey) ?? 0;
    var pause = const Duration(seconds: 2);

    while (!_stopped) {
      final client = _client = http.Client();
      try {
        final response = await client
            .get(
              Uri.parse(
                '$address/outbox?after=$after&wait=${LinkReceiver._wait}',
              ),
              headers: {
                'Authorization': 'Bearer $token',
                'X-Device-Key': public,
                'X-Device-Name': Uri.encodeComponent(
                  name.isEmpty ? 'Phone' : name,
                ),
                'X-Device-Kind': 'phone',
              },
            )
            .timeout(const Duration(seconds: LinkReceiver._wait + 20));
        if (response.statusCode != 200) {
          // A token taken away is not coming back by itself.
          pause = response.statusCode == 401
              ? const Duration(minutes: 5)
              : _longer(pause);
          _status(
            response.statusCode == 401
                ? 'The panel turned the token down'
                : 'The panel answered ${response.statusCode}',
          );
          await Future<void>.delayed(pause);
          continue;
        }
        pause = const Duration(seconds: 2);
        _status(null);
        final items =
            (jsonDecode(response.body) as Map<String, dynamic>)['items']
                as List? ??
            const [];
        for (final item in items.cast<Map<String, dynamic>>()) {
          await _show(pair, item);
          after = item['id'] as int > after ? item['id'] as int : after;
        }
        if (items.isNotEmpty) await prefs.setInt(LinkReceiver._afterKey, after);
      } catch (e) {
        if (_stopped) break;
        debugPrint('Links: $e');
        _status('Cannot reach the panel');
        await Future<void>.delayed(pause);
        pause = _longer(pause);
      } finally {
        client.close();
      }
    }
  }

  static Duration _longer(Duration d) =>
      d * 2 > const Duration(minutes: 1) ? const Duration(minutes: 1) : d * 2;

  Future<void> _show(SimpleKeyPair pair, Map<String, dynamic> item) async {
    try {
      final link = await LinkReceiver.open(
        pair,
        item['sealed'] as Map<String, dynamic>,
      );
      final url = '${link['url'] ?? ''}';
      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        return;
      }
      final from = '${link['from'] ?? uri.host}';
      final title = '${link['title'] ?? url}';
      await LinkReceiver.notifications.show(
        id: (item['id'] as int) & 0x7fffffff,
        title: 'From the panel · $from',
        body: title,
        payload: url,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'links',
            'Links from the panel',
            channelDescription: 'A link sent with “Send to…” on the panel.',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(title),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Links: could not open one: $e');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _stopped = true;
    _client?.close();
  }
}

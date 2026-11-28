import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
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
/// or after five minutes with nothing — from a foreground service, so it
/// carries on with the app closed and the screen off. The notification
/// that says so can be hidden in Android's settings for the app.
///
/// It sips the battery. The phone sleeps while a request is held: the
/// panel's answer wakes it, as any message does. It is never kept awake,
/// nor its Wi-Fi at full power, both of which this once did, for good — the
/// phone could not sleep at all. A panel on the home network is asked only
/// over Wi-Fi, Ethernet or a VPN, never over mobile data, where it cannot
/// answer; away from home nothing is asked until the network changes, and
/// links wait on the panel (a week) until the phone is back.
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
  static const _waitKey = 'linksWait';

  /// Which [options] the service was last started with. Android restarts a
  /// running service after the app is updated with the options it had,
  /// which is how phones kept the old locks: see [_Collector.onStart].
  static const _optionsKey = 'serviceOptions';
  static const int _optionsVersion = 2;

  /// Bound into the key and the seal on the panel: `LinkOutbox.label`.
  static const String label = 'homecanvas/link/v1';

  /// How long the panel is asked to hold a request, in seconds: the most
  /// it holds one (`ShareInboxService.outboxWait`). Through a reverse proxy
  /// that cuts that short, [proxyWait] (`ShareInboxService.proxyWait`).
  static const int longWait = 300;
  static const int proxyWait = 50;

  /// Whether a request held for [wait] seconds that ended in [status] was
  /// cut short by a proxy in between: a gateway that gave up waiting
  /// (nginx's 504, Cloudflare's 524, a 502 from others).
  @visibleForTesting
  static bool cutShort(int status, int wait) =>
      wait > proxyWait && (status == 502 || status == 504 || status == 524);

  /// Whether [address] is a panel on a home network: a private or
  /// link-local address (or Tailscale's), or a name only a home network
  /// answers — `.local`, `.lan`, `.home.arpa`, `.internal`, or no dot.
  @visibleForTesting
  static bool atHome(String address) {
    final host = (Uri.tryParse(address)?.host ?? '').toLowerCase();
    if (host.isEmpty) return false;
    final ip = InternetAddress.tryParse(host);
    if (ip == null) {
      return !host.contains('.') ||
          host.endsWith('.local') ||
          host.endsWith('.lan') ||
          host.endsWith('.home.arpa') ||
          host.endsWith('.internal');
    }
    final b = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4) {
      return b[0] == 10 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168) ||
          (b[0] == 169 && b[1] == 254) ||
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127);
    }
    return (b[0] & 0xfe) == 0xfc || (b[0] == 0xfe && (b[1] & 0xc0) == 0x80);
  }

  /// Whether the panel at [address] is worth asking over [network]: not at
  /// all with no network, and one at home only over Wi-Fi, Ethernet or a
  /// VPN. Over mobile data it cannot answer, and each try would wake the
  /// radio for nothing.
  @visibleForTesting
  static bool worthAsking(String address, List<ConnectivityResult> network) {
    if (network.every((n) => n == ConnectivityResult.none)) return false;
    if (!atHome(address)) return true;
    return network.any(
      (n) =>
          n == ConnectivityResult.wifi ||
          n == ConnectivityResult.ethernet ||
          n == ConnectivityResult.vpn,
    );
  }

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

  /// No wake lock and no Wi-Fi lock. Both were on, held for as long as the
  /// service ran: the phone could not sleep, nor its Wi-Fi rest, all day.
  /// A held request needs neither — the answer wakes the phone.
  static ForegroundTaskOptions get options => ForegroundTaskOptions(
    eventAction: ForegroundTaskEventAction.nothing(),
    autoRunOnBoot: true,
    autoRunOnMyPackageReplaced: true,
    allowWakeLock: false,
    allowWifiLock: false,
  );

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
      foregroundTaskOptions: options,
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
    await (await SharedPreferences.getInstance()).setInt(
      _optionsKey,
      _optionsVersion,
    );
    await FlutterForegroundTask.startService(
      serviceId: 7,
      serviceTypes: [ForegroundServiceTypes.remoteMessaging],
      notificationTitle: 'Ready for links from the panel',
      notificationText: 'Send one from a post or a story there',
      callback: startLinkReceiver,
    );
  }

  /// Started again if the system stopped it, or if it is running with the
  /// options of an older version of the app.
  static Future<void> ensureRunning() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await FlutterForegroundTask.isRunningService ||
        prefs.getInt(_optionsKey) != _optionsVersion) {
      await restart();
    }
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

  /// The network as Android last said, and the watch on it.
  List<ConnectivityResult> _network = const [];
  StreamSubscription<List<ConnectivityResult>>? _watch;

  /// Completed when the network changes, to end a wait early.
  Completer<void>? _changed;

  /// The request on its way was dropped for a change of network, which is
  /// not the panel failing.
  bool _dropped = false;

  /// What the service's notification says, so it is only updated on a
  /// change.
  String _said = 'ready';

  void _say(String state) {
    if (state == _said) return;
    _said = state;
    final (title, text) = switch (state) {
      'ready' => (
        'Ready for links from the panel',
        'Send one from a post or a story there',
      ),
      'away' => (
        'Links wait on the panel',
        'Collected when you are back on its network',
      ),
      _ => ('Not collecting links', state),
    };
    unawaited(
      FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      ),
    );
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Restarted by Android after an update, still with the old options and
    // their locks: put right here, without waiting for the app to be opened.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt(LinkReceiver._optionsKey) !=
        LinkReceiver._optionsVersion) {
      await prefs.setInt(
        LinkReceiver._optionsKey,
        LinkReceiver._optionsVersion,
      );
      try {
        await FlutterForegroundTask.updateService(
          foregroundTaskOptions: LinkReceiver.options,
        );
        await FlutterForegroundTask.restartService();
        return;
      } catch (e) {
        debugPrint('Links: could not restart with new options: $e');
      }
    }
    await LinkReceiver.initNotifications();
    unawaited(_run());
  }

  /// Waits for [d], or with none until the network changes; either ends
  /// early on a change of network, or the service stopping.
  Future<void> _wait([Duration? d]) async {
    final changed = _changed = Completer<void>();
    await Future.any([changed.future, if (d != null) Future<void>.delayed(d)]);
    _changed = null;
  }

  void _wake() {
    final c = _changed;
    if (c != null && !c.isCompleted) c.complete();
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
    var wait = prefs.getInt(LinkReceiver._waitKey) ?? LinkReceiver.longWait;
    var pause = _first;

    final connectivity = Connectivity();
    try {
      _network = await connectivity.checkConnectivity();
    } catch (e) {
      // Not known: asked anyway, as before there was a watch on it.
      _network = const [ConnectivityResult.other];
    }
    _watch = connectivity.onConnectivityChanged.listen((network) {
      _network = network;
      // Home again, or onto another network: the panel is asked at once
      // over the new one, and whatever was asked over the old abandoned.
      pause = _first;
      if (_client != null) {
        _dropped = true;
        _client?.close();
        _client = null;
      }
      _wake();
    });

    while (!_stopped) {
      if (!LinkReceiver.worthAsking(address, _network)) {
        _say('away');
        await _wait();
        continue;
      }
      // Kept between requests: one connection for the day rather than a new
      // one every few minutes.
      final client = _client ??= http.Client();
      _dropped = false;
      try {
        final response = await client
            .get(
              Uri.parse('$address/outbox?after=$after&wait=$wait'),
              headers: {
                'Authorization': 'Bearer $token',
                'X-Device-Key': public,
                'X-Device-Name': Uri.encodeComponent(
                  name.isEmpty ? 'Phone' : name,
                ),
                'X-Device-Kind': 'phone',
              },
            )
            .timeout(Duration(seconds: wait + 20));
        if (LinkReceiver.cutShort(response.statusCode, wait)) {
          // A proxy will not hold one that long: asked for less from now on.
          wait = LinkReceiver.proxyWait;
          await prefs.setInt(LinkReceiver._waitKey, wait);
          continue;
        }
        if (response.statusCode != 200) {
          // A token taken away is not coming back by itself.
          pause = response.statusCode == 401
              ? const Duration(minutes: 5)
              : _longer(pause);
          _say(
            response.statusCode == 401
                ? 'The panel turned the token down'
                : 'The panel answered ${response.statusCode}',
          );
          await _wait(pause);
          continue;
        }
        pause = _first;
        _say('ready');
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
        if (identical(_client, client)) {
          client.close();
          _client = null;
        }
        if (_dropped) {
          _dropped = false;
          continue;
        }
        debugPrint('Links: $e');
        _say('Cannot reach the panel');
        await _wait(pause);
        pause = _longer(pause);
      }
    }
  }

  static const _first = Duration(seconds: 2);

  /// Twice as long each time, to five minutes: a panel restarting is back
  /// within a few tries, and one switched off is not asked all day. Coming
  /// home, or any change of network, asks at once whatever this has got to.
  static Duration _longer(Duration d) =>
      d * 2 > const Duration(minutes: 5) ? const Duration(minutes: 5) : d * 2;

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
    await _watch?.cancel();
    _wake();
  }
}

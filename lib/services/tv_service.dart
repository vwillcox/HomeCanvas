import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../config/app_config.dart' show TvSettings;
import 'config_service.dart';
import 'private_file.dart';
import 'retry_schedule.dart';
import 'vidaa_client.dart';
import 'wake_on_lan.dart';
import '../l10n/l10n.dart';

/// Talks to a Hisense VIDAA television.
///
/// A port of the standalone vidaa_remote app's controller, moved in here so
/// the dashboard's TV widget can drive the set directly. The protocol work —
/// the credential derivation, the MQTT topics, pairing — is that app's, and
/// is reused rather than rewritten.
///
/// Only one client may hold a session: the MQTT client id is derived from the
/// device UUID, so a second connection using the same UUID displaces the
/// first and the two then fight over it. Two remotes therefore need two
/// UUIDs, which is what the standalone app and this widget now have — see the
/// TV Remote section of INSTALL.md.

enum ConnState { disconnected, connecting, connected, needsPairing, error }

/// Owns the VidaaClient, connection lifecycle, token persistence and pairing.
class TvService extends ChangeNotifier {
  TvService(this._config);

  final ConfigService _config;

  TvSettings get settings => _config.config.tv;
  String get host => settings.host;
  String get uuid => settings.uuid;

  VidaaClient? _client;
  ConnState conn = ConnState.disconnected;
  String? lastError;

  /// Whether a connection is wanted: something asked for one and has not asked
  /// to stop. Retries only happen while this is true.
  bool _wanted = false;
  Timer? _retry;

  /// Backoff between attempts, shared with the widgets that poll the network.
  ///
  /// The failure this exists for is the panel's own boot: labwc starts the
  /// session, the session starts this, and the USB network adapter is still
  /// waiting on DHCP. The first attempt fails with "network is unreachable"
  /// and, before this, that was that — the remote sat there looking alive,
  /// connected to nothing, until somebody thought to restart it. It went
  /// three days once.
  ///
  /// [RetrySchedule.settled] never really applies here: a connection has no
  /// ordinary refresh interval, and once connected there is no timer at all.
  /// It matches the ceiling so the backoff is never clamped below it.
  final RetrySchedule _schedule = RetrySchedule(
    settled: const Duration(seconds: 60),
    first: const Duration(seconds: 4),
    ceiling: const Duration(seconds: 60),
  );

  /// Fires shortly before the access token expires, to renew it while the
  /// session is still up. Without it a panel left running past the token's
  /// two days had nothing good to reconnect with, and one left past the
  /// refresh token's thirty would have to pair again.
  Timer? _renewal;

  void _cancelRenewal() {
    _renewal?.cancel();
    _renewal = null;
  }

  void _scheduleRenewal() {
    _cancelRenewal();
    if (_accessToken == null || _accessExpiry == 0) return;
    // _accessValid already allows five minutes; renew ten before the end.
    final secs = (_accessExpiry - 600 - _nowSec()).clamp(60, 1 << 30);
    _renewal = Timer(Duration(seconds: secs), () {
      _renewal = null;
      if (_wanted) unawaited(_attemptOnce(renew: true));
    });
  }

  /// How many attempts have failed in a row. Zero once connected.
  int get failedAttempts => _schedule.failures;

  /// Whether another attempt is booked in.
  bool get retryPending => _retry != null;

  final TvState state = TvState();
  bool get isConnected => conn == ConnState.connected;

  List<int>? _certBytes;
  List<int>? _keyBytes;
  String? _accessToken;
  String? _refreshToken;

  /// Where the session token lives, under $HOME/.config/vidaa (override the
  /// whole path with $VIDAA_TOKEN_FILE).
  ///
  /// The file name carries the UUID, because a token belongs to the identity
  /// that obtained it. The standalone remote app stores its own alongside
  /// this one, and a shared file meant whichever paired last overwrote the
  /// other's token — leaving the first to re-pair, which re-pairs the second,
  /// and so on.
  File get _tokenFileSync {
    final override = Platform.environment['VIDAA_TOKEN_FILE'];
    if (override != null && override.isNotEmpty) return File(override);
    final home = Platform.environment['HOME'] ?? '.';
    final dir = Directory('$home/.config/vidaa');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final safe = uuid.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
    return File('${dir.path}/vidaa_token_$safe.json');
  }

  Future<File> get _tokenFile async => _tokenFileSync;

  /// The TV's input list as it last sent it, beside the token.
  File get _sourcesFile => File(
    _tokenFileSync.path.replaceFirst(RegExp(r'\.json$'), '_inputs.json'),
  );

  /// Set as a PIN is accepted: the one time asking for the inputs is free,
  /// because the code has only just left the screen.
  bool _askForInputs = false;

  /// Loads the client certificate and key the television's MQTT interface
  /// requires.
  ///
  /// These are the manufacturer's own credentials — the set accepts no other —
  /// so they cannot be generated or rotated. They are still kept out of the
  /// repository (`assets/certs/*.key` is git-ignored); supply a copy at that
  /// path, as the TV Remote section of INSTALL.md describes.
  ///
  /// Without it this throws [TvCredentialsMissing], which the caller turns
  /// into a clear message rather than the mbedTLS handshake error an empty key
  /// produces four steps later.
  Future<void> _loadAssets() async {
    _certBytes ??= await _loadCert('assets/certs/vidaa_client.pem');
    _keyBytes ??= await _loadCert('assets/certs/vidaa_client.key');
  }

  static Future<List<int>> _loadCert(String asset) async {
    List<int> bytes;
    try {
      bytes = (await rootBundle.load(asset)).buffer.asUint8List();
    } catch (e) {
      throw TvCredentialsMissing('$asset is not bundled with this build');
    }
    // A blank or placeholder file is the more likely failure than a missing
    // one, since removing a leaked key tends to leave the path behind.
    if (bytes.length < 64) {
      throw TvCredentialsMissing('$asset is empty or a placeholder');
    }
    return bytes;
  }

  int _accessExpiry = 0; // unix seconds
  int _refreshExpiry = 0;

  int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
  // 5-minute safety margin so we refresh slightly before actual expiry.
  bool get _accessValid =>
      _accessToken != null && _nowSec() < _accessExpiry - 300;

  Future<void> _loadToken() async {
    try {
      final f = await _tokenFile;
      if (f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        if (j['host'] == host) {
          _accessToken = j['accesstoken'] as String?;
          _refreshToken = j['refreshtoken'] as String?;
          _accessExpiry = (j['access_expiry'] as num?)?.toInt() ?? 0;
          _refreshExpiry = (j['refresh_expiry'] as num?)?.toInt() ?? 0;
        }
      }
    } catch (_) {}
  }

  Future<void> _saveToken(Map<String, dynamic> tok) async {
    _accessToken = tok['accesstoken'] as String?;
    _refreshToken = tok['refreshtoken'] as String? ?? _refreshToken;
    final now = _nowSec();
    final aDays = (tok['accesstoken_duration_day'] as num?)?.toInt() ?? 2;
    final rDays = (tok['refreshtoken_duration_day'] as num?)?.toInt() ?? 30;
    // Prefer the TV-provided issue time; fall back to now.
    final aTime = int.tryParse('${tok['accesstoken_time'] ?? now}') ?? now;
    final rTime = int.tryParse('${tok['refreshtoken_time'] ?? now}') ?? now;
    _accessExpiry = aTime + aDays * 86400;
    _refreshExpiry = rTime + rDays * 86400;
    final f = await _tokenFile;
    // Private and whole: these tokens are as good as the TV's remote.
    await writePrivateFile(
      f.path,
      jsonEncode({
        'host': host,
        'accesstoken': _accessToken,
        'refreshtoken': _refreshToken,
        'access_expiry': _accessExpiry,
        'refresh_expiry': _refreshExpiry,
        'saved_at': DateTime.now().toIso8601String(),
      }),
    );
  }

  void _setConn(ConnState s, {String? err, bool retry = false}) {
    conn = s;
    lastError = err;
    if (s == ConnState.connected) {
      _schedule.reset();
      _cancelRetry();
    } else if (retry) {
      _scheduleRetry();
    }
    notifyListeners();
  }

  /// Book another attempt.
  ///
  /// Not booked for [ConnState.needsPairing] — that is waiting on a person to
  /// read a number off the television, and reconnecting underneath them would
  /// throw the PIN away. Nor for missing credentials, which no amount of
  /// waiting fixes.
  void _scheduleRetry() {
    _cancelRetry();
    if (!_wanted) return;
    _retry = Timer(_schedule.next(hasContent: false), () {
      _retry = null;
      if (_wanted && conn != ConnState.connected) unawaited(_attemptOnce());
    });
  }

  void _cancelRetry() {
    _retry?.cancel();
    _retry = null;
  }

  /// Build a fresh client (optionally token-authenticated) and connect it.
  Future<bool> _openAndConnect(String? token) async {
    _client?.disconnect();
    // The set says whether it is on to each session as it begins; until
    // this one has heard, what an old one heard may no longer be so.
    state.powerKnown = false;
    late final VidaaClient client;
    client = VidaaClient(
      host: host,
      uuid: uuid,
      certBytes: _certBytes,
      keyBytes: _keyBytes,
      accessToken: token,
      state: state,
      onState: (_) => notifyListeners(),
      onLog: (s) => debugPrint('[vidaa] $s'),
      onSourceList: (payload) {
        try {
          _sourcesFile.writeAsStringSync(payload);
        } catch (e) {
          debugPrint('[vidaa] could not keep the input list: $e');
        }
      },
      onLost: () {
        if (!identical(_client, client)) return;
        // A pairing session counts too. Ignoring its loss left the widget
        // asking for a PIN over a connection that was gone: "Show PIN" was
        // dropped as "not sent, not connected", nothing came up on the TV,
        // and nothing tried again, for days.
        if (conn != ConnState.connected && conn != ConnState.needsPairing) {
          return;
        }
        _cancelRenewal();
        _setConn(ConnState.connecting, retry: true);
      },
    );
    _client = client;
    try {
      final ok = await _client!.connect();
      if (!ok && token != null && !client.refused) _unanswered = true;
      return ok;
    } catch (e) {
      // Recorded, not acted on: this is one route out of several the caller
      // is still working through, and whether to retry is its decision.
      lastError = '$e';
      if (token != null) _unanswered = true;
      return false;
    }
  }

  /// Set during an attempt when a token was offered and the television never
  /// answered — see [VidaaClient.refused]. Such an attempt proves nothing
  /// about the tokens, so it ends in a retry rather than in pairing.
  bool _unanswered = false;

  void _finishConnected() {
    // Not the state: asking for it puts the pairing code up on the TV, and
    // the set announces its state to every client that connects regardless.
    // Tested against the set: connecting alone, or asking for the volume,
    // brings no code; asking for the state does, every time.
    _client!.getVolume();
    // Not asked for here. The set runs its authentication check whenever it
    // is asked for the source list, which puts the pairing code up on the
    // television — and asking on every connect put it up each time the
    // panel restarted, with a perfectly good token. The list is kept on
    // disk instead, and asked for again only just after pairing, when the
    // code has been on screen anyway, or when someone taps refresh.
    if (_askForInputs) {
      _askForInputs = false;
      _client!.getSourceList();
    } else if (state.sources.isEmpty) {
      try {
        final kept = _sourcesFile;
        if (kept.existsSync()) _client!.loadSourceList(kept.readAsStringSync());
      } catch (_) {}
    }
    _setConn(ConnState.connected);
    _scheduleRenewal();
    _learnMac();
  }

  /// Notes the set's hardware address, for Wake-on-LAN, from the panel's
  /// neighbour table — where reaching the set has just put it. Read again on
  /// every connection, so a new set at the same address is picked up too.
  void _learnMac() {
    try {
      final mac = macIn(File('/proc/net/arp').readAsStringSync(), host);
      if (mac == null || mac == settings.mac) return;
      settings.mac = mac;
      unawaited(_config.save());
      debugPrint('[vidaa] the television is $mac, for Wake-on-LAN');
    } catch (_) {
      // Not Linux, or no table to read: Wake-on-LAN just isn't available.
    }
  }

  /// The hardware address `/proc/net/arp` gives [ip], or null when it has
  /// none — not listed, or a lookup that was never answered.
  @visibleForTesting
  static String? macIn(String arpTable, String ip) {
    for (final line in arpTable.split('\n').skip(1)) {
      final f = line.trim().split(RegExp(r'\s+'));
      if (f.length < 4 || f[0] != ip || f[2] == '0x0') continue;
      final mac = f[3].toLowerCase();
      if (WakeOnLan.magicPacket(mac) == null || mac == '00:00:00:00:00:00') {
        continue;
      }
      return mac;
    }
    return null;
  }

  /// The television's inputs, empty until it has answered.
  List<TvSource> get sources => state.sources;

  /// Re-reads the inputs. Only for an explicit user action — see the note in
  /// [_finishConnected] about what asking costs: it shows the pairing code on
  /// the TV for a moment.
  void refreshSources() => _client?.getSourceList();

  /// Ask for a connection, and keep asking.
  ///
  /// Returns once the first attempt has finished, which is not the same as
  /// being connected: if it failed, another is already booked. Call it as
  /// often as you like — a second call while one is pending just brings the
  /// next attempt forward.
  Future<void> connect() async {
    _wanted = true;
    _cancelRetry();
    _schedule.reset();
    await _attemptOnce();
  }

  /// The attempt under way, if one is: a second asker waits for it rather
  /// than starting another, which would drop the first one's session from
  /// under it.
  Future<void>? _attempting;

  Future<void> _attemptOnce({bool renew = false}) => _attempting ??= _attempt(
    renew: renew,
  ).whenComplete(() => _attempting = null);

  /// Stop trying, and drop any session.
  ///
  /// The counterpart to [connect]: without it a service told to stop would
  /// reconnect itself a few seconds later.
  void disconnect() {
    _wanted = false;
    _cancelRetry();
    _cancelRenewal();
    _client?.disconnect();
    _client = null;
    _setConn(ConnState.disconnected);
  }

  /// One attempt: a saved or refreshed token if possible, else pairing.
  ///
  /// [renew] goes straight to the refresh token, for a token still valid but
  /// about to stop being.
  Future<void> _attempt({bool renew = false}) async {
    // Nothing to connect to. Checked before anything else so an unconfigured
    // or switched-off television costs no socket, no timer and no error on
    // screen — and so the retry loop cannot spin on a blank address.
    if (!settings.isConfigured) {
      _wanted = false;
      _cancelRetry();
      _setConn(ConnState.disconnected);
      return;
    }
    _setConn(ConnState.connecting);
    try {
      await _loadAssets();
    } on TvCredentialsMissing catch (e) {
      // Stops here rather than connecting without them: the handshake would
      // fail anyway, several layers down, with an error naming TLS instead of
      // the thing actually missing.
      // Not retried: no amount of waiting puts a file on the disk.
      _setConn(
        ConnState.error,
        err: tr(
          'widget.tv.tvClientCertificateNotSet',
          'TV client certificate not set up — {message}',
          {'message': e.message},
        ),
      );
      return;
    }
    await _loadToken();
    _unanswered = false;

    // A) Access token still valid -> use it directly.
    if (!renew && _accessValid && await _openAndConnect(_accessToken)) {
      _finishConnected();
      return;
    }
    // B) Refresh an expired/unknown session using the refresh token.
    if (_refreshToken != null && await _refreshAndConnect()) {
      return;
    }
    // C) We have some access token of unknown validity -> try it anyway.
    if (_accessToken != null && await _openAndConnect(_accessToken)) {
      _finishConnected();
      return;
    }
    // Not D while the set has not answered a token. A drop in the network
    // made all three time out, it came back in time for D, and a panel with
    // a refresh token good for weeks was put into pairing — from which it
    // never retried. Pairing is for tokens the set has turned down.
    if (_unanswered) {
      _setConn(
        ConnState.error,
        err: tr('widget.tv.couldNotConnectTo', 'Could not connect to {host}', {
          'host': host,
        }),
        retry: true,
      );
      return;
    }
    // D) No usable credentials -> connect unauthenticated for pairing.
    if (await _openAndConnect(null)) {
      _setConn(ConnState.needsPairing);
      return;
    }
    _setConn(
      ConnState.error,
      err: tr('widget.tv.couldNotConnectTo', 'Could not connect to {host}', {
        'host': host,
      }),
      retry: true,
    );
  }

  /// Renew the access token: connect with dynamic creds (restricted ACL still
  /// allows the token-issuance topic), request a new token, reconnect with it.
  Future<bool> _refreshAndConnect() async {
    // The TV expects the refresh token to be used as the MQTT password for the
    // renewal connection (mirrors the official app).
    if (!await _openAndConnect(_refreshToken)) return false;
    // Let the token-issuance subscription settle before asking for the token,
    // otherwise the response can be missed.
    await Future.delayed(const Duration(milliseconds: 800));
    final tok = await _client!.requestToken(_refreshToken!);
    if (tok == null || tok['accesstoken'] == null) return false;
    await _saveToken(tok);
    if (await _openAndConnect(_accessToken)) {
      _finishConnected();
      return true;
    }
    return false;
  }

  /// Begin pairing: shows the PIN on the TV. Caller then collects the PIN.
  void startPairing() {
    _client?.startPairing();
    _setConn(ConnState.needsPairing);
  }

  /// Pair again, for when the remote has stopped working: puts the code up
  /// on the TV, connecting first if there is no session to ask through.
  ///
  /// What the widget's "Show PIN" calls too, rather than [startPairing]: that
  /// one only sends, and a pairing session can be gone by the time someone
  /// gets to the button.
  Future<void> pairAgain() async {
    _wanted = true;
    _cancelRetry();
    // The session itself, not [conn]: a pairing session still up is fine to
    // ask through, and one marked connected may not be.
    if (!(_client?.isConnected ?? false)) {
      _setConn(ConnState.connecting);
      try {
        await _loadAssets();
      } on TvCredentialsMissing catch (e) {
        _setConn(
          ConnState.error,
          err: tr(
            'widget.tv.tvClientCertificateNotSet',
            'TV client certificate not set up — {message}',
            {'message': e.message},
          ),
        );
        return;
      }
      if (!await _openAndConnect(null)) {
        _setConn(
          ConnState.error,
          err: tr(
            'widget.tv.couldNotConnectTo',
            'Could not connect to {host}',
            {'host': host},
          ),
          retry: true,
        );
        return;
      }
    }
    startPairing();
  }

  /// Submit the PIN shown on the TV. Returns true on success (token saved).
  Future<bool> submitPin(String pin) async {
    final tok = await _client?.submitPin(pin);
    if (tok != null && tok['accesstoken'] != null) {
      await _saveToken(tok);
      _askForInputs = true;
      // Reconnect with the token for full ACL access.
      _client?.disconnect();
      await Future.delayed(const Duration(milliseconds: 400));
      await connect();
      return isConnected;
    }
    return false;
  }

  /// Switches the set on or off, as asked — not a press of the power key,
  /// which only flips it whichever way it is, and which "turn the TV off"
  /// must not do to a set that is already off.
  ///
  /// Connects first if there is no session: the panel may never have shown
  /// a TV tile since it started. A set in standby is still on the network
  /// and takes the power key; one switched off beyond that answers nothing,
  /// and is sent a Wake-on-LAN packet instead, before trying to connect
  /// rather than after half a minute of not getting through.
  Future<TvSwitch> setPower(bool on) async {
    if (!settings.isConfigured) return TvSwitch.notSetUp;
    var woken = false;
    if (!_sessionUp) {
      if (on && settings.mac.isNotEmpty) {
        woken = await WakeOnLan.send(settings.mac, host);
      }
      await connect();
    }
    if (conn == ConnState.needsPairing) return TvSwitch.needsPairing;
    if (!_sessionUp) return woken ? TvSwitch.woken : TvSwitch.unreachable;
    // Said by the set as each session starts, so it is seldom long.
    await _until(() => state.powerKnown, const Duration(seconds: 3));
    // Already so — or brought so just now by the packet: either way, no key,
    // which would only switch it back.
    if (state.powerKnown && state.powerOn == on) return TvSwitch.already;
    _client?.sendKey('KEY_POWER');
    return TvSwitch.done;
  }

  /// Connected, and the session not gone underneath without a word.
  bool get _sessionUp => isConnected && (_client?.isConnected ?? false);

  /// Waits for [ok], as long as [within]; whether it came.
  Future<bool> _until(bool Function() ok, Duration within) async {
    if (ok()) return true;
    final came = Completer<void>();
    void check() {
      if (ok() && !came.isCompleted) came.complete();
    }

    addListener(check);
    try {
      await came.future.timeout(within);
    } on TimeoutException {
      // Not said in time; the caller makes do.
    } finally {
      removeListener(check);
    }
    return ok();
  }

  // --- command surface used by the UI ---
  void key(String k) => _client?.sendKey(k);
  void volumeUp() => _client?.sendKey('KEY_VOLUMEUP');
  void volumeDown() => _client?.sendKey('KEY_VOLUMEDOWN');
  void mute() => _client?.sendKey('KEY_MUTE');
  void power() => _client?.sendKey('KEY_POWER');
  void changeSource(String id) => _client?.changeSource(id);
  void launchApp(Map<String, dynamic> app) => _client?.launchApp(app);
  void refresh() {
    _client?.getVolume();
  }

  @override
  void dispose() {
    _wanted = false;
    _cancelRetry();
    _cancelRenewal();
    _client?.disconnect();
    super.dispose();
  }
}

/// What became of [TvService.setPower].
enum TvSwitch {
  /// The power key was sent.
  done,

  /// The set already was as asked.
  already,

  /// It answered nothing, and was sent a Wake-on-LAN packet — which it may
  /// or may not act on.
  woken,

  /// It answered nothing, and there was no other way to reach it.
  unreachable,

  /// It answers, but this panel is not paired with it yet.
  needsPairing,

  /// There is no television in Settings.
  notSetUp,
}

/// The TV client certificate or key is absent, empty, or a placeholder.
///
/// Its own type so the UI can say "the TV credentials are not set up" rather
/// than surfacing a TLS handshake failure from several layers down.
class TvCredentialsMissing implements Exception {
  TvCredentialsMissing(this.message);
  final String message;
  @override
  String toString() => tr(
    'widget.tv.tvCredentialsMissing',
    'TV credentials missing: {message}',
    {'message': message},
  );
}

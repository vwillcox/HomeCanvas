import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../config/app_config.dart' show YouTubeSettings;
import 'config_service.dart';
import 'kiosk_browser.dart';
import 'mpv_tuning.dart';
import 'youtube_link.dart';

/// How a video sent to the panel is being shown.
enum YouTubeView { closed, full, pip }

/// Something YouTube or yt-dlp said no to, worded for the screen.
class YouTubeException implements Exception {
  const YouTubeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A video, resolved to something mpv can play.
@immutable
class YouTubeStream {
  const YouTubeStream({
    required this.title,
    required this.channel,
    required this.uri,
    this.headers = const {},
    this.duration,
    this.isLive = false,
  });

  final String title;
  final String channel;

  /// One address for mpv. YouTube serves picture and sound separately above
  /// 360p, so this is usually an `edl://` joining the two.
  final String uri;
  final Map<String, String> headers;
  final Duration? duration;
  final bool isLive;

  /// From yt-dlp's `-J` output, or null when it names nothing playable.
  static YouTubeStream? fromInfo(Map<String, dynamic> info) {
    var headers = info['http_headers'];
    String? uri;
    final formats = (info['requested_formats'] as List?)?.whereType<Map>();
    if (formats != null && formats.isNotEmpty) {
      final urls = formats.map((f) => f['url']).whereType<String>().toList();
      if (urls.isEmpty) return null;
      uri = urls.length == 1 ? urls.single : edl(urls);
      headers = formats.first['http_headers'] ?? headers;
    } else {
      uri = info['url'] as String?;
    }
    if (uri == null || uri.isEmpty) return null;
    final seconds = (info['duration'] as num?)?.toDouble();
    return YouTubeStream(
      title: info['title'] as String? ?? 'YouTube',
      channel: (info['channel'] ?? info['uploader'] ?? '') as String,
      uri: uri,
      headers: headers is Map
          ? {
              for (final e in headers.entries)
                if (e.value is String) '${e.key}': e.value as String,
            }
          : const {},
      duration: seconds == null
          ? null
          : Duration(milliseconds: (seconds * 1000).round()),
      isLive: info['is_live'] == true,
    );
  }

  /// Several streams as one, the way mpv's own YouTube support joins them.
  ///
  /// Each address is prefixed with its length, so the `;` and `%` that
  /// YouTube's addresses are full of need no escaping.
  static String edl(List<String> urls) => 'edl://${urls.map(
        (u) => '!new_stream;!no_clip;!no_chapters;%${utf8.encode(u).length}%$u',
      ).join(';')}';
}

/// One video in a feed such as the subscriptions page.
@immutable
class YouTubeFeedItem {
  const YouTubeFeedItem({
    required this.link,
    required this.title,
    this.channel = '',
    this.duration,
  });

  final YouTubeLink link;
  final String title;
  final String channel;
  final Duration? duration;

  /// From yt-dlp's `--flat-playlist -J` output. Entries without a video id —
  /// a Short shelf, a channel — are left out.
  static List<YouTubeFeedItem> listFromInfo(Map<String, dynamic> info) {
    final entries = (info['entries'] as List?)?.whereType<Map>() ?? const [];
    return [
      for (final e in entries)
        if (YouTubeLink.parse(
              'https://www.youtube.com/watch?v=${e['id'] ?? ''}',
            )
            case final link?)
          YouTubeFeedItem(
            link: link,
            title: e['title'] as String? ?? '',
            channel: (e['channel'] ?? e['uploader'] ?? '') as String,
            duration: (e['duration'] as num?) == null
                ? null
                : Duration(seconds: (e['duration'] as num).round()),
          ),
    ];
  }
}

/// YouTube, played by the kiosk itself rather than in a browser.
///
/// A browser window cannot sit inside a dashboard tile or float as a
/// resizable picture-in-picture over the kiosk — labwc gives no client a way
/// to place another's window — so the video is played by the same mpv the
/// photo videos use, and drawn by Flutter wherever it is wanted.
///
/// mpv needs a stream address, which is what yt-dlp is for. The Debian
/// package lags YouTube by months and stops working in between, so a current
/// build is fetched into [AppPaths.bin] and updated daily, along with deno,
/// which yt-dlp now needs to work out YouTube's stream signatures.
///
/// One video at a time is "sent to the panel": the full-screen player and the
/// picture-in-picture window are two views of that one session. Dashboard
/// tiles play their own, and only [resolve] is shared with them.
class YouTubeService extends ChangeNotifier {
  YouTubeService(this._config);

  final ConfigService _config;

  YouTubeSettings get settings => _config.config.youtube;

  /// The browser profile the sign-in lives in.
  static const String loginProfile = 'youtube';

  /// Straight to YouTube's sign-in, and back to YouTube afterwards.
  static const String signInUrl =
      'https://accounts.google.com/ServiceLogin?service=youtube'
      '&continue=https%3A%2F%2Fwww.youtube.com%2F';

  /// The subscriptions feed, by yt-dlp's name for it rather than its
  /// address: the address answers with an empty list when nobody is signed
  /// in, while this refuses — which is what makes it a test of the sign-in.
  static const String subscriptionsUrl = ':ytsubs';

  /// Decoded and drawn by the CPU.
  ///
  /// There is no hardware decoder to use — the Pi 5's only one is for HEVC.
  /// media_kit's OpenGL output would take the drawing off the CPU, and was
  /// tried: on this Pi it shows a solid blue picture even with decoding in
  /// software, and dropped a third of a 60fps video's frames besides,
  /// because it draws on the GTK thread the whole UI shares. The software
  /// output draws each frame into memory for Flutter to upload instead; see
  /// [MpvTuning] for what keeps that at 60fps.
  static const videoConfig = VideoControllerConfiguration(
    enableHardwareAcceleration: false,
    hwdec: 'no',
  );

  /// Paused or finished for this long, a video sent to the panel closes —
  /// a kiosk left on a paused video is a kiosk showing it tomorrow morning.
  static const Duration idleClose = Duration(minutes: 30);

  /// Stream addresses stay good for about six hours. Reused well within that.
  static const Duration _streamLife = Duration(minutes: 30);

  static const Duration _feedLife = Duration(minutes: 15);

  Timer? _updateTimer;
  Timer? _idleTimer;

  /// Called as a video starts, so music playing already can be paused.
  void Function()? onStart;

  void start() {
    // Checked again on each start, so a sign-in that has lapsed — or never
    // took — says so instead of showing an empty subscriptions tile.
    unawaited(update().then((_) async {
      if (settings.signedIn) await checkSignIn();
    }));
    _updateTimer ??= Timer.periodic(const Duration(days: 1), (_) => update());
    _idleTimer ??= Timer.periodic(const Duration(minutes: 1), (_) => _idleCheck());
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _idleTimer?.cancel();
    _player?.dispose();
    super.dispose();
  }

  // --- yt-dlp ---------------------------------------------------------------

  String get _managedYtDlp => p.join(AppPaths.bin, 'yt-dlp');
  String get _managedDeno => p.join(AppPaths.bin, 'deno');

  String? _ytDlpVersion;
  bool _installing = false;
  String? toolStatus;

  /// yt-dlp's version, or null when it is not installed. Known after
  /// [update] or [install] has run.
  String? get ytDlpVersion => _ytDlpVersion;
  bool get installing => _installing;

  static Future<String?> _which(String name) async {
    try {
      final r = await Process.run('which', [name]);
      if (r.exitCode == 0) return (r.stdout as String).trim();
    } catch (_) {}
    return null;
  }

  Future<String?> _ytDlp() async =>
      await File(_managedYtDlp).exists() ? _managedYtDlp : await _which('yt-dlp');

  Future<String?> _deno() async =>
      await File(_managedDeno).exists() ? _managedDeno : await _which('deno');

  /// Whether a yt-dlp of [version] understands `--js-runtimes`, which arrived
  /// in 2025.11 along with YouTube's need for one. Passing it to an older
  /// build is an error, not a no-op.
  @visibleForTesting
  static bool takesJsRuntimes(String? version) {
    final m = RegExp(r'^(\d{4})\.(\d{2})').firstMatch(version ?? '');
    if (m == null) return false;
    final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!);
    return y > 2025 || (y == 2025 && mo >= 11);
  }

  /// The options every call shares. [account] names the signed-in cookies,
  /// as yt-dlp takes them — see [_account].
  @visibleForTesting
  static List<String> baseArgs(
          {String? deno, List<String> account = const []}) =>
      [
        '--ignore-config',
        '--no-warnings',
        '--no-progress',
        if (deno != null) ...['--js-runtimes', 'deno:$deno'],
        ...account,
      ];

  /// H.264 because the Pi 5's only video decoder is for HEVC, which YouTube
  /// does not serve, and H.264 is the cheapest of the rest in software:
  /// 1080p60 decoded in 11.1s per 20s of video on the panel, against 12.1s
  /// for VP9 and 15.4s for AV1. The most frames a second on offer, then —
  /// there is room for 60 once the frames are drawn by the GPU. AAC sound,
  /// which mpv joins to it as it is.
  @visibleForTesting
  static List<String> streamArgs(int maxHeight) => [
        '-J',
        '--no-playlist',
        '-S', 'vcodec:h264,res:$maxHeight,fps,acodec:m4a',
        '-f', 'bv*+ba/b',
      ];

  Future<List<String>> _args() async {
    final deno = takesJsRuntimes(_ytDlpVersion) ? await _deno() : null;
    return baseArgs(
      deno: deno,
      account: settings.signedIn ? await _account() : const [],
    );
  }

  /// Cookies uploaded from another browser, when there are some — see
  /// [useCookies]. yt-dlp writes the file back as YouTube renews them, which
  /// is what keeps a sign-in made elsewhere working here.
  static String get cookiesFile =>
      p.join(AppPaths.profiles, 'youtube-cookies.txt');

  /// How the account is reached: uploaded cookies if there are any,
  /// otherwise the kiosk's own sign-in browser profile.
  Future<List<String>> _account() async {
    if (await File(cookiesFile).exists()) return ['--cookies', cookiesFile];
    final browser = await KioskBrowser.resolve();
    if (browser == null) return const [];
    final dir = KioskBrowser.profileDir(browser, loginProfile, keep: true);
    return dir == null ? const [] : ['--cookies-from-browser', '$browser:$dir'];
  }

  /// Domains whose cookies are kept from an upload. YouTube's sign-in rests
  /// on Google's own cookies as well as its own; nothing else in a browser's
  /// cookie file has any business on the panel.
  static const _cookieDomains = ['youtube.com', 'google.com'];

  /// [text] as a Netscape `cookies.txt`, cut down to YouTube's and Google's
  /// cookies — or null when it holds none of them, or is not such a file.
  @visibleForTesting
  static String? filterCookies(String text) {
    final kept = <String>[];
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trimRight();
      // "#HttpOnly_" marks an HttpOnly cookie, not a comment — and the
      // sign-in cookies are exactly those.
      final bare = line.startsWith('#HttpOnly_')
          ? line.substring('#HttpOnly_'.length)
          : line;
      if (bare.isEmpty || bare.startsWith('#')) continue;
      final fields = bare.split('\t');
      if (fields.length != 7) continue;
      final domain = fields[0].toLowerCase().replaceFirst(RegExp(r'^\.'), '');
      if (_cookieDomains.any((d) => domain == d || domain.endsWith('.$d'))) {
        kept.add(line);
      }
    }
    if (kept.isEmpty) return null;
    return '# Netscape HTTP Cookie File\n'
        '# YouTube and Google only, uploaded to HomeCanvas.\n'
        '${kept.join('\n')}\n';
  }

  /// Signs in with cookies exported from a browser elsewhere — so the
  /// password is typed on a computer or phone, not on the panel. Returns
  /// null when it worked, or what went wrong.
  Future<String?> useCookies(String text) async {
    final cookies = filterCookies(text);
    if (cookies == null) {
      return 'That file has no YouTube cookies in it. Export them from a '
          'window signed in to youtube.com.';
    }
    final file = File(cookiesFile);
    await file.parent.create(recursive: true);
    // Written readable by this user only before anything goes in it: these
    // are as good as the account's password for as long as they last.
    final part = File('${file.path}.part');
    await part.writeAsString('');
    await Process.run('chmod', ['600', part.path]);
    await part.writeAsString(cookies, flush: true);
    await part.rename(file.path);
    if (await checkSignIn()) return null;
    await file.delete();
    return 'YouTube did not accept those cookies — they may have been '
        'signed out. Sign in again in a private window and export from there.';
  }

  /// How the panel is signed in, for Settings and the sign-in page.
  Future<String?> accountSource() async {
    if (!settings.signedIn) return null;
    return await File(cookiesFile).exists()
        ? 'cookies uploaded from another browser'
        : 'signed in on the panel';
  }

  /// Runs yt-dlp and returns what it printed as JSON.
  Future<Map<String, dynamic>> _run(List<String> args,
      {Duration timeout = const Duration(seconds: 60)}) async {
    final exe = await _ytDlp();
    if (exe == null) {
      throw const YouTubeException(
          'YouTube needs yt-dlp. Install it in Settings → Music → YouTube.');
    }
    _ytDlpVersion ??= await _version(exe);
    final ProcessResult r;
    try {
      r = await Process.run(exe, [...await _args(), ...args],
              stdoutEncoding: utf8, stderrEncoding: utf8)
          .timeout(timeout);
    } on TimeoutException {
      throw const YouTubeException('YouTube took too long to answer.');
    }
    if (r.exitCode != 0) {
      throw YouTubeException(explain(r.stderr as String));
    }
    final out = jsonDecode(r.stdout as String);
    if (out is! Map<String, dynamic>) {
      throw const YouTubeException('YouTube sent back nothing playable.');
    }
    return out;
  }

  /// After the panel's own sign-in window closes: gets its cookies where
  /// yt-dlp can read them, then checks.
  ///
  /// The window is closed by stopping Firefox, which leaves what it last
  /// wrote — a sign-in included — in the cookie database's write-ahead log.
  /// yt-dlp copies the database alone and never sees it, so the log is
  /// merged in first. Python's sqlite3 does that; the installer needs Python
  /// already.
  Future<bool> afterPanelSignIn() async {
    final browser = await KioskBrowser.resolve();
    final dir = browser == 'firefox'
        ? KioskBrowser.profileDir(browser!, loginProfile, keep: true)
        : null;
    if (dir != null && await File('$dir/cookies.sqlite').exists()) {
      // Firefox is still letting go of the file for a moment after the kill.
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        final r = await Process.run('python3', [
          '-c',
          'import sqlite3, sys\n'
              'c = sqlite3.connect(sys.argv[1])\n'
              'c.execute("pragma wal_checkpoint(TRUNCATE)")\n'
              'c.close()',
          '$dir/cookies.sqlite',
        ]);
        if (r.exitCode != 0) debugPrint('YouTube: cookies: ${r.stderr}');
      } catch (e) {
        debugPrint('YouTube: could not settle the sign-in cookies: $e');
      }
    }
    return checkSignIn();
  }

  /// Whether yt-dlp's complaint is that there is no account to use.
  @visibleForTesting
  static bool wantsSignIn(String message) {
    final m = message.toLowerCase();
    return m.contains('--cookies') ||
        m.contains('logged in') ||
        m.contains('log in') ||
        m.contains('sign in');
  }

  /// yt-dlp's last complaint, without its prefix and advice.
  @visibleForTesting
  static String explain(String stderr) {
    final errors = stderr
        .split('\n')
        .where((l) => l.startsWith('ERROR:'))
        .map((l) => l.substring(6).trim())
        .toList();
    if (errors.isEmpty) return 'YouTube would not play this video.';
    final last = errors.last
        .replaceFirst(RegExp(r'^\[[^\]]+\]\s*[A-Za-z0-9_-]*:\s*'), '')
        .trim();
    if (last.contains('Sign in to confirm your age') ||
        last.contains('members-only') ||
        last.contains('only available when logged in') ||
        last.contains('Private video')) {
      return '$last Signing in to YouTube in Settings may let it play.';
    }
    return last;
  }

  Future<String?> _version(String exe) async {
    try {
      final r = await Process.run(exe, ['--version']);
      if (r.exitCode == 0) return (r.stdout as String).trim();
    } catch (_) {}
    return null;
  }

  /// Brings the fetched yt-dlp up to date, if it is the fetched one.
  /// A packaged or hand-installed one is its owner's to update.
  Future<void> update() async {
    final exe = await _ytDlp();
    if (exe == _managedYtDlp) {
      try {
        final r = await Process.run(exe!, ['-U']);
        debugPrint('YouTube: ${(r.stdout as String).trim().split('\n').last}');
      } catch (e) {
        debugPrint('YouTube: could not update yt-dlp: $e');
      }
    }
    _ytDlpVersion = exe == null ? null : await _version(exe);
    notifyListeners();
  }

  /// Fetches the current yt-dlp and deno into [AppPaths.bin].
  ///
  /// Both are single self-contained programs published for this machine's
  /// architecture, so this is a download and nothing more — no packages, no
  /// Python environment, nothing needing sudo.
  Future<void> install() async {
    if (_installing) return;
    _installing = true;
    toolStatus = 'Downloading yt-dlp…';
    notifyListeners();
    try {
      final arm = Platform.version.contains('arm64');
      await Directory(AppPaths.bin).create(recursive: true);
      await _download(
        'https://github.com/yt-dlp/yt-dlp/releases/latest/download/'
        '${arm ? 'yt-dlp_linux_aarch64' : 'yt-dlp_linux'}',
        _managedYtDlp,
      );
      await Process.run('chmod', ['+x', _managedYtDlp]);

      toolStatus = 'Downloading deno…';
      notifyListeners();
      final zip = p.join(AppPaths.bin, 'deno.zip');
      await _download(
        'https://github.com/denoland/deno/releases/latest/download/'
        'deno-${arm ? 'aarch64' : 'x86_64'}-unknown-linux-gnu.zip',
        zip,
      );
      final unzip = await Process.run('unzip', ['-oq', zip, '-d', AppPaths.bin]);
      await File(zip).delete();
      if (unzip.exitCode != 0) {
        throw YouTubeException('Could not unpack deno: ${unzip.stderr}');
      }
      _ytDlpVersion = await _version(_managedYtDlp);
      toolStatus = null;
    } catch (e) {
      toolStatus = 'Could not install: $e';
      debugPrint('YouTube: install failed: $e');
    } finally {
      _installing = false;
      notifyListeners();
    }
  }

  static Future<void> _download(String url, String to) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw YouTubeException('$url answered ${res.statusCode}');
      }
      // Written beside it and moved into place, so a download cut short
      // never leaves a broken program where the working one was.
      final part = File('$to.part');
      await res.pipe(part.openWrite());
      await part.rename(to);
    } finally {
      client.close();
    }
  }

  // --- Resolving ------------------------------------------------------------

  final Map<String, (DateTime, Future<YouTubeStream>)> _streams = {};

  /// What mpv should open for [link], no taller than [maxHeight] (or the
  /// setting). Shared between the panel's player and the dashboard's tiles,
  /// so a tile tapped to go full screen does not ask YouTube twice.
  Future<YouTubeStream> resolve(YouTubeLink link, {int? maxHeight}) {
    final height = maxHeight ?? settings.maxHeight;
    final key = '${link.id}@$height';
    final cached = _streams[key];
    if (cached != null && DateTime.now().difference(cached.$1) < _streamLife) {
      return cached.$2;
    }
    final future = () async {
      final info = await _run([...streamArgs(height), link.watchUrl]);
      final stream = YouTubeStream.fromInfo(info);
      if (stream == null) {
        throw const YouTubeException('YouTube sent back nothing playable.');
      }
      return stream;
    }();
    _streams[key] = (DateTime.now(), future);
    // A failure is not worth remembering; the next attempt might work.
    unawaited(future.then<void>((_) {}, onError: (Object _) {
      if (_streams[key]?.$2 == future) _streams.remove(key);
    }));
    return future;
  }

  Future<void> setMaxHeight(int height) async {
    settings.maxHeight = height;
    // Addresses already worked out are for the old size.
    _streams.clear();
    notifyListeners();
    await _config.save();
  }

  // --- The account ----------------------------------------------------------

  List<YouTubeFeedItem>? _subscriptions;
  DateTime? _subscriptionsAt;
  bool _subscriptionsLoading = false;
  String? subscriptionsError;

  /// The latest from the account's subscriptions, or null until fetched.
  /// Fetches, or refreshes a stale copy, in the background as a side effect.
  List<YouTubeFeedItem>? subscriptions() {
    final at = _subscriptionsAt;
    if (settings.signedIn &&
        !_subscriptionsLoading &&
        (at == null || DateTime.now().difference(at) > _feedLife)) {
      unawaited(_fetchSubscriptions());
    }
    return _subscriptions;
  }

  Future<void> _fetchSubscriptions() async {
    _subscriptionsLoading = true;
    try {
      final info = await _run(
          ['-J', '--flat-playlist', '-I', '1:30', subscriptionsUrl]);
      _subscriptions = YouTubeFeedItem.listFromInfo(info);
      subscriptionsError = null;
    } catch (e) {
      subscriptionsError = '$e';
    } finally {
      _subscriptionsAt = DateTime.now();
      _subscriptionsLoading = false;
      notifyListeners();
    }
  }

  /// Whether the panel is signed in, judged by whether the subscriptions
  /// feed — which refuses without an account — opens.
  ///
  /// Only a refusal of that kind counts as signed out. A network that is not
  /// up yet, early in a boot, must not throw away a good sign-in.
  Future<bool> checkSignIn() async {
    final was = settings.signedIn;
    settings.signedIn = true;
    try {
      await _run(['-J', '--flat-playlist', '-I', '1', subscriptionsUrl]);
    } on YouTubeException catch (e) {
      final refused = wantsSignIn(e.message);
      debugPrint('YouTube: sign-in check: ${refused ? 'signed out' : e}');
      settings.signedIn = refused ? false : was;
    }
    _subscriptions = null;
    _subscriptionsAt = null;
    _streams.clear();
    await _config.save();
    notifyListeners();
    return settings.signedIn;
  }

  /// Forgets the account: the uploaded cookies, and the profile holding the
  /// panel's own sign-in, go entirely.
  Future<void> signOut() async {
    try {
      await File(cookiesFile).delete();
    } catch (_) {}
    final browser = await KioskBrowser.resolve();
    final dir = browser == null
        ? null
        : KioskBrowser.profileDir(browser, loginProfile, keep: true);
    if (dir != null) {
      try {
        await Directory(dir).delete(recursive: true);
      } catch (_) {}
    }
    settings.signedIn = false;
    _subscriptions = null;
    _subscriptionsAt = null;
    _streams.clear();
    await _config.save();
    notifyListeners();
  }

  // --- The video sent to the panel -----------------------------------------

  Player? _player;
  VideoController? _controller;
  YouTubeView _view = YouTubeView.closed;
  YouTubeLink? _link;
  YouTubeStream? _stream;
  String? _error;
  bool _loading = false;
  int _session = 0;
  DateTime _lastPlaying = DateTime.now();

  Player? get player => _player;
  VideoController? get controller => _controller;
  YouTubeView get view => _view;
  YouTubeLink? get link => _link;
  YouTubeStream? get stream => _stream;
  String? get error => _error;
  bool get loading => _loading;

  /// Whether a video sent to the panel is actually playing — which keeps the
  /// screen from switching itself off under it.
  bool get playing =>
      _view != YouTubeView.closed && (_player?.state.playing ?? false);

  /// Where the picture-in-picture window was left, in logical pixels. Kept
  /// here rather than in the window so it comes back where it was.
  Rect? pipRect;

  /// Sends [link] to the panel, full screen, from [at] or the link's own
  /// start time.
  Future<void> play(YouTubeLink link, {Duration? at}) async {
    final session = ++_session;
    _link = link;
    _stream = null;
    _error = null;
    _loading = true;
    _view = YouTubeView.full;
    _lastPlaying = DateTime.now();
    await _player?.stop();
    notifyListeners();
    onStart?.call();

    final YouTubeStream stream;
    try {
      stream = await resolve(link);
    } catch (e) {
      if (session != _session) return;
      _error = '$e';
      _loading = false;
      notifyListeners();
      return;
    }
    if (session != _session) return;

    var player = _player;
    if (player == null) {
      player = _player = Player();
      await MpvTuning.apply(player);
    }
    _controller ??= VideoController(player, configuration: videoConfig);
    final from = at ?? link.start;
    // The level first, so a loud video does not begin at mpv's 100%.
    await applyAudio(player, settings);
    await player.open(Media(
      stream.uri,
      httpHeaders: stream.headers,
      start: !stream.isLive && from > Duration.zero ? from : null,
    ));
    if (session != _session) return;
    _stream = stream;
    _loading = false;
    notifyListeners();
  }

  void showFull() => _setView(YouTubeView.full);
  void showPip() => _setView(YouTubeView.pip);

  void _setView(YouTubeView v) {
    if (_view == YouTubeView.closed || _view == v) return;
    _view = v;
    notifyListeners();
  }

  Future<void> close() async {
    _session++;
    _view = YouTubeView.closed;
    _loading = false;
    _error = null;
    _stream = null;
    _link = null;
    notifyListeners();
    await _player?.stop();
  }

  /// Frames dropped since the video started, once a minute, so whether it
  /// plays smoothly can be read off the log rather than guessed at.
  Future<void> _logSmoothness() async {
    final platform = _player?.platform;
    if (platform is! NativePlayer) return;
    Future<String> get(String p) async {
      try {
        return await platform.getProperty(p);
      } catch (_) {
        return '?';
      }
    }

    debugPrint('YouTube: at ${await get('time-pos')}s, '
        '${await get('video-params/w')}x'
        '${await get('video-params/h')} at '
        '${await get('container-fps')} fps, drawing '
        '${await get('estimated-vf-fps')}; dropped '
        '${await get('frame-drop-count')} (decoder '
        '${await get('decoder-frame-drop-count')})');
  }

  Future<void> setVolume(double v) async {
    settings.volume = v.clamp(0, 100).toDouble();
    settings.muted = settings.volume <= 0;
    await _audioChanged();
  }

  Future<void> toggleMute() async {
    settings.muted = !settings.muted;
    if (!settings.muted && settings.volume <= 0) settings.volume = 40;
    await _audioChanged();
  }

  Future<void> _audioChanged() async {
    final player = _player;
    if (player != null) await applyAudio(player, settings);
    notifyListeners();
    await _config.save();
  }

  /// Sets [player] to the level in [s]. mpv's `mute` as well as its volume:
  /// the photo player found volume 0 alone still audible on this hardware.
  static Future<void> applyAudio(Player player, YouTubeSettings s,
      {bool? muted}) async {
    final mute = muted ?? s.muted;
    await player.setVolume(mute ? 0 : s.volume);
    final platform = player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('mute', mute ? 'yes' : 'no');
      } catch (_) {}
    }
  }

  void _idleCheck() {
    if (_view == YouTubeView.closed || _loading || _error != null) return;
    if (_player?.state.playing ?? false) {
      _lastPlaying = DateTime.now();
      unawaited(_logSmoothness());
    } else if (DateTime.now().difference(_lastPlaying) > idleClose) {
      unawaited(close());
    }
  }
}

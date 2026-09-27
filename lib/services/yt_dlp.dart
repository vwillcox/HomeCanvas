import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import 'programs.dart';

/// Something a video site or yt-dlp said no to, worded for the screen.
class VideoException implements Exception {
  const VideoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// yt-dlp: what turns a YouTube, Floatplane or Nebula page into a stream
/// mpv can play, and reads the sites' feeds.
///
/// The Debian package lags YouTube by months and stops working in between,
/// so a current build is fetched into [AppPaths.bin] and updated daily,
/// along with deno, which yt-dlp now needs to work out YouTube's stream
/// signatures. An installed one on the PATH is used when there is none.
class YtDlp extends ChangeNotifier {
  Timer? _updateTimer;

  String get _managedYtDlp => p.join(AppPaths.bin, 'yt-dlp');
  String get _managedDeno => p.join(AppPaths.bin, 'deno');

  String? _version;
  bool _installing = false;

  /// What an install is doing, or what went wrong with it.
  String? status;

  /// yt-dlp's version, or null when it is not installed. Known once [start]
  /// or [install] has run.
  String? get version => _version;
  bool get ready => _version != null;
  bool get installing => _installing;

  /// Brings yt-dlp up to date now and daily after. The returned future is
  /// the first check, after which [ready] is known.
  Future<void> start() {
    _updateTimer ??= Timer.periodic(const Duration(days: 1), (_) => update());
    return update();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<String?> _ytDlp() async =>
      await File(_managedYtDlp).exists() ? _managedYtDlp : await findOnPath('yt-dlp');

  Future<String?> _deno() async =>
      await File(_managedDeno).exists() ? _managedDeno : await findOnPath('deno');

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

  /// The options every call shares. [account] is a site's signed-in
  /// cookies, as yt-dlp takes them.
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

  /// H.264, the cheapest to decode in software of what YouTube serves:
  /// 1080p60 decoded in 11.1s per 20s of video on the panel, against 12.1s
  /// for VP9 and 15.4s for AV1. The most frames a second on offer, then, and
  /// AAC sound, joined as it is. yt-dlp ranks codecs AV1, VP9, HEVC, H.264;
  /// `vcodec:h264` caps the choice there.
  ///
  /// With [hevc] — a hardware HEVC decoder here — a site's HEVC is taken
  /// instead, but only up to 30 frames a second. Nebula serves it 10-bit,
  /// and though the Pi decodes it for next to nothing, turning each 10-bit
  /// frame into a picture is more than the drawing thread manages sixty
  /// times a second: a 60fps video dropped 386 frames a minute as HEVC and
  /// none as H.264, where 25fps HEVC dropped one in 100 seconds on a fifth
  /// of the CPU. It is the choice Nebula's own site offers as "a more
  /// compatible video format".
  static List<String> streamArgs(int maxHeight, {bool hevc = false}) => [
        '-J',
        '--no-playlist',
        '-S', 'vcodec:h264,res:$maxHeight,fps,acodec:m4a',
        '-f',
        [
          if (hevc) ...[
            'bv*[vcodec^=hvc1][fps<=30]+ba',
            'bv*[vcodec^=hev1][fps<=30]+ba',
          ],
          'bv*+ba',
          'b',
        ].join('/'),
      ];

  /// Whether this machine has a hardware HEVC decoder mpv can use — the
  /// Pi 5's `rpi-hevc-dec`, found by name among the video devices.
  static final bool hevcDecoder = () {
    try {
      final dir = Directory('/sys/class/video4linux');
      if (!dir.existsSync()) return false;
      return dir.listSync().any((d) {
        final name = File('${d.path}/name');
        return name.existsSync() &&
            name.readAsStringSync().toLowerCase().contains('hevc');
      });
    } catch (_) {
      return false;
    }
  }();

  /// Runs yt-dlp with [account]'s cookies and returns what it printed as
  /// JSON. Throws [VideoException], worded for the screen, when it fails.
  Future<Map<String, dynamic>> run(List<String> args,
      {List<String> account = const [],
      Duration timeout = const Duration(seconds: 60)}) async {
    final exe = await _ytDlp();
    if (exe == null) {
      throw const VideoException(
          'Videos need yt-dlp. Install it in Settings → Music → Videos.');
    }
    _version ??= await _versionOf(exe);
    final deno = takesJsRuntimes(_version) ? await _deno() : null;
    final ProcessResult r;
    try {
      r = await Process.run(
              exe, [...baseArgs(deno: deno, account: account), ...args],
              stdoutEncoding: utf8, stderrEncoding: utf8)
          .timeout(timeout);
    } on TimeoutException {
      throw const VideoException('The site took too long to answer.');
    }
    if (r.exitCode != 0) {
      throw VideoException(explain(r.stderr as String));
    }
    // A video's full list of formats runs to a megabyte of JSON: parsed on
    // another isolate, so a video already playing does not drop frames.
    final out = await compute(jsonDecode, r.stdout as String);
    if (out is! Map<String, dynamic>) {
      throw const VideoException('The site sent back nothing playable.');
    }
    return out;
  }

  /// Whether yt-dlp's complaint is that there is no account to use.
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
    if (errors.isEmpty) return 'That video would not play.';
    final last = errors.last
        .replaceFirst(RegExp(r'^\[[^\]]+\]\s*[A-Za-z0-9_-]*:\s*'), '')
        .trim();
    if (last.contains('Sign in to confirm your age') ||
        last.contains('members-only') ||
        last.contains('only available when logged in') ||
        last.contains('Private video')) {
      return '$last Signing in, in Settings → Music → Videos, may let it '
          'play.';
    }
    return last;
  }

  static Future<String?> _versionOf(String exe) async {
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
        debugPrint('yt-dlp: ${(r.stdout as String).trim().split('\n').last}');
      } catch (e) {
        debugPrint('yt-dlp: could not update: $e');
      }
    }
    _version = exe == null ? null : await _versionOf(exe);
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
    status = 'Downloading yt-dlp…';
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

      status = 'Downloading deno…';
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
        throw VideoException('Could not unpack deno: ${unzip.stderr}');
      }
      _version = await _versionOf(_managedYtDlp);
      status = null;
    } catch (e) {
      status = 'Could not install: $e';
      debugPrint('yt-dlp: install failed: $e');
    } finally {
      _installing = false;
      notifyListeners();
    }
  }

  static Future<void> _download(String url, String to) async {
    // Given up on rather than left hanging, if GitHub cannot be reached.
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw VideoException('$url answered ${res.statusCode}');
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
}

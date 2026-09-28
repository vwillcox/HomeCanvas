import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import 'config_service.dart';
import 'cookie_file.dart';
import 'kiosk_browser.dart';
import 'retry_schedule.dart';
import 'video_link.dart';
import 'yt_dlp.dart';
import '../l10n/l10n.dart';

/// One video in a site's feed of the latest from the account.
@immutable
class FeedVideo {
  const FeedVideo({
    required this.link,
    required this.title,
    this.channel = '',
    this.released,
    this.duration,
  });

  final VideoLink link;
  final String title;

  /// Who made it: the channel or creator.
  final String channel;
  final DateTime? released;
  final Duration? duration;
}

/// The site turned the account away: signed out, or never signed in.
class SignedOut implements Exception {
  const SignedOut();
}

/// A video site the panel can be signed in to, with a feed of the latest
/// from the account — YouTube, Floatplane, Nebula.
///
/// All of them work the same way. The sign-in is a `cookies.txt` of the
/// site's own cookies, readable by the kiosk's user alone, made either by
/// uploading a browser's cookies from the editor's sign-in page or by
/// signing in on the panel, in the kiosk's browser, and copying them out of
/// its profile. yt-dlp and mpv are both handed that file. The feed is
/// fetched when asked for and kept for fifteen minutes — retried sooner
/// while there is none to show.
///
/// What differs is only how a site checks the account and lists its videos:
/// [verify] and [fetchFeed].
abstract class VideoSite extends ChangeNotifier {
  VideoSite(this.config, this.ytDlp);

  final ConfigService config;
  final YtDlp ytDlp;

  // --- What each site says about itself -------------------------------------

  /// Stable, and the same as its links' [VideoLink.site]: `floatplane`. Also
  /// names its cookie file, its browser profile and its sign-in page.
  String get id;

  /// For people: "Floatplane".
  String get name;

  /// Where its sign-in page is, for signing in on the panel.
  String get signInUrl;

  /// Whose cookies are kept from an upload. Nothing else in a browser's
  /// cookie file has any business on the panel.
  List<String> get cookieDomains;

  /// The cookie the sign-in rests on, when there is one to insist on.
  String? get signInCookie => null;

  /// Kept in the settings, so the tile knows at start-up without asking.
  bool get storedSignedIn;
  set storedSignedIn(bool value);

  /// Checks the account with the site. Throws [SignedOut] when it is turned
  /// away; anything else thrown means the answer could not be had.
  Future<void> verify();

  /// The newest videos from the account's subscriptions, at most [count].
  /// Throws [SignedOut] when the site turns the account away.
  Future<List<FeedVideo>> fetchFeed(int count);

  // --- The account -------------------------------------------------------------

  /// The browser profile a sign-in on the panel is made in.
  String get loginProfile => id;

  String get cookiesFile => p.join(AppPaths.profiles, '$id-cookies.txt');

  /// Told when the account changes, so streams worked out for the old one
  /// are not reused.
  VoidCallback? onAccountChanged;

  bool get signedIn => storedSignedIn;

  /// Whether signing in could work yet — yt-dlp installed.
  bool get ready => ytDlp.ready;

  /// Checked on each start, so a sign-in that has lapsed — or never took —
  /// says so instead of showing an empty tile.
  void start() {
    if (signedIn) unawaited(checkSignIn());
  }

  /// yt-dlp's options for acting as this account.
  Future<List<String>> ytDlpAccount() async =>
      await File(cookiesFile).exists() ? ['--cookies', cookiesFile] : const [];

  /// Runs yt-dlp as this account.
  Future<Map<String, dynamic>> runYtDlp(List<String> args) async =>
      ytDlp.run(args, account: await ytDlpAccount());

  /// Whether the account works. Only the site turning it away counts as
  /// signed out: a network that is not up yet, early in a boot, must not
  /// throw a good sign-in away.
  Future<bool> checkSignIn() async {
    await _check();
    await _accountChanged();
    return signedIn;
  }

  /// Asks the site about the account and records the answer — or returns
  /// null, recording nothing, when the site could not be asked.
  Future<bool?> _check() async {
    if (!await File(cookiesFile).exists()) {
      storedSignedIn = false;
      return false;
    }
    try {
      await verify();
      storedSignedIn = true;
      return true;
    } on SignedOut {
      await _forgetCookies();
      storedSignedIn = false;
      return false;
    } catch (e) {
      debugPrint('$name: could not check the sign-in: $e');
      return null;
    }
  }

  /// Signs in with a `cookies.txt` uploaded from a browser elsewhere — so
  /// the password is typed there, not on the panel. Null when it worked,
  /// otherwise what went wrong, worded for the page.
  Future<String?> useCookies(String text) async {
    final cookies =
        CookieFile.filter(text, cookieDomains, mustHave: signInCookie);
    if (cookies == null) {
      return 'That file has no $name sign-in in it'
          '${signInCookie == null ? '' : ' (no $signInCookie cookie)'}. '
          'Export it from a window signed in to ${cookieDomains.first}.';
    }
    await CookieFile.writePrivate(cookiesFile, cookies);
    final accepted = await _check();
    // Taken on trust when the site cannot be reached to ask: the first
    // fetch of the feed will say soon enough if they were no good. Thrown
    // away, they would have to be exported and uploaded all over again.
    if (accepted == null) storedSignedIn = true;
    await _accountChanged();
    if (accepted == false) {
      return tr('video.didNotAcceptThoseCookies', '{name} did not accept those cookies — they may have been signed out. Sign in again in a private window and export from there.', {'name': name});
    }
    return null;
  }

  /// After signing in on the panel: copies the kiosk browser's cookies for
  /// the site into the same file an upload would make, then checks them.
  Future<bool> afterPanelSignIn() async {
    final browser = await KioskBrowser.resolve();
    final dir = browser == 'firefox'
        ? KioskBrowser.profileDir(browser!, loginProfile, keep: true)
        : null;
    if (dir == null ||
        !await CookieFile.fromFirefox(dir, cookiesFile, cookieDomains)) {
      return false;
    }
    return checkSignIn();
  }

  /// How the panel is signed in, for people; null when it is not.
  Future<String?> accountSource() async => signedIn ? 'signed in' : null;

  /// Forgets the account entirely: its cookies, and the browser profile a
  /// sign-in on the panel was made in.
  Future<void> signOut() async {
    await _forgetCookies();
    final browser = await KioskBrowser.resolve();
    final dir = browser == null
        ? null
        : KioskBrowser.profileDir(browser, loginProfile, keep: true);
    if (dir != null) {
      try {
        await Directory(dir).delete(recursive: true);
      } catch (_) {}
    }
    storedSignedIn = false;
    await _accountChanged();
  }

  Future<void> _forgetCookies() async {
    try {
      await File(cookiesFile).delete();
    } catch (_) {}
  }

  Future<void> _accountChanged() async {
    _videos = null;
    _nextFetch = null;
    _retry.reset();
    _retryTimer?.cancel();
    onAccountChanged?.call();
    await config.save();
    notifyListeners();
  }

  // --- The feed ----------------------------------------------------------------

  /// Fifteen minutes between fetches once there is a feed to show; sooner,
  /// backing off, while there is not — the first fetch after a boot often
  /// beats the network up.
  final RetrySchedule _retry =
      RetrySchedule(settled: const Duration(minutes: 15));

  /// Enough for the largest tile; each tile shows as many as it is set to.
  static const int _feedSize = 30;

  List<FeedVideo>? _videos;
  DateTime? _nextFetch;
  Timer? _retryTimer;
  bool _loading = false;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  /// Why the last fetch failed, worded for the tile. Null when it worked.
  String? error;

  bool get loading => _loading;

  /// The latest videos, or null until fetched. Fetches, or refreshes a
  /// stale copy, in the background as a side effect.
  List<FeedVideo>? videos() {
    final next = _nextFetch;
    if (signedIn &&
        !_loading &&
        (next == null || !DateTime.now().isBefore(next))) {
      unawaited(_fetch());
    }
    return _videos;
  }

  /// Fetches now, rather than when fifteen minutes are up.
  Future<void> refresh() async {
    if (_loading || !signedIn) return;
    // Told before the fetch starts, so the button shows it has been heard;
    // not inside _fetch, which videos() calls from a widget's build.
    _loading = true;
    notifyListeners();
    await _fetch();
  }

  Future<void> _fetch() async {
    _loading = true;
    try {
      _videos = await fetchFeed(_feedSize);
      error = null;
    } on SignedOut {
      storedSignedIn = false;
      error = null;
      unawaited(config.save());
    } on VideoException catch (e) {
      error = e.message;
    } catch (e) {
      error = tr('video.couldNotReach', 'Could not reach {name}.', {'name': name});
      debugPrint('$name: feed: $e');
    } finally {
      final wait = _retry.next(hasContent: _videos != null);
      _nextFetch = DateTime.now().add(wait);
      // The feed is only fetched when a tile asks for it, and an empty tile
      // is not rebuilt by anything else: nudged when a retry is due.
      _retryTimer?.cancel();
      if (_videos == null && signedIn) {
        _retryTimer = Timer(wait, notifyListeners);
      }
      _loading = false;
      notifyListeners();
    }
  }
}

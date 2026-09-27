import 'package:flutter/foundation.dart';

import 'video_link.dart';
import 'video_site.dart';
import 'yt_dlp.dart';

/// Nebula: the latest from the creators the account follows.
///
/// Everything goes through yt-dlp, which knows Nebula's API: its feed of
/// followed creators, `nebula.tv/myshows`, lists the videos, and the account
/// is the `nebula_auth.apiToken` cookie nebula.tv sets on signing in. Nebula
/// serves HEVC, which the Pi 5 decodes in hardware — see
/// [YtDlp.streamArgs] for when that is used.
class NebulaSite extends VideoSite {
  NebulaSite(super.config, super.ytDlp);

  @override
  String get id => 'nebula';

  @override
  String get name => 'Nebula';

  @override
  String get signInUrl => 'https://nebula.tv/login';

  /// Nebula has answered to three names.
  @override
  List<String> get cookieDomains =>
      const ['nebula.tv', 'nebula.app', 'watchnebula.com'];

  @override
  String get signInCookie => 'nebula_auth.apiToken';

  @override
  bool get storedSignedIn => config.config.nebula.signedIn;

  @override
  set storedSignedIn(bool value) => config.config.nebula.signedIn = value;

  static const String feedUrl = 'https://nebula.tv/myshows';

  /// Whether yt-dlp's complaint is Nebula refusing the account. Signed out,
  /// the feed is answered with a bare 400, not a message about signing in.
  @visibleForTesting
  static bool refused(String message) =>
      RegExp(r'HTTP Error (400|401|403)').hasMatch(message) ||
      YtDlp.wantsSignIn(message);

  Future<Map<String, dynamic>> _feed(int count) async {
    try {
      return await runYtDlp(
          ['-J', '--flat-playlist', '-I', '1:$count', feedUrl]);
    } on VideoException catch (e) {
      if (refused(e.message)) throw const SignedOut();
      rethrow;
    }
  }

  @override
  Future<void> verify() => _feed(1);

  @override
  Future<List<FeedVideo>> fetchFeed(int count) async =>
      feedFromInfo(await _feed(count));

  /// The videos in yt-dlp's `--flat-playlist -J` of a Nebula feed. Each entry
  /// names its video by `display_id`, the slug of its address.
  @visibleForTesting
  static List<FeedVideo> feedFromInfo(Map<String, dynamic> info) {
    final entries = (info['entries'] as List?)?.whereType<Map>() ?? const [];
    final out = <FeedVideo>[];
    for (final e in entries) {
      final slug = e['display_id'];
      if (slug is! String || slug.isEmpty) continue;
      final at = e['timestamp'] ?? e['release_timestamp'];
      final seconds = e['duration'];
      out.add(FeedVideo(
        link: NebulaLink(slug, thumbnailUrl: e['thumbnail'] as String?),
        title: '${e['title'] ?? ''}',
        channel: '${e['channel'] ?? e['uploader'] ?? ''}',
        released: at is num
            ? DateTime.fromMillisecondsSinceEpoch((at * 1000).round(),
                isUtc: true)
            : null,
        duration: seconds is num && seconds > 0
            ? Duration(seconds: seconds.round())
            : null,
      ));
    }
    return out;
  }
}

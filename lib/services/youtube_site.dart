import 'package:flutter/foundation.dart';

import 'video_site.dart';
import 'youtube_link.dart';
import 'yt_dlp.dart';

/// YouTube: the account's subscriptions, for the dashboard tile, and the
/// sign-in that lets Premium, members-only and age-restricted videos play.
class YouTubeSite extends VideoSite {
  YouTubeSite(super.config, super.ytDlp);

  @override
  String get id => 'youtube';

  @override
  String get name => 'YouTube';

  /// Straight to YouTube's sign-in, and back to YouTube afterwards.
  @override
  String get signInUrl =>
      'https://accounts.google.com/ServiceLogin?service=youtube'
      '&continue=https%3A%2F%2Fwww.youtube.com%2F';

  /// YouTube's sign-in rests on Google's own cookies as well as its own.
  static const domains = ['youtube.com', 'google.com'];

  @override
  List<String> get cookieDomains => domains;

  @override
  bool get storedSignedIn => config.config.youtube.signedIn;

  @override
  set storedSignedIn(bool value) => config.config.youtube.signedIn = value;

  /// The subscriptions feed, by yt-dlp's name for it rather than its
  /// address: the address answers with an empty list when nobody is signed
  /// in, while this refuses — which is what makes it a test of the sign-in.
  static const String subscriptionsUrl = ':ytsubs';

  Future<Map<String, dynamic>> _subscriptions(int count) async {
    try {
      return await runYtDlp(
          ['-J', '--flat-playlist', '-I', '1:$count', subscriptionsUrl]);
    } on VideoException catch (e) {
      if (YtDlp.wantsSignIn(e.message)) throw const SignedOut();
      rethrow;
    }
  }

  @override
  Future<void> verify() => _subscriptions(1);

  @override
  Future<List<FeedVideo>> fetchFeed(int count) async =>
      feedFromInfo(await _subscriptions(count));

  /// From yt-dlp's `--flat-playlist -J` output. Entries without a video id —
  /// a Short shelf, a channel — are left out.
  @visibleForTesting
  static List<FeedVideo> feedFromInfo(Map<String, dynamic> info) {
    final entries = (info['entries'] as List?)?.whereType<Map>() ?? const [];
    return [
      for (final e in entries)
        if (YouTubeLink.parse(
              'https://www.youtube.com/watch?v=${e['id'] ?? ''}',
            )
            case final link?)
          FeedVideo(
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

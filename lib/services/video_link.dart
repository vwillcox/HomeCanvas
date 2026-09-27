import 'youtube_link.dart';

/// A video on a site the panel can play: YouTube, Floatplane or Nebula.
///
/// What the player needs is the same for each — an address for yt-dlp, a
/// picture to show while it loads, and where to start — so the player, the
/// picture-in-picture window and the dashboard tiles take one of these
/// rather than knowing about any one site.
abstract class VideoLink {
  /// Stable within the site: the cache of resolved streams is keyed on it.
  String get id;

  /// Which site, and so which sign-in yt-dlp uses: `youtube`, `floatplane`,
  /// `nebula` — the same as `VideoSite.id`.
  String get site;

  /// The site's name, for people: "Floatplane".
  String get siteName;

  /// The page yt-dlp is given.
  String get url;

  /// Shown while the stream is fetched. Null when there is none to hand.
  String? get thumbnailUrl;

  Duration get start;

  /// The video [url] points to on any supported site, or null.
  static VideoLink? parse(String url) =>
      YouTubeLink.parse(url) ??
      FloatplaneLink.parse(url) ??
      NebulaLink.parse(url);
}

/// A Floatplane post. Its id is the post's, from `floatplane.com/post/<id>`.
class FloatplaneLink implements VideoLink {
  const FloatplaneLink(this.id, {this.thumbnailUrl});

  @override
  final String id;

  @override
  final String? thumbnailUrl;

  @override
  String get site => 'floatplane';

  @override
  String get siteName => 'Floatplane';

  @override
  String get url => 'https://www.floatplane.com/post/$id';

  @override
  Duration get start => Duration.zero;

  static final RegExp _post = RegExp(
      r'^https?://(?:www\.|beta\.)?floatplane\.com/post/(\w+)',
      caseSensitive: false);

  static FloatplaneLink? parse(String url) {
    final m = _post.firstMatch(url.trim());
    return m == null ? null : FloatplaneLink(m.group(1)!);
  }

  @override
  bool operator ==(Object other) => other is FloatplaneLink && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'FloatplaneLink($id)';
}

/// A Nebula video. Its id is the video's slug, from `nebula.tv/videos/<slug>`.
class NebulaLink implements VideoLink {
  const NebulaLink(this.id, {this.thumbnailUrl});

  @override
  final String id;

  @override
  final String? thumbnailUrl;

  @override
  String get site => 'nebula';

  @override
  String get siteName => 'Nebula';

  @override
  String get url => 'https://nebula.tv/videos/$id';

  @override
  Duration get start => Duration.zero;

  /// Nebula has answered to three names; links to all of them still go round.
  static final RegExp _video = RegExp(
      r'^https?://(?:www\.|beta\.)?(?:nebula\.tv|nebula\.app|watchnebula\.com)'
      r'/videos/([\w-]+)',
      caseSensitive: false);

  static NebulaLink? parse(String url) {
    final m = _video.firstMatch(url.trim());
    return m == null ? null : NebulaLink(m.group(1)!);
  }

  @override
  bool operator ==(Object other) => other is NebulaLink && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'NebulaLink($id)';
}

/// A YouTube video, picked out of whichever of YouTube's many link shapes it
/// arrived as.
///
/// The phone's share sheet sends `youtu.be/ID?si=…`, a browser sends
/// `youtube.com/watch?v=ID`, Shorts and live streams have paths of their own,
/// and a news feed can carry an embed. All of them name the same eleven
/// characters, and that id is all the kiosk needs to play one.
class YouTubeLink {
  const YouTubeLink(this.id, {this.start = Duration.zero});

  final String id;

  /// Where to start, from the link's `t=` or `start=`. Zero for the start.
  final Duration start;

  /// The address yt-dlp is given — the plain watch page, without the tracking
  /// and playlist parameters a shared link carries.
  String get watchUrl => 'https://www.youtube.com/watch?v=$id';

  /// A still of the video, served by YouTube without signing in.
  String get thumbnailUrl => 'https://i.ytimg.com/vi/$id/hqdefault.jpg';

  static final RegExp _id = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static const _hosts = {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtube-nocookie.com',
    'www.youtube-nocookie.com',
  };

  /// The video [url] points to, or null when it is not a YouTube video.
  static YouTubeLink? parse(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.scheme.startsWith('http')) return null;
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    String? id;
    if (host == 'youtu.be') {
      id = segments.firstOrNull;
    } else if (_hosts.contains(host)) {
      if (segments.firstOrNull == 'watch') {
        id = uri.queryParameters['v'];
      } else if (segments.length >= 2 &&
          const {'shorts', 'live', 'embed', 'v'}.contains(segments[0])) {
        id = segments[1];
      }
    }
    if (id == null || !_id.hasMatch(id)) return null;

    final t = uri.queryParameters['t'] ?? uri.queryParameters['start'];
    return YouTubeLink(id, start: parseTime(t));
  }

  /// A `t=` value: plain seconds (`90`, `90s`) or `1h2m3s`.
  static Duration parseTime(String? t) {
    if (t == null || t.isEmpty) return Duration.zero;
    final plain = int.tryParse(t.endsWith('s') ? t.substring(0, t.length - 1) : t);
    if (plain != null) return Duration(seconds: plain);
    final m = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$').firstMatch(t);
    if (m == null) return Duration.zero;
    int part(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    return Duration(hours: part(1), minutes: part(2), seconds: part(3));
  }

  @override
  bool operator ==(Object other) =>
      other is YouTubeLink && other.id == id && other.start == start;

  @override
  int get hashCode => Object.hash(id, start);

  @override
  String toString() => 'YouTubeLink($id, $start)';
}

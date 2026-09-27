import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'cookie_file.dart';
import 'video_link.dart';
import 'video_site.dart';

/// Floatplane: the latest from the creators the account subscribes to.
///
/// Floatplane has no public API, but its site runs on a documented one
/// (github.com/Jman012/FloatplaneAPI) authorised by one cookie, `sails.sid`.
/// The feed is read from there; playing a post is yt-dlp's job. Its streams
/// are encrypted, and mpv needs the cookie as well to fetch the key — see
/// `VideoStream.cookiesFile`.
class FloatplaneSite extends VideoSite {
  FloatplaneSite(super.config, super.ytDlp);

  @override
  String get id => 'floatplane';

  @override
  String get name => 'Floatplane';

  @override
  String get signInUrl => 'https://www.floatplane.com/login';

  @override
  List<String> get cookieDomains => const ['floatplane.com'];

  @override
  String get signInCookie => 'sails.sid';

  @override
  bool get storedSignedIn => config.config.floatplane.signedIn;

  @override
  set storedSignedIn(bool value) => config.config.floatplane.signedIn = value;

  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://www.floatplane.com',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      // Floatplane asks clients of its API to say who they are.
      'User-Agent': 'HomeCanvas (+https://github.com/vwillcox/HomeCanvas)',
      'Accept': 'application/json',
    },
  ));

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }

  Future<Object?> _get(String path, Map<String, dynamic> query) async {
    String? sid;
    try {
      sid = CookieFile.value(await File(cookiesFile).readAsString(),
          'sails.sid');
    } catch (_) {}
    if (sid == null) throw const SignedOut();
    try {
      final r = await _dio.get<Object?>(path,
          queryParameters: query,
          options: Options(headers: {'Cookie': 'sails.sid=$sid'}));
      return r.data;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) throw const SignedOut();
      rethrow;
    }
  }

  @override
  Future<void> verify() => _get('/api/v3/user/subscriptions', const {});

  @override
  Future<List<FeedVideo>> fetchFeed(int count) async {
    final subs = await _get('/api/v3/user/subscriptions', const {});
    final creators = <String>{
      if (subs is List)
        for (final s in subs.whereType<Map>())
          if (s['creator'] is String) s['creator'] as String,
    }.toList();
    if (creators.isEmpty) return const [];
    // The site writes the creator ids as `ids[0]=…&ids[1]=…`; the published
    // description of the API says repeated `ids=`. Tried in that order.
    try {
      return feedFromApi(await _get('/api/v3/content/creator/list', {
        for (var i = 0; i < creators.length; i++) 'ids[$i]': creators[i],
        'limit': count,
      }));
    } on DioException catch (e) {
      if (e.response?.statusCode != 400) rethrow;
      return feedFromApi(await _get(
          '/api/v3/content/creator/list', {'ids': creators, 'limit': count}));
    }
  }

  /// The video posts in a `/api/v3/content/creator/list` reply, newest first.
  /// Posts that are only text, pictures or audio are left out: the tile is
  /// for watching.
  @visibleForTesting
  static List<FeedVideo> feedFromApi(Object? json) {
    final posts = json is Map ? json['blogPosts'] : null;
    if (posts is! List) return const [];
    final out = <FeedVideo>[];
    for (final post in posts.whereType<Map>()) {
      final id = post['id'];
      final metadata = post['metadata'];
      if (id is! String || id.isEmpty) continue;
      if (metadata is Map && metadata['hasVideo'] != true) continue;
      final creator = post['creator'];
      final thumbnail = post['thumbnail'];
      final seconds =
          metadata is Map ? (metadata['videoDuration'] as num?) : null;
      out.add(FeedVideo(
        link: FloatplaneLink(
          id,
          thumbnailUrl: thumbnail is Map ? _image(thumbnail) : null,
        ),
        title: '${post['title'] ?? ''}',
        channel: creator is Map ? '${creator['title'] ?? ''}' : '',
        released: DateTime.tryParse('${post['releaseDate'] ?? ''}'),
        duration: seconds == null || seconds <= 0
            ? null
            : Duration(seconds: seconds.round()),
      ));
    }
    out.sort((a, b) => (b.released ?? DateTime(0))
        .compareTo(a.released ?? DateTime(0)));
    return out;
  }

  /// The smallest of a thumbnail's sizes that is still sharp on a tile —
  /// the full one is often 1920 wide, and a grid of six of those is a lot of
  /// decoding for the Pi to do behind a playing video.
  static String? _image(Map image) {
    final sizes = [
      image,
      ...((image['childImages'] as List?)?.whereType<Map>() ?? const <Map>[]),
    ].where((i) => i['path'] is String && i['width'] is num).toList()
      ..sort((a, b) => (a['width'] as num).compareTo(b['width'] as num));
    if (sizes.isEmpty) return null;
    final good = sizes.firstWhere((i) => (i['width'] as num) >= 400,
        orElse: () => sizes.last);
    return good['path'] as String;
  }
}

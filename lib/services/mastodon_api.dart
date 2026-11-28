import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../map_text.dart';
import 'http_client.dart';
import 'social.dart';

/// What a Mastodon tile can show.
enum MastodonFeed {
  home,
  notifications,
  mentions,
  local,
  federated,
  trending,
  hashtag,
  list,
  mine,
  bookmarks,
  favourites,
}

/// An account on a Mastodon server, signed in with an access token from its
/// Preferences → Development.
@immutable
class MastodonAccount {
  const MastodonAccount({required this.server, required this.token});

  /// `https://mastodon.social`, as [serverAddress] gives it.
  final String server;
  final String token;

  /// Who it is, for keeping things apart by: the token itself stays out.
  String get key => '$server ${token.hashCode}';
}

/// Which of two Mastodon ids is newer. They are numbers written out — too
/// big for an int on some servers — so the longer is the newer, and of two
/// the same length, the later in order.
int compareMastodonIds(String a, String b) =>
    a.length != b.length ? a.length - b.length : a.compareTo(b);

/// What a failed request means.
SocialFailure classifyMastodon(DioException e) {
  final r = e.response;
  if (r == null) return SocialFailure.unreachable;
  return switch (r.statusCode) {
    401 => SocialFailure.badCredentials,
    403 => SocialFailure.forbidden,
    404 => SocialFailure.notFound,
    429 => SocialFailure.rateLimited,
    _ => SocialFailure.unexpected,
  };
}

/// Mastodon's REST API, for the dashboard's Mastodon tiles and for the
/// notifications popped up on the panel.
class MastodonApi {
  MastodonApi({Dio? dio}) : _dio = dio ?? _shared;

  static final Dio _shared = httpClient(
    headers: const {'User-Agent': homeCanvasAgent},
  );

  final Dio _dio;

  /// Who each token belongs to, asked once.
  static final Map<String, Map<String, dynamic>> _me = {};

  /// Lists by name, as found, for each account.
  static final Map<String, String> _lists = {};

  /// Replaces every feed fetched — for tests, which have no network.
  @visibleForTesting
  static Future<SocialFeed> Function(
    MastodonAccount account,
    MastodonFeed feed,
  )?
  debugFeed;

  Future<Object?> _get(
    MastodonAccount a,
    String path, [
    Map<String, dynamic>? query,
  ]) async {
    try {
      final r = await _dio.get<Object?>(
        '${a.server}$path',
        queryParameters: query,
        // Only ever sent to the server the token is for.
        options: Options(headers: {'Authorization': 'Bearer ${a.token}'}),
      );
      return r.data;
    } on DioException catch (e) {
      final said = e.response?.data;
      throw SocialException(
        classifyMastodon(e),
        said is Map ? said.text('error') : '',
      );
    }
  }

  /// The account [a] signs in as. Asked once — it also proves the token.
  Future<Map<String, dynamic>> me(MastodonAccount a) async {
    final known = _me[a.key];
    if (known != null) return known;
    final data = await _get(a, '/api/v1/accounts/verify_credentials');
    if (data is! Map) throw const SocialException(SocialFailure.unexpected);
    return _me[a.key] = data.cast<String, dynamic>();
  }

  /// [feed], as [a] sees it. [hashtag] and [list] say which, for those
  /// feeds; [limit] is at most 40, Mastodon's own most.
  Future<SocialFeed> feed(
    MastodonAccount a,
    MastodonFeed feed, {
    String hashtag = '',
    String list = '',
    int limit = 20,
  }) async {
    final fake = debugFeed;
    if (fake != null) return fake(a, feed);

    final me = await this.me(a);
    final who = '@${me.text('acct')}@${Uri.parse(a.server).host}';
    final n = limit.clamp(1, 40);
    if (feed == MastodonFeed.notifications || feed == MastodonFeed.mentions) {
      return SocialFeed(
        who: who,
        notices: await notices(
          a,
          limit: n,
          mentionsOnly: feed == MastodonFeed.mentions,
        ),
      );
    }
    final tag = hashtag.trim().replaceFirst(RegExp('^#'), '');
    if (feed == MastodonFeed.hashtag && tag.isEmpty) {
      throw const SocialException(SocialFailure.notFound);
    }
    final (String path, Map<String, dynamic> query) = switch (feed) {
      MastodonFeed.home => ('/api/v1/timelines/home', const {}),
      MastodonFeed.local => ('/api/v1/timelines/public', {'local': true}),
      MastodonFeed.federated => ('/api/v1/timelines/public', const {}),
      MastodonFeed.trending => ('/api/v1/trends/statuses', const {}),
      MastodonFeed.hashtag => (
        '/api/v1/timelines/tag/${Uri.encodeComponent(tag)}',
        const {},
      ),
      MastodonFeed.list => (
        '/api/v1/timelines/list/${await _listId(a, list)}',
        const {},
      ),
      MastodonFeed.mine => (
        '/api/v1/accounts/${Uri.encodeComponent(me.text('id'))}/statuses',
        const {},
      ),
      MastodonFeed.bookmarks => ('/api/v1/bookmarks', const {}),
      MastodonFeed.favourites => ('/api/v1/favourites', const {}),
      MastodonFeed.notifications || MastodonFeed.mentions => ('', const {}),
    };
    final data = await _get(a, path, {...query, 'limit': n});
    return SocialFeed(
      who: who,
      posts: [
        for (final s in (data is List ? data : const []).whereType<Map>())
          parseStatus(s.cast<String, dynamic>()),
      ],
    );
  }

  /// [a]'s notifications, newest first: only those after [sinceId], when
  /// given, and only mentions with [mentionsOnly].
  Future<List<SocialNotice>> notices(
    MastodonAccount a, {
    String? sinceId,
    int limit = 30,
    bool mentionsOnly = false,
  }) async {
    final data = await _get(a, '/api/v1/notifications', {
      'limit': limit.clamp(1, 40),
      'since_id': ?sinceId,
      if (mentionsOnly) 'types[]': 'mention',
    });
    return [
      for (final n in (data is List ? data : const []).whereType<Map>())
        parseNotification(n.cast<String, dynamic>()),
    ];
  }

  /// The id of [a]'s list called [name] — or [name] itself, if it is one.
  Future<String> _listId(MastodonAccount a, String name) async {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) throw const SocialException(SocialFailure.notFound);
    final known = _lists['${a.key} $wanted'];
    if (known != null) return known;
    final data = await _get(a, '/api/v1/lists');
    for (final l in (data is List ? data : const []).whereType<Map>()) {
      if (l.text('title').toLowerCase() == wanted || l.text('id') == wanted) {
        return _lists['${a.key} $wanted'] = l.text('id');
      }
    }
    throw SocialException(SocialFailure.notFound, name);
  }

  /// Someone, from Mastodon's account.
  static SocialPerson parseAccount(Object? raw) {
    if (raw is! Map) return const SocialPerson(name: '', handle: '');
    final codes = [
      for (final e in (raw['emojis'] as List? ?? const []).whereType<Map>())
        e.text('shortcode'),
    ];
    final handle = raw.text('acct');
    final name = withoutShortcodes(raw.text('display_name'), codes);
    final avatar = raw.text('avatar_static');
    return SocialPerson(
      name: name.isEmpty ? raw.text('username') : name,
      handle: handle,
      avatar: avatar.isEmpty ? null : avatar,
    );
  }

  /// A post, from Mastodon's status. A boost is the post boosted, with who
  /// boosted it.
  static SocialPost parseStatus(Map<String, dynamic> raw) {
    final boosted = raw['reblog'];
    final s = boosted is Map ? boosted.cast<String, dynamic>() : raw;
    final codes = [
      for (final e in (s['emojis'] as List? ?? const []).whereType<Map>())
        e.text('shortcode'),
    ];
    final warning = withoutShortcodes(s.text('spoiler_text'), codes);
    final card = s['card'];
    final linkTitle = card is Map ? card.text('title') : '';
    final url = s.text('url').isNotEmpty ? s.text('url') : s.text('uri');
    int count(String key) => (s[key] as num?)?.toInt() ?? 0;
    return SocialPost(
      id: s.text('id'),
      author: parseAccount(s['account']),
      text: withoutShortcodes(postText(s.text('content')), codes),
      at: DateTime.tryParse(s.text('created_at'))?.toLocal(),
      url: url.isEmpty ? null : url,
      images: [
        for (final m
            in (s['media_attachments'] as List? ?? const []).whereType<Map>())
          if (m.text('preview_url').isNotEmpty)
            SocialImage(
              preview: m.text('preview_url'),
              // A video or GIF has a still for its preview, and that is all
              // a tile can show of it.
              full: m.text('type') == 'image' && m.text('url').isNotEmpty
                  ? m.text('url')
                  : m.text('preview_url'),
              alt: m.text('description'),
            ),
      ],
      replies: count('replies_count'),
      boosts: count('reblogs_count'),
      likes: count('favourites_count'),
      boostedBy: boosted is Map ? parseAccount(raw['account']) : null,
      isReply: s['in_reply_to_id'] != null,
      warning: warning.isEmpty ? null : warning,
      sensitive: s['sensitive'] == true,
      linkTitle: linkTitle.isEmpty ? null : linkTitle,
    );
  }

  /// A notification, from Mastodon's.
  static SocialNotice parseNotification(Map<String, dynamic> n) {
    final status = n['status'];
    final post = status is Map ? parseStatus(status.cast()) : null;
    final kind = switch (n.text('type')) {
      'mention' when post?.isReply ?? false => SocialNoticeKind.reply,
      'mention' => SocialNoticeKind.mention,
      'quote' => SocialNoticeKind.quote,
      'reblog' => SocialNoticeKind.boost,
      'favourite' => SocialNoticeKind.like,
      'follow' => SocialNoticeKind.follow,
      'follow_request' => SocialNoticeKind.followRequest,
      'poll' => SocialNoticeKind.poll,
      'status' => SocialNoticeKind.post,
      'update' => SocialNoticeKind.edit,
      _ => SocialNoticeKind.other,
    };
    return SocialNotice(
      id: n.text('id'),
      kind: kind,
      who: parseAccount(n['account']),
      at: DateTime.tryParse(n.text('created_at'))?.toLocal(),
      post: post,
    );
  }
}

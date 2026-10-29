import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../map_text.dart';
import 'http_client.dart';
import 'social.dart';

/// What a Bluesky tile can show.
enum BlueskyFeed {
  following,
  discover,
  notifications,
  mentions,
  custom,
  list,
  mine,
  likes,
}

/// A Bluesky account, signed in with an app password from its Settings →
/// Privacy and security → App passwords.
@immutable
class BlueskyAccount {
  const BlueskyAccount({
    required this.identifier,
    required this.password,
    this.service = defaultService,
  });

  /// Where an account made on bsky.app signs in. One on a server of its own
  /// signs in there instead.
  static const defaultService = 'https://bsky.social';

  /// The handle, without the @ — or the account's email address, or its DID.
  final String identifier;
  final String password;
  final String service;

  /// Who it is, for keeping things apart by: the password itself stays out.
  String get key => '$service $identifier ${password.hashCode}';
}

/// The handle from what someone typed: `@alice.bsky.social`, or a link to
/// the profile on bsky.app.
String blueskyIdentifier(String typed) {
  var s = typed.trim();
  final link = RegExp(r'bsky\.app/profile/([^/?#]+)').firstMatch(s);
  if (link != null) s = link[1]!;
  return s.replaceFirst(RegExp('^@'), '');
}

/// The Discover feed, as made by Bluesky itself.
const kBlueskyDiscover =
    'at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/whats-hot';

/// Labels that mark a post's pictures as not for everyone.
const _adult = {'porn', 'sexual', 'nudity', 'graphic-media', 'gore'};

/// What a failed request means. Bluesky answers 400 for a feed, list or
/// handle it does not know.
SocialFailure classifyBluesky(DioException e) {
  final r = e.response;
  if (r == null) return SocialFailure.unreachable;
  return switch (r.statusCode) {
    401 => SocialFailure.badCredentials,
    403 => SocialFailure.forbidden,
    400 || 404 => SocialFailure.notFound,
    429 => SocialFailure.rateLimited,
    _ => SocialFailure.unexpected,
  };
}

/// A signed-in session: tokens, and the server the account lives on.
class _Session {
  _Session({
    required this.access,
    required this.refresh,
    required this.did,
    required this.handle,
    required this.pds,
  });

  final String access;
  final String refresh;
  final String did;
  final String handle;

  /// The account's own server, which every request after signing in goes
  /// to: bsky.social only signs people in.
  final String pds;

  static _Session from(Map<String, dynamic> j, String fallback) {
    var pds = fallback;
    final doc = j['didDoc'];
    if (doc is Map) {
      for (final s in (doc['service'] as List? ?? const []).whereType<Map>()) {
        final at = s.text('serviceEndpoint');
        if (s.text('id').endsWith('#atproto_pds') &&
            at.startsWith('https://')) {
          pds = at;
        }
      }
    }
    return _Session(
      access: j.text('accessJwt'),
      refresh: j.text('refreshJwt'),
      did: j.text('did'),
      handle: j.text('handle'),
      pds: trimAddress(pds),
    );
  }
}

/// Bluesky's XRPC API, for the dashboard's Bluesky tiles and for the
/// notifications popped up on the panel.
///
/// Signing in is held to 30 times in five minutes and 300 a day, so a
/// session, once made, is kept and renewed with its refresh token rather
/// than made again — and a password turned down is not tried again for half
/// an hour, unless it is changed.
class BlueskyApi {
  BlueskyApi({Dio? dio}) : _dio = dio ?? _shared;

  static final Dio _shared = httpClient(
    headers: const {'User-Agent': homeCanvasAgent},
  );

  final Dio _dio;

  static final Map<String, _Session> _sessions = {};
  static final Map<String, Future<_Session>> _signingIn = {};
  static final Map<String, DateTime> _refused = {};
  static const _holdOff = Duration(minutes: 30);

  /// Replaces every feed fetched — for tests, which have no network.
  @visibleForTesting
  static Future<SocialFeed> Function(BlueskyAccount account, BlueskyFeed feed)?
  debugFeed;

  /// Forgets every session — for tests.
  @visibleForTesting
  static void debugForget() {
    _sessions.clear();
    _signingIn.clear();
    _refused.clear();
  }

  Future<_Session> _session(BlueskyAccount a) async =>
      _sessions[a.key] ?? await _once(a, () => _signIn(a));

  /// One sign-in or renewal at a time for each account, however many tiles
  /// and checks ask for it at once.
  ///
  /// The block, not an arrow: what [Map.remove] returns is this very
  /// future, and whenComplete would wait for it — that is, forever.
  Future<_Session> _once(BlueskyAccount a, Future<_Session> Function() run) =>
      _signingIn[a.key] ??= run().whenComplete(() {
        _signingIn.remove(a.key);
      });

  Future<_Session> _signIn(BlueskyAccount a) async {
    final refused = _refused[a.key];
    if (refused != null && DateTime.now().difference(refused) < _holdOff) {
      throw const SocialException(SocialFailure.badCredentials);
    }
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '${a.service}/xrpc/com.atproto.server.createSession',
        data: {'identifier': a.identifier, 'password': a.password},
      );
      return _sessions[a.key] = _Session.from(r.data ?? const {}, a.service);
    } on DioException catch (e) {
      final failure = classifyBluesky(e);
      // A 400 here is a malformed handle: as wrong as a wrong password.
      if (failure == SocialFailure.badCredentials ||
          failure == SocialFailure.notFound) {
        _refused[a.key] = DateTime.now();
        throw SocialException(SocialFailure.badCredentials, _said(e));
      }
      throw SocialException(failure, _said(e));
    }
  }

  /// A fresh session for [old], whose access token has run out: from its
  /// refresh token, or by signing in again once that has run out too.
  Future<_Session> _renew(BlueskyAccount a, _Session old) => _once(a, () async {
    // Another request may have renewed it while this one waited.
    final now = _sessions[a.key];
    if (now != null && now.access != old.access) return now;
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '${old.pds}/xrpc/com.atproto.server.refreshSession',
        options: Options(headers: {'Authorization': 'Bearer ${old.refresh}'}),
      );
      return _sessions[a.key] = _Session.from(r.data ?? const {}, old.pds);
    } on DioException {
      _sessions.remove(a.key);
      return _signIn(a);
    }
  });

  static String _said(DioException e) {
    final said = e.response?.data;
    if (said is! Map) return '';
    return said.text('message').isNotEmpty
        ? said.text('message')
        : said.text('error');
  }

  static bool _expired(DioException e) {
    final said = e.response?.data;
    final error = said is Map ? said.text('error') : '';
    return error == 'ExpiredToken' || error == 'InvalidToken';
  }

  Future<Map<String, dynamic>> _get(
    BlueskyAccount a,
    String method,
    Map<String, dynamic> query,
  ) async {
    var s = await _session(a);
    for (var attempt = 0; ; attempt++) {
      try {
        final r = await _dio.get<Map<String, dynamic>>(
          '${s.pds}/xrpc/$method',
          queryParameters: query,
          options: Options(
            headers: {'Authorization': 'Bearer ${s.access}'},
            listFormat: ListFormat.multi,
          ),
        );
        return r.data ?? const {};
      } on DioException catch (e) {
        if (attempt == 0 && _expired(e)) {
          s = await _renew(a, s);
          continue;
        }
        throw SocialException(classifyBluesky(e), _said(e));
      }
    }
  }

  /// [feed], as [a] sees it. [custom] and [list] say which, for those feeds:
  /// a link to it on bsky.app or its at:// address — or, for a list, its
  /// name. [limit] is at most 100.
  Future<SocialFeed> feed(
    BlueskyAccount a,
    BlueskyFeed feed, {
    String custom = '',
    String list = '',
    int limit = 30,
  }) async {
    final fake = debugFeed;
    if (fake != null) return fake(a, feed);

    final s = await _session(a);
    final who = '@${s.handle}';
    final n = limit.clamp(1, 100);
    if (feed == BlueskyFeed.notifications || feed == BlueskyFeed.mentions) {
      return SocialFeed(
        who: who,
        notices: await notices(
          a,
          limit: n,
          mentionsOnly: feed == BlueskyFeed.mentions,
        ),
      );
    }
    final (String method, Map<String, dynamic> query) = switch (feed) {
      BlueskyFeed.following => ('app.bsky.feed.getTimeline', const {}),
      BlueskyFeed.discover => (
        'app.bsky.feed.getFeed',
        {'feed': kBlueskyDiscover},
      ),
      BlueskyFeed.custom => (
        'app.bsky.feed.getFeed',
        {'feed': await _address(a, custom, 'app.bsky.feed.generator', 'feed')},
      ),
      BlueskyFeed.list => (
        'app.bsky.feed.getListFeed',
        {'list': await _listAddress(a, s, list)},
      ),
      BlueskyFeed.mine => (
        'app.bsky.feed.getAuthorFeed',
        {'actor': s.did, 'filter': 'posts_and_author_threads'},
      ),
      BlueskyFeed.likes => ('app.bsky.feed.getActorLikes', {'actor': s.did}),
      BlueskyFeed.notifications || BlueskyFeed.mentions => ('', const {}),
    };
    final data = await _get(a, method, {...query, 'limit': n});
    return SocialFeed(
      who: who,
      posts: [
        for (final item in (data['feed'] as List? ?? const []).whereType<Map>())
          ?parseFeedItem(item.cast<String, dynamic>()),
      ],
    );
  }

  /// [a]'s notifications, newest first — only mentions, replies and quotes
  /// with [mentionsOnly].
  Future<List<SocialNotice>> notices(
    BlueskyAccount a, {
    int limit = 30,
    bool mentionsOnly = false,
  }) async {
    final data = await _get(a, 'app.bsky.notification.listNotifications', {
      'limit': limit.clamp(1, 100),
      if (mentionsOnly) 'reasons': const ['mention', 'reply', 'quote'],
    });
    final raw = [
      for (final n
          in (data['notifications'] as List? ?? const []).whereType<Map>())
        n.cast<String, dynamic>(),
    ];
    // A like or a repost points at your post rather than carrying it, so
    // the posts are asked for, all at once.
    final subjects = {
      for (final n in raw)
        if (!_carriesPost.contains(n.text('reason')) &&
            n.text('reasonSubject').startsWith('at://'))
          n.text('reasonSubject'),
    };
    final posts = await _posts(a, subjects.take(25).toList());
    return [for (final n in raw) parseNotification(n, posts)];
  }

  /// Reasons whose notification is a post of its own.
  static const _carriesPost = {'mention', 'reply', 'quote', 'subscribed-post'};

  /// The posts at [uris], by address. Without them a notification still
  /// says who did what, so a failure here is no failure.
  Future<Map<String, SocialPost>> _posts(
    BlueskyAccount a,
    List<String> uris,
  ) async {
    if (uris.isEmpty) return const {};
    try {
      final data = await _get(a, 'app.bsky.feed.getPosts', {'uris': uris});
      return {
        for (final p in (data['posts'] as List? ?? const []).whereType<Map>())
          p.text('uri'): parsePost(p.cast<String, dynamic>()),
      };
    } on SocialException {
      return const {};
    }
  }

  /// The at:// address of a feed or list from [typed]: that address
  /// itself, or a link to it on bsky.app — whose profile may be a handle,
  /// looked up here.
  Future<String> _address(
    BlueskyAccount a,
    String typed,
    String collection,
    String segment,
  ) async {
    final s = typed.trim();
    if (s.startsWith('at://')) return s;
    final link = RegExp(
      'bsky\\.app/profile/([^/?#]+)/$segment/([^/?#]+)',
    ).firstMatch(s);
    if (link == null) throw SocialException(SocialFailure.notFound, typed);
    var actor = link[1]!;
    if (!actor.startsWith('did:')) {
      final r = await _get(a, 'com.atproto.identity.resolveHandle', {
        'handle': actor,
      });
      actor = r.text('did');
    }
    return 'at://$actor/$collection/${link[2]}';
  }

  /// The at:// address of one of [s]'s lists, from a link to it or its
  /// name.
  Future<String> _listAddress(
    BlueskyAccount a,
    _Session s,
    String typed,
  ) async {
    final t = typed.trim();
    if (t.isEmpty) throw const SocialException(SocialFailure.notFound);
    if (t.startsWith('at://') || t.contains('bsky.app/')) {
      return _address(a, t, 'app.bsky.graph.list', 'lists');
    }
    final data = await _get(a, 'app.bsky.graph.getLists', {
      'actor': s.did,
      'limit': 100,
    });
    for (final l in (data['lists'] as List? ?? const []).whereType<Map>()) {
      if (l.text('name').toLowerCase() == t.toLowerCase()) return l.text('uri');
    }
    throw SocialException(SocialFailure.notFound, typed);
  }

  /// Someone, from Bluesky's profile view.
  static SocialPerson parseActor(Object? raw) {
    if (raw is! Map) return const SocialPerson(name: '', handle: '');
    final handle = raw.text('handle');
    final name = raw.text('displayName');
    final avatar = raw.text('avatar');
    return SocialPerson(
      name: name.isEmpty ? handle : name,
      handle: handle,
      avatar: avatar.isEmpty ? null : avatar,
    );
  }

  /// A post's page on bsky.app.
  static String postUrl(String uri, String handle) {
    final parts = uri.replaceFirst('at://', '').split('/');
    if (parts.length < 3) return 'https://bsky.app';
    // An account whose handle no longer checks out is reached by its DID.
    final who = handle.isEmpty || handle == 'handle.invalid'
        ? parts[0]
        : handle;
    return 'https://bsky.app/profile/$who/post/${parts.last}';
  }

  /// Pictures, and a linked page's title, from what is embedded in a post.
  static (List<SocialImage>, String?) _embedded(Object? embed) {
    if (embed is! Map) return (const [], null);
    final type = embed.text(r'$type');
    if (type.startsWith('app.bsky.embed.recordWithMedia')) {
      return _embedded(embed['media']);
    }
    if (type.startsWith('app.bsky.embed.images')) {
      return (
        [
          for (final i
              in (embed['images'] as List? ?? const []).whereType<Map>())
            if (i.text('thumb').isNotEmpty)
              SocialImage(
                preview: i.text('thumb'),
                full: i.text('fullsize').isEmpty
                    ? i.text('thumb')
                    : i.text('fullsize'),
                alt: i.text('alt'),
              ),
        ],
        null,
      );
    }
    if (type.startsWith('app.bsky.embed.video')) {
      final still = embed.text('thumbnail');
      return (
        [
          if (still.isNotEmpty)
            SocialImage(preview: still, full: still, alt: embed.text('alt')),
        ],
        null,
      );
    }
    if (type.startsWith('app.bsky.embed.external')) {
      final page = embed['external'];
      if (page is! Map) return (const [], null);
      final title = page.text('title');
      final thumb = page.text('thumb');
      return (
        [if (thumb.isNotEmpty) SocialImage(preview: thumb, full: thumb)],
        title.isEmpty ? null : title,
      );
    }
    return (const [], null);
  }

  /// A post, from Bluesky's post view.
  static SocialPost parsePost(
    Map<String, dynamic> post, {
    SocialPerson? boostedBy,
  }) {
    final record = post['record'] is Map ? post['record'] as Map : const {};
    final author = parseActor(post['author']);
    final (images, linkTitle) = _embedded(post['embed']);
    final labels = {
      for (final l in (post['labels'] as List? ?? const []).whereType<Map>())
        l.text('val'),
    };
    int count(String key) => (post[key] as num?)?.toInt() ?? 0;
    return SocialPost(
      id: post.text('uri'),
      author: author,
      text: record.text('text'),
      at:
          (DateTime.tryParse(record.text('createdAt')) ??
                  DateTime.tryParse(post.text('indexedAt')))
              ?.toLocal(),
      url: postUrl(post.text('uri'), author.handle),
      images: images,
      replies: count('replyCount'),
      boosts: count('repostCount'),
      likes: count('likeCount'),
      boostedBy: boostedBy,
      isReply: record['reply'] != null,
      sensitive: labels.any(_adult.contains),
      linkTitle: linkTitle,
    );
  }

  /// A post in a feed, with who reposted it there. Null for anything that
  /// isn't one.
  static SocialPost? parseFeedItem(Map<String, dynamic> item) {
    final post = item['post'];
    if (post is! Map) return null;
    final reason = item['reason'];
    final reposted =
        reason is Map && reason.text(r'$type').endsWith('#reasonRepost');
    return parsePost(
      post.cast<String, dynamic>(),
      boostedBy: reposted ? parseActor(reason['by']) : null,
    );
  }

  /// A notification, from Bluesky's — with the post it is about from
  /// [subjects] where it doesn't carry its own.
  static SocialNotice parseNotification(
    Map<String, dynamic> n, [
    Map<String, SocialPost> subjects = const {},
  ]) {
    final reason = n.text('reason');
    final who = parseActor(n['author']);
    final at = DateTime.tryParse(n.text('indexedAt'))?.toLocal();
    final kind = switch (reason) {
      'like' || 'like-via-repost' => SocialNoticeKind.like,
      'repost' || 'repost-via-repost' => SocialNoticeKind.boost,
      'follow' => SocialNoticeKind.follow,
      'mention' => SocialNoticeKind.mention,
      'reply' => SocialNoticeKind.reply,
      'quote' => SocialNoticeKind.quote,
      'subscribed-post' => SocialNoticeKind.post,
      _ => SocialNoticeKind.other,
    };
    final record = n['record'];
    final own = _carriesPost.contains(reason) && record is Map
        ? SocialPost(
            id: n.text('uri'),
            author: who,
            text: record.text('text'),
            at: at,
            url: postUrl(n.text('uri'), who.handle),
          )
        : null;
    return SocialNotice(
      id: n.text('uri'),
      kind: kind,
      who: who,
      at: at,
      post: own ?? subjects[n.text('reasonSubject')],
    );
  }
}

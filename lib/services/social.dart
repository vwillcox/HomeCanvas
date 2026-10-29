import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';
import 'plain_text.dart';

/// The two social networks the dashboard reads. They differ in what things
/// are called — a Mastodon boost is a Bluesky repost, a favourite a like —
/// and in nothing the tiles care about besides.
enum SocialNetwork {
  mastodon('Mastodon'),
  bluesky('Bluesky');

  const SocialNetwork(this.title);

  /// Its own name, which is the same in every language.
  final String title;
}

/// Someone on either network.
@immutable
class SocialPerson {
  const SocialPerson({required this.name, required this.handle, this.avatar});

  /// Their display name, or their handle when they have none.
  final String name;

  /// Without the @: `alice@mastodon.social`, `alice.bsky.social`.
  final String handle;

  /// A picture of them, if they have one.
  final String? avatar;
}

/// A picture attached to a post.
@immutable
class SocialImage {
  const SocialImage({required this.preview, required this.full, this.alt = ''});

  final String preview;
  final String full;

  /// Its description, as its poster wrote it.
  final String alt;
}

/// A post, from either network, as a tile draws it.
@immutable
class SocialPost {
  const SocialPost({
    required this.id,
    required this.author,
    required this.text,
    this.at,
    this.url,
    this.images = const [],
    this.replies = 0,
    this.boosts = 0,
    this.likes = 0,
    this.boostedBy,
    this.isReply = false,
    this.warning,
    this.sensitive = false,
    this.linkTitle,
  });

  final String id;
  final SocialPerson author;

  /// Plain text, its paragraphs a blank line apart.
  final String text;
  final DateTime? at;

  /// Its page on the web.
  final String? url;
  final List<SocialImage> images;
  final int replies;
  final int boosts;
  final int likes;

  /// Who boosted or reposted it into the feed, when someone did.
  final SocialPerson? boostedBy;

  /// An answer to another post.
  final bool isReply;

  /// A content warning: what the post is about, with the post itself held
  /// back behind it. Mastodon's; Bluesky has none.
  final String? warning;

  /// Its pictures are marked as not for everyone.
  final bool sensitive;

  /// The title of a page it links to and shows a card for.
  final String? linkTitle;
}

/// What a notification is about.
enum SocialNoticeKind {
  mention,
  reply,
  quote,
  boost,
  like,
  follow,
  followRequest,
  poll,
  post,
  edit,
  other,
}

/// One notification.
@immutable
class SocialNotice {
  const SocialNotice({
    required this.id,
    required this.kind,
    required this.who,
    this.at,
    this.post,
  });

  final String id;
  final SocialNoticeKind kind;

  /// Who did it.
  final SocialPerson who;
  final DateTime? at;

  /// The post it is about — theirs for a reply, yours for a like.
  final SocialPost? post;

  /// Someone talking to you, rather than reacting to what you said: what
  /// the panel pops up when it is set to mentions only.
  bool get direct =>
      kind == SocialNoticeKind.mention ||
      kind == SocialNoticeKind.reply ||
      kind == SocialNoticeKind.quote;
}

/// What a tile shows: posts, or notifications.
@immutable
class SocialFeed {
  const SocialFeed({required this.who, this.posts = const [], this.notices});

  /// The account it was read as, for the tile's heading: `@alice@host`.
  final String who;
  final List<SocialPost> posts;

  /// Set for a feed of notifications, in place of [posts].
  final List<SocialNotice>? notices;
}

/// Why a feed could not be read, in terms a tile can explain.
enum SocialFailure {
  /// The token or password was turned down.
  badCredentials,

  /// No such hashtag, list, feed or server.
  notFound,

  /// The account may not see it.
  forbidden,

  /// Asked too often.
  rateLimited,

  /// Nothing answered.
  unreachable,

  /// Something else.
  unexpected,
}

class SocialException implements Exception {
  const SocialException(this.failure, [this.detail = '']);
  final SocialFailure failure;

  /// What the server said, when it said anything useful.
  final String detail;

  @override
  String toString() =>
      'SocialException($failure${detail.isEmpty ? '' : ': $detail'})';
}

/// A server's address from what someone typed — `mastodon.social`, its
/// address with or without https://, or a whole Mastodon handle,
/// `@me@mastodon.social` — or null when it is none of those.
///
/// Held to a host name and an optional port, so what a token is sent to is
/// a server and never somewhere else on one.
String? serverAddress(String typed) {
  var s = typed.trim();
  if (s.isEmpty) return null;
  final handle = RegExp(r'^@?[\w.-]+@([\w.-]+)$').firstMatch(s);
  if (handle != null) s = handle[1]!;
  var scheme = 'https';
  final given = RegExp(r'^(https?)://', caseSensitive: false).firstMatch(s);
  if (given != null) {
    scheme = given[1]!.toLowerCase();
    s = s.substring(given[0]!.length);
  }
  final host = s.split(RegExp('[/?#]')).first.toLowerCase();
  final name = RegExp(
    r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*'
    r'(?::\d{1,5})?$',
  );
  return name.hasMatch(host) ? '$scheme://$host' : null;
}

/// What [notice] says, in a line: "Alice boosted your post".
String noticeLine(SocialNotice notice, SocialNetwork network) {
  final name = {'name': notice.who.name};
  final bluesky = network == SocialNetwork.bluesky;
  return switch (notice.kind) {
    SocialNoticeKind.mention => tr(
      'widget.social.mentioned',
      '{name} mentioned you',
      name,
    ),
    SocialNoticeKind.reply => tr(
      'widget.social.replied',
      '{name} replied',
      name,
    ),
    SocialNoticeKind.quote => tr(
      'widget.social.quoted',
      '{name} quoted your post',
      name,
    ),
    SocialNoticeKind.boost when bluesky => tr(
      'widget.social.reposted',
      '{name} reposted your post',
      name,
    ),
    SocialNoticeKind.boost => tr(
      'widget.social.boosted',
      '{name} boosted your post',
      name,
    ),
    SocialNoticeKind.like when bluesky => tr(
      'widget.social.liked',
      '{name} liked your post',
      name,
    ),
    SocialNoticeKind.like => tr(
      'widget.social.favourited',
      '{name} favourited your post',
      name,
    ),
    SocialNoticeKind.follow => tr(
      'widget.social.followed',
      '{name} followed you',
      name,
    ),
    SocialNoticeKind.followRequest => tr(
      'widget.social.askedToFollow',
      '{name} asked to follow you',
      name,
    ),
    SocialNoticeKind.poll => tr(
      'widget.social.pollEnded',
      'A poll by {name} has ended',
      name,
    ),
    SocialNoticeKind.post => tr('widget.social.posted', '{name} posted', name),
    SocialNoticeKind.edit => tr(
      'widget.social.edited',
      '{name} edited a post',
      name,
    ),
    SocialNoticeKind.other => tr(
      'widget.social.somethingFrom',
      'Something new from {name}',
      name,
    ),
  };
}

/// Mastodon's HTML for a post as text, its paragraphs and line breaks kept.
///
/// Mastodon shortens a long link by wrapping the parts it hides in
/// `invisible` spans and marking where it cut with an `ellipsis` one; a
/// browser's stylesheet does the rest. Without one, the whole address would
/// show, so the hidden parts go and the cut gets its ellipsis.
String postText(String html) {
  var s = html
      .replaceAll(RegExp(r'<span class="invisible">[^<]*</span>'), '')
      .replaceAllMapped(
        RegExp(r'<span class="ellipsis">([^<]*)</span>'),
        (m) => '${m[1]}…',
      )
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>\s*<p[^>]*>', caseSensitive: false), '\n\n');
  s = s.replaceAll(RegExp(r'<[^>]*>'), '');
  // A line at a time, since plainText runs a line's spaces together.
  return [
    for (final line in s.split('\n')) plainText(line),
  ].join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// [text] with Mastodon's custom emoji — `:blobcat:` — taken out. They are
/// pictures the server draws in place of the code, and the code alone reads
/// as noise.
String withoutShortcodes(String text, Iterable<String> codes) {
  var out = text;
  for (final code in codes) {
    out = out.replaceAll(':$code:', '');
  }
  return out.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
}

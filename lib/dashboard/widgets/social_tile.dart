import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../screens/link_viewer_screen.dart';
import '../../services/social.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/shown_timers.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'tile_bits.dart';
import 'video_grid.dart' show releasedAgo;

/// A Mastodon or Bluesky feed on a tile — posts, or notifications — newest
/// first, fetched again on a timer and when pulled down. Touch a post to
/// read all of it, see its pictures, and open its page.
///
/// The Mastodon tile and the Bluesky tile are both this, told what to fetch.
class SocialTile extends StatefulWidget {
  const SocialTile({
    super.key,
    required this.w,
    required this.network,
    required this.title,
    required this.asked,
    required this.load,
    this.missing,
  });

  final DashboardWidgetContext w;
  final SocialNetwork network;

  /// The feed's name, for the heading: "Home", "#caturday".
  final String title;

  /// Everything [load] depends on, as one string. When it changes, what is
  /// shown is thrown away and fetched again.
  final String asked;
  final Future<SocialFeed> Function() load;

  /// What is missing from the settings before anything can be fetched, or
  /// null when nothing is.
  final String? missing;

  @override
  State<SocialTile> createState() => _SocialTileState();
}

class _SocialTileState extends State<SocialTile>
    with PauseWhenHidden, ShownTimers {
  SocialFeed? _feed;
  SocialException? _failure;
  DateTime? _at;
  bool _busy = false;
  Timer? _timer;

  /// Bumped whenever what is asked for changes, so an answer to an older
  /// question is thrown away when it lands rather than shown.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _schedule();
  }

  @override
  void didUpdateWidget(covariant SocialTile old) {
    super.didUpdateWidget(old);
    if (widget.asked != old.asked) {
      _generation++;
      _feed = null;
      _failure = null;
      _at = null;
      unawaited(_load(force: true));
    }
    if (widget.w.config.options['refreshMinutes'] !=
        old.w.config.options['refreshMinutes']) {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    final minutes =
        (int.tryParse('${widget.w.config.options['refreshMinutes'] ?? 5}') ?? 5)
            .clamp(1, 240);
    _timer = everyWhileShown(Duration(minutes: minutes), () {
      unawaited(_load());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// With [force], runs even while another fetch is out.
  Future<void> _load({bool force = false}) async {
    if (widget.missing != null || (_busy && !force)) return;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final feed = await widget.load();
      if (!mounted || generation != _generation) return;
      setState(() {
        _feed = feed;
        _failure = null;
        _at = DateTime.now();
      });
    } on SocialException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _failure = e);
    } catch (e) {
      debugPrint('${widget.network.title}: $e');
      if (!mounted || generation != _generation) return;
      setState(
        () => _failure = const SocialException(SocialFailure.unexpected),
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  String _failureText(SocialException e) {
    final network = {'network': widget.network.title};
    return switch (e.failure) {
      SocialFailure.badCredentials => tr(
        'widget.social.badCredentials',
        '{network} did not accept the sign-in. Check it in the widget '
            'settings.',
        network,
      ),
      SocialFailure.forbidden => tr(
        'widget.social.forbidden',
        '{network} won’t show this feed to this account.',
        network,
      ),
      SocialFailure.notFound => tr(
        'widget.social.notFound',
        '{network} has no such feed. Check the hashtag, list or link in the '
            'widget settings.',
        network,
      ),
      SocialFailure.rateLimited => tr(
        'widget.social.rateLimited',
        '{network} has asked the panel to slow down. It will try again '
            'shortly.',
        network,
      ),
      SocialFailure.unreachable => tr(
        'widget.social.unreachable',
        'Could not reach {network}',
        network,
      ),
      SocialFailure.unexpected => tr(
        'widget.social.unexpected',
        '{network} gave an answer the tile didn’t understand',
        network,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final missing = widget.missing;
    if (missing != null) return TileMessage(missing, theme: t);
    final feed = _feed;
    if (feed == null) {
      return TileMessage(
        _failure != null
            ? _failureText(_failure!)
            : tr('widget.social.asking', 'Asking {network}…', {
                'network': widget.network.title,
              }),
        theme: t,
      );
    }
    return Refreshed(
      theme: t,
      at: _at,
      child: LayoutBuilder(
        builder: (context, c) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left off a short tile, which has no room to spare for it.
            if (c.maxHeight >= 160) ...[
              TileLabel(
                icon: Icons.alternate_email,
                text: '${widget.title} · ${feed.who}',
                theme: t,
                trailing: _failure == null
                    ? null
                    : StatusChip(
                        text: tr('widget.social.outOfDate', 'Out of date'),
                        colour: StatusColours.of(t).warn,
                      ),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(child: _list(feed)),
          ],
        ),
      ),
    );
  }

  /// [posts] less the boosts and replies the settings leave out.
  List<SocialPost> _shown(List<SocialPost> posts) {
    final boosts = widget.w.option('showBoosts', true);
    final replies = widget.w.option('showReplies', true);
    return [
      for (final p in posts)
        if ((boosts || p.boostedBy == null) && (replies || !p.isReply)) p,
    ];
  }

  Widget _list(SocialFeed feed) {
    final t = widget.w.theme;
    final notices = feed.notices;
    final posts = notices == null ? _shown(feed.posts) : const <SocialPost>[];
    final count = notices?.length ?? posts.length;
    if (count == 0) {
      return TileMessage(
        notices == null
            ? tr('widget.social.noPosts', 'Nothing here yet.')
            : tr('widget.social.noNotifications', 'No notifications.'),
        theme: t,
      );
    }
    final now = DateTime.now();
    // Always scrollable, so the pull works even when everything fits.
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, _) => Divider(
          height: 18,
          thickness: 1,
          color: t.textSecondary.withValues(alpha: 0.15),
        ),
        itemBuilder: (context, i) => notices != null
            ? _NoticeRow(
                notice: notices[i],
                w: widget.w,
                network: widget.network,
                now: now,
              )
            : _PostRow(
                post: posts[i],
                w: widget.w,
                network: widget.network,
                now: now,
              ),
      ),
    );
  }
}

/// How many lines of a post the settings allow, or null for all of it.
int? _lines(DashboardWidgetContext w) {
  final n = int.tryParse('${w.config.options['lines'] ?? 6}') ?? 6;
  return n <= 0 ? null : n;
}

/// Its pictures, unless the settings leave them out or hide them, or a
/// content warning holds them back. A warning is a choice to read on, made
/// by [opened] the post; sensitive pictures stay hidden if the settings say.
List<SocialImage> _pictures(
  DashboardWidgetContext w,
  SocialPost post, {
  bool opened = false,
}) =>
    (post.warning != null && !opened) ||
        !w.option('showImages', true) ||
        (post.sensitive && w.option('hideSensitive', true))
    ? const []
    : post.images;

IconData _likeIcon(SocialNetwork network) => network == SocialNetwork.bluesky
    ? Icons.favorite_border_rounded
    : Icons.star_border_rounded;

/// A post: who wrote it and when, what they said, its pictures and how it
/// has been received.
class _PostRow extends StatelessWidget {
  const _PostRow({
    required this.post,
    required this.w,
    required this.network,
    required this.now,
  });

  final SocialPost post;
  final DashboardWidgetContext w;
  final SocialNetwork network;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final muted = TextStyle(color: t.textSecondary, fontSize: 12, height: 1.2);
    final pictures = _pictures(w, post);
    final boostedBy = post.boostedBy;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showSocialPost(context, post, w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SocialAvatar(person: post.author, theme: t, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (boostedBy != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Icon(Icons.repeat, size: 13, color: t.textSecondary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            network == SocialNetwork.bluesky
                                ? tr(
                                    'widget.social.repostedBy',
                                    'Reposted by {name}',
                                    {'name': boostedBy.name},
                                  )
                                : tr(
                                    'widget.social.boostedBy',
                                    'Boosted by {name}',
                                    {'name': boostedBy.name},
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        post.author.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 14,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '@${post.author.handle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                    if (post.at != null) ...[
                      const SizedBox(width: 6),
                      Text(releasedAgo(post.at!, now), style: muted),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                if (post.warning != null)
                  Text(
                    tr('widget.social.warning', 'Content warning: {what}', {
                      'what': post.warning,
                    }),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.accent,
                      fontSize: 14,
                      height: 1.3,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else if (post.text.isNotEmpty)
                  Text(
                    post.text,
                    maxLines: _lines(w),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 15,
                      height: 1.3,
                    ),
                  ),
                if (pictures.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _PictureStrip(images: pictures, theme: t),
                  )
                else if (post.sensitive &&
                    post.images.isNotEmpty &&
                    post.warning == null &&
                    w.option('showImages', true))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      tr(
                        'widget.social.sensitiveHidden',
                        'Sensitive pictures hidden',
                      ),
                      style: muted,
                    ),
                  ),
                if (post.linkTitle != null &&
                    pictures.isEmpty &&
                    post.warning == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.link, size: 14, color: t.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            post.linkTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (w.option('showCounts', true))
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Row(
                      children: [
                        _count(Icons.chat_bubble_outline_rounded, post.replies),
                        _count(Icons.repeat, post.boosts),
                        _count(_likeIcon(network), post.likes),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _count(IconData icon, int n) {
    final t = w.theme;
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: t.textSecondary),
          const SizedBox(width: 4),
          Text(
            '$n',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// A notification: who, what they did, and what was said.
class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    required this.notice,
    required this.w,
    required this.network,
    required this.now,
  });

  final SocialNotice notice;
  final DashboardWidgetContext w;
  final SocialNetwork network;
  final DateTime now;

  IconData get _icon => switch (notice.kind) {
    SocialNoticeKind.mention => Icons.alternate_email,
    SocialNoticeKind.reply => Icons.reply_rounded,
    SocialNoticeKind.quote => Icons.format_quote_rounded,
    SocialNoticeKind.boost => Icons.repeat,
    SocialNoticeKind.like => _likeIcon(network),
    SocialNoticeKind.follow ||
    SocialNoticeKind.followRequest => Icons.person_add_alt_1_rounded,
    SocialNoticeKind.poll => Icons.poll_outlined,
    SocialNoticeKind.post => Icons.notes_rounded,
    SocialNoticeKind.edit => Icons.edit_outlined,
    SocialNoticeKind.other => Icons.notifications_none_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final post = notice.post;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: post == null ? null : () => showSocialPost(context, post, w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SocialAvatar(person: notice.who, theme: t, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(_icon, size: 15, color: t.accent),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        noticeLine(notice, network),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 14,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (notice.at != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        releasedAgo(notice.at!, now),
                        style: TextStyle(color: t.textSecondary, fontSize: 12),
                      ),
                    ],
                  ],
                ),
                if (post != null && post.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      post.text,
                      // What someone said to you in full, as far as the
                      // settings allow; your own post, liked, as a reminder.
                      maxLines: notice.direct ? _lines(w) : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: notice.direct ? t.textPrimary : t.textSecondary,
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Up to three of a post's pictures, side by side.
class _PictureStrip extends StatelessWidget {
  const _PictureStrip({required this.images, required this.theme});

  final List<SocialImage> images;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final shown = images.take(3).toList();
    return SizedBox(
      height: 120,
      child: Row(
        children: [
          for (var i = 0; i < shown.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(tileCorner(theme, 8)),
                  child: CachedNetworkImage(
                    imageUrl: shown[i].preview,
                    fit: BoxFit.cover,
                    // Decoded at the strip's height, not the picture's: a
                    // feed of them at full size is a lot of a Pi's memory.
                    memCacheHeight: 240,
                    placeholder: (_, _) => ColoredBox(
                      color: theme.textSecondary.withValues(alpha: 0.12),
                    ),
                    errorWidget: (_, _, _) => ColoredBox(
                      color: theme.textSecondary.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Someone's picture, or the first letter of their name where they have
/// none — round, or square on a console.
class SocialAvatar extends StatelessWidget {
  const SocialAvatar({
    super.key,
    required this.person,
    required this.theme,
    this.size = 36,
  });

  final SocialPerson person;
  final DashboardTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: theme.accent.withValues(alpha: 0.25),
      child: Text(
        person.name.isEmpty ? '?' : person.name.characters.first.toUpperCase(),
        style: TextStyle(
          color: theme.textPrimary,
          fontSize: size * 0.45,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final avatar = person.avatar;
    return ClipRRect(
      borderRadius: BorderRadius.circular(tileCorner(theme, size / 2)),
      child: avatar == null
          ? letter
          : CachedNetworkImage(
              imageUrl: avatar,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Bluesky's are a thousand pixels across, for a 36-pixel face.
              memCacheWidth: (size * 2).round(),
              placeholder: (_, _) => letter,
              errorWidget: (_, _, _) => letter,
            ),
    );
  }
}

/// [post] in full, over the dashboard: all of what was said, its pictures,
/// and a way to its page.
void showSocialPost(
  BuildContext context,
  SocialPost post,
  DashboardWidgetContext w,
) {
  final t = w.theme;
  final pictures = _pictures(w, post, opened: true);
  final url = post.url;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          SocialAvatar(person: post.author, theme: t, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.author.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22),
                ),
                Text(
                  '@${post.author.handle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, color: t.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (post.warning != null) ...[
                Text(
                  tr('widget.social.warning', 'Content warning: {what}', {
                    'what': post.warning,
                  }),
                  style: const TextStyle(
                    fontSize: 18,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Text(
                post.text,
                style: const TextStyle(fontSize: 20, height: 1.4),
              ),
              for (final image in pictures)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 480),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(tileCorner(t, 10)),
                      child: Semantics(
                        label: image.alt,
                        child: CachedNetworkImage(
                          imageUrl: image.full,
                          fit: BoxFit.contain,
                          memCacheWidth: 1520,
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actions: [
        if (url != null)
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      LinkViewerScreen(url: url, title: post.author.name),
                ),
              );
            },
            icon: const Icon(Icons.open_in_browser, size: 26),
            label: Text(
              tr('widget.social.openPage', 'Open the page'),
              style: const TextStyle(fontSize: 20),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
          ),
          child: Text(
            tr('widget.social.close', 'Close'),
            style: const TextStyle(fontSize: 20),
          ),
        ),
      ],
    ),
  );
}

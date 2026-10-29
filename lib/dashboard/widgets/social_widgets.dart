import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/bluesky_api.dart';
import '../../services/mastodon_api.dart';
import '../../services/social.dart';
import '../../services/social_notifier.dart';
import '../widget_registry.dart';
import 'social_tile.dart';

/// The name of a feed for a tile's heading, from its setting.
String _feedTitle(String feed, {String hashtag = '', String list = ''}) =>
    switch (feed) {
      'home' => tr('widget.social.feed.home', 'Home'),
      'following' => tr('widget.social.feed.following', 'Following'),
      'discover' => tr('widget.social.feed.discover', 'Discover'),
      'notifications' => tr(
        'widget.social.feed.notifications',
        'Notifications',
      ),
      'mentions' => tr('widget.social.feed.mentions', 'Mentions'),
      'local' => tr('widget.social.feed.local', 'Local'),
      'federated' => tr('widget.social.feed.federated', 'Federated'),
      'trending' => tr('widget.social.feed.trending', 'Trending'),
      'hashtag' => '#${hashtag.trim().replaceFirst(RegExp('^#'), '')}',
      'list' when list.trim().isNotEmpty && !list.contains('/') => list.trim(),
      'list' => tr('widget.social.feed.list', 'List'),
      'custom' => tr('widget.social.feed.custom', 'Feed'),
      'mine' => tr('widget.social.feed.mine', 'Your posts'),
      'bookmarks' => tr('widget.social.feed.bookmarks', 'Bookmarks'),
      'favourites' => tr('widget.social.feed.favourites', 'Favourites'),
      'likes' => tr('widget.social.feed.likes', 'Likes'),
      _ => '',
    };

int _count(DashboardWidgetContext w) =>
    (int.tryParse('${w.config.options['count'] ?? 20}') ?? 20).clamp(1, 100);

/// Mastodon on a tile: a feed of the account's, or its notifications.
class MastodonTile extends StatelessWidget {
  const MastodonTile({super.key, required this.w});
  final DashboardWidgetContext w;

  static final _api = MastodonApi();

  @override
  Widget build(BuildContext context) {
    final account = mastodonAccountOf(w.config.options);
    final feed =
        MastodonFeed.values.asNameMap()[w.option('feed', 'home')] ??
        MastodonFeed.home;
    final hashtag = w.option('hashtag', '');
    final list = w.option('list', '');
    final count = _count(w);
    final typed = w.option('server', '').trim();
    return SocialTile(
      w: w,
      network: SocialNetwork.mastodon,
      title: _feedTitle(feed.name, hashtag: hashtag, list: list),
      asked: [account?.key, feed.name, hashtag, list, count].join('|'),
      missing: account != null
          ? null
          : typed.isNotEmpty && serverAddress(typed) == null
          ? tr(
              'widget.mastodon.notAServer',
              '“{typed}” isn’t a server. Use its name, like mastodon.social.',
              {'typed': typed},
            )
          : tr(
              'widget.mastodon.signIn',
              'Add your server and an access token in the widget settings.',
            ),
      load: () =>
          _api.feed(account!, feed, hashtag: hashtag, list: list, limit: count),
    );
  }
}

/// Bluesky on a tile: a feed of the account's, or its notifications.
class BlueskyTile extends StatelessWidget {
  const BlueskyTile({super.key, required this.w});
  final DashboardWidgetContext w;

  static final _api = BlueskyApi();

  @override
  Widget build(BuildContext context) {
    final account = blueskyAccountOf(w.config.options);
    final feed =
        BlueskyFeed.values.asNameMap()[w.option('feed', 'following')] ??
        BlueskyFeed.following;
    final custom = w.option('customFeed', '');
    final list = w.option('list', '');
    final count = _count(w);
    return SocialTile(
      w: w,
      network: SocialNetwork.bluesky,
      title: _feedTitle(feed.name, list: list),
      asked: [account?.key, feed.name, custom, list, count].join('|'),
      missing: account == null
          ? tr(
              'widget.bluesky.signIn',
              'Add your handle and an app password in the widget settings.',
            )
          : null,
      load: () =>
          _api.feed(account!, feed, custom: custom, list: list, limit: count),
    );
  }
}

/// Whether, and for what, the panel pops up a card: the same for both.
const _notifyOption = WidgetOption(
  key: 'notify',
  label: 'Notify on the panel',
  kind: OptionKind.choice,
  defaultValue: 'off',
  choices: {
    'off': 'No',
    'mentions': 'Mentions, replies and quotes',
    'all': 'Every notification',
  },
  help:
      'A card pops up in the corner of whatever the panel is showing, with '
      'the chime a share from the phone gets, whatever feed this tile shows '
      'and whichever page it is on. Touch the card to read it. Silent, and '
      'the screen left off, while Do Not Disturb is on.',
);

/// How the posts are shown: the same for both, in each one's own words.
List<WidgetOption> _displayOptions({required bool bluesky}) => [
  WidgetOption(
    key: 'count',
    label: 'Posts',
    kind: OptionKind.number,
    defaultValue: 20,
    help: 'How many to fetch, newest first. The tile scrolls for the rest.',
  ),
  WidgetOption(
    key: 'lines',
    label: 'Lines of each post',
    kind: OptionKind.choice,
    defaultValue: '6',
    choices: {'3': '3', '6': '6', '10': '10', '0': 'All of it'},
    help: 'However many, touching a post shows all of it.',
  ),
  WidgetOption(
    key: 'showImages',
    label: 'Pictures',
    kind: OptionKind.boolean,
    defaultValue: true,
  ),
  WidgetOption(
    key: 'hideSensitive',
    label: 'Hide sensitive pictures',
    kind: OptionKind.boolean,
    defaultValue: true,
    help: bluesky
        ? 'Pictures Bluesky labels as adult or graphic are left out.'
        : 'Pictures their poster marked sensitive are left out.',
  ),
  WidgetOption(
    key: 'showBoosts',
    label: bluesky ? 'Reposts' : 'Boosts',
    kind: OptionKind.boolean,
    defaultValue: true,
  ),
  WidgetOption(
    key: 'showReplies',
    label: 'Replies',
    kind: OptionKind.boolean,
    defaultValue: true,
  ),
  WidgetOption(
    key: 'showCounts',
    label: bluesky
        ? 'Replies, reposts and likes under each post'
        : 'Replies, boosts and favourites under each post',
    kind: OptionKind.boolean,
    defaultValue: true,
  ),
  WidgetOption(
    key: 'refreshMinutes',
    label: 'Refresh interval',
    kind: OptionKind.choice,
    defaultValue: '5',
    choices: {
      '2': '2 minutes',
      '5': '5 minutes',
      '15': '15 minutes',
      '30': '30 minutes',
      '60': '1 hour',
    },
    help: 'How often the tile fetches again while it is on screen.',
  ),
];

final mastodonWidgetType = DashboardWidgetType(
  type: 'mastodon',
  category: WidgetCategory.reference,
  name: 'Mastodon',
  description:
      'Your home timeline, notifications, a hashtag, a list or your server’s '
      'local feed, signed in with an access token — and, if you like, a card '
      'on the panel when a notification comes in.',
  glyph: '🐘',
  defaultWidth: 4,
  defaultHeight: 4,
  minWidth: 2,
  minHeight: 2,
  options: [
    WidgetOption(
      key: 'server',
      label: 'Server',
      defaultValue: '',
      help:
          'Where your account is: mastodon.social, say, or your whole '
          'handle — @you@mastodon.social.',
    ),
    WidgetOption(
      key: 'token',
      label: 'Access token',
      kind: OptionKind.secret,
      defaultValue: '',
      help:
          'Made in Mastodon under Preferences → Development → New '
          'application: give it any name, leave only “read” ticked, save, '
          'and copy “Your access token”. Sent only to your server.',
    ),
    WidgetOption(
      key: 'feed',
      label: 'Feed',
      kind: OptionKind.choice,
      defaultValue: 'home',
      choices: {
        'home': 'Home — who you follow',
        'notifications': 'Notifications',
        'mentions': 'Mentions',
        'local': 'Local — everyone on your server',
        'federated': 'Federated — everyone your server knows',
        'trending': 'Trending posts',
        'hashtag': 'A hashtag',
        'list': 'One of your lists',
        'mine': 'Your own posts',
        'bookmarks': 'Your bookmarks',
        'favourites': 'Your favourites',
      },
    ),
    WidgetOption(
      key: 'hashtag',
      label: 'Hashtag',
      defaultValue: '',
      help: 'For the hashtag feed, with or without the #.',
    ),
    WidgetOption(
      key: 'list',
      label: 'List',
      defaultValue: '',
      help: 'For the list feed: the list’s name, as it is in Mastodon.',
    ),
    _notifyOption,
    ..._displayOptions(bluesky: false),
  ],
  preview: [
    PreviewLine('🐘 Mastodon', scale: 0.12, accent: true),
    PreviewLine('Alex · 5 min ago', px: 12, muted: true),
    PreviewLine('A post from your home timeline', px: 15),
  ],
  build: (context, w) => MastodonTile(w: w),
);

final blueskyWidgetType = DashboardWidgetType(
  type: 'bluesky',
  category: WidgetCategory.reference,
  name: 'Bluesky',
  description:
      'Who you follow, Discover, your notifications, a custom feed or one of '
      'your lists, signed in with an app password — and, if you like, a card '
      'on the panel when a notification comes in.',
  glyph: '🦋',
  defaultWidth: 4,
  defaultHeight: 4,
  minWidth: 2,
  minHeight: 2,
  options: [
    WidgetOption(
      key: 'handle',
      label: 'Handle',
      defaultValue: '',
      help: 'Yours, as on your profile: you.bsky.social.',
    ),
    WidgetOption(
      key: 'appPassword',
      label: 'App password',
      kind: OptionKind.secret,
      defaultValue: '',
      help:
          'Made in Bluesky under Settings → Privacy and security → App '
          'passwords. Not your own password: an app password can be taken '
          'back by itself, and cannot change your account. Sent only to '
          'Bluesky.',
    ),
    WidgetOption(
      key: 'feed',
      label: 'Feed',
      kind: OptionKind.choice,
      defaultValue: 'following',
      choices: {
        'following': 'Following',
        'discover': 'Discover',
        'notifications': 'Notifications',
        'mentions': 'Mentions, replies and quotes',
        'custom': 'A custom feed',
        'list': 'One of your lists',
        'mine': 'Your own posts',
        'likes': 'Posts you liked',
      },
    ),
    WidgetOption(
      key: 'customFeed',
      label: 'Custom feed',
      defaultValue: '',
      help:
          'For a custom feed: its link. Open the feed on bsky.app and copy '
          'the address.',
    ),
    WidgetOption(
      key: 'list',
      label: 'List',
      defaultValue: '',
      help: 'For the list feed: the list’s name, or its link on bsky.app.',
    ),
    _notifyOption,
    WidgetOption(
      key: 'service',
      label: 'Server (optional)',
      defaultValue: '',
      help:
          'Only for an account on a server of its own. Leave it empty for '
          'an account made on bsky.app.',
    ),
    ..._displayOptions(bluesky: true),
  ],
  preview: [
    PreviewLine('🦋 Bluesky', scale: 0.12, accent: true),
    PreviewLine('Alex · 5 min ago', px: 12, muted: true),
    PreviewLine('A post from who you follow', px: 15),
  ],
  build: (context, w) => BlueskyTile(w: w),
);

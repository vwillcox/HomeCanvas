import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/link_viewer_screen.dart';
import '../../services/article_reader.dart';
import '../../services/kiosk_browser.dart' show ReaderStyle;
import '../../services/feed_service.dart';
import '../../services/video_link.dart';
import '../../services/video_player_service.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import '../../l10n/l10n.dart';

/// Headlines from an RSS or Atom feed.
class DashboardNewsWidget extends StatelessWidget {
  const DashboardNewsWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    // Absent in the editor's off-screen previews, which read nothing out.
    final reader = context.watch<ArticleReader?>();
    final urls = feedUrls(w);
    if (urls.isEmpty) {
      return Center(
        child: Text(
          tr(
            'widget.news.addAFeedAddressIn',
            'Add a feed address in this widget’s settings.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: t.textSecondary, fontSize: 15),
        ),
      );
    }

    final feeds = context.watch<FeedService>();
    final maxAge = Duration(minutes: refreshMinutes(w));
    // Filtered before mixing and counting, so a tile of seven stays a tile of
    // seven headlines rather than three headlines and four gaps.
    final hidePromos = w.option('hidePromotions', true);
    final lists = [
      for (final u in urls)
        [
          for (final item in feeds.feed(u, maxAge: maxAge))
            if (!hidePromos || !isPromotional(item)) item,
        ],
    ];
    final names = {
      for (final r in w.rows('sources'))
        '${r['url'] ?? ''}'.trim(): '${r['name'] ?? ''}'.trim(),
    };

    // One feed to a tab, each keeping the publisher's own order. The tab
    // says where a headline is from, so the headlines needn't.
    if (w.option('layout', 'blended') == 'tabs' && urls.length > 1) {
      String site(int i) => lists[i].firstOrNull?.link ?? urls[i];
      return _FeedTabs(
        count: urls.length,
        page: (i) => _headlines(
          context,
          feeds,
          reader,
          key: ValueKey(urls[i]),
          items: lists[i],
          error: feeds.errorFor(urls[i]),
          refresh: [urls[i]],
        ),
        tab: (i, selected) => _tab(
          icon: feeds.siteIcon(site(i)),
          name: names[urls[i]] ?? '',
          link: site(i),
          selected: selected,
        ),
      );
    }

    // Which feed each headline came from, for its icon. Items are the cached
    // instances themselves, so identity is enough to find them again.
    final sourceOf = Map<FeedItem, String>.identity();
    for (var i = 0; i < urls.length; i++) {
      for (final item in lists[i]) {
        sourceOf.putIfAbsent(item, () => urls[i]);
      }
    }

    // Everything the feeds carry: the tile shows what fits and scrolls for
    // the rest. One feed needs no blending, and going through the mixer would
    // only reorder it away from the order the publisher chose.
    return _headlines(
      context,
      feeds,
      reader,
      items: lists.length == 1
          ? lists.first
          : FeedService.mix(lists,
              max: lists.fold(0, (n, l) => n + l.length)),
      error: urls.map(feeds.errorFor).whereType<String>().firstOrNull,
      refresh: urls,
      sourceOf: w.option('showSource', true) ? sourceOf : null,
      names: names,
    );
  }

  /// A tab along the bottom: the feed's icon and name.
  Widget _tab({
    required String? icon,
    required String name,
    required String link,
    required bool selected,
  }) {
    final t = w.theme;
    final host = (Uri.tryParse(link)?.host ?? '').replaceFirst('www.', '');
    final label = w.option('tabLabel', 'both');
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: selected
                ? t.accent
                : t.textSecondary.withValues(alpha: 0.15),
            width: selected ? 3 : 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (label != 'name')
            _SourceIcon(
              icon: icon,
              name: name,
              link: link,
              theme: t,
              // Alone, it is the whole label, so it can be read as one.
              side: label == 'icon' ? 24 : 16,
            ),
          if (label == 'both') const SizedBox(width: 6),
          if (label != 'icon')
            Flexible(
              child: Text(
                name.isNotEmpty ? name : host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? t.textPrimary : t.textSecondary,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// [items] as a scrolling list that, pulled down from the top, fetches
  /// [refresh] again. With [sourceOf], each headline carries its feed's icon.
  Widget _headlines(
    BuildContext context,
    FeedService feeds,
    ArticleReader? reader, {
    Key? key,
    required List<FeedItem> items,
    required String? error,
    required List<String> refresh,
    Map<FeedItem, String>? sourceOf,
    Map<String, String> names = const {},
  }) {
    final t = w.theme;
    if (items.isEmpty) {
      return Center(
        key: key,
        child: Text(
          error ?? tr('widget.news.fetchingHeadlines', 'Fetching headlines…'),
          style: TextStyle(color: t.textSecondary, fontSize: 15),
        ),
      );
    }

    final showSummary = w.option('showSummary', false);
    final showTime = w.option('showTime', true);
    final shown = items;

    // Always scrollable, so the pull works even when every headline fits.
    return RefreshIndicator(
      key: key,
      onRefresh: () => feeds.refresh(refresh),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: shown.length,
        separatorBuilder: (_, _) => Divider(
          height: 14,
          thickness: 1,
          color: t.textSecondary.withValues(alpha: 0.15),
        ),
        itemBuilder: (context, i) {
          final item = shown[i];
          final tappable = w.option('openOnTap', true) &&
              (item.link != null || item.summary != null);
          // The headline being read aloud, marked so you can see which.
          final beingRead = reader != null &&
              reader.active &&
              item.link != null &&
              reader.link == item.link;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: tappable ? () => _open(context, item) : null,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sourceOf != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 1.5),
                      child: _SourceIcon(
                        icon: feeds.siteIcon(item.link ?? sourceOf[item]),
                        name: names[sourceOf[item]] ?? '',
                        link: item.link ?? sourceOf[item] ?? '',
                        theme: t,
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                  if (beingRead) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.volume_up_rounded,
                        size: 17,
                        color: t.accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: showSummary ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: beingRead ? t.accent : t.textPrimary,
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              if (showSummary && item.summary != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    item.summary!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: t.textSecondary, fontSize: 13, height: 1.25),
                  ),
                ),
              if (showTime && item.published != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    ago(item.published!),
                    style: TextStyle(
                      color: t.textSecondary.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          );
        },
      ),
    );
  }

  /// Show whatever the feed gave us, and offer the page itself.
  ///
  /// Most feeds carry a paragraph of summary, which on a wall panel is often
  /// all anyone wants — so that comes first and costs nothing, with the full
  /// article a deliberate second tap rather than the only option.
  void _open(BuildContext context, FeedItem item) {
    final reader = context.read<ArticleReader?>();
    final summary = item.summary ?? '';
    // Straight to the page only when there is nothing else to offer — no
    // summary to show, and no voice to read it out.
    if (summary.isEmpty && (reader == null || !w.option('readAloud', true))) {
      if (item.link != null) _openPage(context, item);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.title, style: const TextStyle(fontSize: 24)),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Text(
              summary.isEmpty ? tr('widget.news.theFeedGivesNoSummary', 'The feed gives no summary of this one.') : summary,
              style: const TextStyle(fontSize: 18, height: 1.4),
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        actions: [
          // The whole article read out, a paragraph at a time, while you
          // get on with something else. Controls stay along the bottom of
          // the screen.
          if (reader != null && w.option('readAloud', true))
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                reader.read(
                  title: item.title,
                  link: item.link,
                  summary: item.summary,
                  speeds: voiceSpeeds(w),
                  sayAuthor: w.option('readAuthor', true),
                );
              },
              icon: const Icon(Icons.record_voice_over_rounded, size: 26),
              label: Text(tr('widget.news.readAloud', 'Read aloud'), style: TextStyle(fontSize: 20)),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
              ),
            ),
          if (item.link != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openPage(context, item);
              },
              icon: const Icon(Icons.open_in_browser, size: 26),
              label: Text(tr('widget.news.readThePage', 'Read the page'),
                  style: TextStyle(fontSize: 20)),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
            ),
            child: Text(tr('widget.news.close', 'Close'), style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
  }

  void _openPage(BuildContext context, FeedItem item) {
    // A news item that is a YouTube, Floatplane or Nebula video plays on
    // the panel.
    final video = VideoLink.parse(item.link!);
    if (video != null) {
      unawaited(context.read<VideoPlayerService>().play(video));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LinkViewerScreen(
        url: item.link!,
        title: item.title,
        reader: readerStyle(w),
      ),
    ));
  }

  /// Each voice's pace from the settings, by voice id. Until the list has
  /// been saved, its declared default — the male voice a little faster —
  /// which the editor shows as the list's first row.
  static Map<String, double> voiceSpeeds(DashboardWidgetContext w) {
    final rows = w.config.options.containsKey('voiceSpeeds')
        ? w.rows('voiceSpeeds')
        : const [
            {'voice': 'en_GB-alan-medium', 'speed': '1.15'},
          ];
    return {
      for (final r in rows)
        if ('${r['voice'] ?? ''}'.isNotEmpty)
          '${r['voice']}': double.tryParse('${r['speed']}') ?? 1,
    };
  }

  /// How articles should open, from this widget's settings — or null for the
  /// page as the site serves it.
  static ReaderStyle? readerStyle(DashboardWidgetContext w) {
    if (!w.option('readerView', true)) return null;
    const steps = {'medium': 10, 'large': 11, 'huge': 12};
    return ReaderStyle(
      fontStep: steps[w.option<String>('readerTextSize', 'large')] ?? 11,
      colourScheme: w.option('readerTheme', 'dark'),
    );
  }

  /// Also used to build the editor's live preview.
  /// Every configured feed, falling back to the single `url` this widget
  /// originally took so a dashboard built before it accepted several keeps
  /// working untouched.
  static List<String> feedUrls(DashboardWidgetContext w) {
    final rows = w.rows('sources');
    final urls = [
      for (final r in rows)
        if ('${r['url'] ?? ''}'.trim().isNotEmpty) '${r['url']}'.trim(),
    ];
    if (urls.isNotEmpty) return urls;
    final legacy = w.option('url', '').trim();
    return legacy.isEmpty ? const [] : [legacy];
  }

  static int refreshMinutes(DashboardWidgetContext w) =>
      (int.tryParse('${w.config.options['refreshMinutes'] ?? 15}') ?? 15)
          .clamp(1, 1440);

  static String ago(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return tr('widget.news.justNow', 'just now');
    if (d.inMinutes < 60) return tr('widget.news.mAgo', '{inMinutes}m ago', {'inMinutes': d.inMinutes});
    if (d.inHours < 24) return tr('widget.news.hAgo', '{inHours}h ago', {'inHours': d.inHours});
    return tr('widget.news.dAgo', '{inDays}d ago', {'inDays': d.inDays});
  }
}

/// One page at a time, with a row of tabs along the bottom to choose it.
class _FeedTabs extends StatefulWidget {
  const _FeedTabs({required this.count, required this.page, required this.tab});

  final int count;
  final Widget Function(int i) page;
  final Widget Function(int i, bool selected) tab;

  @override
  State<_FeedTabs> createState() => _FeedTabsState();
}

class _FeedTabsState extends State<_FeedTabs> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    // A feed removed in the settings can take the chosen tab with it.
    final selected = _selected < widget.count ? _selected : 0;
    return Column(
      children: [
        Expanded(child: widget.page(selected)),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < widget.count; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selected = i),
                  child: widget.tab(i, i == selected),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A headline's source: the site's icon, or a letter where there is none.
class _SourceIcon extends StatelessWidget {
  const _SourceIcon({
    required this.icon,
    required this.name,
    required this.link,
    required this.theme,
    this.side = 16,
  });

  final String? icon;
  final String name;
  final String link;
  final DashboardTheme theme;
  final double side;

  @override
  Widget build(BuildContext context) {
    final letter = SizedBox(
      width: side,
      height: side,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.accent.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            _initial(),
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: side * 0.625,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
    if (icon == null) return letter;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: icon!,
        width: side,
        height: side,
        fit: BoxFit.cover,
        placeholder: (_, _) => letter,
        errorWidget: (_, _, _) => letter,
      ),
    );
  }

  /// The feed's name if it was given one, or else the site's.
  String _initial() {
    final host = (Uri.tryParse(link)?.host ?? '').replaceFirst('www.', '');
    final from = name.isNotEmpty ? name : host;
    return from.isEmpty ? '•' : from[0].toUpperCase();
  }
}

final newsWidgetType = DashboardWidgetType(
  type: 'news',
  category: WidgetCategory.reference,
  name: 'News feed',
  description: 'Headlines from any RSS or Atom feed.',
  glyph: '📰',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 1,
  minHeight: 1,
  options: const [
    WidgetOption(
      key: 'sources',
      label: 'Feeds',
      kind: OptionKind.list,
      addLabel: 'Add a feed',
      help: 'RSS or Atom. With more than one, headlines are blended: each is '
          'ranked on how recent it is and on how much that feed has already '
          'contributed, so a busy wire service can’t bury a quieter source.',
      fields: [
        WidgetOption(key: 'name', label: 'Name', defaultValue: ''),
        WidgetOption(
          key: 'url',
          label: 'Address',
          defaultValue: '',
          help: 'For example https://feeds.bbci.co.uk/news/rss.xml',
        ),
      ],
    ),
    WidgetOption(
      key: 'layout',
      label: 'Layout',
      kind: OptionKind.choice,
      defaultValue: 'blended',
      choices: {
        'blended': 'One list, all the feeds blended together',
        'tabs': 'A tab for each feed, along the bottom',
      },
      help: 'Tabs need more than one feed; with just one, it is a plain list.',
    ),
    WidgetOption(
      key: 'tabLabel',
      label: 'Tabs show',
      kind: OptionKind.choice,
      defaultValue: 'both',
      choices: {
        'both': 'The site’s icon and the feed’s name',
        'icon': 'Just the icon',
        'name': 'Just the name',
      },
      help: 'Icons alone fit more tabs across a narrow tile. A feed with no '
          'name shows its site’s address.',
    ),
    WidgetOption(
      key: 'refreshMinutes',
      label: 'Check for new items every (minutes)',
      kind: OptionKind.choice,
      defaultValue: '15',
      choices: {
        '2': 'Every 2 minutes',
        '5': 'Every 5 minutes',
        '15': 'Every 15 minutes',
        '30': 'Every 30 minutes',
        '60': 'Hourly',
        '180': 'Every 3 hours',
        '720': 'Twice a day',
      },
      help: 'Little point checking a weekly blog every two minutes, or a wire '
          'service twice a day.',
    ),
    WidgetOption(
      key: 'showSummary',
      label: 'Show a line of summary',
      kind: OptionKind.boolean,
      defaultValue: false,
    ),
    WidgetOption(
      key: 'showSource',
      label: 'Show which feed each headline is from',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'A small icon — the site’s own, or the first letter of the '
          'feed’s name where it has none. Not needed with tabs, which say '
          'it already.',
    ),
    WidgetOption(
      key: 'showTime',
      label: 'Show how long ago',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'openOnTap',
      label: 'Open a headline when tapped',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'Shows the feed’s own summary, with the full page a tap further. '
          'Turn off for a panel nobody should be browsing from.',
    ),
    WidgetOption(
      key: 'hidePromotions',
      label: 'Hide promo codes, coupons and sponsored posts',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'Some feeds are more shopping than news — WIRED’s is mostly coupon '
          'posts. Judged from the headline, the address and the publisher’s '
          'own category. Reviews and buying guides are kept.',
    ),
    WidgetOption(
      key: 'readerView',
      label: 'Open articles in reader view',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'Just the text and pictures — no adverts, cookie banners or '
          'autoplaying video — sized to fill the screen. Video and live pages '
          'open normally, since there is no article in them to show.',
    ),
    WidgetOption(
      key: 'readerTextSize',
      label: 'Reader text size',
      kind: OptionKind.choice,
      defaultValue: 'large',
      choices: {
        'medium': 'Medium — 32px',
        'large': 'Large — 40px',
        'huge': 'Very large — 56px, readable across a room',
      },
      help: 'The column widens or narrows to fill the screen at whichever '
          'size you pick.',
    ),
    WidgetOption(
      key: 'readerTheme',
      label: 'Reader colours',
      kind: OptionKind.choice,
      defaultValue: 'dark',
      choices: {
        'dark': 'Dark',
        'light': 'Light',
        'sepia': 'Sepia',
        'contrast': 'High contrast',
      },
    ),
    WidgetOption(
      key: 'readAloud',
      label: 'Offer “Read aloud”',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'A button on each headline that reads the whole article out, a '
          'paragraph at a time, with pause and stop along the bottom of the '
          'screen. Needs piper on the Pi — see INSTALL.md.',
    ),
    WidgetOption(
      key: 'readAuthor',
      label: 'Say who wrote it',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: '“By …” after the headline, when the page names its author.',
    ),
    WidgetOption(
      key: 'voiceSpeeds',
      label: 'Voice speeds',
      kind: OptionKind.list,
      addLabel: 'Set a voice’s speed',
      help: 'Each writer is read in one of the voices installed on the Pi, '
          'always the same one. Any voice not listed here reads at its own '
          'pace.',
      defaultValue: [
        {'voice': 'en_GB-alan-medium', 'speed': '1.15'},
      ],
      fields: [
        WidgetOption(
          key: 'voice',
          label: 'Voice',
          kind: OptionKind.choice,
          choicesFrom: 'voices',
          defaultValue: 'main',
        ),
        WidgetOption(
          key: 'speed',
          label: 'Speed',
          kind: OptionKind.choice,
          defaultValue: '1.0',
          choices: {
            '0.85': 'Slower',
            '1.0': 'Normal',
            '1.15': 'A little faster',
            '1.3': 'Faster',
            '1.5': 'Much faster',
          },
        ),
      ],
    ),
  ],
  preview: const [
    PreviewLine('Council approves new cycle route', scale: 0.13, px: 15),
    PreviewLine('2h ago', scale: 0.09, muted: true, px: 12),
    PreviewLine('Storm expected to clear by Thursday',
        scale: 0.13, px: 15),
    PreviewLine('4h ago', scale: 0.09, muted: true, px: 12),
  ],
  live: (config, data) {
    if (data.feeds == null) return const [];
    final urls = <String>[
      for (final r in (config.options['sources'] as List?) ?? const [])
        if (r is Map && '${r['url'] ?? ''}'.trim().isNotEmpty)
          '${r['url']}'.trim(),
    ];
    if (urls.isEmpty && '${config.options['url'] ?? ''}'.trim().isNotEmpty) {
      urls.add('${config.options['url']}'.trim());
    }
    if (urls.isEmpty) return const [];

    // Enough to fill the tile; the panel scrolls for the rest.
    const shown = 10;
    final hidePromos = config.options['hidePromotions'] != false;
    final lists = [
      for (final u in urls)
        [
          for (final item in data.feeds!.feed(u))
            if (!hidePromos || !isPromotional(item)) item,
        ],
    ];
    // Blended exactly as the panel blends them, so the preview is not a
    // different selection of headlines from the one on the wall.
    final items = lists.length == 1
        ? lists.first.take(shown).toList()
        : FeedService.mix(lists, max: shown);
    if (items.isEmpty) return const [];
    return [
      for (final item in items) ...[
        PreviewLine(item.title, scale: 0.13, px: 15),
        if (config.options['showTime'] != false && item.published != null)
          PreviewLine(DashboardNewsWidget.ago(item.published!),
              scale: 0.09, muted: true, px: 12),
      ],
    ];
  },
  build: (context, w) => DashboardNewsWidget(w: w),
);

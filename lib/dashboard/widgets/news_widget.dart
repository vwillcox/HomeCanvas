import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/link_viewer_screen.dart';
import '../../services/article_reader.dart';
import '../../services/elevenlabs_tts.dart';
import '../../services/kiosk_browser.dart' show ReaderStyle;
import '../../services/feed_service.dart';
import '../../services/news_mix.dart';
import '../../services/video_link.dart';
import '../../services/video_player_service.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import '../../l10n/l10n.dart';
import '../../widgets/lcars.dart';
import '../../widgets/send_to_device.dart';
import 'tile_bits.dart';

/// Headlines from an RSS or Atom feed.
class DashboardNewsWidget extends StatelessWidget {
  const DashboardNewsWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final feeds = context.watch<FeedService>();
    return Refreshed(
      theme: w.theme,
      // Of several feeds, the one fetched longest ago.
      at: Refreshed.oldest(feedUrls(w).map(feeds.refreshedAt)),
      child: _feeds(context),
    );
  }

  Widget _feeds(BuildContext context) {
    final t = w.theme;
    // Absent in the editor's off-screen previews, which read nothing out.
    final reader = context.watch<ArticleReader?>();
    final sources = sourcesIn(w.config.options);
    if (sources.isEmpty) {
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
    // seven headlines rather than three headlines and four gaps — and a
    // county paper narrowed to one town is just that town's news.
    final hidePromos = w.option('hidePromotions', true);
    final lists = [
      for (final s in sources)
        [
          for (final item in feeds.feed(s.url, maxAge: maxAge))
            if ((!hidePromos || !isPromotional(item)) && s.keeps(item)) item,
        ],
    ];
    final names = {for (final s in sources) s.url: s.name};

    // Which feed each headline came from, for its icon and for "also in".
    // Items are the cached instances themselves, so identity is enough to
    // find them again.
    final from = Map<FeedItem, String>.identity();
    for (var i = 0; i < sources.length; i++) {
      for (final item in lists[i]) {
        from.putIfAbsent(item, () => sources[i].url);
      }
    }

    // The headlines of the feeds at [these] as one list. Everything they
    // carry: the tile shows what fits and scrolls for the rest. One feed
    // keeps the order its publisher chose; several are blended, and a story
    // more than one of them is telling is told once.
    List<NewsStory> storiesOf(List<int> these) {
      if (these.length == 1) {
        return [for (final item in lists[these.single]) NewsStory(item)];
      }
      final mixed = FeedService.mix([
        for (final i in these) lists[i],
      ], max: these.fold(0, (n, i) => n + lists[i].length));
      return sameStories(mixed, sourceOf: (item) => from[item]);
    }

    String? errorOf(List<int> these) => these
        .map((i) => feeds.errorFor(sources[i].url))
        .whereType<String>()
        .firstOrNull;

    // A tab for each topic, its feeds blended, and for each feed filed
    // under none. A feed's own tab says where its headlines are from, so
    // they needn't; a topic's mixes several, so they do.
    final tabs = newsTabs(sources);
    if (w.option('layout', 'blended') == 'tabs' && tabs.length > 1) {
      final at = Map<NewsSource, int>.identity();
      for (var i = 0; i < sources.length; i++) {
        at[sources[i]] = i;
      }
      List<int> these(int tab) => [for (final s in tabs[tab].sources) at[s]!];
      return _FeedTabs(
        count: tabs.length,
        page: (i) => _headlines(
          context,
          feeds,
          reader,
          key: ValueKey('${tabs[i].name}·${these(i).first}'),
          stories: storiesOf(these(i)),
          error: errorOf(these(i)),
          refresh: [for (final j in these(i)) sources[j].url],
          from: from,
          names: names,
          showSource: these(i).length > 1 && w.option('showSource', true),
        ),
        tab: (i, selected) {
          final tab = tabs[i];
          // A topic is several sites, so it is named rather than pictured.
          if (tab.isTopic) {
            return _tab(
              icon: null,
              name: tab.name,
              link: tab.topic,
              selected: selected,
              topic: true,
            );
          }
          final j = at[tab.sources.first]!;
          final site = lists[j].firstOrNull?.link ?? sources[j].url;
          return _tab(
            icon: feeds.siteIcon(site),
            name: tab.name,
            link: site,
            selected: selected,
          );
        },
      );
    }

    final all = [for (var i = 0; i < sources.length; i++) i];
    return _headlines(
      context,
      feeds,
      reader,
      stories: storiesOf(all),
      error: errorOf(all),
      refresh: [for (final s in sources) s.url],
      from: from,
      names: names,
      showSource: w.option('showSource', true),
    );
  }

  /// A tab along the bottom: the feed's icon and name — or, for a [topic],
  /// just its name.
  Widget _tab({
    required String? icon,
    required String name,
    required String link,
    required bool selected,
    bool topic = false,
  }) {
    final t = w.theme;
    final host = (Uri.tryParse(link)?.host ?? '').replaceFirst('www.', '');
    final label = topic ? 'name' : w.option('tabLabel', 'both');
    if (t.isLcars) {
      // A console's tab is a block, in the feed's own colour, a black line
      // from the next, and near-white for the one showing.
      return Container(
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: lcarsLine / 2),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        color: selected ? lcarsLit : t.block(lcarsIndex(link)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (label != 'name')
              _SourceIcon(
                icon: icon,
                name: name,
                link: link,
                theme: t,
                side: label == 'icon' ? 28 : 18,
              ),
            if (label == 'both') const SizedBox(width: 6),
            if (label != 'icon')
              Flexible(
                child: Text(
                  lcarsCaps(name.isNotEmpty ? name : host),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: lcarsInk,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
          ],
        ),
      );
    }
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

  /// [stories] as a scrolling list that, pulled down from the top, fetches
  /// [refresh] again. [from] is the feed each headline came from; with
  /// [showSource], each carries that feed's icon.
  Widget _headlines(
    BuildContext context,
    FeedService feeds,
    ArticleReader? reader, {
    Key? key,
    required List<NewsStory> stories,
    required String? error,
    required List<String> refresh,
    required Map<FeedItem, String> from,
    Map<String, String> names = const {},
    bool showSource = false,
  }) {
    final t = w.theme;
    final sourceOf = showSource ? from : null;
    if (stories.isEmpty) {
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
    final shown = stories;

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
          final story = shown[i];
          final item = story.item;
          // Who else is telling it: "also BBC News, The Guardian".
          final also = [
            for (final a in story.also)
              (name: _nameOf(from[a], a, names), item: a),
          ];
          final tappable =
              w.option('openOnTap', true) &&
              (item.link != null || item.summary != null);
          // The headline being read aloud, marked so you can see which.
          final beingRead =
              reader != null &&
              reader.active &&
              item.link != null &&
              reader.link == item.link;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: tappable ? () => _open(context, item, also: also) : null,
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
                        color: t.textSecondary,
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                  ),
                if ((showTime && item.published != null) || also.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        if (showTime && item.published != null)
                          ago(item.published!),
                        if (also.isNotEmpty)
                          tr('widget.news.alsoIn', 'also {names}', {
                            'names': [for (final a in also) a.name].join(', '),
                          }),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
  ///
  /// [also] is the same story from other feeds, each a tap from its own
  /// telling of it.
  void _open(
    BuildContext context,
    FeedItem item, {
    List<({String name, FeedItem item})> also = const [],
  }) {
    final reader = context.read<ArticleReader?>();
    final summary = item.summary ?? '';
    // Straight to the page only when there is nothing else to offer — no
    // summary to show, no voice to read it out, and no one else telling it.
    if (summary.isEmpty &&
        also.isEmpty &&
        (reader == null || !w.option('readAloud', true))) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  summary.isEmpty
                      ? tr(
                          'widget.news.theFeedGivesNoSummary',
                          'The feed gives no summary of this one.',
                        )
                      : summary,
                  style: const TextStyle(fontSize: 18, height: 1.4),
                ),
                if (also.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(
                    tr('widget.news.alsoReportedBy', 'Also reported by'),
                    style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Each outlet's own headline, a touch from its page.
                  for (final a in also)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: OutlinedButton(
                        onPressed: a.item.link == null
                            ? null
                            : () {
                                Navigator.of(ctx).pop();
                                _openPage(context, a.item);
                              },
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                        ),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${a.name}  ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(text: a.item.title),
                            ],
                          ),
                          style: const TextStyle(fontSize: 16, height: 1.3),
                        ),
                      ),
                    ),
                ],
              ],
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
                  cloud: elevenLabs(w),
                );
              },
              icon: const Icon(Icons.record_voice_over_rounded, size: 26),
              label: Text(
                tr('widget.news.readAloud', 'Read aloud'),
                style: TextStyle(fontSize: 20),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 18,
                ),
              ),
            ),
          if (item.link != null)
            SendToDeviceButton(url: item.link!, title: item.title),
          if (item.link != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openPage(context, item);
              },
              icon: const Icon(Icons.open_in_browser, size: 26),
              label: Text(
                tr('widget.news.readThePage', 'Read the page'),
                style: TextStyle(fontSize: 20),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 18,
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
            ),
            child: Text(
              tr('widget.news.close', 'Close'),
              style: TextStyle(fontSize: 20),
            ),
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LinkViewerScreen(
          url: item.link!,
          title: item.title,
          reader: readerStyle(w),
        ),
      ),
    );
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

  /// The ElevenLabs voice to read in, when the settings choose it and give
  /// a key — otherwise null, and piper reads.
  static ElevenLabsVoice? elevenLabs(DashboardWidgetContext w) {
    if (w.option<String>('voiceEngine', 'piper') != 'elevenlabs') return null;
    final key = w.option<String>('elevenLabsKey', '').trim();
    if (key.isEmpty) return null;
    final voice = w.option<String>('elevenLabsVoice', '').trim();
    return ElevenLabsVoice(
      apiKey: key,
      voiceId: voice.isEmpty ? kElevenLabsDefaultVoice : voice,
      model: w.option<String>('elevenLabsModel', kElevenLabsDefaultModel),
    );
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
  static List<String> feedUrls(DashboardWidgetContext w) => [
    for (final s in sourcesIn(w.config.options)) s.url,
  ];

  /// The feeds [options] list, with their topics and places.
  static List<NewsSource> sourcesIn(Map<String, dynamic> options) {
    final sources = [
      for (final r in (options['sources'] as List?) ?? const [])
        if (r is Map) NewsSource.fromRow(r),
    ].where((s) => s.url.isNotEmpty).toList();
    if (sources.isNotEmpty) return sources;
    final legacy = '${options['url'] ?? ''}'.trim();
    return legacy.isEmpty ? const [] : [NewsSource(url: legacy)];
  }

  /// What to call the feed at [url] that [item] came from: the name it was
  /// given, or else its site — "theguardian.com".
  static String _nameOf(String? url, FeedItem item, Map<String, String> names) {
    final given = names[url] ?? '';
    if (given.isNotEmpty) return given;
    final host = Uri.tryParse(item.link ?? url ?? '')?.host ?? '';
    return host.replaceFirst(RegExp(r'^(www|feeds)\.'), '');
  }

  static int refreshMinutes(DashboardWidgetContext w) =>
      (int.tryParse('${w.config.options['refreshMinutes'] ?? 15}') ?? 15).clamp(
        1,
        1440,
      );

  static String ago(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return tr('widget.news.justNow', 'just now');
    if (d.inMinutes < 60) {
      return tr('widget.news.mAgo', '{inMinutes}m ago', {
        'inMinutes': d.inMinutes,
      });
    }
    if (d.inHours < 24) {
      return tr('widget.news.hAgo', '{inHours}h ago', {'inHours': d.inHours});
    }
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
          color: theme.isLcars
              ? lcarsInk.withValues(alpha: 0.2)
              : theme.accent.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(tileCorner(theme, 4)),
        ),
        child: Center(
          child: Text(
            _initial(),
            style: TextStyle(
              color: theme.isLcars ? lcarsInk : theme.textPrimary,
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
      borderRadius: BorderRadius.circular(tileCorner(theme, 4)),
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

/// Colchester and the places round it, for narrowing Essex-wide feeds to
/// the town's own news.
const colchesterPlaces =
    'Colchester, Wivenhoe, Tiptree, Mersea, Stanway, Lexden, Dedham, '
    'Rowhedge, Marks Tey, Copford, West Bergholt, Boxted, Great Horkesley, '
    'Highwoods, Greenstead, Prettygate, Myland, Berechurch, Old Heath, '
    'Shrub End, Fingringhoe, Abberton, Layer de la Haye, Eight Ash Green, '
    'Ardleigh, Elmstead, Jumbo water tower, University of Essex';

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
      help:
          'RSS or Atom. With more than one, headlines are blended: each is '
          'ranked on how recent it is and on how much that feed has already '
          'contributed, so a busy wire service can’t bury a quieter source. '
          'A story several feeds are telling is shown once, with who else '
          'has it. The ready-made sets add feeds for a topic in one go.',
      fields: [
        WidgetOption(key: 'name', label: 'Name', defaultValue: ''),
        WidgetOption(
          key: 'url',
          label: 'Address',
          defaultValue: '',
          help: 'For example https://feeds.bbci.co.uk/news/rss.xml',
        ),
        WidgetOption(
          key: 'topic',
          label: 'Topic',
          defaultValue: '',
          help:
              'Optional. With tabs, feeds that share a topic share a tab — '
              '“Tech”, “UK”, “Colchester” — blended into one list.',
        ),
        WidgetOption(
          key: 'only',
          label: 'Only headlines mentioning',
          defaultValue: '',
          help:
              'Optional. Words or places, separated by commas — '
              '“Colchester, Wivenhoe, Tiptree” — to narrow a county paper '
              'to one town. Looked for in the headline, its summary and its '
              'address.',
        ),
      ],
      presets: {
        'tech': OptionPreset(
          'Tech — The Register, Ars Technica, BBC Technology, The Verge, '
          'Engadget',
          [
            {
              'name': 'The Register',
              'url': 'https://www.theregister.com/headlines.atom',
              'topic': 'Tech',
            },
            {
              'name': 'Ars Technica',
              'url': 'https://feeds.arstechnica.com/arstechnica/index',
              'topic': 'Tech',
            },
            {
              'name': 'BBC Technology',
              'url': 'https://feeds.bbci.co.uk/news/technology/rss.xml',
              'topic': 'Tech',
            },
            {
              'name': 'The Verge',
              'url': 'https://www.theverge.com/rss/index.xml',
              'topic': 'Tech',
            },
            {
              'name': 'Engadget',
              'url': 'https://www.engadget.com/rss.xml',
              'topic': 'Tech',
            },
          ],
        ),
        'ai': OptionPreset(
          'AI — MIT Technology Review, The Verge, Ars Technica, The '
          'Guardian, The Decoder, Simon Willison',
          [
            {
              'name': 'MIT Technology Review',
              'url':
                  'https://www.technologyreview.com/topic/'
                  'artificial-intelligence/feed',
              'topic': 'AI',
            },
            {
              'name': 'The Verge AI',
              'url':
                  'https://www.theverge.com/rss/'
                  'ai-artificial-intelligence/index.xml',
              'topic': 'AI',
            },
            {
              'name': 'Ars Technica AI',
              'url': 'https://arstechnica.com/ai/feed/',
              'topic': 'AI',
            },
            {
              'name': 'The Guardian AI',
              'url':
                  'https://www.theguardian.com/technology/'
                  'artificialintelligenceai/rss',
              'topic': 'AI',
            },
            {
              'name': 'The Decoder',
              'url': 'https://the-decoder.com/feed/',
              'topic': 'AI',
            },
            {
              'name': 'Simon Willison',
              'url': 'https://simonwillison.net/atom/everything/',
              'topic': 'AI',
            },
          ],
        ),
        'uk': OptionPreset(
          'UK — BBC News, The Guardian, Sky News, The Independent',
          [
            {
              'name': 'BBC News UK',
              'url': 'https://feeds.bbci.co.uk/news/uk/rss.xml',
              'topic': 'UK',
            },
            {
              'name': 'The Guardian UK',
              'url': 'https://www.theguardian.com/uk-news/rss',
              'topic': 'UK',
            },
            {
              'name': 'Sky News UK',
              'url': 'https://feeds.skynews.com/feeds/rss/uk.xml',
              'topic': 'UK',
            },
            {
              'name': 'The Independent UK',
              'url': 'https://www.independent.co.uk/news/uk/rss',
              'topic': 'UK',
            },
          ],
        ),
        'colchester': OptionPreset(
          'Colchester — the Daily Gazette, Essex Live, BBC Essex, Gazette '
          'sport',
          [
            {
              'name': 'Daily Gazette',
              'url': 'https://www.gazette-news.co.uk/news/rss/',
              'topic': 'Colchester',
              'only': colchesterPlaces,
            },
            {
              'name': 'Essex Live',
              'url':
                  'https://www.essexlive.news/all-about/colchester?service=rss',
              'topic': 'Colchester',
            },
            {
              'name': 'BBC Essex',
              'url': 'https://feeds.bbci.co.uk/news/england/essex/rss.xml',
              'topic': 'Colchester',
              'only': colchesterPlaces,
            },
            {
              'name': 'Gazette sport',
              'url': 'https://www.gazette-news.co.uk/sport/rss/',
              'topic': 'Colchester',
              'only': colchesterPlaces,
            },
          ],
        ),
      },
    ),
    WidgetOption(
      key: 'layout',
      label: 'Layout',
      kind: OptionKind.choice,
      defaultValue: 'blended',
      choices: {
        'blended': 'One list, all the feeds blended together',
        'tabs': 'A tab for each topic or feed, along the bottom',
      },
      help:
          'Tabs need more than one feed; with just one, it is a plain list. '
          'Feeds given the same topic share a tab.',
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
      help:
          'Icons alone fit more tabs across a narrow tile. A feed with no '
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
      help:
          'Little point checking a weekly blog every two minutes, or a wire '
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
      help:
          'A small icon — the site’s own, or the first letter of the '
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
      help:
          'Shows the feed’s own summary, with the full page a tap further. '
          'Turn off for a panel nobody should be browsing from.',
    ),
    WidgetOption(
      key: 'hidePromotions',
      label: 'Hide promo codes, coupons and sponsored posts',
      kind: OptionKind.boolean,
      defaultValue: true,
      help:
          'Some feeds are more shopping than news — WIRED’s is mostly coupon '
          'posts. Judged from the headline, the address and the publisher’s '
          'own category. Reviews and buying guides are kept.',
    ),
    WidgetOption(
      key: 'readerView',
      label: 'Open articles in reader view',
      kind: OptionKind.boolean,
      defaultValue: true,
      help:
          'Just the text and pictures — no adverts, cookie banners or '
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
      help:
          'The column widens or narrows to fill the screen at whichever '
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
      help:
          'A button on each headline that reads the whole article out, a '
          'paragraph at a time, with pause and stop along the bottom of the '
          'screen. Needs piper on the Pi — see INSTALL.md — or an ElevenLabs '
          'account.',
    ),
    WidgetOption(
      key: 'readAuthor',
      label: 'Say who wrote it',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: '“By …” after the headline, when the page names its author.',
    ),
    WidgetOption(
      key: 'voiceEngine',
      label: 'Read in',
      kind: OptionKind.choice,
      defaultValue: 'piper',
      choices: {
        'piper': 'Piper, on the Pi (recommended)',
        'elevenlabs': 'ElevenLabs',
      },
      help:
          'Piper is free, works without the internet and sends nothing '
          'anywhere. ElevenLabs sounds more natural, but sends each article '
          'to ElevenLabs and uses your account’s credits — about one per '
          'character with Flash. Piper reads whenever ElevenLabs can’t.',
    ),
    WidgetOption(
      key: 'elevenLabsKey',
      label: 'ElevenLabs API key',
      kind: OptionKind.secret,
      defaultValue: '',
      help:
          'On elevenlabs.io: your profile → API keys. A key limited to '
          'Text to Speech is all it needs.',
    ),
    WidgetOption(
      key: 'elevenLabsVoice',
      label: 'ElevenLabs voice ID',
      defaultValue: '',
      help:
          'Optional — George, a British narrator, otherwise. Copy a voice’s '
          'ID from the Voices page on elevenlabs.io.',
    ),
    WidgetOption(
      key: 'elevenLabsModel',
      label: 'ElevenLabs model',
      kind: OptionKind.choice,
      defaultValue: kElevenLabsDefaultModel,
      choices: {
        'eleven_flash_v2_5': 'Flash — quick, half the credits',
        'eleven_multilingual_v2': 'Multilingual — the most natural',
      },
    ),
    WidgetOption(
      key: 'voiceSpeeds',
      label: 'Voice speeds',
      kind: OptionKind.list,
      addLabel: 'Set a voice’s speed',
      help:
          'Each writer is read in one of the voices installed on the Pi, '
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
    PreviewLine('Storm expected to clear by Thursday', scale: 0.13, px: 15),
    PreviewLine('4h ago', scale: 0.09, muted: true, px: 12),
  ],
  live: (config, data) {
    if (data.feeds == null) return const [];
    final sources = DashboardNewsWidget.sourcesIn(config.options);
    if (sources.isEmpty) return const [];

    // Enough to fill the tile; the panel scrolls for the rest.
    const shown = 10;
    final hidePromos = config.options['hidePromotions'] != false;
    // The first tab's feeds when there are tabs, or all of them.
    final tabs = newsTabs(sources);
    final these = config.options['layout'] == 'tabs' && tabs.length > 1
        ? tabs.first.sources
        : sources;
    final from = Map<FeedItem, String>.identity();
    final lists = [
      for (final s in these)
        [
          for (final item in data.feeds!.feed(s.url))
            if ((!hidePromos || !isPromotional(item)) && s.keeps(item)) item,
        ],
    ];
    for (var i = 0; i < these.length; i++) {
      for (final item in lists[i]) {
        from.putIfAbsent(item, () => these[i].url);
      }
    }
    // Blended exactly as the panel blends them, so the preview is not a
    // different selection of headlines from the one on the wall.
    final items = lists.length == 1
        ? lists.first.take(shown).toList()
        : [
            for (final s in sameStories(
              FeedService.mix(lists, max: shown * 2),
              sourceOf: (item) => from[item],
            ).take(shown))
              s.item,
          ];
    if (items.isEmpty) return const [];
    return [
      for (final item in items) ...[
        PreviewLine(item.title, scale: 0.13, px: 15),
        if (config.options['showTime'] != false && item.published != null)
          PreviewLine(
            DashboardNewsWidget.ago(item.published!),
            scale: 0.09,
            muted: true,
            px: 12,
          ),
      ],
    ];
  },
  build: (context, w) => DashboardNewsWidget(w: w),
);

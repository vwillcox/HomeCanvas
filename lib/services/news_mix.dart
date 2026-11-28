import 'dart:math' as math;

import 'feed_service.dart';

/// One feed, as the News tile's settings give it: where it is, what to
/// call it, the topic it is filed under, and — for a paper that covers a
/// whole county — the places a headline must mention to be kept.
class NewsSource {
  const NewsSource({
    required this.url,
    this.name = '',
    this.topic = '',
    this.only = const [],
  });

  final String url;
  final String name;

  /// Feeds that share a topic share a tab, blended together. Empty for a
  /// feed with a tab of its own.
  final String topic;

  /// Words or places, any one of which a headline must mention — in its
  /// title, its summary or its address — to be shown. Empty for every
  /// headline.
  final List<String> only;

  static NewsSource fromRow(Map<dynamic, dynamic> row) => NewsSource(
    url: '${row['url'] ?? ''}'.trim(),
    name: '${row['name'] ?? ''}'.trim(),
    topic: '${row['topic'] ?? ''}'.trim(),
    only: words(row['only']),
  );

  /// "Colchester, Wivenhoe; Tiptree" as its parts.
  static List<String> words(Object? v) => [
    if (v != null)
      for (final w in '$v'.split(RegExp(r'[,;\n]')))
        if (w.trim().isNotEmpty) w.trim(),
  ];

  /// Whether [item] is one to show: about one of [only], or any at all when
  /// it names none.
  bool keeps(FeedItem item) {
    if (only.isEmpty) return true;
    final pattern = _patterns[only.join('\n')] ??= RegExp(
      '\\b(${[for (final w in only) RegExp.escape(w.toLowerCase())].join('|')})\\b',
    );
    // The address too: a local paper's headline is often "Man jailed after
    // break-in" with the town only in the page's name.
    final path = Uri.tryParse(item.link ?? '')?.path ?? '';
    final text = [
      item.title,
      item.summary ?? '',
      path.replaceAll(RegExp(r'[-_/.]+'), ' '),
    ].join(' ').toLowerCase().replaceAll('’', "'");
    return pattern.hasMatch(text);
  }

  static final Map<String, RegExp> _patterns = {};
}

/// A tab along the foot of the tile: a topic's feeds together, or a feed
/// filed under none.
class NewsTab {
  const NewsTab({required this.name, required this.sources, this.topic = ''});

  /// The topic, or the feed's own name.
  final String name;
  final String topic;
  final List<NewsSource> sources;

  bool get isTopic => topic.isNotEmpty;
}

/// The tabs [sources] make, in the order their first feed is listed: each
/// topic once, with every feed that names it, and each feed without one by
/// itself — so a tile set up before topics existed keeps a tab per feed.
List<NewsTab> newsTabs(List<NewsSource> sources) {
  final tabs = <NewsTab>[];
  final byTopic = <String, List<NewsSource>>{};
  for (final s in sources) {
    if (s.topic.isEmpty) {
      tabs.add(NewsTab(name: s.name, sources: [s]));
      continue;
    }
    // "AI" and "ai" are the same topic, named as it was first written.
    final key = s.topic.toLowerCase();
    final had = byTopic[key];
    if (had != null) {
      had.add(s);
      continue;
    }
    final list = byTopic[key] = [s];
    tabs.add(NewsTab(name: s.topic, topic: s.topic, sources: list));
  }
  return tabs;
}

/// A headline, with the same story as other feeds tell it.
class NewsStory {
  NewsStory(this.item);

  final FeedItem item;

  /// The same story from other feeds, one each, in the order they ranked.
  final List<FeedItem> also = [];
}

/// [items] — already ranked, best first — with the same story from several
/// feeds told once, under the first of them.
///
/// Headlines are compared on their words, each weighted by how rare it is
/// among the headlines being shown: "Essex" in a county's news, or "AI" in
/// AI news, says little about which story it is, while "abattoir" or
/// "Heathrow" says a lot. Two headlines are one story when they share at
/// least three words and those make up half the weight of the shorter.
///
/// Only across feeds, never within one: a paper running two pieces about
/// the same crash means two pieces, and an outlet is never "also" itself.
List<NewsStory> sameStories(
  List<FeedItem> items, {
  required String? Function(FeedItem item) sourceOf,
  double share = 0.5,
}) {
  final words = [for (final i in items) headlineWords(i.title)];
  final seenIn = <String, int>{};
  for (final w in words) {
    for (final word in w) {
      seenIn[word] = (seenIn[word] ?? 0) + 1;
    }
  }
  final n = items.length;
  double weight(String word) =>
      math.log((n + 1) / ((seenIn[word] ?? 0) + 0.5)).clamp(0.1, 99);
  double weightOf(Set<String> s) => s.fold(0.0, (t, w) => t + weight(w));

  final stories = <NewsStory>[];
  final leadWords = <Set<String>>[];
  final leadWeight = <double>[];
  final sourcesIn = <Set<String?>>[];

  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final mine = words[i];
    final from = sourceOf(item);
    final myWeight = weightOf(mine);
    var joined = false;
    if (mine.length >= 3 && from != null) {
      for (var s = 0; s < stories.length; s++) {
        if (sourcesIn[s].contains(from)) continue;
        final shared = mine.intersection(leadWords[s]);
        if (shared.length < 3) continue;
        final least = math.min(myWeight, leadWeight[s]);
        if (least <= 0 || weightOf(shared) / least < share) continue;
        stories[s].also.add(item);
        sourcesIn[s].add(from);
        joined = true;
        break;
      }
    }
    if (joined) continue;
    stories.add(NewsStory(item));
    leadWords.add(mine);
    leadWeight.add(myWeight);
    sourcesIn.add({from});
  }
  return stories;
}

/// The words of a headline that say what it is about: lower case, without
/// the little words, a plural's "s" taken off.
Set<String> headlineWords(String title) {
  final out = <String>{};
  final plain = title.toLowerCase().replaceAll(RegExp(r"['’]s\b"), '');
  for (var w in plain.split(RegExp(r"[^a-z0-9£$%]+"))) {
    if (w.length < 2 || _filler.contains(w)) continue;
    if (w.length > 4 && w.endsWith('s') && !w.endsWith('ss')) {
      w = w.substring(0, w.length - 1);
    }
    out.add(w);
  }
  return out;
}

/// Words in almost any headline, and so in none in particular.
const _filler = {
  'a', 'an', 'the', 'and', 'or', 'but', 'of', 'to', 'in', 'on', 'at', 'by', //
  'for', 'with', 'from', 'as', 'is', 'are', 'was', 'were', 'be', 'been',
  'it', 'its', 'this', 'that', 'these', 'those', 'into', 'over', 'after',
  'before', 'about', 'up', 'out', 'off', 'down', 'amid', 'than', 'new',
  'says', 'said', 'say', 'will', 'would', 'could', 'can', 'may', 'might',
  'has', 'have', 'had', 'not', 'no', 'how', 'why', 'what', 'who', 'when',
  'where', 'which', 'his', 'her', 'their', 'our', 'your', 'you', 'we',
  'they', 'he', 'she', 'them', 'him', 'my', 'me', 'us', 'more', 'most',
  'all', 'just', 'now', 'get', 'gets', 'got', 'make', 'makes', 'one', 'two',
  'first', 'last', 'latest', 'live', 'update', 'updates', 'watch', 'video',
  'here', 'there', 'year', 'years', 'day', 'days', 'week', 'set', 'being',
  'do', 'does', 'did', 'if', 'so', 'some', 'any', 'other', 'very',
  'like', 'way', 'take', 'takes', 'back', 'still', 'yet', 'also', 'only',
  'under', 'against', 'during', 'while', 'through', 'per', 'via', 'vs',
  'go', 'goes', 'going', 'gone', 'come', 'comes', 'coming',
};

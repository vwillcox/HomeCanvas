import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'plain_text.dart';

/// An article's words, ready to be read out: its title, its author when the
/// page names one, and its paragraphs.
@immutable
class Article {
  const Article({required this.title, required this.paragraphs, this.author});

  final String title;
  final List<String> paragraphs;

  /// As the byline has it — "Steven Levy", "Anna Smith and Raj Patel".
  final String? author;

  int get length => paragraphs.fold(0, (n, p) => n + p.length);
}

/// Pulls the article out of a news page — the words a person would read, not
/// the menus, share buttons, "related" boxes and adverts around them.
///
/// Two ways, most reliable first:
///
/// 1. **The page's own description of itself.** Most news sites embed the
///    whole article as `articleBody` in JSON-LD for search engines. When it
///    is there it is exactly the text, with nothing to strip.
/// 2. **The page itself.** The block holding most of the page's paragraph
///    text — `<article>` when there is one — with the furniture cut out
///    first, keeping paragraphs, subheadings and quotes.
///
/// Returns null when neither finds enough to be an article; the caller then
/// falls back to the feed's own summary.
class ArticleText {
  /// Less than this is a teaser or a video page, not an article.
  static const minLength = 300;

  static Article? extract(String page, {String? fallbackTitle}) {
    final doc = html.parse(page);
    final title = _title(doc) ?? fallbackTitle ?? '';
    final record = _jsonLdArticle(doc);
    // Before the page is read: that takes bylines out as furniture.
    final author = _author(doc, record);
    for (final paragraphs in [_bodyOf(record), _fromPage(doc)]) {
      if (paragraphs == null) continue;
      final article =
          Article(title: title, paragraphs: paragraphs, author: author);
      if (article.length >= minLength) return article;
    }
    return null;
  }

  // --- The author ------------------------------------------------------------

  /// Who wrote it: the article's own record first, then the page's author
  /// tags. Never a link — some sites put the author's profile address in
  /// `article:author`, which is no use to say out loud.
  static String? _author(Document doc, Map? record) {
    List<String> tidy(Iterable<String> raw) {
      final out = <String>[];
      for (final c in raw) {
        final n =
            clean(c).replaceFirst(RegExp(r'^by\s+', caseSensitive: false), '');
        // A byline is a name or two, not a link or a sentence.
        if (n.isEmpty || n.startsWith('http') || n.contains('/')) continue;
        if (n.length > 80 || out.contains(n)) continue;
        out.add(n);
      }
      return out;
    }

    // Everyone the record names; otherwise the page's first author tag.
    var names = tidy([
      ..._names(record?['author']),
      ..._names(record?['creator']),
    ]);
    if (names.isEmpty) {
      names = tidy([
        doc.querySelector('meta[name="author"]')?.attributes['content'] ?? '',
        doc.querySelector('meta[property="article:author"]')
                ?.attributes['content'] ??
            '',
        doc.querySelector('[rel="author"]')?.text ?? '',
      ]).take(1).toList();
    }
    if (names.isEmpty) return null;
    if (names.length == 1) return names.single;
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  /// Names from JSON-LD's author field, in any of its forms: a string, a
  /// Person or Organization, or a list of either.
  static List<String> _names(Object? v) => switch (v) {
        String s => [s],
        Map m => _names(m['name']),
        List l => [for (final e in l) ..._names(e)],
        _ => const [],
      };

  static String? _title(Document doc) {
    final og = doc
        .querySelector('meta[property="og:title"]')
        ?.attributes['content'];
    final t = clean(og ?? doc.querySelector('h1')?.text ?? '');
    return t.isEmpty ? null : t;
  }

  // --- JSON-LD ---------------------------------------------------------------

  static const _articleTypes = {
    'Article',
    'NewsArticle',
    'BlogPosting',
    'ReportageNewsArticle',
    'AnalysisNewsArticle',
    'TechArticle',
  };

  /// The page's JSON-LD record of the article — one with a body if there
  /// is one, since that is the record that is really about this page.
  static Map? _jsonLdArticle(Document doc) {
    final found = <Map>[];
    for (final s in doc.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        _collect(jsonDecode(s.text), found);
      } catch (_) {
        continue;
      }
    }
    return found.where((m) => m['articleBody'] is String).firstOrNull ??
        found.firstOrNull;
  }

  static void _collect(Object? node, List<Map> into) {
    if (node is List) {
      for (final n in node) {
        _collect(n, into);
      }
    } else if (node is Map) {
      final type = node['@type'];
      final types = type is List ? type.map((t) => '$t') : ['$type'];
      if (types.any(_articleTypes.contains)) into.add(node);
      if (node['@graph'] != null) _collect(node['@graph'], into);
    }
  }

  static List<String>? _bodyOf(Map? record) {
    final body = record?['articleBody'];
    if (body is! String || body.isEmpty) return null;
    // Some sites put HTML in it: its paragraph ends become the line breaks
    // the body is split on, and [clean] takes the rest of the markup and the
    // entities out of each line. Otherwise breaks come as newlines, or not
    // at all.
    final parts = body
        .replaceAll(
          RegExp(r'<(br|/p|/div|/li|/h[1-6])\b[^<>]*>', caseSensitive: false),
          '\n',
        )
        .split(RegExp(r'\n\s*\n|\n'))
        .map(clean)
        .where((p) => p.isNotEmpty && !_boilerplate.hasMatch(p))
        .toList();
    return parts.isEmpty ? null : parts;
  }

  // --- The page --------------------------------------------------------------

  static const _furniture =
      'script, style, noscript, template, iframe, svg, nav, header, footer, '
      'aside, form, button, figure, figcaption, [role="navigation"], '
      '[role="banner"], [role="contentinfo"], [aria-hidden="true"]';

  /// Class and id words that mark a block as around the article, not in it.
  static final _aroundWords = RegExp(
    r'(^|[-_\s])(share|social|related|recommend|newsletter|promo|advert|ad|'
    r'ads|sponsor|comment|comments|subscribe|cookie|consent|footer|nav|menu|'
    r'breadcrumb|byline|author|caption|credit|tags|sidebar|popup|modal|'
    r'most-read|trending|read-more|signup|paywall)([-_\s]|$)',
    caseSensitive: false,
  );

  static List<String>? _fromPage(Document doc) {
    final body = doc.body;
    if (body == null) return null;
    for (final e in body.querySelectorAll(_furniture)) {
      e.remove();
    }
    for (final e in body.querySelectorAll('[class], [id]')) {
      final words = '${e.className} ${e.id}';
      // Never the article itself, however it happens to be named.
      if (e.localName == 'article' || e.localName == 'main') continue;
      if (_aroundWords.hasMatch(words)) e.remove();
    }

    // The block holding the most paragraph text. <article> first, since a
    // page that has one almost always means it.
    final candidates = [
      ...body.querySelectorAll('article'),
      ...body.querySelectorAll('main'),
      for (final p in body.querySelectorAll('p')) ?p.parent,
    ];
    Element? best;
    var bestScore = 0;
    for (final c in candidates.toSet()) {
      final score = c
          .querySelectorAll('p')
          .fold<int>(0, (n, p) => n + clean(p.text).length);
      if (score > bestScore) {
        best = c;
        bestScore = score;
      }
    }
    if (best == null) return null;

    final out = <String>[];
    for (final e in best.querySelectorAll('p, h2, h3, h4, blockquote, li')) {
      // A list item only when it is prose, not a menu entry; and nothing
      // already inside something taken.
      if (e.localName == 'li' && clean(e.text).length < 80) continue;
      if (_insideTaken(e)) continue;
      final text = clean(e.text);
      final heading = const {'h2', 'h3', 'h4'}.contains(e.localName);
      if (text.isEmpty) continue;
      // The story is over: what follows is other stories.
      if (heading && _endOfStory.hasMatch(text)) break;
      if (!heading && text.length < 40 && !text.endsWith('.')) continue;
      if (_boilerplate.hasMatch(text)) continue;
      if (out.isNotEmpty && out.last == text) continue;
      out.add(heading && !RegExp(r'[.!?:]$').hasMatch(text) ? '$text.' : text);
    }
    return out.isEmpty ? null : out;
  }

  static bool _insideTaken(Element e) {
    for (var p = e.parent; p != null; p = p.parent) {
      if (const {'p', 'blockquote', 'li'}.contains(p.localName)) return true;
    }
    return false;
  }

  /// Lines that are about the page rather than the story — a sign-up pitch,
  /// a link list's "Published 9 May" — wherever they fall.
  static final _boilerplate = RegExp(
    r'^(advertisement|sponsored|sign up|subscribe|read more|related:|'
    r'share this|follow us|image:|photo:|©|copyright)'
    r'|subscribe today|unlimited access to|read previous newsletters|'
    r'updates from your .* topics|published\s?\d{1,2} \w+( ago)?\.?$',
    caseSensitive: false,
  );

  /// Headings that start the list of other stories under an article.
  static final _endOfStory = RegExp(
    r'^(related( topics| stories| articles| content)?|more on this story|'
    r'top stories|most read|more from|you may also like|read next|'
    r'recommended|elsewhere)\b',
    caseSensitive: false,
  );

  /// One run of text as it should be read: any markup gone, every HTML
  /// entity decoded — the embedded article body and page titles are often
  /// still encoded — invisible characters dropped, whitespace collapsed, and
  /// stray space before punctuation removed.
  static String clean(String s) =>
      plainText(s).replaceAll(RegExp(r' ([,.;:!?])'), r'$1');
}

/// Splits paragraphs into pieces a voice can be given one at a time: whole
/// paragraphs where they are short enough, otherwise runs of whole sentences.
///
/// Small enough that the first words come quickly and a stop is heard at
/// once; large enough that the voice keeps its phrasing across sentences.
List<String> speakableChunks(List<String> paragraphs, {int max = 420}) {
  final out = <String>[];
  for (final p in paragraphs) {
    if (p.length <= max) {
      out.add(p);
      continue;
    }
    // A sentence ends at a stop *followed by a space* (or the end): the
    // point in "f/1.48" or "3.5 million" is not one. Splitting there, then
    // joining the pieces with a space, had the voice read "one. forty-eight".
    final sentences = RegExp(r'.+?[.!?]+["”’)]*(?=\s|$)|.+$', dotAll: true)
        .allMatches(p)
        .map((m) => m[0]!.trim())
        .where((s) => s.isNotEmpty);
    var run = '';
    for (final s in sentences) {
      if (run.isNotEmpty && run.length + s.length + 1 > max) {
        out.add(run);
        run = '';
      }
      // A single sentence longer than the limit goes on its own.
      run = run.isEmpty ? s : '$run $s';
    }
    if (run.isNotEmpty) out.add(run);
  }
  return out;
}

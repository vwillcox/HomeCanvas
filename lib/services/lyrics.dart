import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'http_client.dart';
import 'itunes_art.dart' show sameName;

/// One line of a song's words, and when it is sung. A line with no words is
/// a break: an intro, a solo, the gap between verses.
@immutable
class LyricLine {
  const LyricLine(this.at, this.text);

  final Duration at;
  final String text;

  bool get isBreak => text.isEmpty;
}

/// A song's words, as LRCLIB has them.
///
/// [synced] words come with the time each line is sung, so the player can
/// light the line being sung; plain words have no times, and are only shown
/// in order. An [instrumental] has none at all, and says so.
@immutable
class Lyrics {
  const Lyrics({required this.lines, required this.synced})
    : instrumental = false;

  const Lyrics.instrumental()
    : lines = const [],
      synced = false,
      instrumental = true;

  final List<LyricLine> lines;
  final bool synced;
  final bool instrumental;

  /// Whether there is anything to sing along to.
  bool get hasWords => lines.any((l) => !l.isBreak);

  /// The line being sung at [t]: the last whose time has come, or -1 before
  /// the first. Always -1 for plain words, which have no times.
  int lineAt(Duration t) {
    if (!synced || lines.isEmpty || t < lines.first.at) return -1;
    var lo = 0, hi = lines.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (lines[mid].at <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// When the line after [i] is sung, or null after the last.
  Duration? nextAt(int i) => i + 1 < lines.length ? lines[i + 1].at : null;
}

/// The words of an LRC file: `[01:14.32] a line`, a line with several times
/// for a chorus sung more than once, an `[offset:+250]` to shift them all,
/// and tags such as `[ar:…]` that are not words at all.
///
/// Breaks are kept, one at a time, and one is put before the first line when
/// the singing does not start for a while — so the player has something to
/// show through the intro. Null when there is no line with a time.
Lyrics? parseLrc(String lrc) {
  final stamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  final offsetTag = RegExp(
    r'^\[offset:\s*([+-]?\d+)\s*\]',
    caseSensitive: false,
  );
  var offset = 0;
  final found = <LyricLine>[];
  for (final raw in lrc.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    final o = offsetTag.firstMatch(line);
    if (o != null) {
      offset = int.parse(o[1]!);
      continue;
    }
    final stamps = <Duration>[];
    var rest = line;
    while (true) {
      final m = stamp.matchAsPrefix(rest);
      if (m == null) break;
      final frac = m[3] ?? '0';
      // "07" is 70 ms and "7" is 700: the digits are a fraction, not a count.
      final ms = int.parse(frac.padRight(3, '0'));
      stamps.add(
        Duration(
          minutes: int.parse(m[1]!),
          seconds: int.parse(m[2]!),
          milliseconds: ms,
        ),
      );
      rest = rest.substring(m.end).trimLeft();
    }
    if (stamps.isEmpty) continue;
    for (final at in stamps) {
      found.add(LyricLine(at, rest.trim()));
    }
  }
  if (found.isEmpty) return null;
  // LRC's offset is how much earlier the words should come: positive is
  // sooner.
  final shift = Duration(milliseconds: offset);
  found.sort((a, b) => a.at.compareTo(b.at));
  final lines = <LyricLine>[];
  for (final l in found) {
    final at = l.at - shift;
    final line = LyricLine(at < Duration.zero ? Duration.zero : at, l.text);
    // One break is enough, and one at the very end says nothing.
    if (line.isBreak && (lines.isEmpty || lines.last.isBreak)) continue;
    lines.add(line);
  }
  while (lines.isNotEmpty && lines.last.isBreak) {
    lines.removeLast();
  }
  if (lines.isEmpty) return null;
  if (lines.first.at > const Duration(seconds: 4)) {
    lines.insert(0, const LyricLine(Duration.zero, ''));
  }
  return Lyrics(lines: List.unmodifiable(lines), synced: true);
}

/// Plain words, one line each, a blank line kept as one break between
/// verses.
Lyrics? parsePlainLyrics(String text) {
  final lines = <LyricLine>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = LyricLine(Duration.zero, raw.trim());
    if (line.isBreak && (lines.isEmpty || lines.last.isBreak)) continue;
    lines.add(line);
  }
  while (lines.isNotEmpty && lines.last.isBreak) {
    lines.removeLast();
  }
  if (lines.isEmpty) return null;
  return Lyrics(lines: List.unmodifiable(lines), synced: false);
}

/// A title as a lyrics site files it: no "- Remastered 2011", no "(feat. …)".
String plainTitle(String title) => title
    .replaceAll(
      RegExp(
        r'\s+-\s+[^-]*\b(remaster(ed)?|version|mono|stereo|edit|mix|live|single)\b.*$',
        caseSensitive: false,
      ),
      '',
    )
    .replaceAll(
      RegExp(
        r'\s*[\(\[](feat|ft|with)\.?\s[^\)\]]*[\)\]]',
        caseSensitive: false,
      ),
      '',
    )
    .trim();

/// The first of several artists: "John Williams" of "John Williams, London
/// Symphony Orchestra".
String firstArtist(String artist) => artist
    .split(RegExp(r',|;| & | feat\.? | x ', caseSensitive: false))
    .first
    .trim();

/// The words from one of LRCLIB's records, or null where it has none.
Lyrics? lyricsFromRecord(Map record) {
  if (record['instrumental'] == true) return const Lyrics.instrumental();
  final synced = record['syncedLyrics'];
  if (synced is String && synced.trim().isNotEmpty) {
    final l = parseLrc(synced);
    if (l != null && l.hasWords) return l;
  }
  final plain = record['plainLyrics'];
  if (plain is String && plain.trim().isNotEmpty) {
    return parsePlainLyrics(plain);
  }
  return null;
}

/// Which of LRCLIB's search results is this song: by the same artist, of the
/// same name, and as long, give or take a few seconds — a live take or a
/// radio edit has its words at other times. Timed words beat plain ones; an
/// instrumental counts only where nothing has words. Null for none.
Map? bestRecord(
  List records, {
  required String artist,
  required String title,
  required Duration duration,
}) {
  final who = firstArtist(artist).toLowerCase();
  Map? best;
  var bestScore = -1 << 30;
  for (final r in records) {
    if (r is! Map) continue;
    if (!sameName('${r['trackName'] ?? ''}', title)) continue;
    final by = '${r['artistName'] ?? ''}'.toLowerCase();
    if (who.isNotEmpty && !by.contains(who) && !who.contains(by)) continue;
    final seconds = (r['duration'] as num?)?.toDouble();
    final off = duration > Duration.zero && seconds != null
        ? (seconds - duration.inMilliseconds / 1000).abs()
        : 0.0;
    if (off > 4) continue;
    final synced = '${r['syncedLyrics'] ?? ''}'.trim().isNotEmpty;
    final plain = '${r['plainLyrics'] ?? ''}'.trim().isNotEmpty;
    final score =
        (synced
            ? 300
            : plain
            ? 200
            : r['instrumental'] == true
            ? 100
            : -1000) -
        (off * 10).round();
    if (score > bestScore) {
      bestScore = score;
      best = r;
    }
  }
  return bestScore < 0 ? null : best;
}

/// Finds a song's words on [LRCLIB](https://lrclib.net): free, open, with no
/// key, and the one place the player sends a song's name for them. It is
/// sent the artist, title, album and length, and nothing else.
///
/// A song is looked up once: the answer, words or none, is kept for the
/// last few dozen songs, so a track played again, or the player opened and
/// closed, asks nothing more.
class LyricsFinder {
  LyricsFinder({Dio? dio})
    : _dio =
          dio ??
          httpClient(
            connect: const Duration(seconds: 6),
            receive: const Duration(seconds: 10),
            headers: {
              'User-Agent':
                  'HomeCanvas (https://github.com/vwillcox/HomeCanvas)',
            },
          );

  static final LyricsFinder instance = LyricsFinder();

  static const _base = 'https://lrclib.net/api';
  static const _keep = 40;

  final Dio _dio;
  // A map literal keeps its order: the first key is the oldest.
  final _known = <String, Future<Lyrics?>>{};

  /// What [find] already knows of a song, without asking: whether it has
  /// an answer, and the words if the answer was some.
  ({bool known, Lyrics? lyrics}) cached(String artist, String title) {
    final key = keyOf(artist, title);
    return (known: _settled.containsKey(key), lyrics: _settled[key]);
  }

  final _settled = <String, Lyrics?>{};

  static String keyOf(String artist, String title) => '$artist|$title';

  Future<Lyrics?> find({
    required String artist,
    required String title,
    String album = '',
    Duration duration = Duration.zero,
  }) {
    final key = keyOf(artist, title);
    final had = _known.remove(key);
    if (had != null) {
      _known[key] = had;
      return had;
    }
    final asking = _ask(artist, title, album, duration).then((answer) {
      final (lyrics, keep) = answer;
      // Not kept when LRCLIB couldn't be reached: worth asking again.
      if (keep) {
        _settled[key] = lyrics;
      } else {
        _known.remove(key);
      }
      return lyrics;
    });
    _known[key] = asking;
    while (_known.length > _keep) {
      _settled.remove(_known.keys.first);
      _known.remove(_known.keys.first);
    }
    return asking;
  }

  /// The words, and whether the answer is worth keeping — no, when LRCLIB
  /// couldn't be reached to give one.
  Future<(Lyrics?, bool)> _ask(
    String artist,
    String title,
    String album,
    Duration duration,
  ) async {
    if (title.trim().isEmpty) return (null, true);
    // The exact record first, which LRCLIB matches on all four; then a
    // search, for a title with "- Remastered" on it or an album it files
    // under another name.
    if (duration > Duration.zero && album.isNotEmpty) {
      try {
        final r = await _dio.get(
          '$_base/get',
          queryParameters: {
            'artist_name': artist,
            'track_name': title,
            'album_name': album,
            'duration': (duration.inMilliseconds / 1000).round(),
          },
        );
        if (r.data is Map) {
          final l = lyricsFromRecord(r.data as Map);
          if (l != null) return (l, true);
        }
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) {
          debugPrint('Lyrics: LRCLIB get failed: ${e.message}');
        }
      } catch (e) {
        debugPrint('Lyrics: $e');
      }
    }
    try {
      final song = plainTitle(title);
      final r = await _dio.get(
        '$_base/search',
        queryParameters: {
          'track_name': song,
          'artist_name': firstArtist(artist),
        },
      );
      if (r.data is List) {
        final best = bestRecord(
          r.data as List,
          artist: artist,
          title: song,
          duration: duration,
        );
        if (best != null) return (lyricsFromRecord(best), true);
      }
    } catch (e) {
      debugPrint('Lyrics: LRCLIB search failed: $e');
      return (null, false);
    }
    return (null, true);
  }
}

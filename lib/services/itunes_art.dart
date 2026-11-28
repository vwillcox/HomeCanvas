import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Whether two names are of the same song or album: alike once case and
/// punctuation are gone, or one the other with a subtitle or "(Remastered)"
/// after it. Letters of any alphabet count, so a title in Japanese matches
/// itself rather than reducing to nothing.
bool sameName(String a, String b) {
  String plain(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N} ]+', unicode: true), ' ')
      .trim()
      .replaceAll(RegExp(r' +'), ' ');
  final x = plain(a), y = plain(b);
  if (x.isEmpty || y.isEmpty) return false;
  return x == y || x.startsWith('$y ') || y.startsWith('$x ');
}

/// A song's cover from the iTunes Search API, at 600 px; null when iTunes
/// has no such song.
///
/// Only a result by the same artist and of the same song. The artist alone
/// is not enough: a film score's cues share their names with half of
/// iTunes, and the composer's best-known album came back for a cue from
/// another score entirely.
Future<String?> itunesSongArt(
  Dio dio, {
  required String artist,
  required String song,
}) async {
  try {
    final r = await dio.get(
      'https://itunes.apple.com/search',
      queryParameters: {
        'term': '$artist $song'.trim(),
        'entity': 'song',
        'limit': 5,
      },
      options: Options(
        // iTunes answers as text/javascript, which Dio leaves undecoded.
        responseType: ResponseType.plain,
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final body = jsonDecode(r.data as String) as Map<String, dynamic>;
    final first = artist.toLowerCase().split(' ').first;
    for (final item in (body['results'] as List?) ?? const []) {
      if (item is! Map) continue;
      final by = '${item['artistName'] ?? ''}'.toLowerCase();
      if (artist.isNotEmpty && !by.contains(first)) continue;
      if (!sameName('${item['trackName'] ?? ''}', song)) continue;
      final url = '${item['artworkUrl100'] ?? ''}';
      if (url.isNotEmpty) return url.replaceAll('100x100bb', '600x600bb');
    }
  } catch (e) {
    debugPrint('Artwork lookup failed: $e');
  }
  return null;
}

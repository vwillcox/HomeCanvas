import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Turns an HLS playlist of fragmented MP4 into mpv's own list of the same
/// fragments, so that ffmpeg's HLS reader is never used for it.
///
/// ffmpeg's reader has a fault with some streams: started anywhere but the
/// beginning — by a seek, or a playlist that starts later — it misreads the
/// picture ("Invalid NAL unit size") and gives up, so the picture froze
/// while the sound carried on. Nebula's recording of a livestream did it on
/// every seek past what had been downloaded. The fragments themselves are
/// sound: each decodes perfectly with the stream's setup file in front of it.
///
/// mpv's EDL has a mode for exactly that — `!mp4_dash`, the setup file once,
/// then every fragment with its length — which is how mpv's own YouTube
/// support plays fragmented streams. mpv knows where each fragment starts,
/// so a seek opens the right one: 1.8 seconds to anywhere in the video,
/// against a frozen picture.
///
/// Only for playlists it can describe exactly: a finished video (not live),
/// fragmented MP4 (with an `EXT-X-MAP` setup file), and not encrypted —
/// Floatplane's encrypted streams are left to ffmpeg, which fetches their
/// keys and has not shown the fault.
class HlsEdl {
  HlsEdl._();

  /// The EDL for [playlist], fetched from [url]; null when it is not a
  /// playlist this can describe.
  @visibleForTesting
  static String? fromPlaylist(String playlist, Uri url) {
    final lines = const LineSplitter().convert(playlist);
    if (lines.isEmpty || lines.first.trim() != '#EXTM3U') return null;
    if (!lines.any((l) => l.startsWith('#EXT-X-ENDLIST'))) return null;
    if (lines.any((l) => l.startsWith('#EXT-X-KEY') && !l.contains('NONE'))) {
      return null;
    }
    // A master playlist lists other playlists, not fragments.
    if (lines.any((l) => l.startsWith('#EXT-X-STREAM-INF'))) return null;

    String? init;
    String? length;
    final parts = <String>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('#EXT-X-MAP:')) {
        // A second setup file part-way through is a change of stream that
        // one EDL header cannot describe.
        if (init != null) return null;
        final m = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (m == null || line.contains('BYTERANGE')) return null;
        init = url.resolve(m.group(1)!).toString();
      } else if (line.startsWith('#EXT-X-BYTERANGE')) {
        return null;
      } else if (line.startsWith('#EXTINF:')) {
        length = line.substring(8).split(',').first.trim();
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        if (length == null || double.tryParse(length) == null) return null;
        parts.add('${escape(url.resolve(line).toString())},length=$length');
        length = null;
      }
    }
    if (init == null || parts.isEmpty) return null;
    return 'edl://!mp4_dash,init=${escape(init)};${parts.join(';')}';
  }

  /// An address in EDL: prefixed with its length, so the `,` `;` and `%`
  /// that streaming addresses are full of need no escaping.
  static String escape(String url) => '%${utf8.encode(url).length}%$url';

  /// [url]'s playlist as an EDL, or [url] itself when it cannot be — not
  /// HLS, not fragmented MP4, or unreachable.
  static Future<String> resolve(String url,
      {Map<String, String> headers = const {}}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.scheme.startsWith('http')) return url;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(uri);
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return url;
      // A playlist, not a video: a few hundred kilobytes at most. Anything
      // bigger is not what this is for.
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in res) {
        bytes.add(chunk);
        if (bytes.length > 2 * 1024 * 1024) return url;
      }
      return fromPlaylist(
              utf8.decode(bytes.takeBytes(), allowMalformed: true), uri) ??
          url;
    } catch (e) {
      debugPrint('Video: could not read the playlist, leaving it to ffmpeg: '
          '$e');
      return url;
    } finally {
      client.close();
    }
  }
}

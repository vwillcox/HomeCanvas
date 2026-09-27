import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'yt_dlp.dart';

/// A video, resolved to something mpv can play.
@immutable
class VideoStream {
  const VideoStream({
    required this.title,
    required this.channel,
    required this.uri,
    this.headers = const {},
    this.duration,
    this.isLive = false,
    this.cookiesFile,
    this.hevc = false,
    this.audioUri,
    this.hls = false,
  });

  final String title;
  final String channel;

  /// The picture — and the sound too, when they come as one. YouTube's
  /// separate picture and sound are joined here into an `edl://`; an HLS
  /// stream's picture may be an `edl://` of its fragments — see `HlsEdl`.
  final String uri;
  final Map<String, String> headers;
  final Duration? duration;
  final bool isLive;

  /// The signed-in cookies mpv needs as well as yt-dlp, when there are some.
  /// Floatplane's streams are encrypted, and the key comes from floatplane.com
  /// only to the account: without its cookie mpv fetches an error page for a
  /// key and reports the video as a file it does not recognise.
  final String? cookiesFile;

  /// The picture is HEVC, which the Pi 5 decodes in hardware — see
  /// [YtDlp.hevcDecoder].
  final bool hevc;

  /// The sound, when it is a separate HLS stream from the picture — as
  /// Nebula's are. Given to mpv as an external audio track rather than joined
  /// to the picture: mpv's own YouTube support does the same, and for good
  /// reason — a livestream recording joined that way played at a twentieth
  /// of real time, while each half played at full speed alone.
  final String? audioUri;

  /// Delivered as HLS, and so worth offering to `HlsEdl`.
  final bool hls;

  VideoStream copyWith({String? uri, String? audioUri, String? cookiesFile}) =>
      VideoStream(
        title: title,
        channel: channel,
        uri: uri ?? this.uri,
        headers: headers,
        duration: duration,
        isLive: isLive,
        cookiesFile: cookiesFile ?? this.cookiesFile,
        hevc: hevc,
        audioUri: audioUri ?? this.audioUri,
        hls: hls,
      );

  /// Readies [player] for this stream, before it opens it: its cookies, and
  /// the hardware decoder when the picture is HEVC.
  ///
  /// `drm-copy` decodes on the Pi's HEVC block and copies each frame back to
  /// memory, which the software drawing path needs — plain `drm` hands over
  /// surfaces it cannot read, the solid blue picture of old. Measured on
  /// 10-bit 1080p HEVC: 2.8s of CPU per 10s of video, against 15.7s decoding
  /// it in software. Everything else is decoded in software, as before.
  Future<void> prepare(Player player) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final file = cookiesFile;
    try {
      await platform.setProperty('cookies', file == null ? 'no' : 'yes');
      if (file != null) await platform.setProperty('cookies-file', file);
      // The audio track list outlives a file, so it is emptied every time.
      await platform.command(['change-list', 'audio-files', 'clr', '']);
      final audio = audioUri;
      if (audio != null) {
        // "append" takes the address whole; setting the list outright would
        // split it at every colon, as a list of paths.
        await platform.command(['change-list', 'audio-files', 'append', audio]);
      }
      await platform.setProperty(
          'hwdec', hevc && YtDlp.hevcDecoder ? 'drm-copy' : 'no');
    } catch (e) {
      debugPrint('Video: mpv would not take the stream settings: $e');
    }
  }

  /// From yt-dlp's `-J` output, or null when it names nothing playable.
  static VideoStream? fromInfo(Map<String, dynamic> info) {
    var headers = info['http_headers'];
    String? uri;
    String? audioUri;
    final formats = [
      ...?(info['requested_formats'] as List?)?.whereType<Map>(),
    ];
    final hls = [...formats, info]
        .any((f) => '${f['protocol'] ?? ''}'.contains('m3u8'));
    if (formats.isNotEmpty) {
      final urls = formats.map((f) => f['url']).whereType<String>().toList();
      if (urls.isEmpty) return null;
      if (urls.length == 2 && hls) {
        uri = urls.first;
        audioUri = urls.last;
      } else {
        uri = urls.length == 1 ? urls.single : edl(urls);
      }
      headers = formats.first['http_headers'] ?? headers;
    } else {
      uri = info['url'] as String?;
    }
    if (uri == null || uri.isEmpty) return null;
    final seconds = (info['duration'] as num?)?.toDouble();
    final vcodec =
        '${formats.firstOrNull?['vcodec'] ?? info['vcodec'] ?? ''}';
    return VideoStream(
      title: info['title'] as String? ?? 'Video',
      channel: (info['channel'] ?? info['uploader'] ?? '') as String,
      uri: uri,
      headers: headers is Map
          ? {
              for (final e in headers.entries)
                if (e.value is String) '${e.key}': e.value as String,
            }
          : const {},
      duration: seconds == null
          ? null
          : Duration(milliseconds: (seconds * 1000).round()),
      isLive: info['is_live'] == true,
      audioUri: audioUri,
      hls: hls,
      hevc: const ['hvc1', 'hev1', 'hevc', 'h265'].any(vcodec.startsWith),
    );
  }

  /// Several streams as one, the way mpv's own YouTube support joins them.
  ///
  /// Each address is prefixed with its length, so the `;` and `%` that
  /// streaming addresses are full of need no escaping.
  static String edl(List<String> urls) => 'edl://${urls.map(
        (u) => '!new_stream;!no_clip;!no_chapters;%${utf8.encode(u).length}%$u',
      ).join(';')}';
}

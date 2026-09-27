import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/hls_edl.dart';
import 'package:home_canvas/services/video_stream.dart';

void main() {
  final url = Uri.parse('https://starlight.nebula.tv/tok/stream/chunk.m3u8');
  const base = 'https://starlight.nebula.tv/tok/stream/';
  String esc(String u) => HlsEdl.escape(u);

  // A playlist as Nebula serves it: fragmented MP4, finished, not encrypted.
  const nebula = '#EXTM3U\n'
      '#EXT-X-VERSION:6\n'
      '#EXT-X-PLAYLIST-TYPE:VOD\n'
      '#EXT-X-TARGETDURATION:7\n'
      '#EXT-X-MAP:URI="init.mp4"\n'
      '#EXTINF:6.006,\n'
      'seg-1.m4s\n'
      '#EXTINF:4.2,\n'
      'seg-2.m4s\n'
      '#EXT-X-ENDLIST\n';

  test('lists the setup file once and every fragment with its length', () {
    expect(
      HlsEdl.fromPlaylist(nebula, url),
      'edl://!mp4_dash,init=${esc('${base}init.mp4')};'
      '${esc('${base}seg-1.m4s')},length=6.006;'
      '${esc('${base}seg-2.m4s')},length=4.2',
    );
  });

  test('keeps addresses whole, however many commas and semicolons', () {
    const odd = 'https://cdn/a;b,c%d.m4s';
    expect(HlsEdl.escape(odd), '%${odd.length}%$odd');
  });

  test('leaves alone what it cannot describe exactly', () {
    String without(String line) => nebula.replaceFirst(line, '');
    for (final (why, playlist) in [
      ('still live', without('#EXT-X-ENDLIST\n')),
      ('not fragmented MP4', without('#EXT-X-MAP:URI="init.mp4"\n')),
      ('encrypted',
          nebula.replaceFirst('#EXTINF:6.006',
              '#EXT-X-KEY:METHOD=AES-128,URI="https://k"\n#EXTINF:6.006')),
      ('byte ranges', nebula.replaceFirst('seg-1', '#EXT-X-BYTERANGE:10@0\nseg-1')),
      ('a master playlist', '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nv.m3u8\n'),
      ('not a playlist', '<html>'),
    ]) {
      expect(HlsEdl.fromPlaylist(playlist, url), isNull, reason: why);
    }
  });

  test('HLS picture and sound are kept apart, not joined', () {
    final s = VideoStream.fromInfo({
      'title': 't',
      'requested_formats': [
        {'url': 'https://v/chunk.m3u8', 'protocol': 'm3u8_native', 'vcodec': 'avc1'},
        {'url': 'https://a/chunk.m3u8', 'protocol': 'm3u8_native', 'vcodec': 'none'},
      ],
    })!;
    expect(s.uri, 'https://v/chunk.m3u8');
    expect(s.audioUri, 'https://a/chunk.m3u8');
    expect(s.hls, isTrue);

    final youtube = VideoStream.fromInfo({
      'title': 't',
      'requested_formats': [
        {'url': 'https://v', 'protocol': 'https'},
        {'url': 'https://a', 'protocol': 'https'},
      ],
    })!;
    expect(youtube.uri, startsWith('edl://'));
    expect(youtube.audioUri, isNull);
    expect(youtube.hls, isFalse);
  });
}

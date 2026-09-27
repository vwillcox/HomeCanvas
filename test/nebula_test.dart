import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/nebula_site.dart';
import 'package:home_canvas/services/video_link.dart';
import 'package:home_canvas/services/video_stream.dart';
import 'package:home_canvas/services/yt_dlp.dart';

void main() {
  test('reads a Nebula video link, under any of its names', () {
    const slug = 'realengineering-the-unconventional-engineering-of-the-x59';
    for (final url in [
      'https://nebula.tv/videos/$slug',
      'https://nebula.tv/videos/$slug/',
      'https://www.nebula.tv/videos/$slug?ref=share',
      'https://nebula.app/videos/$slug',
      'https://watchnebula.com/videos/$slug',
    ]) {
      expect(NebulaLink.parse(url)?.id, slug, reason: url);
    }
    expect(NebulaLink.parse('https://nebula.tv/realengineering'), isNull);
    expect(NebulaLink.parse('https://nebula.tv/myshows'), isNull);
    expect(VideoLink.parse('https://nebula.tv/videos/$slug')?.site, 'nebula');
    expect(const NebulaLink('abc').url, 'https://nebula.tv/videos/abc');
  });

  test('turns the feed into videos, as yt-dlp lists them', () {
    // An entry as yt-dlp's Nebula extractor gives it, cut down.
    final videos = NebulaSite.feedFromInfo({
      'entries': [
        {
          '_type': 'url_transparent',
          'display_id':
              'realengineering-the-unconventional-engineering-of-the-x59',
          'title': 'The Unconventional Engineering of the X-59',
          'channel': 'Real Engineering',
          'thumbnail': 'https://images.nebula.tv/4e8fe810',
          'timestamp': 1790434803,
          'duration': 1087,
          'url': 'https://nebula.tv/videos/realengineering-the-uncon'
              'ventional-engineering-of-the-x59/#__youtubedl_smuggle=%7B',
        },
        {'title': 'no slug'},
      ],
    });
    final v = videos.single;
    expect(v.link.id,
        'realengineering-the-unconventional-engineering-of-the-x59');
    expect(v.link.thumbnailUrl, 'https://images.nebula.tv/4e8fe810');
    expect(v.title, 'The Unconventional Engineering of the X-59');
    expect(v.channel, 'Real Engineering');
    expect(v.duration, const Duration(seconds: 1087));
    expect(v.released,
        DateTime.fromMillisecondsSinceEpoch(1790434803000, isUtc: true));
    expect(NebulaSite.feedFromInfo({}), isEmpty);
  });

  test('knows Nebula turning the account away from other failures', () {
    // Signed out, Nebula's feed answers a bare 400.
    expect(
        NebulaSite.refused('myshows: Unable to download JSON metadata: '
            'HTTP Error 400: Bad Request'),
        isTrue);
    expect(NebulaSite.refused('HTTP Error 403: Forbidden'), isTrue);
    expect(NebulaSite.refused('Unable to download webpage: '
        '<urlopen error [Errno -3] Temporary failure in name resolution>'),
        isFalse);
  });

  group('HEVC', () {
    test('a stream says whether its picture is HEVC', () {
      VideoStream stream(String vcodec) => VideoStream.fromInfo({
            'title': 't',
            'requested_formats': [
              {'url': 'https://v/1', 'vcodec': vcodec},
              {'url': 'https://a/1', 'vcodec': 'none'},
            ],
          })!;
      expect(stream('hvc1.2.4.L123').hevc, isTrue);
      expect(stream('hev1.1.6.L120').hevc, isTrue);
      expect(stream('avc1.640029').hevc, isFalse);
      expect(
          VideoStream.fromInfo({'url': 'https://v', 'vcodec': 'avc1'})!.hevc,
          isFalse);
    });

    test('is asked for first only where it can be decoded in hardware, and '
        'only up to 30 frames a second', () {
      expect(
          YtDlp.streamArgs(1080, hevc: true),
          containsAllInOrder([
            '-f',
            'bv*[vcodec^=hvc1][fps<=30]+ba/bv*[vcodec^=hev1][fps<=30]+ba/'
                'bv*+ba/b',
          ]));
      expect(YtDlp.streamArgs(1080),
          containsAllInOrder(['-f', 'bv*+ba/b']));
      expect(YtDlp.streamArgs(1080, hevc: true),
          containsAllInOrder(['-S', 'vcodec:h264,res:1080,fps,acodec:m4a']));
    });
  });
}

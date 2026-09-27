import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/youtube_link.dart';
import 'package:home_canvas/services/youtube_service.dart';

void main() {
  group('YouTubeLink.parse', () {
    const id = 'aqz-KE-bpKQ';

    test('reads every shape a video link arrives in', () {
      for (final url in [
        'https://www.youtube.com/watch?v=$id',
        'https://youtube.com/watch?v=$id&list=PL123&index=2',
        'https://m.youtube.com/watch?v=$id',
        'https://music.youtube.com/watch?v=$id&feature=share',
        'https://youtu.be/$id?si=AbCdEf123',
        'https://www.youtube.com/shorts/$id',
        'https://www.youtube.com/live/$id?si=x',
        'https://www.youtube.com/embed/$id',
        'https://www.youtube-nocookie.com/embed/$id',
        '  https://youtu.be/$id  ',
      ]) {
        expect(YouTubeLink.parse(url)?.id, id, reason: url);
      }
    });

    test('is not fooled by other sites or other YouTube pages', () {
      for (final url in [
        'https://www.bbc.co.uk/news/articles/c1234',
        'https://www.youtube.com/@blender',
        'https://www.youtube.com/feed/subscriptions',
        'https://www.youtube.com/watch?v=short',
        'https://notyoutube.com/watch?v=$id',
        'youtube.com/watch?v=$id',
        'not a link',
      ]) {
        expect(YouTubeLink.parse(url), isNull, reason: url);
      }
    });

    test('starts where the link says', () {
      expect(YouTubeLink.parse('https://youtu.be/$id?t=90')!.start,
          const Duration(seconds: 90));
      expect(YouTubeLink.parse('https://www.youtube.com/watch?v=$id&t=1m30s')!
          .start, const Duration(seconds: 90));
      expect(YouTubeLink.parse('https://www.youtube.com/embed/$id?start=42')!
          .start, const Duration(seconds: 42));
      expect(YouTubeLink.parse('https://youtu.be/$id')!.start, Duration.zero);
    });

    test('reads YouTube time stamps', () {
      expect(YouTubeLink.parseTime('75s'), const Duration(seconds: 75));
      expect(YouTubeLink.parseTime('1h2m3s'),
          const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(YouTubeLink.parseTime('rubbish'), Duration.zero);
      expect(YouTubeLink.parseTime(null), Duration.zero);
    });

    test('drops the tracking from what it hands on', () {
      expect(YouTubeLink.parse('https://youtu.be/$id?si=tracking')!.watchUrl,
          'https://www.youtube.com/watch?v=$id');
    });
  });

  group('YouTubeStream.fromInfo', () {
    test('joins separate picture and sound into one address', () {
      final s = YouTubeStream.fromInfo({
        'title': 'Big Buck Bunny',
        'channel': 'Blender',
        'duration': 634.5,
        'requested_formats': [
          {
            'url': 'https://v.example/video;a=1%2F',
            'http_headers': {'User-Agent': 'UA'},
          },
          {'url': 'https://v.example/audio'},
        ],
      })!;
      expect(s.title, 'Big Buck Bunny');
      expect(s.channel, 'Blender');
      expect(s.duration, const Duration(milliseconds: 634500));
      expect(s.headers, {'User-Agent': 'UA'});
      expect(
        s.uri,
        'edl://!new_stream;!no_clip;!no_chapters;%30%https://v.example/video;a=1%2F;'
        '!new_stream;!no_clip;!no_chapters;%23%https://v.example/audio',
      );
    });

    test('takes a single stream as it is', () {
      final s = YouTubeStream.fromInfo({
        'title': 'Live',
        'uploader': 'Someone',
        'url': 'https://v.example/live.m3u8',
        'is_live': true,
      })!;
      expect(s.uri, 'https://v.example/live.m3u8');
      expect(s.channel, 'Someone');
      expect(s.isLive, isTrue);
      expect(s.duration, isNull);
    });

    test('gives nothing when there is nothing to play', () {
      expect(YouTubeStream.fromInfo({'title': 'x'}), isNull);
      expect(YouTubeStream.fromInfo({'requested_formats': [{}]}), isNull);
    });
  });

  test('a feed keeps only its videos', () {
    final items = YouTubeFeedItem.listFromInfo({
      'entries': [
        {'id': 'aqz-KE-bpKQ', 'title': 'Bunny', 'channel': 'Blender',
            'duration': 634},
        {'id': 'UCsomechannelid', 'title': 'A channel'},
        {'title': 'No id at all'},
      ],
    });
    expect(items.map((i) => i.title), ['Bunny']);
    expect(items.single.duration, const Duration(seconds: 634));
    expect(YouTubeFeedItem.listFromInfo({}), isEmpty);
  });

  group('yt-dlp', () {
    test('is only told about deno when it knows what that means', () {
      expect(YouTubeService.takesJsRuntimes('2025.04.30'), isFalse);
      expect(YouTubeService.takesJsRuntimes('2025.11.12'), isTrue);
      expect(YouTubeService.takesJsRuntimes('2026.08.19'), isTrue);
      expect(YouTubeService.takesJsRuntimes(null), isFalse);
    });

    test('is asked for H.264 at the most frames a second, no taller than the '
        'setting', () {
      final args = YouTubeService.streamArgs(720);
      expect(args,
          containsAllInOrder(['-S', 'vcodec:h264,res:720,fps,acodec:m4a']));
      expect(args, contains('--no-playlist'));
    });

    test('uses the account only when there is one', () {
      expect(YouTubeService.baseArgs(), isNot(contains('--cookies-from-browser')));
      expect(
        YouTubeService.baseArgs(
            deno: '/d', account: ['--cookies-from-browser', 'firefox:/p']),
        containsAllInOrder(
            ['--js-runtimes', 'deno:/d', '--cookies-from-browser', 'firefox:/p']),
      );
    });

    test('keeps only YouTube and Google cookies from an upload', () {
      const upload = '# Netscape HTTP Cookie File\n'
          '.youtube.com\tTRUE\t/\tTRUE\t1893456000\tPREF\tf6=40000000\n'
          '#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t1893456000\tLOGIN_INFO\tabc\n'
          '.google.com\tTRUE\t/\tTRUE\t1893456000\tSAPISID\txyz\n'
          'accounts.google.com\tFALSE\t/\tTRUE\t1893456000\tLSID\tq\n'
          '.bank.example\tTRUE\t/\tTRUE\t1893456000\tsession\tsecret\n'
          '.notyoutube.com\tTRUE\t/\tTRUE\t1893456000\tid\tnope\n'
          '# a comment\n'
          'garbage line\n';
      final kept = YouTubeService.filterCookies(upload)!;
      expect(kept, contains('PREF'));
      expect(kept, contains('#HttpOnly_.youtube.com'));
      expect(kept, contains('SAPISID'));
      expect(kept, contains('LSID'));
      expect(kept, isNot(contains('bank.example')));
      expect(kept, isNot(contains('notyoutube')));
      expect(kept, startsWith('# Netscape HTTP Cookie File'));
    });

    test('refuses an upload with no YouTube cookies in it', () {
      expect(YouTubeService.filterCookies(''), isNull);
      expect(YouTubeService.filterCookies('not a cookie file at all'), isNull);
      expect(
          YouTubeService.filterCookies(
              '.example.com\tTRUE\t/\tTRUE\t0\tid\t1\n'),
          isNull);
    });

    test('knows "sign in first" from any other failure', () {
      expect(
          YouTubeService.wantsSignIn(
              'This feed is only available when logged in. Use '
              '--cookies-from-browser or --cookies for the authentication.'),
          isTrue);
      expect(YouTubeService.wantsSignIn('Unable to download webpage: '
          'network is unreachable'), isFalse);
      expect(YouTubeService.wantsSignIn('YouTube took too long to answer.'),
          isFalse);
    });

    test('its complaints are cut down to the point', () {
      expect(
        YouTubeService.explain('WARNING: meh\n'
            'ERROR: [youtube] aqz-KE-bpKQ: Video unavailable. This video is private\n'),
        'Video unavailable. This video is private',
      );
      expect(
        YouTubeService.explain(
            'ERROR: [youtube] aqz-KE-bpKQ: Sign in to confirm your age.'),
        contains('Signing in to YouTube in Settings'),
      );
      expect(YouTubeService.explain(''), 'YouTube would not play this video.');
    });
  });
}

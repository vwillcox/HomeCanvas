import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/widgets/video_grid.dart';
import 'package:home_canvas/services/cookie_file.dart';
import 'package:home_canvas/services/floatplane_site.dart';
import 'package:home_canvas/services/video_link.dart';

void main() {
  group('links', () {
    test('reads a Floatplane post link', () {
      for (final url in [
        'https://www.floatplane.com/post/AbC123xyz',
        'https://floatplane.com/post/AbC123xyz?utm=share',
        'https://beta.floatplane.com/post/AbC123xyz',
      ]) {
        expect(FloatplaneLink.parse(url)?.id, 'AbC123xyz', reason: url);
      }
      expect(FloatplaneLink.parse('https://www.floatplane.com/channel/x/home'),
          isNull);
      expect(FloatplaneLink.parse('https://notfloatplane.com/post/x'), isNull);
    });

    test('any link goes to the right site', () {
      expect(VideoLink.parse('https://youtu.be/aqz-KE-bpKQ')?.site, 'youtube');
      expect(VideoLink.parse('https://www.floatplane.com/post/AbC')?.site,
          'floatplane');
      expect(VideoLink.parse('https://www.bbc.co.uk/news'), isNull);
    });

    test('a post is played from its page', () {
      expect(const FloatplaneLink('AbC').url,
          'https://www.floatplane.com/post/AbC');
    });
  });

  group('cookie files', () {
    const file = '# Netscape HTTP Cookie File\n'
        '#HttpOnly_.floatplane.com\tTRUE\t/\tTRUE\t1893456000\tsails.sid\ts%3Aabc\n'
        'www.floatplane.com\tFALSE\t/\tFALSE\t1893456000\tpref\tdark\n'
        '.youtube.com\tTRUE\t/\tTRUE\t1893456000\tPREF\tx\n';

    test('keeps one site, and insists on the cookie its sign-in rests on', () {
      final kept =
          CookieFile.filter(file, ['floatplane.com'], mustHave: 'sails.sid')!;
      expect(kept, contains('sails.sid'));
      expect(kept, contains('pref'));
      expect(kept, isNot(contains('youtube')));
      expect(
          CookieFile.filter(
              'www.floatplane.com\tFALSE\t/\tFALSE\t0\tpref\tdark\n',
              ['floatplane.com'],
              mustHave: 'sails.sid'),
          isNull,
          reason: 'Floatplane cookies, but not the sign-in');
    });

    test('reads a cookie, HttpOnly or not', () {
      expect(CookieFile.value(file, 'sails.sid'), 's%3Aabc');
      expect(CookieFile.value(file, 'pref'), 'dark');
      expect(CookieFile.value(file, 'missing'), isNull);
    });
  });

  group('the feed', () {
    Map<String, Object?> post(String id,
            {bool video = true, String date = '2026-09-26T10:00:00.000Z'}) =>
        {
          'id': id,
          'title': 'Post $id',
          'releaseDate': date,
          'creator': {'id': 'c1', 'title': 'Linus Tech Tips'},
          'metadata': {'hasVideo': video, 'videoDuration': 754.2},
          'thumbnail': {
            'width': 1920,
            'height': 1080,
            'path': 'https://pbs.floatplane.com/big.jpeg',
            'childImages': [
              {'width': 400, 'height': 225, 'path': 'https://pbs.floatplane.com/400.jpeg'},
              {'width': 1280, 'height': 720, 'path': 'https://pbs.floatplane.com/1280.jpeg'},
            ],
          },
        };

    test('keeps the video posts, newest first', () {
      final posts = FloatplaneSite.feedFromApi({
        'blogPosts': [
          post('older', date: '2026-09-20T10:00:00.000Z'),
          post('text only', video: false),
          post('newer', date: '2026-09-27T09:00:00.000Z'),
        ],
        'lastElements': [],
      });
      expect(posts.map((p) => p.link.id), ['newer', 'older']);
      final p = posts.first;
      expect(p.title, 'Post newer');
      expect(p.channel, 'Linus Tech Tips');
      expect(p.duration, const Duration(seconds: 754));
      expect(p.released, DateTime.utc(2026, 9, 27, 9));
    });

    test('shows the smallest thumbnail still sharp on a tile', () {
      final p = FloatplaneSite.feedFromApi({'blogPosts': [post('a')]}).single;
      expect(p.link.thumbnailUrl, 'https://pbs.floatplane.com/400.jpeg');
    });

    test('copes with a reply that is not a feed', () {
      expect(FloatplaneSite.feedFromApi(null), isEmpty);
      expect(FloatplaneSite.feedFromApi({'blogPosts': 'nope'}), isEmpty);
      expect(FloatplaneSite.feedFromApi({'blogPosts': [{'title': 'no id'}]}),
          isEmpty);
    });
  });

  test('says how long ago a video went up', () {
    final now = DateTime(2026, 9, 27, 12);
    expect(releasedAgo(now.subtract(const Duration(minutes: 5)), now),
        '5 min ago');
    expect(releasedAgo(now.subtract(const Duration(hours: 3)), now), '3 h ago');
    expect(releasedAgo(now.subtract(const Duration(days: 2)), now), '2 d ago');
    expect(releasedAgo(DateTime(2026, 3, 12), now), '12 Mar');
  });
}

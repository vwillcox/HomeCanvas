import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/models/immich_models.dart';
import 'package:home_canvas/screens/album_screen.dart';
import 'package:home_canvas/screens/home_screen.dart';
import 'package:home_canvas/widgets/glass.dart';

Album album(String name, int count, {DateTime? updated, String? cover = 'c'}) =>
    Album(
      id: name,
      name: name,
      assetCount: count,
      thumbnailAssetId: cover,
      updatedAt: updated,
    );

Asset photo(String id, String? localDateTime) => Asset.fromJson({
  'id': id,
  'type': 'IMAGE',
  'localDateTime': ?localDateTime,
});

void main() {
  group('sorting the albums', () {
    final a = album('Comics', 122, updated: DateTime(2026, 9, 1));
    final b = album('beach', 3, updated: DateTime(2026, 9, 20));
    final c = album('Screenshots', 272, updated: DateTime(2025, 1, 1));
    final d = album('Undated', 5);

    test('recent: newest first, never-updated last', () {
      expect(sortAlbums([a, b, c, d], AlbumSort.recent).map((x) => x.name), [
        'beach',
        'Comics',
        'Screenshots',
        'Undated',
      ]);
    });

    test('A–Z ignores case', () {
      expect(sortAlbums([a, b, c], AlbumSort.name).map((x) => x.name), [
        'beach',
        'Comics',
        'Screenshots',
      ]);
    });

    test('most items first', () {
      expect(sortAlbums([a, b, c], AlbumSort.size).map((x) => x.name), [
        'Screenshots',
        'Comics',
        'beach',
      ]);
    });

    test("ties keep Immich's own order", () {
      final x = album('x', 5), y = album('y', 5), z = album('z', 5);
      expect(sortAlbums([y, z, x], AlbumSort.size).map((e) => e.name), [
        'y',
        'z',
        'x',
      ]);
    });

    test('does not reorder the list it was given', () {
      final list = [a, b, c];
      sortAlbums(list, AlbumSort.name);
      expect(list, [a, b, c]);
    });
  });

  group('which albums are shown', () {
    test('empty albums are left out', () {
      final shown = visibleAlbums([
        album('Family', 683),
        album('3D Converted', 0),
        album('Download', 2),
      ]);
      expect(shown.map((a) => a.name), ['Family', 'Download']);
    });

    test('an album with a single photo still counts', () {
      expect(visibleAlbums([album('DCIM', 1)]), hasLength(1));
    });

    test('a library of only empty albums shows nothing', () {
      expect(visibleAlbums([album('a', 0), album('b', 0)]), isEmpty);
    });
  });

  group('when a photo was taken', () {
    test("is read from Immich's localDateTime", () {
      final p = photo('1', '2025-04-11T12:12:16.000Z');
      expect(p.taken!.year, 2025);
      expect(p.taken!.month, 4);
    });

    test('is the camera clock, not shifted by the trailing Z', () {
      // Immich writes wall-clock time with a Z it does not mean. Converted to
      // local time on a machine east of UTC, 23:30 on the 31st would become
      // the 1st of the next month.
      final p = photo('1', '2026-08-31T23:30:00.000Z');
      expect(p.taken!.month, 8);
      expect(p.taken!.day, 31);
    });

    test('is absent when Immich does not say', () {
      expect(photo('1', null).taken, isNull);
    });
  });

  group('grouping an album by month', () {
    test('runs of the same month become one group, in order', () {
      final g = groupByMonth([
        photo('a', '2026-09-20T10:00:00.000Z'),
        photo('b', '2026-09-02T10:00:00.000Z'),
        photo('c', '2026-08-30T10:00:00.000Z'),
      ]);
      expect(g.map((x) => x.label), ['September 2026', 'August 2026']);
      expect([g[0].start, g[0].end, g[1].start, g[1].end], [0, 2, 2, 3]);
    });

    test("the album's own order is kept, even when months repeat", () {
      final g = groupByMonth([
        photo('a', '2026-09-01T10:00:00.000Z'),
        photo('b', '2026-08-01T10:00:00.000Z'),
        photo('c', '2026-09-05T10:00:00.000Z'),
      ]);
      expect(g.map((x) => x.label), [
        'September 2026',
        'August 2026',
        'September 2026',
      ]);
    });

    test('the same month in different years is not merged', () {
      final g = groupByMonth([
        photo('a', '2026-09-01T10:00:00.000Z'),
        photo('b', '2025-09-01T10:00:00.000Z'),
      ]);
      expect(g, hasLength(2));
    });

    test('undated photos form an unlabelled group', () {
      final g = groupByMonth([photo('a', null), photo('b', null)]);
      expect(g.single.label, isNull);
      expect(g.single.end, 2);
    });

    test('every photo lands in exactly one group', () {
      final assets = [
        for (var i = 0; i < 40; i++)
          photo(
            '$i',
            '2026-${(i % 12 + 1).toString().padLeft(2, '0')}-01T00:00:00.000Z',
          ),
      ];
      final g = groupByMonth(assets);
      expect(g.first.start, 0);
      expect(g.last.end, assets.length);
      for (var i = 1; i < g.length; i++) {
        expect(g[i].start, g[i - 1].end);
      }
    });

    test('an empty album has no groups', () {
      expect(groupByMonth(const []), isEmpty);
    });
  });

  group('choosing the headings', () {
    List<Asset> spread(List<String> dates) => [
      for (var i = 0; i < dates.length; i++) photo('$i', dates[i]),
    ];
    String day(int y, int m) =>
        '$y-${m.toString().padLeft(2, '0')}-01T00:00:00.000Z';

    test('full months keep their own headings', () {
      final a = spread([
        for (var i = 0; i < 10; i++) day(2026, 9),
        for (var i = 0; i < 10; i++) day(2026, 8),
      ]);
      expect(groupAssets(a).map((g) => g.label), [
        'September 2026',
        'August 2026',
      ]);
    });

    test('thin months next to each other share a heading', () {
      // The top of the Family album: July, June and May 2026 with two, one
      // and two photos — three headings over five pictures, before.
      final a = spread([
        day(2026, 7),
        day(2026, 7),
        day(2026, 6),
        day(2026, 5),
        day(2026, 5),
        for (var i = 0; i < 10; i++) day(2025, 7),
      ]);
      expect(groupAssets(a).map((g) => g.label), [
        'May – July 2026',
        'July 2025',
      ]);
    });

    test('thin months across years become a span of years', () {
      final a = spread([for (var y = 2024; y >= 2016; y--) day(y, 6)]);
      expect(groupAssets(a).map((g) => g.label).first, '2017 – 2024');
    });

    test('a full month is never swallowed into a range', () {
      final a = spread([
        day(2026, 7),
        for (var i = 0; i < 392; i++) day(2025, 7),
        day(2024, 1),
      ]);
      expect(groupAssets(a).map((g) => g.label), contains('July 2025'));
      final july = groupAssets(a).firstWhere((g) => g.label == 'July 2025');
      expect(july.end - july.start, 392);
    });

    test('undated photos are never given a date by merging', () {
      final a = spread([day(2026, 7), '', '', day(2026, 6)]);
      final g = groupAssets(a);
      expect(g.map((x) => x.label), ['July 2026', null, 'June 2026']);
    });

    test('every photo still lands in exactly one group, in order', () {
      final a = spread([
        for (var i = 0; i < 60; i++) day(2000 + (i * 7) % 26, i % 12 + 1),
      ]);
      final g = groupAssets(a);
      expect(g.first.start, 0);
      expect(g.last.end, a.length);
      for (var i = 1; i < g.length; i++) {
        expect(g[i].start, g[i - 1].end);
      }
    });

    test('a single month is just that month', () {
      expect(
        groupAssets(spread([day(2026, 9)])).single.label,
        'September 2026',
      );
    });
  });

  group('the span an album covers', () {
    test('within a month', () {
      expect(
        dateSpan([
          photo('a', '2024-03-01T00:00:00.000Z'),
          photo('b', '2024-03-20T00:00:00.000Z'),
        ]),
        'March 2024',
      );
    });

    test('across months in one year', () {
      expect(
        dateSpan([
          photo('a', '2024-06-01T00:00:00.000Z'),
          photo('b', '2024-03-20T00:00:00.000Z'),
        ]),
        'March – June 2024',
      );
    });

    test('across years', () {
      expect(
        dateSpan([
          photo('a', '2019-06-01T00:00:00.000Z'),
          photo('b', '2026-03-20T00:00:00.000Z'),
        ]),
        '2019 – 2026',
      );
    });

    test('nothing to say without dates', () {
      expect(dateSpan([photo('a', null)]), isNull);
    });
  });

  group('words', () {
    test('the greeting follows the hour', () {
      expect(greetingFor(DateTime(2026, 9, 24, 7)), 'Good morning');
      expect(greetingFor(DateTime(2026, 9, 24, 12)), 'Good afternoon');
      expect(greetingFor(DateTime(2026, 9, 24, 18)), 'Good evening');
      expect(greetingFor(DateTime(2026, 9, 24, 23)), 'Good night');
      expect(greetingFor(DateTime(2026, 9, 24, 3)), 'Good night');
    });

    test('the date is written out', () {
      expect(longDate(DateTime(2026, 9, 24)), 'Thursday 24 September');
    });

    test('large counts are grouped, and singular is singular', () {
      expect(grouped(1204), '1,204');
      expect(grouped(1000000), '1,000,000');
      expect(grouped(12), '12');
      expect(plural(1, 'item'), '1 item');
      expect(plural(1204, 'item'), '1,204 items');
      expect(plural(2, 'photo'), '2 photos');
    });
  });
}

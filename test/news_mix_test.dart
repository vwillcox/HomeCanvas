import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/news_widget.dart';
import 'package:home_canvas/services/feed_service.dart';
import 'package:home_canvas/services/news_mix.dart';
import 'package:provider/provider.dart';

FeedItem item(String title, {String? summary, String? link}) =>
    FeedItem(title: title, summary: summary, link: link);

/// The other headlines a tile shows at the same time — it is against these
/// that a word counts as rare or common.
final filler = [
  for (final t in const [
    'Council approves new cycle lanes for the town centre',
    'Storm brings flooding to coastal villages overnight',
    'Museum reopens after two-year renovation',
    'School inspectors praise improvement at academy',
    'Hospital waiting lists fall for third month',
    'Bus fares frozen until the spring',
    'Theatre announces pantomime cast for Christmas',
    'Football club appoints new head coach',
    'Bakery wins national award for sourdough',
    'Library extends opening hours at weekends',
    'Planning row over homes on farmland',
    'Charity shop volunteers honoured by mayor',
    'Train operator apologises for weekend cancellations',
    'Farmers warn of poor harvest after dry summer',
    'Zoo welcomes rare red panda cubs',
    'Swimming pool to close for repairs',
    'Police appeal after jewellery stolen in burglary',
    'Festival line-up revealed for next summer',
    'Energy prices expected to rise in January',
    'Parking charges to rise at hospital car parks',
  ])
    item(t),
];

/// [items] and the filler, each from its own feed unless [from] says.
List<NewsStory> storiesOf(List<FeedItem> items, Map<FeedItem, String> from) =>
    sameStories([
      ...items,
      ...filler,
    ], sourceOf: (i) => from[i] ?? 'filler${filler.indexOf(i)}');

void main() {
  tileTests();
  group('NewsSource', () {
    test('reads a settings row', () {
      final s = NewsSource.fromRow({
        'name': ' Gazette ',
        'url': ' https://example.com/news/rss/ ',
        'topic': 'Colchester',
        'only': 'Colchester, Wivenhoe;Tiptree\n, ',
      });
      expect(s.url, 'https://example.com/news/rss/');
      expect(s.name, 'Gazette');
      expect(s.topic, 'Colchester');
      expect(s.only, ['Colchester', 'Wivenhoe', 'Tiptree']);
    });

    test('keeps everything when it names no places', () {
      const s = NewsSource(url: 'u');
      expect(s.keeps(item('Anything at all')), isTrue);
    });

    test('keeps a headline naming a place, whole words only', () {
      final s = NewsSource(
        url: 'u',
        only: NewsSource.words('Colchester, West Bergholt, Mersea'),
      );
      expect(s.keeps(item('Colchester council approves budget')), isTrue);
      expect(s.keeps(item('Bridge closure on MERSEA island')), isTrue);
      expect(s.keeps(item('Road shut in Chelmsford')), isFalse);
      // Not a word of its own.
      expect(s.keeps(item('Colchesterian society meets')), isFalse);
    });

    test('looks in the summary and the address too', () {
      final s = NewsSource(
        url: 'u',
        only: NewsSource.words('Tiptree, West Bergholt'),
      );
      expect(
        s.keeps(
          item(
            'Café owner shortlisted for award',
            summary: 'A Tiptree café owner has been shortlisted…',
          ),
        ),
        isTrue,
      );
      expect(
        s.keeps(
          item(
            'Man jailed after break-in',
            link: 'https://example.com/news/123.west-bergholt-man-jailed/',
          ),
        ),
        isTrue,
      );
      expect(
        s.keeps(
          item(
            'Man jailed after break-in',
            link: 'https://example.com/news/123.harlow-man-jailed/',
          ),
        ),
        isFalse,
      );
    });

    test('the Colchester places narrow a county feed', () {
      final s = NewsSource(url: 'u', only: NewsSource.words(colchesterPlaces));
      expect(s.keeps(item('Lexden roadworks to start in March')), isTrue);
      expect(s.keeps(item('University of Essex fireworks return')), isTrue);
      expect(s.keeps(item('Delays on the M25 after crash')), isFalse);
    });
  });

  group('newsTabs', () {
    test('a tab per topic, in the order first listed, and per lone feed', () {
      const a = NewsSource(url: 'a', name: 'Alpha', topic: 'Tech');
      const b = NewsSource(url: 'b', name: 'Beta', topic: 'UK');
      const c = NewsSource(url: 'c', name: 'Gamma');
      const d = NewsSource(url: 'd', name: 'Delta', topic: 'tech');
      final tabs = newsTabs([a, b, c, d]);
      expect([for (final t in tabs) t.name], ['Tech', 'UK', 'Gamma']);
      expect([for (final s in tabs.first.sources) s.url], ['a', 'd']);
      expect(tabs.first.isTopic, isTrue);
      expect(tabs.last.isTopic, isFalse);
    });

    test('feeds with no topics keep a tab each, as before', () {
      final tabs = newsTabs(const [
        NewsSource(url: 'a', name: 'A'),
        NewsSource(url: 'b', name: 'B'),
      ]);
      expect([for (final t in tabs) t.name], ['A', 'B']);
    });
  });

  group('sameStories', () {
    test('tells the same story from several feeds once', () {
      final one = item('Harbour Rail to cut thousands of jobs to save costs');
      final two = item('Harbour Rail cutting thousands of jobs in cost drive');
      final three = item('Thousands of Harbour Rail jobs to go, union warns');
      final other = item('Snow expected across the north this weekend');
      final from = Map<FeedItem, String>.identity()
        ..addAll({one: 'sky', two: 'bbc', three: 'guardian', other: 'bbc'});
      final stories = storiesOf([one, other, two, three], from);
      expect(stories.length, 2 + filler.length);
      expect(stories.first.item, same(one));
      expect(stories.first.also, [same(two), same(three)]);
      expect(stories[1].item, same(other));
      expect(stories[1].also, isEmpty);
    });

    test('never merges within one feed', () {
      final one = item('Delays of an hour on the A12 after serious crash');
      final two = item(
        'Recap: an hour of delays on the A12 after serious crash',
      );
      final same = Map<FeedItem, String>.identity()
        ..addAll({one: 'gazette', two: 'gazette'});
      expect(storiesOf([one, two], same).length, 2 + filler.length);
      // From two papers, the same pair is one story.
      final apart = Map<FeedItem, String>.identity()
        ..addAll({one: 'gazette', two: 'bbc'});
      expect(storiesOf([one, two], apart).length, 1 + filler.length);
    });

    test('one telling per outlet', () {
      final one = item('Harbour Rail to cut thousands of jobs to save costs');
      final two = item('Harbour Rail cutting thousands of jobs in cost drive');
      final three = item(
        'Harbour Rail jobs: thousands to be cut in cost drive',
      );
      final from = Map<FeedItem, String>.identity()
        ..addAll({one: 'sky', two: 'bbc', three: 'bbc'});
      final stories = storiesOf([one, two, three], from);
      expect(stories.first.also, [same(two)]);
      expect(stories.length, 2 + filler.length);
    });

    test('words every headline has do not make one story', () {
      // "Essex" and "police" are in everything here; the stories differ.
      final items = [
        item('Essex police appeal after shop break-in at Lexden'),
        item('Essex police praise volunteers at station awards'),
        item('Essex police warn of phone scam targeting pensioners'),
        item('Essex police recover stolen tractor from field'),
      ];
      final from = Map<FeedItem, String>.identity();
      for (var i = 0; i < items.length; i++) {
        from[items[i]] = 'feed$i';
      }
      expect(storiesOf(items, from).length, 4 + filler.length);
    });

    test('short headlines are left alone', () {
      final one = item('Budget day');
      final two = item('Budget day live');
      final from = Map<FeedItem, String>.identity()
        ..addAll({one: 'a', two: 'b'});
      expect(storiesOf([one, two], from).length, 2 + filler.length);
    });
  });

  test('headlineWords drops the little words and plural s', () {
    expect(headlineWords('Cyber attacks hit the UK’s meat processors'), {
      'cyber',
      'attack',
      'hit',
      'uk',
      'meat',
      'processor',
    });
  });

  group('the News tile', () {
    test('sourcesIn reads topics and places, and the old single address', () {
      final sources = DashboardNewsWidget.sourcesIn({
        'sources': [
          {'name': 'A', 'url': 'https://a.example/rss', 'topic': 'Tech'},
          {'name': 'Empty', 'url': ''},
          {'name': 'B', 'url': 'https://b.example/rss', 'only': 'Colchester'},
        ],
      });
      expect(
        [for (final s in sources) s.url],
        ['https://a.example/rss', 'https://b.example/rss'],
      );
      expect(sources.first.topic, 'Tech');
      expect(sources.last.only, ['Colchester']);
      final legacy = DashboardNewsWidget.sourcesIn({
        'url': ' https://c.example/ ',
      });
      expect(legacy.single.url, 'https://c.example/');
    });

    test(
      'offers a ready-made set for each topic, every feed filed under it',
      () {
        final sources = newsWidgetType.options.firstWhere(
          (o) => o.key == 'sources',
        );
        expect(sources.presets.keys, ['tech', 'ai', 'uk', 'colchester']);
        final json = sources.toJson();
        expect((json['presets'] as Map).keys, [
          'tech',
          'ai',
          'uk',
          'colchester',
        ]);
        final topics = {
          'tech': 'Tech',
          'ai': 'AI',
          'uk': 'UK',
          'colchester': 'Colchester',
        };
        for (final e in sources.presets.entries) {
          expect(e.value.rows, isNotEmpty);
          for (final row in e.value.rows) {
            expect(row['url'], startsWith('https://'));
            expect(row['name'], isNotEmpty);
            expect(row['topic'], topics[e.key]);
          }
        }
        // The county-wide feeds are narrowed to the town.
        final col = sources.presets['colchester']!.rows;
        expect(
          col.where((r) => r['url']!.contains('england/essex')).single['only'],
          colchesterPlaces,
        );
      },
    );
  });
}

/// The tile itself, its feeds seeded rather than fetched.
void tileTests() {
  testWidgets('a tab per topic, a town filtered, a story told once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final feeds = FeedService();
    addTearDown(feeds.dispose);
    feeds
      ..seed('https://tech.example/rss', [
        item('Chipmaker unveils a faster laptop processor', summary: 's'),
      ])
      ..seed('https://one.example/rss', [
        item(
          'Harbour Rail to cut thousands of jobs to save costs',
          summary: 'Harbour Rail says…',
          link: 'https://one.example/harbour-rail',
        ),
        ...filler.take(10),
      ])
      ..seed('https://two.example/rss', [
        item(
          'Harbour Rail cutting thousands of jobs in cost drive',
          summary: 'The operator…',
          link: 'https://two.example/harbour-rail-jobs',
        ),
        ...filler.skip(10),
      ])
      ..seed('https://county.example/rss', [
        item('Colchester market returns to the high street', summary: 's'),
        item('Harlow road shut for resurfacing', summary: 's'),
      ]);
    final w = DashboardWidgetContext(
      theme: kBuiltInThemes.first,
      config: DashboardWidgetConfig(
        id: 'news',
        type: 'news',
        x: 0,
        y: 0,
        width: 6,
        height: 6,
        options: {
          'layout': 'tabs',
          'showSource': false,
          'showTime': false,
          'sources': [
            {
              'name': 'Tech One',
              'url': 'https://tech.example/rss',
              'topic': 'Tech',
            },
            {
              'name': 'Paper One',
              'url': 'https://one.example/rss',
              'topic': 'UK',
            },
            {
              'name': 'Paper Two',
              'url': 'https://two.example/rss',
              'topic': 'uk',
            },
            {
              'name': 'County',
              'url': 'https://county.example/rss',
              'topic': 'Colchester',
              'only': 'Colchester, Wivenhoe',
            },
          ],
        },
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: feeds,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 700,
              child: Builder(
                builder: (context) => newsWidgetType.build(context, w),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Three tabs: the two UK feeds share one.
    for (final tab in ['Tech', 'UK', 'Colchester']) {
      expect(find.text(tab), findsOneWidget);
    }
    expect(
      find.text('Chipmaker unveils a faster laptop processor'),
      findsOneWidget,
    );

    await tester.tap(find.text('Colchester'));
    await tester.pump();
    expect(
      find.text('Colchester market returns to the high street'),
      findsOneWidget,
    );
    expect(find.text('Harlow road shut for resurfacing'), findsNothing);

    await tester.tap(find.text('UK'));
    await tester.pump();
    expect(
      find.text('Harbour Rail to cut thousands of jobs to save costs'),
      findsOneWidget,
    );
    // Told once, with who else has it.
    expect(
      find.text('Harbour Rail cutting thousands of jobs in cost drive'),
      findsNothing,
    );
    expect(find.text('also Paper Two'), findsOneWidget);

    await tester.tap(
      find.text('Harbour Rail to cut thousands of jobs to save costs'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Also reported by'), findsOneWidget);
    expect(
      find.textContaining(
        'Harbour Rail cutting thousands of jobs in cost drive',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });
}

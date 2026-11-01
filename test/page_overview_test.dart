import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/page_overview.dart';
import 'package:home_canvas/dashboard/schedule.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/screens/dashboard_screen.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/dashboard_service.dart';
import 'package:home_canvas/services/screen_idle_service.dart';

/// Every page of the dashboard at once: where the cards go, what each is
/// called, the map drawn for a page with no picture, and the ways in and
/// out of it.
void main() {
  setUpAll(registerBuiltInWidgets);

  DashboardWidgetConfig tile(
    String id,
    String type,
    int page, {
    int x = 0,
    int y = 0,
    int w = 4,
    int h = 2,
  }) => DashboardWidgetConfig(
    id: id,
    type: type,
    x: x,
    y: y,
    width: w,
    height: h,
    page: page,
  );

  group('arrangeCards', () {
    test('thirteen pages on a panel: as big as they can be, none touching', () {
      const area = Size(1920, 1100);
      final cards = arrangeCards(13, area, aspect: 1920 / 1100);
      expect(cards, hasLength(13));
      // Five across, three down, is the biggest they can be.
      expect(cards[4].picture.top, cards[0].picture.top);
      expect(cards[5].picture.top, greaterThan(cards[0].picture.top));
      for (final c in cards) {
        expect(c.picture.left, greaterThanOrEqualTo(0));
        expect(c.picture.right, lessThanOrEqualTo(area.width));
        expect(c.label.bottom, lessThanOrEqualTo(area.height));
        expect(c.picture.width / c.picture.height, closeTo(1920 / 1100, 0.01));
      }
      for (var i = 0; i < cards.length; i++) {
        for (var j = i + 1; j < cards.length; j++) {
          final a = cards[i].card.expandToInclude(cards[i].label);
          final b = cards[j].card.expandToInclude(cards[j].label);
          expect(a.overlaps(b), isFalse, reason: 'cards $i and $j');
        }
      }
    });

    test('in a frame, the picture keeps the page\'s shape, inside it', () {
      const area = Size(1920, 1100);
      const frame = EdgeInsets.only(left: 20, top: 36);
      final cards = arrangeCards(
        7,
        area,
        aspect: 1920 / 1100,
        label: 0,
        frame: frame,
      );
      for (final c in cards) {
        expect(c.picture.width / c.picture.height, closeTo(1920 / 1100, 0.01));
        expect(c.picture.left - c.card.left, 20);
        expect(c.picture.top - c.card.top, 36);
        expect(c.card.bottom, lessThanOrEqualTo(area.height));
        expect(c.card.top, greaterThanOrEqualTo(0));
      }
    });

    test('a short last row is centred', () {
      const area = Size(1920, 1100);
      final cards = arrangeCards(7, area, aspect: 1920 / 1100);
      final last = cards.last.picture;
      final row = cards.where((c) => c.picture.top == last.top).toList();
      final left = row.first.picture.left;
      final right = area.width - row.last.picture.right;
      expect(left, closeTo(right, 0.5));
    });

    test('nothing to arrange, or nowhere to put it', () {
      expect(arrangeCards(0, const Size(800, 600), aspect: 1), isEmpty);
      expect(arrangeCards(3, Size.zero, aspect: 1), isEmpty);
      final one = arrangeCards(1, const Size(800, 600), aspect: 4 / 3);
      expect(one.single.picture.center.dx, closeTo(400, 0.5));
    });
  });

  group('pageTitle', () {
    test("a page's own name, when it has one", () {
      final s = DashboardSettings(
        pages: [DashboardPage(name: '  Morning ')],
        widgets: [tile('c', 'clock', 0)],
      );
      expect(pageTitle(s, 0), 'Morning');
    });

    test('otherwise, its two biggest tiles and how many more', () {
      final s = DashboardSettings(
        widgets: [
          tile('a', 'clock', 0, w: 2, h: 2),
          tile('b', 'news', 0, w: 8, h: 6),
          tile('c', 'weather', 0, w: 4, h: 4),
          tile('d', 'notes', 0, w: 1, h: 1),
          tile('e', 'timers', 0, w: 1, h: 1),
        ],
      );
      final news = WidgetRegistry.find('news')!.localName;
      final weather = WidgetRegistry.find('weather')!.localName;
      expect(pageTitle(s, 0), '$news · $weather +3');
    });

    test('two of the same kind are named once', () {
      final s = DashboardSettings(
        widgets: [tile('a', 'clock', 0), tile('b', 'clock', 0, x: 4)],
      );
      expect(pageTitle(s, 0), WidgetRegistry.find('clock')!.localName);
    });

    test('a page with nothing on it says so', () {
      final s = DashboardSettings(widgets: [tile('a', 'clock', 1)]);
      expect(pageTitle(s, 0), 'Nothing on it yet');
    });
  });

  test('pageLayout changes when a tile moves, and only then', () {
    final s = DashboardSettings(
      widgets: [tile('a', 'clock', 0), tile('b', 'news', 1)],
    );
    final before = pageLayout(s, 0);
    expect(pageLayout(s, 0), before);
    s.widgets[1].x = 6; // on another page
    expect(pageLayout(s, 0), before);
    s.widgets[0].y = 3;
    expect(pageLayout(s, 0), isNot(before));
    final moved = pageLayout(s, 0);
    s.themeId = 'lcars';
    expect(pageLayout(s, 0), isNot(moved), reason: 'another theme');
  });

  testWidgets('the map of a page fits, in every theme, however small', (
    tester,
  ) async {
    final s = DashboardSettings(
      widgets: [
        tile('a', 'clock', 0, w: 4, h: 2),
        tile('b', 'news', 0, x: 4, w: 8, h: 8),
        tile('c', 'weather', 0, y: 2, w: 4, h: 3),
        tile('d', 'grid_carbon', 0, y: 5, w: 2, h: 3),
        tile('e', 'no_such_widget', 0, x: 2, y: 5, w: 2, h: 1),
      ],
    );
    for (final theme in kBuiltInThemes) {
      for (final size in const [Size(340, 195), Size(160, 92)]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox.fromSize(
                size: size,
                child: PageMap(settings: s, theme: theme, page: 0),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: '${theme.id} at $size');
      }
    }
  });

  group('the overview itself', () {
    final s = DashboardSettings(
      pages: [
        DashboardPage(name: 'Main'),
        DashboardPage(name: 'Travel'),
      ],
      widgets: [
        tile('a', 'clock', 0),
        tile('b', 'news', 1),
        tile('c', 'weather', 2),
      ],
    );

    Future<
      ({List<int> chosen, List<bool> closed, GlobalKey<PageOverviewState> key})
    >
    show(WidgetTester tester, DashboardTheme theme) async {
      tester.view.physicalSize = const Size(1920, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final chosen = <int>[];
      final closed = <bool>[];
      final key = GlobalKey<PageOverviewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageOverview(
              key: key,
              settings: s,
              theme: theme,
              pages: const [0, 1, 2],
              current: 1,
              shots: const {},
              onChosen: chosen.add,
              onClosed: () => closed.add(true),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return (chosen: chosen, closed: closed, key: key);
    }

    final glass = kBuiltInThemes.firstWhere((t) => !t.isLcars);
    final lcars = kBuiltInThemes.firstWhere((t) => t.isLcars);

    testWidgets('every page is a card, named, and a card touched is chosen', (
      tester,
    ) async {
      final o = await show(tester, glass);
      expect(find.text('Main'), findsOneWidget);
      expect(find.text('Travel'), findsOneWidget);
      expect(
        find.text(WidgetRegistry.find('weather')!.localName),
        findsWidgets,
        reason: 'the unnamed page is named for what is on it',
      );
      await tester.tap(find.text('Main'));
      await tester.pump();
      expect(o.chosen, [0], reason: 'chosen at once, so the page is ready');
      expect(o.closed, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(o.closed, [true]);
    });

    testWidgets('closed, it goes back to the page it came from', (
      tester,
    ) async {
      final o = await show(tester, glass);
      unawaited(o.key.currentState!.close());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(o.chosen, [1]);
      expect(o.closed, [true]);
    });

    testWidgets('on a console the cards come up one at a time, lettered', (
      tester,
    ) async {
      final o = await show(tester, lcars);
      expect(find.text('MAIN'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('MAIN'));
      await tester.pump();
      expect(o.chosen, [0]);
      await tester.pump(const Duration(milliseconds: 300));
      expect(o.closed, [true]);
    });
  });

  group('on the dashboard', () {
    late ConfigService config;

    Future<void> open(WidgetTester tester, {bool topBar = true}) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      config = ConfigService();
      config.config.dashboard
        ..pageSeconds = 5
        ..topBar = topBar
        ..pages = [DashboardPage(name: 'First'), DashboardPage(name: 'Second')]
        ..widgets = [
          tile('p0', 'page_0', 0),
          tile('p1', 'page_1', 1),
          tile('p2', 'page_2', 2),
        ];
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: config),
            ChangeNotifierProvider(create: (_) => DashboardService(config)),
            Provider(create: (_) => ScreenIdleService(config, const [])),
          ],
          child: const MaterialApp(home: DashboardScreen()),
        ),
      );
      await tester.pump();
    }

    bool showing(int page) =>
        find.textContaining('page_$page').evaluate().isNotEmpty;

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets(
      'All pages opens it; a card goes to its page; it holds the turn',
      (tester) async {
        await open(tester, topBar: false);
        expect(find.byType(PageOverview), findsNothing);
        await tester.tap(find.byIcon(Icons.grid_view_rounded));
        await settle(tester);
        expect(find.byType(PageOverview), findsOneWidget);
        // Held: ten seconds on, still no turn under it.
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(PageOverview), findsOneWidget);
        await tester.tap(find.text('Second'));
        await settle(tester);
        expect(find.byType(PageOverview), findsNothing);
        expect(showing(1), isTrue);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('back puts it away and stays on the dashboard', (tester) async {
      await open(tester, topBar: false);
      DashboardScreen.requestedOverview.value = true;
      await settle(tester);
      expect(find.byType(PageOverview), findsOneWidget);
      final handled = await tester.binding.handlePopRoute();
      expect(handled, isTrue);
      await settle(tester);
      expect(find.byType(PageOverview), findsNothing);
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(showing(0), isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('All pages again puts it away', (tester) async {
      await open(tester, topBar: false);
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await settle(tester);
      expect(find.byType(PageOverview), findsOneWidget);
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await settle(tester);
      expect(find.byType(PageOverview), findsNothing);
      expect(showing(0), isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a page dot, with it up, chooses that page', (tester) async {
      await open(tester, topBar: false);
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await settle(tester);
      // The page dots float over the cards, and still go to their page.
      final dots = find.byType(AnimatedContainer);
      expect(dots, findsNWidgets(3));
      await tester.tap(dots.at(2));
      await settle(tester);
      expect(find.byType(PageOverview), findsNothing);
      expect(showing(2), isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('two fingers drawn together open it', (tester) async {
      await open(tester, topBar: false);
      final centre = tester.getCenter(find.byType(PageView));
      final a = await tester.startGesture(
        centre - const Offset(300, 0),
        pointer: 50,
      );
      final b = await tester.startGesture(
        centre + const Offset(300, 0),
        pointer: 51,
      );
      for (var i = 1; i <= 10; i++) {
        await a.moveTo(centre - Offset(300 - i * 25.0, 0));
        await b.moveTo(centre + Offset(300 - i * 25.0, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await settle(tester);
      expect(find.byType(PageOverview), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

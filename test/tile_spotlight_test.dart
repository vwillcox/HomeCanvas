import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/tile_spotlight.dart';
import 'package:home_canvas/screens/dashboard_screen.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/dashboard_service.dart';
import 'package:home_canvas/services/screen_idle_service.dart';

/// Holding a tile brings it close: out of the grid and up to fill the
/// screen, and back into its place.
void main() {
  late ConfigService config;

  DashboardWidgetConfig tile(String id, int page, {int x = 0}) =>
      DashboardWidgetConfig(
        // A type this build does not have: it draws a plain note naming
        // itself, which is all that is needed to see where it is.
        id: id,
        type: 'kind_$id',
        x: x,
        y: 0,
        width: 3,
        height: 2,
        page: page,
      );

  Future<void> open(WidgetTester tester, {int pageSeconds = 0}) async {
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    config = ConfigService();
    config.config.dashboard
      ..pageSeconds = pageSeconds
      ..topBar = false
      ..widgets = [tile('a', 0), tile('b', 0, x: 4), tile('c', 1)];
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: config),
          ChangeNotifierProvider(create: (_) => DashboardService(config)),
          Provider(create: (_) => ScreenIdleService(config, const [])),
        ],
        child: MaterialApp(
          // Something under the dashboard, for back to go back to.
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () =>
                    Navigator.of(context).push(DashboardScreen.route()),
                child: const Text('under'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('under'));
    await tester.pumpAndSettle();
  }

  Finder note(String id) => find.text('Unknown widget "kind_$id"');

  Future<void> wait(WidgetTester tester, Duration d) async {
    for (var t = Duration.zero; t < d; t += const Duration(milliseconds: 100)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> hold(WidgetTester tester, String id) async {
    await tester.longPress(note(id));
    await wait(tester, const Duration(milliseconds: 600));
  }

  testWidgets('a held tile fills the screen, its place left empty', (
    tester,
  ) async {
    await open(tester);
    final before = tester.getRect(note('a'));
    await hold(tester, 'a');

    expect(find.byType(TileSpotlight), findsOneWidget);
    // Once, brought close — not also on the grid behind.
    expect(note('a'), findsOneWidget);
    final after = tester.getRect(note('a'));
    expect(after.width, greaterThan(before.width * 1.4));
    // Named in a header of its own, over the dashboard.
    expect(find.text('kind_a'), findsOneWidget);
    // The other tiles stay where they were, behind it.
    expect(note('b'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('it goes back with its back button, and is on the grid again', (
    tester,
  ) async {
    await open(tester);
    final before = tester.getRect(note('a'));
    await hold(tester, 'a');
    await tester.tap(find.byTooltip('Put it back'));
    await wait(tester, const Duration(milliseconds: 500));
    expect(find.byType(TileSpotlight), findsNothing);
    expect(tester.getRect(note('a')), before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tap on it stays with it; a tap around it puts it back', (
    tester,
  ) async {
    await open(tester);
    await hold(tester, 'a');
    await tester.tap(note('a'));
    await wait(tester, const Duration(milliseconds: 500));
    expect(find.byType(TileSpotlight), findsOneWidget);

    await tester.tapAt(const Offset(8, 600)); // the blurred margin
    await wait(tester, const Duration(milliseconds: 500));
    expect(find.byType(TileSpotlight), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('back puts the tile back rather than leaving the dashboard', (
    tester,
  ) async {
    await open(tester);
    await hold(tester, 'a');
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await wait(tester, const Duration(milliseconds: 500));
    expect(find.byType(TileSpotlight), findsNothing);
    expect(find.byType(DashboardScreen), findsOneWidget);
    // And the next back leaves, as it always did.
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the page does not turn while it is up', (tester) async {
    await open(tester, pageSeconds: 5);
    await wait(tester, const Duration(seconds: 3));
    await hold(tester, 'a');
    await wait(tester, const Duration(seconds: 12));
    expect(find.byType(TileSpotlight), findsOneWidget);
    expect(note('c'), findsNothing, reason: 'still on the first page');

    await tester.tap(find.byTooltip('Put it back'));
    // A full page's time from when it is back, not what was left before.
    await wait(tester, const Duration(seconds: 4));
    expect(note('a'), findsOneWidget);
    await wait(tester, const Duration(seconds: 2));
    expect(note('c'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('it goes back by itself when left alone', (tester) async {
    await open(tester);
    await hold(tester, 'a');
    await wait(tester, const Duration(seconds: 90));
    // Touched: its time starts again.
    await tester.tap(note('a'));
    await wait(tester, const Duration(seconds: 90));
    expect(find.byType(TileSpotlight), findsOneWidget);
    await wait(tester, const Duration(seconds: 31));
    expect(find.byType(TileSpotlight), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('asked for from outside, by type, on the page showing', (
    tester,
  ) async {
    await open(tester);
    // On another page: nothing.
    DashboardScreen.requestedLift.value = 'kind_c';
    await wait(tester, const Duration(milliseconds: 700));
    expect(find.byType(TileSpotlight), findsNothing);
    expect(DashboardScreen.requestedLift.value, isNull);

    DashboardScreen.requestedLift.value = 'kind_b';
    await wait(tester, const Duration(milliseconds: 700));
    expect(find.byType(TileSpotlight), findsOneWidget);
    expect(find.text('kind_b'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('its page and then the tile, asked for together', (tester) async {
    await open(tester);
    // As "bring the c closer" does it from the first page.
    DashboardScreen.requestedPage.value = 1;
    DashboardScreen.requestedLift.value = 'c';
    await wait(tester, const Duration(milliseconds: 900));
    expect(find.byType(TileSpotlight), findsOneWidget);
    expect(find.text('kind_c'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('the room it is given', () {
    const stage = Rect.fromLTWH(24, 92, 1872, 1084);

    test('a small tile is drawn larger, a large one mostly given room', () {
      final small = TileSpotlight.zoomFor(
        const Rect.fromLTWH(0, 0, 300, 260),
        stage,
      );
      expect(small, TileSpotlight.maxZoom);
      final large = TileSpotlight.zoomFor(
        const Rect.fromLTWH(0, 0, 1100, 800),
        stage,
      );
      expect(large, inInclusiveRange(1.1, 1.25));
      // Never smaller than it was, even for a tile wider than the stage.
      expect(
        TileSpotlight.zoomFor(const Rect.fromLTWH(0, 0, 1900, 300), stage),
        1,
      );
    });

    test('counted in cells, the way the widgets size themselves', () {
      final c = TileSpotlight.cellsFor(
        tile('a', 3),
        const Size(1170, 677),
        const Size(160, 140),
      );
      expect((c.width, c.height, c.x, c.y), (7, 5, 0, 0));
      expect((c.id, c.type, c.page), ('a', 'kind_a', 3));
      // Never past the grid.
      final big = TileSpotlight.cellsFor(
        tile('a', 0),
        const Size(5000, 5000),
        const Size(160, 140),
      );
      expect((big.width, big.height), (12, 8));
    });
  });
}

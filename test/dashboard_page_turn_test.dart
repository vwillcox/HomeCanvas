import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:immich_kiosk_pi/dashboard/dashboard_model.dart';
import 'package:immich_kiosk_pi/screens/dashboard_screen.dart';
import 'package:immich_kiosk_pi/services/config_service.dart';
import 'package:immich_kiosk_pi/services/dashboard_service.dart';
import 'package:immich_kiosk_pi/services/screen_idle_service.dart';

/// Pages that turn themselves, and the page dots that show and hold it.
void main() {
  late ConfigService config;

  DashboardWidgetConfig on(int page) => DashboardWidgetConfig(
    // A type this build does not have: it draws a plain note naming
    // itself, which is all a test of page turning needs to see.
    id: 'p$page',
    type: 'page_$page',
    x: 0,
    y: 0,
    width: 4,
    height: 2,
    page: page,
  );

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    config = ConfigService();
    config.config.dashboard
      ..pageSeconds = 5
      ..topBar = false
      ..widgets = [on(0), on(1), on(2)];
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
    await tester.pump(); // the turn starts after the first frame
  }

  bool showing(int page) =>
      find.textContaining('page_$page').evaluate().isNotEmpty;

  Future<void> wait(WidgetTester tester, Duration d) async {
    // In small steps, so the page animation and the turn both advance.
    for (var t = Duration.zero; t < d; t += const Duration(milliseconds: 100)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('turns on its own, with a pause button beside the dots', (
    tester,
  ) async {
    await open(tester);
    expect(showing(0), isTrue);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await wait(tester, const Duration(milliseconds: 5600));
    expect(showing(1), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pause holds the page; play carries on from where it stopped', (
    tester,
  ) async {
    await open(tester);
    await wait(tester, const Duration(seconds: 3));
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await wait(tester, const Duration(seconds: 20));
    expect(showing(0), isTrue, reason: 'held while paused');
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    // Three seconds had gone; two are left.
    await wait(tester, const Duration(milliseconds: 2600));
    expect(showing(1), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('touching a page gives it its full time again', (tester) async {
    await open(tester);
    await wait(tester, const Duration(seconds: 4));
    await tester.tapAt(const Offset(960, 800)); // empty grid
    await wait(tester, const Duration(seconds: 3));
    expect(showing(0), isTrue, reason: 'the clock started again on the touch');
    await wait(tester, const Duration(seconds: 3));
    expect(showing(1), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no pause button when the pages do not turn themselves', (
    tester,
  ) async {
    await open(tester);
    config.config.dashboard.pageSeconds = 0;
    config.notifyListeners();
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
    await wait(tester, const Duration(seconds: 8));
    expect(showing(0), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}

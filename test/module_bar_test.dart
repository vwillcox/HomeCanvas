import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/services/camera_service.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/locked_folder_service.dart';
import 'package:home_canvas/widgets/glass.dart';
import 'package:home_canvas/widgets/module_bar.dart';

Future<void> pumpBar(WidgetTester tester, ModuleBar bar) async {
  tester.view.physicalSize = const Size(1920, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = ConfigService();
  config.config.dashboard.enabled = true;
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: config),
      ChangeNotifierProvider(create: (_) => CameraService(config)),
      ChangeNotifierProvider(create: (_) => LockedFolderService(config)),
    ],
    child: MaterialApp(home: Scaffold(body: Center(child: bar))),
  ));
  await tester.pump();
}

/// Unmount, then let the simulated clock tick once: the bar's check for the
/// TV remote starts a real process, which leaves an instant timer behind.
Future<void> done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

PillIconButton button(WidgetTester tester, String tooltip) =>
    tester.widget<PillIconButton>(find.byWidgetPredicate(
        (w) => w is PillIconButton && w.tooltip == tooltip));

void main() {
  testWidgets('on the photos, Photos is lit and Dashboard is not',
      (tester) async {
    await pumpBar(tester, const ModuleBar(current: KioskModule.photos));
    expect(button(tester, 'Photos').selected, isTrue);
    expect(button(tester, 'Dashboard').selected, isFalse);
    await done(tester);
  });

  testWidgets('on the dashboard, the other way round', (tester) async {
    await pumpBar(tester, const ModuleBar(current: KioskModule.dashboard));
    expect(button(tester, 'Photos').selected, isFalse);
    expect(button(tester, 'Dashboard').selected, isTrue);
    await done(tester);
  });

  testWidgets('Refresh only where there is something to refresh',
      (tester) async {
    await pumpBar(tester, const ModuleBar(current: KioskModule.dashboard));
    expect(find.byTooltip('Refresh'), findsNothing);

    var refreshed = 0;
    await pumpBar(
        tester,
        ModuleBar(
            current: KioskModule.photos, onRefresh: () => refreshed++));
    await tester.tap(find.byTooltip('Refresh'));
    expect(refreshed, 1);
    await done(tester);
  });

  testWidgets('the notifications slider and Settings are on both screens',
      (tester) async {
    for (final m in KioskModule.values) {
      await pumpBar(tester, ModuleBar(current: m));
      expect(find.byType(DndSwitch), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
    }
    await done(tester);
  });

  testWidgets('takes a theme\'s colours, so it reads on a light theme',
      (tester) async {
    const ink = Color(0xFF1E1B16);
    await pumpBar(
        tester,
        const ModuleBar(
            current: KioskModule.dashboard,
            colour: ink,
            accent: Color(0xFFB4531F)));
    expect(button(tester, 'Settings').colour, ink);
    expect(button(tester, 'Dashboard').selectedColour, const Color(0xFFB4531F));
    await done(tester);
  });
}

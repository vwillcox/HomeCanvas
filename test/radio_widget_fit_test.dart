import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/audio_levels_service.dart';
import 'package:home_canvas/services/radio_service.dart';
import 'package:home_canvas/services/radio_stations.dart';

import 'new_widgets_fit_test.dart' show tile;

/// Every Radio look, idle and playing, in every theme, from a page to
/// itself down to a strip — without overflowing or throwing.
void main() {
  setUpAll(registerBuiltInWidgets);

  // Twelve stations, so the dial takes two rows and the grid several.
  final rows = [
    for (final id in [
      'bbc_radio_4', 'bbc_6music', 'classic_fm', 'fip', 'kexp', 'fm4', //
      'nrk_p1', 'triple_j', 'bbc_radio_2', 'somafm_groove_salad',
      'swiss_jazz', 'rte_radio_1',
    ])
      {'station': id, 'name': '', 'url': ''},
  ];

  const sizes = [(12, 8), (6, 4), (4, 3), (4, 2), (2, 1), (12, 1), (2, 8)];

  // Nothing to hear in a test, and no capture to start.
  final levels = AudioLevelsService(
    open: () async => PcmStream(bytes: const Stream.empty(), stop: () async {}),
  );

  Future<void> draw(
    WidgetTester tester,
    RadioService radio,
    Size size, {
    required String look,
    required DashboardTheme theme,
  }) async {
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final w = DashboardWidgetContext(
      theme: theme,
      config: DashboardWidgetConfig(
        id: 'w',
        type: 'radio',
        x: 0,
        y: 0,
        width: 4,
        height: 3,
        options: {'stations': rows, 'look': look},
      ),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: radio),
          // One for the whole test, as the app has: a new one each draw
          // would be thrown away while its capture was still stopping.
          ChangeNotifierProvider.value(value: levels),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: size,
                child: Builder(
                  builder: (context) =>
                      WidgetRegistry.find('radio')!.build(context, w),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  for (final playing in [false, true]) {
    testWidgets('every look fits, ${playing ? 'playing' : 'idle'}', (
      tester,
    ) async {
      final radio = RadioService();
      if (playing) {
        radio.debugPlaying(
          radioStation('fip')!,
          title:
              'Orchestre Poly-Rythmo de Cotonou - Gbeti Madjro (A Very Long '
              'Extended Version Recorded Live)',
          history: [
            for (var i = 0; i < 12; i++)
              RadioSong(
                'Somebody With A Long Name - Song number $i of the evening',
                'FIP',
                DateTime(2026, 10, 24, 20, i),
              ),
          ],
        );
      }
      for (final look in ['auto', 'compact', 'studio', 'dial', 'grid']) {
        for (final theme in kBuiltInThemes) {
          for (final (cw, ch) in sizes) {
            await draw(tester, radio, tile(cw, ch), look: look, theme: theme);
            final e = tester.takeException();
            expect(e, isNull, reason: '$look, ${theme.id}, $cw × $ch: $e');
          }
        }
      }
      // Leave nothing ticking behind.
      await tester.pumpWidget(const SizedBox());
      radio.dispose();
    });
  }
}

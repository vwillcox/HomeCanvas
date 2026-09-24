import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:immich_kiosk_pi/dashboard/dashboard_model.dart';
import 'package:immich_kiosk_pi/dashboard/dashboard_theme.dart';
import 'package:immich_kiosk_pi/dashboard/tile_renderer.dart';
import 'package:immich_kiosk_pi/screens/dashboard_screen.dart';
import 'package:immich_kiosk_pi/services/config_service.dart';
import 'package:immich_kiosk_pi/services/dashboard_service.dart';

/// The editor's previews are pictures the kiosk draws of its own tiles.
void main() {
  late DashboardService service;

  Future<void> mount(WidgetTester tester) async {
    service = DashboardService(ConfigService());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: service,
        child: const MaterialApp(
          home: Stack(children: [SizedBox.expand(), TileRenderHost()]),
        ),
      ),
    );
  }

  TileRenderRequest request(Size size) => TileRenderRequest(
    // A type this build does not have, so the tile draws its "unknown
    // widget" note and needs none of the services a real widget reads.
    config: DashboardWidgetConfig(
      id: 'w1',
      type: 'no_such_widget',
      x: 0,
      y: 0,
      width: 4,
      height: 2,
    ),
    theme: kBuiltInThemes.first,
    settings: DashboardSettings.fromJson(const {}),
    size: size,
  );

  testWidgets('offers itself to the editor server while mounted', (
    tester,
  ) async {
    await mount(tester);
    expect(service.renderTile, isNotNull);
    await tester.pumpWidget(const SizedBox());
    expect(service.renderTile, isNull);
  });

  testWidgets('draws a tile at the size asked for, as a PNG', (tester) async {
    await mount(tester);
    final pending = service.renderTile!(request(const Size(300, 160)));
    List<int>? png;
    var finished = false;
    pending.then((v) {
      png = v;
      finished = true;
    });
    // The host waits on frames and a settling delay, which run on the test's
    // clock, then takes the picture, which the engine does in real time — so
    // step both until it is done.
    for (var i = 0; i < 100 && !finished; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(png, isNotNull);
    // PNG signature, then the IHDR's width and height.
    expect(png!.sublist(1, 4), 'PNG'.codeUnits);
    int be32(int at) =>
        png![at] << 24 | png![at + 1] << 16 | png![at + 2] << 8 | png![at + 3];
    expect(be32(16), 300);
    expect(be32(20), 160);
    // Taken down once drawn: nothing left running off screen.
    await tester.pump();
    await tester.pump();
    expect(find.byType(DashboardTile), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/home_assistant_service.dart';

HaEntity light(String id, String name, String state) =>
    HaEntity(id: id, state: state, attributes: {'friendly_name': name});

void main() {
  setUpAll(registerBuiltInWidgets);

  late ConfigService config;
  late HomeAssistantService ha;

  setUp(() {
    config = ConfigService();
    config.config.homeAssistant
      ..baseUrl = 'http://ha.local:8123'
      ..token = 'x';
    ha = HomeAssistantService(config)
      ..debugSet([
        light('light.lounge_1', 'Lounge 1', 'on'),
        light('light.lamp', 'lamp', 'off'),
        light('light.bedroom_1', 'Bedroom 1', 'off'),
        light('light.bedroom_2', 'Bedroom 2', 'unavailable'),
        const HaEntity(
          id: 'sensor.indoor_temperature',
          state: '21.5',
          attributes: {
            'friendly_name': 'Indoor Temperature',
            'unit_of_measurement': '°C',
          },
        ),
        light('switch.socket_1', 'Power strip Socket 1', 'on'),
        light('lock.front_door', 'Front door', 'locked'),
      ])
      ..debugSetAreas(const [
        HaArea(
          id: 'living_room',
          name: 'Living Room',
          entities: [
            'light.lounge_1',
            'light.lamp',
            'sensor.indoor_temperature',
          ],
        ),
        HaArea(id: 'kitchen', name: 'Kitchen', entities: []),
        HaArea(
          id: 'bedroom',
          name: 'Bedroom',
          entities: ['light.bedroom_1', 'light.bedroom_2', 'lock.front_door'],
        ),
      ]);
  });

  Future<void> draw(
    WidgetTester tester,
    Size size, {
    String theme = 'glass',
  }) async {
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final w = DashboardWidgetContext(
      theme: kBuiltInThemes.firstWhere(
        (t) => t.id == theme,
        orElse: () => kBuiltInThemes.first,
      ),
      config: DashboardWidgetConfig(
        id: 'w',
        type: 'ha_bridge',
        x: 0,
        y: 0,
        width: 12,
        height: 8,
        options: {
          'extras': [
            {'entity': 'switch.socket_1', 'name': 'Socket 1'},
          ],
        },
      ),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider.value(value: ha)],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: size,
                child: Builder(
                  builder: (context) =>
                      WidgetRegistry.find('ha_bridge')!.build(context, w),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('fits the page, half of it, and a corner of it', (tester) async {
    for (final size in const [
      Size(1880, 1150),
      Size(930, 1150),
      Size(930, 560),
    ]) {
      for (final theme in ['glass', 'lcars']) {
        await draw(tester, size, theme: theme);
        expect(tester.takeException(), isNull, reason: '$size in $theme');
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the rooms are Home Assistant’s, the empty ones left out', (
    tester,
  ) async {
    await draw(tester, const Size(1880, 1150));
    expect(find.text('LIVING ROOM'), findsWidgets);
    expect(find.text('BEDROOM'), findsOneWidget);
    expect(find.text('KITCHEN'), findsNothing);
    expect(find.text('SYSTEMS'), findsOneWidget);
    expect(find.text('ALL DECKS'), findsOneWidget);
    // The first room is showing: its lights, and its temperature.
    expect(find.text('LOUNGE 1'), findsOneWidget);
    expect(find.text('LAMP'), findsOneWidget);
    expect(find.text('21.5 °C'), findsOneWidget);

    await tester.tap(find.text('BEDROOM'));
    await tester.pump();
    expect(find.text('BEDROOM 1'), findsOneWidget);
    expect(find.text('LOUNGE 1'), findsNothing);
    // A lock is never a block to tap.
    expect(find.text('FRONT DOOR'), findsNothing);

    await tester.tap(find.text('SYSTEMS'));
    await tester.pump();
    expect(find.text('SOCKET 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tap switches a light, at once', (tester) async {
    await draw(tester, const Size(1880, 1150));
    expect(ha.entity('light.lamp')!.on, isFalse);
    await tester.tap(find.text('LAMP'));
    await tester.pump();
    expect(ha.entity('light.lamp')!.on, isTrue);
    await tester.pumpWidget(const SizedBox());
    // There is no Home Assistant here: let the request's timeout run out.
    await tester.pump(const Duration(seconds: 15));
  });
}

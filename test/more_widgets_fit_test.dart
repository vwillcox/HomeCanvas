import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:immich_kiosk_pi/dashboard/dashboard_model.dart';
import 'package:immich_kiosk_pi/dashboard/dashboard_theme.dart';
import 'package:immich_kiosk_pi/dashboard/widget_registry.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/trains_widget.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/widgets.dart';
import 'package:immich_kiosk_pi/services/carbon_service.dart';
import 'package:immich_kiosk_pi/services/config_service.dart';
import 'package:immich_kiosk_pi/services/dashboard_service.dart';
import 'package:immich_kiosk_pi/services/govee_service.dart';
import 'package:immich_kiosk_pi/services/shopping_service.dart';
import 'package:immich_kiosk_pi/services/trains_service.dart';

Size tile(int w, int h) {
  const gap = 10.0;
  final cellW = (1900 - gap * 13) / 12;
  final cellH = (1080 - gap * 9) / 8;
  return Size(w * cellW + (w - 1) * gap - 16, h * cellH + (h - 1) * gap - 16);
}

const shapes = [
  (1, 1),
  (2, 1),
  (1, 2),
  (2, 2),
  (3, 2),
  (3, 3),
  (4, 2),
  (4, 3),
  (5, 3),
  (4, 6),
  (1, 6),
  (6, 1),
  (12, 1),
  (1, 8),
  (6, 4),
  (12, 8),
];

/// A board without the network.
class FakeTrains extends TrainsClient {
  FakeTrains(this.result);
  final Board result;
  @override
  Future<Board> board({
    required String token,
    required String from,
    String to = '',
    int windowMinutes = 120,
  }) async => result;
}

void main() {
  setUpAll(registerBuiltInWidgets);

  late ConfigService config;
  late ShoppingService shopping;
  late CarbonService carbon;
  late GoveeService govee;

  setUp(() {
    config = ConfigService();
    shopping = ShoppingService(persist: false);
    carbon = CarbonService(config);
    govee = GoveeService(listen: false);
  });

  Future<void> draw(
    WidgetTester tester,
    String type,
    Size size, {
    Map<String, dynamic>? options,
  }) async {
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final t = WidgetRegistry.find(type)!;
    final w = DashboardWidgetContext(
      theme: kBuiltInThemes.first,
      config: DashboardWidgetConfig(
        id: 'w',
        type: type,
        x: 0,
        y: 0,
        width: 3,
        height: 2,
        options: options,
      ),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: config),
          ChangeNotifierProvider.value(value: shopping),
          ChangeNotifierProvider.value(value: carbon),
          ChangeNotifierProvider.value(value: govee),
          ChangeNotifierProvider(create: (_) => DashboardService(config)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: size,
                child: Builder(builder: (context) => t.build(context, w)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> sweep(
    WidgetTester tester,
    String type, {
    Map<String, dynamic>? options,
  }) async {
    final t = WidgetRegistry.find(type)!;
    for (final (w, h) in shapes) {
      if (w < t.minWidth || h < t.minHeight) continue;
      await draw(tester, type, tile(w, h), options: options);
      final e = tester.takeException();
      expect(e, isNull, reason: '$type at $w × $h: $e');
    }
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('Countdowns fits every tile', (tester) async {
    await sweep(
      tester,
      'countdowns',
      options: {
        'events': [
          {
            'name': 'Sam’s birthday party at the bowling alley',
            'date': '30/09',
          },
          {'name': 'Half term', 'date': '26/10'},
          {'name': 'Christmas', 'date': '25/12'},
          {'name': 'New Year', 'date': '1/1'},
        ],
      },
    );
  });

  testWidgets('Shopping list fits every tile, and a tap ticks', (tester) async {
    for (final n in [3, 15]) {
      for (var i = shopping.items.length; i < n; i++) {
        shopping.add('Item $i: washing-up liquid, the big bottle');
      }
      await sweep(tester, 'shopping');
    }
    await draw(tester, 'shopping', tile(4, 4));
    await tester.tap(find.textContaining('Item 0'));
    await tester.pump();
    expect(shopping.items.last.done, isTrue);
    await tester.pumpWidget(const SizedBox());
    shopping.dispose();
  });

  testWidgets('Grid carbon fits every tile', (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, now.hour);
    carbon.debugSet(
      'CO1',
      CarbonForecast(
        region: 'East England',
        slots: [
          for (var i = 0; i < 96; i++)
            CarbonSlot(
              start.add(Duration(minutes: 30 * i)),
              100 + (i * 37) % 180,
              i % 5 == 0 ? 'very high' : 'low',
            ),
        ],
      ),
    );
    await sweep(tester, 'grid_carbon', options: {'postcode': 'CO1 1ZY'});
  });

  testWidgets('Trains fits every tile', (tester) async {
    final now = DateTime.now();
    TrainsWidget.debugClient = FakeTrains(
      Board(
        station: 'Maidstone East',
        departures: [
          for (var i = 1; i <= 8; i++)
            Departure(
              scheduled: now.add(Duration(minutes: 12 * i)),
              destination: i.isEven
                  ? 'London Victoria'
                  : 'Ashford International & Canterbury West',
              platform: '$i',
              lateMinutes: i == 2 ? 7 : null,
              expected: i == 2 ? now.add(const Duration(minutes: 31)) : null,
              cancelled: i == 3,
              reason: i == 3 ? 'a fault with the signalling system' : null,
            ),
        ],
      ),
    );
    addTearDown(() => TrainsWidget.debugClient = null);
    await sweep(
      tester,
      'trains',
      options: {
        'from': 'MDE',
        'to': 'VIC',
        'toName': 'London',
        'token': 'x',
        'rows': 6,
      },
    );
  });

  testWidgets('Lights fits every tile', (tester) async {
    govee
      ..debugAdd(
        GoveeDevice(id: 'a', sku: 'H61E1', name: 'LED strip behind the TV')
          ..on = true
          ..brightness = 70
          ..colour = const Color(0xFFFF7AB6),
      )
      ..debugAdd(
        GoveeDevice(
          id: 'b',
          sku: 'H5082',
          name: 'Lamp plug',
          canDim: false,
          canColour: false,
        )..on = false,
      )
      ..debugAdd(
        GoveeDevice(id: 'c', sku: 'H6008', name: 'Bedside')..on = true,
      );
    await sweep(tester, 'lights');
    govee.dispose();
  });

  testWidgets('each asks to be set up when it has nothing to go on', (
    tester,
  ) async {
    await draw(tester, 'countdowns', tile(3, 2));
    expect(find.textContaining('Add dates'), findsOneWidget);
    await draw(tester, 'shopping', tile(4, 4));
    expect(find.textContaining('/list'), findsOneWidget);
    await draw(tester, 'trains', tile(5, 3));
    expect(find.textContaining('three-letter code'), findsOneWidget);
    await draw(tester, 'lights', tile(4, 2));
    expect(find.textContaining('LAN Control'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

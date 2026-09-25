import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/servers_widget.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/air_quality_service.dart';
import 'package:home_canvas/services/bins_service.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/dashboard_service.dart';
import 'package:home_canvas/services/notes_service.dart';
import 'package:home_canvas/services/system_stats.dart';
import 'package:home_canvas/services/timer_service.dart';

/// The panel's grid, with the tile's padding taken off, as the dashboard does.
Size tile(int w, int h) {
  const gap = 10.0;
  final cellW = (1900 - gap * 13) / 12;
  final cellH = (1080 - gap * 9) / 8;
  return Size(w * cellW + (w - 1) * gap - 16, h * cellH + (h - 1) * gap - 16);
}

/// Every shape a tile can reasonably be: the corners of the grid, strips,
/// columns, and the sizes these widgets are drawn at by default.
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

void main() {
  setUpAll(registerBuiltInWidgets);

  late Directory dir;
  late ConfigService config;
  late NotesService notes;
  late TimerService timers;
  late BinsService bins;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fit');
    config = ConfigService();
    config.config.weather
      ..latitude = 51.27
      ..longitude = 0.52;
    notes = NotesService(file: '${dir.path}/notes.json', persist: false);
    timers = TimerService();
    bins = BinsService(config);
  });
  tearDown(() async {
    timers.dispose();
    await notes.saved;
    dir.deleteSync(recursive: true);
  });

  Future<void> draw(
    WidgetTester tester,
    String type,
    Size size, {
    Map<String, dynamic>? options,
    DashboardTheme? theme,
  }) async {
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final t = WidgetRegistry.find(type)!;
    final w = DashboardWidgetContext(
      theme: theme ?? kBuiltInThemes.first,
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
          ChangeNotifierProvider.value(value: notes),
          ChangeNotifierProvider.value(value: timers),
          ChangeNotifierProvider.value(value: bins),
          ChangeNotifierProvider(create: (_) => DashboardService(config)),
          ChangeNotifierProvider(
            create: (_) => AirQualityService.withReading(
              config,
              AirQuality.fromOpenMeteo({
                'current': {
                  'european_aqi': 26,
                  'uv_index': 3.4,
                  'grass_pollen': 62.0,
                  'birch_pollen': 12.0,
                  'mugwort_pollen': 0.8,
                },
              }, DateTime(2026, 9, 24)),
            ),
          ),
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
    final type0 = WidgetRegistry.find(type)!;
    for (final (w, h) in shapes) {
      // The editor will not make a tile smaller than the type allows.
      if (w < type0.minWidth || h < type0.minHeight) continue;
      await draw(tester, type, tile(w, h), options: options);
      final e = tester.takeException();
      expect(e, isNull, reason: '$type at $w × $h: $e');
    }
    // Leave nothing ticking behind.
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('Sun & moon fits every tile', (t) => sweep(t, 'sun_moon'));
  testWidgets('Air & pollen fits every tile', (t) => sweep(t, 'air_quality'));

  testWidgets(
    'Bin day fits every tile',
    (t) => sweep(
      t,
      'bins',
      options: {
        'bins': [
          {
            'name': 'Rubbish',
            'colour': '#3A3E47',
            'first': '2026-10-01',
            'everyWeeks': 2,
          },
          {
            'name': 'Recycling',
            'colour': '#2E6FD0',
            'first': '2026-09-24',
            'everyWeeks': 2,
          },
          {
            'name': 'Food',
            'colour': '#5B8C3A',
            'first': '2026-09-03',
            'everyWeeks': 1,
          },
        ],
      },
    ),
  );

  testWidgets('Bin day without bins asks for them', (tester) async {
    await draw(tester, 'bins', tile(3, 2));
    expect(find.textContaining('Add your bins'), findsOneWidget);
  });

  testWidgets('Timers fit every tile, idle and busy', (tester) async {
    await sweep(tester, 'timers');
    timers
      ..start(const Duration(minutes: 11), label: 'Pasta')
      ..start(const Duration(minutes: 7), label: 'Eggs')
      ..start(const Duration(seconds: 1));
    timers.timers.last.finishedAt = DateTime.now();
    await sweep(tester, 'timers');
    // Stops its ticker, which the test would otherwise find still pending.
    for (final t in timers.timers) {
      timers.remove(t.id);
    }
  });

  testWidgets('a preset starts a timer', (tester) async {
    await draw(tester, 'timers', tile(3, 3));
    await tester.tap(find.text('Eggs'));
    await tester.pump();
    expect(timers.timers.single.label, 'Eggs');
    expect(timers.timers.single.total, const Duration(minutes: 7));
    await tester.pumpWidget(const SizedBox());
    timers.remove(timers.timers.single.id);
  });

  testWidgets('Notes fit every tile, from one to a board full', (tester) async {
    await draw(tester, 'notes', tile(5, 3));
    expect(find.textContaining('/notes'), findsOneWidget);
    for (final n in [1, 3, 12]) {
      for (var i = notes.notes.length; i < n; i++) {
        notes.add(
          'Note $i: the parcel is in the shed, round the back by the bins',
          from: 'Sam',
        );
      }
      await sweep(tester, 'notes');
    }
  });

  testWidgets('a note comes down with a tap and a Done', (tester) async {
    notes.add('Feed the fish');
    await draw(tester, 'notes', tile(5, 3));
    await tester.tap(find.text('Feed the fish'));
    await tester.pump();
    await tester.tap(find.text('Done ✓'));
    await tester.pump();
    expect(notes.notes, isEmpty);
  });

  testWidgets('Servers fits every tile, with disks and their health', (
    tester,
  ) async {
    DiskUse disk(String label, String dev, int tb, double pct, DiskState? h) =>
        DiskUse(
          label: label,
          mount: label == 'System' ? '/' : '/mnt/$label',
          device: dev,
          percent: pct,
          size: tb * 1000000000000,
          used: (tb * 1000000000000 * pct / 100).round(),
          health: h == null
              ? null
              : DiskHealth(
                  device: dev,
                  model: 'ST8000',
                  state: h,
                  temperature: 34,
                  pending: h == DiskState.healthy ? 0 : 8,
                ),
        );
    ServersWidget.debugStats = [
      MachineStats(
        name: 'tabletpi',
        cpu: 23,
        memory: 61,
        disk: 38,
        disks: [disk('System', 'mmcblk0', 1, 38, null)],
        temperature: 52,
        uptime: const Duration(days: 11),
        containers: const [ContainerState('homeassistant', true)],
      ),
      MachineStats(
        name: 'NAS',
        cpu: 4,
        memory: 33,
        disk: 42,
        disks: [
          disk('System', 'sdb', 1, 42, DiskState.healthy),
          disk('sata', 'sda', 8, 82, DiskState.warning),
          disk('media', 'sdc', 4, 95, DiskState.failing),
        ],
        temperature: 39,
        uptime: const Duration(days: 55),
        containers: const [
          ContainerState('blog', true),
          ContainerState('backup', false),
        ],
      ),
    ];
    addTearDown(() => ServersWidget.debugStats = null);
    await sweep(tester, 'servers');
    await draw(tester, 'servers', tile(4, 3));
    expect(find.text('Disk failing'), findsOneWidget);
    expect(find.textContaining('6.6 of 8 TB'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Servers and Services ask to be set up', (tester) async {
    await draw(tester, 'servers', tile(4, 3), options: {'showThisPi': false});
    expect(find.textContaining('Glances'), findsOneWidget);
    await draw(tester, 'services', tile(4, 3));
    expect(find.textContaining('Add what to watch'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

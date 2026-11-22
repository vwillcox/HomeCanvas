import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/screens/routines_settings.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/home_assistant_service.dart';
import 'package:home_canvas/services/routines.dart';

/// Saving is counted, not done: the real save writes the kiosk's own config.
class _Config extends ConfigService {
  int saves = 0;

  @override
  Future<void> save() async {
    saves++;
    notifyListeners();
  }
}

/// A Home Assistant with a lounge of two bulbs, a hallway light, and a
/// heater and a fan to ask about.
class _Ha extends HomeAssistantService {
  _Ha(super.config);

  @override
  bool get configured => true;

  @override
  Future<void> refreshAreas() async {}

  @override
  List<HaArea> get areas => const [
    HaArea(
      id: 'living_room',
      name: 'Living Room',
      entities: ['light.lounge_1', 'light.lounge_2'],
    ),
  ];

  @override
  Future<List<HaChoice>> entityChoices(Set<String> domains) async =>
      domains.length == 1
      ? const [
          HaChoice(id: 'light.hallway', name: 'Hallway', area: 'Hallway'),
          HaChoice(id: 'light.lounge_1', name: 'Lounge 1', area: 'Living Room'),
          HaChoice(id: 'light.lounge_2', name: 'Lounge 2', area: 'Living Room'),
        ]
      : const [
          HaChoice(id: 'climate.heater', name: 'Heater', area: 'Living Room'),
          HaChoice(id: 'fan.fan', name: 'Fan', area: 'Living Room'),
        ];
}

void main() {
  late _Config config;

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    config = _Config();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConfigService>.value(value: config),
          ChangeNotifierProvider<HomeAssistantService>.value(
            value: _Ha(config),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: ListView(children: const [RoutinesTile()])),
        ),
      ),
    );
  }

  testWidgets('a routine that sets the lounge, puts the rest off and asks', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byTooltip('Add a routine'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Work');
    await tester.enterText(
      find.widgetWithText(TextField, 'What sets it off — one to a line'),
      'Work mode',
    );

    // The lounge, the whole room.
    await tester.ensureVisible(find.text('Add lights'));
    await tester.tap(find.text('Add lights'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All of Living Room'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('all of Living Room'), findsOneWidget);
    // At 80%, warm white, to begin with.
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('Warm white'), findsOneWidget);

    await tester.ensureVisible(find.text('Turn every other light off'));
    await tester.tap(find.text('Turn every other light off'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Add a question'));
    await tester.tap(find.text('Add a question'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Asked'),
      'Do you want the heater on or off?',
    );
    await tester.ensureVisible(find.text('Choose…'));
    await tester.tap(find.text('Choose…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heater · Living Room').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final r = config.config.routines.last;
    expect(r.name, 'Work');
    expect(r.phrases, ['Work mode']);
    expect(r.lights.single.targets, ['area:living_room']);
    expect(r.lights.single.brightness, 80);
    expect(r.lights.single.white, LightWhite.warm);
    expect(r.otherLightsOff, isTrue);
    expect(r.questions.single.prompt, 'Do you want the heater on or off?');
    expect(r.questions.single.entity, 'climate.heater');
    expect(r.questions.single.name, 'heater');
    expect(config.saves, 1);
    // And listed so.
    expect(
      find.textContaining('1 light set, the rest off, “Do you want'),
      findsOneWidget,
    );
  });

  testWidgets('the Art Matrix, put on by a routine', (tester) async {
    await show(tester);
    config.config.artMatrix.enabled = true;
    await tester.tap(find.byTooltip('Add a routine'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Morning');
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'The Art Matrix'),
        matching: find.text('Leave alone'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('On').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(config.config.routines.last.steps, {RoutineStep.artMatrixOn});
    expect(find.textContaining('Art Matrix on'), findsOneWidget);
  });

  testWidgets('without one, offered only where a routine has it already', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byTooltip('Add a routine'));
    await tester.pumpAndSettle();
    expect(find.text('The Art Matrix'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // Bedtime starts with it off, and keeps it when saved.
    await tester.tap(find.text('Bedtime'));
    await tester.pumpAndSettle();
    expect(find.text('The Art Matrix'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      config.config.routines.first.steps,
      contains(RoutineStep.artMatrixOff),
    );
  });

  testWidgets('cancelled, nothing changes', (tester) async {
    await show(tester);
    final before = config.config.routines.length;
    await tester.tap(find.text('Bedtime'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add lights'));
    await tester.tap(find.text('Add lights'));
    await tester.pumpAndSettle();
    // The light, not the room under its name.
    await tester.tap(find.text('Hallway').first);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(config.config.routines.length, before);
    expect(config.config.routines.first.lights, isEmpty);
    expect(config.saves, 0);
  });
}

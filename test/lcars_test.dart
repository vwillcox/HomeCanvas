import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/look.dart';
import 'package:home_canvas/screens/dashboard_screen.dart';
import 'package:home_canvas/theme.dart';
import 'package:home_canvas/widgets/glass.dart';
import 'package:home_canvas/widgets/lcars.dart';

final lcars = kBuiltInThemes.firstWhere((t) => t.id == 'lcars');

/// [home] on the kiosk as LCARS dresses it.
Widget console(Widget home) => KioskLook(
  theme: lcars,
  child: MaterialApp(theme: buildTheme(lcars), home: Scaffold(body: home)),
);

void main() {
  group('the LCARS theme, as data', () {
    test('is a console, with colours for its blocks', () {
      expect(lcars.isLcars, isTrue);
      expect(lcars.palette, isNotEmpty);
      expect(kBuiltInThemes.where((t) => t.isLcars), [lcars]);
    });

    test('keeps its style and its palette through a theme file', () {
      final back = DashboardTheme.fromJson(lcars.toJson());
      expect(back.style, ThemeStyle.lcars);
      expect(back.palette, lcars.palette);
    });

    test('a theme file that names neither is drawn with tiles', () {
      final plain = DashboardTheme.fromJson(const {'id': 'x', 'style': 'nope'});
      expect(plain.isLcars, isFalse);
      expect(plain.palette, isEmpty);
      // With no palette, a block is the accent rather than nothing.
      expect(plain.block(3), plain.accent);
    });

    test('goes round its palette, the same colour for the same block', () {
      final n = lcars.palette.length;
      expect(lcars.block(n + 1), lcars.palette[1]);
      expect(lcars.block(2), lcars.block(2));
    });

    test('lettering in black reads on every block', () {
      double contrast(Color a, Color b) {
        final la = a.computeLuminance(), lb = b.computeLuminance();
        final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final c in [...lcars.palette, lcarsLit]) {
        expect(contrast(lcarsInk, c), greaterThanOrEqualTo(4.5), reason: '$c');
      }
    });

    test('a block picked by name is the same from one run to the next', () {
      expect(lcarsIndex('Clock 54'), lcarsIndex('Clock 54'));
      expect(lcarsIndex('Clock 54'), isNot(lcarsIndex('Clock 55')));
      expect(lcarsIndex(''), 0);
    });
  });

  group('Material\'s parts on a console', () {
    final app = buildTheme(lcars);

    test('a filled button is a pill of the accent, lettered in black', () {
      final style = app.filledButtonTheme.style!;
      expect(style.backgroundColor!.resolve({}), lcars.accent);
      expect(style.foregroundColor!.resolve({}), lcarsInk);
      expect(style.shape!.resolve({}), isA<StadiumBorder>());
    });

    test('a dialog is black with an edge, since it sits on black', () {
      final shape = app.dialogTheme.shape! as RoundedRectangleBorder;
      expect(app.dialogTheme.backgroundColor, lcars.background.first);
      expect(shape.side.color, lcars.accent);
    });

    test('other themes are left as they were', () {
      final glass = buildTheme(kBuiltInThemes.first);
      expect(glass.dialogTheme.shape, isNull);
      expect(glass.switchTheme.trackColor, isNull);
    });
  });

  group('the shared parts on a console', () {
    testWidgets('a screen is headed by a text bar, in capitals', (tester) async {
      await tester.pumpWidget(
        console(const HeaderTitle(title: 'Settings', subtitle: 'Connected')),
      );
      expect(find.byType(LcarsTextBar), findsOneWidget);
      expect(find.text('SETTINGS'), findsOneWidget);
      expect(find.text('CONNECTED'), findsOneWidget);
      expect(tester.widget<Text>(find.text('SETTINGS')).style!.color,
          lcars.accent);
    });

    testWidgets('a group of settings is a panel with its rows inside',
        (tester) async {
      await tester.pumpWidget(
        console(
          const GlassSection(
            title: 'Display',
            children: [ListTile(title: Text('Brightness'))],
          ),
        ),
      );
      expect(find.byType(LcarsPanel), findsOneWidget);
      expect(find.text('Brightness'), findsOneWidget);
    });

    testWidgets('a button in a strip is a block, lit while chosen',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        console(
          Row(
            children: [
              PillIconButton(icon: Icons.photo, onPressed: () => taps++),
              PillIconButton(icon: Icons.dashboard, onPressed: () {}, selected: true),
            ],
          ),
        ),
      );
      final blocks = tester.widgetList<LcarsBlock>(find.byType(LcarsBlock));
      expect(blocks.first.colour, isNot(lcarsLit));
      expect(blocks.last.colour, lcarsLit);
      await tester.tap(find.byIcon(Icons.photo));
      expect(taps, 1);
    });

    testWidgets('a colour that means something is kept as the block\'s',
        (tester) async {
      const red = Color(0xFFCC0000);
      await tester.pumpWidget(
        console(PillIconButton(icon: Icons.delete, onPressed: () {}, colour: red)),
      );
      expect(tester.widget<LcarsBlock>(find.byType(LcarsBlock)).colour, red);
    });

    testWidgets('a choice is as wide as its word, not the row', (tester) async {
      await tester.pumpWidget(
        console(
          Align(
            alignment: Alignment.topLeft,
            child: ChoicePill(label: 'Newest', selected: true, onTap: () {}),
          ),
        ),
      );
      expect(find.text('NEWEST'), findsOneWidget);
      expect(tester.getSize(find.byType(LcarsBlock)).width, lessThan(200));
    });

    testWidgets('Glass is still glass on any other theme', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: HeaderTitle(title: 'Home'))),
      );
      expect(find.byType(LcarsTextBar), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });
  });

  group('a dashboard tile on a console', () {
    DashboardWidgetConfig tile({int y = 0}) => DashboardWidgetConfig(
      id: 'w1',
      // A type this build does not have, so the tile draws its note and
      // needs none of the services a real widget reads.
      type: 'no_such_widget',
      x: 0,
      y: y,
      width: 4,
      height: 2,
    );

    Future<void> draw(WidgetTester tester, {bool framed = true, int y = 0}) =>
        tester.pumpWidget(
          console(
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 480,
                height: 280,
                child: DashboardTile(
                  config: tile(y: y),
                  theme: lcars,
                  settings: DashboardSettings.fromJson(const {}),
                  framed: framed,
                ),
              ),
            ),
          ),
        );

    testWidgets('is a panel lettered with its name and a number',
        (tester) async {
      await draw(tester);
      final panel = tester.widget<LcarsPanel>(find.byType(LcarsPanel));
      expect(panel.label, matches(RegExp(r'^no_such_widget \d\d$')));
      expect(panel.down, isFalse);
    });

    testWidgets('sweeps down in the lower half of the grid', (tester) async {
      await draw(tester, y: 6);
      expect(tester.widget<LcarsPanel>(find.byType(LcarsPanel)).down, isTrue);
    });

    testWidgets('leaves its contents where they are without its bars',
        (tester) async {
      await draw(tester);
      final framed = tester.getRect(find.textContaining('Unknown widget'));
      await draw(tester, framed: false);
      expect(tester.getRect(find.textContaining('Unknown widget')), framed);
    });
  });
}

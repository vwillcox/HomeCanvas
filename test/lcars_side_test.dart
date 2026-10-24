import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/widgets/lcars.dart';

final lcars = kBuiltInThemes.firstWhere((t) => t.id == 'lcars');

void main() {
  /// A panel of [size] whose widget asks for a side bar of three blocks,
  /// the second one chosen.
  Future<List<String>> panel(
    WidgetTester tester,
    Size size, {
    bool asks = true,
  }) async {
    final tapped = <String>[];
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const inside = SizedBox.expand(key: Key('inside'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: LcarsPanel(
            theme: lcars,
            label: 'Station',
            child: asks
                ? LcarsSide(
                    blocks: [
                      for (final (i, name) in ['One', 'Two', 'Three'].indexed)
                        LcarsSideBlock(
                          label: name,
                          selected: i == 1,
                          onTap: () => tapped.add(name),
                        ),
                    ],
                    child: inside,
                  )
                : inside,
          ),
        ),
      ),
    );
    // Asked for as the widget is built, and drawn from the frame after.
    await tester.pump();
    return tapped;
  }

  double insideLeft(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(const Key('inside'))).dx;

  testWidgets('a screen to itself draws its side bar wide, as the blocks', (
    tester,
  ) async {
    final tapped = await panel(tester, const Size(1920, 1100));
    expect(find.text('ONE'), findsOneWidget);
    expect(find.text('TWO'), findsOneWidget);
    expect(find.text('THREE'), findsOneWidget);
    // The widget moves over for the wider bar.
    expect(insideLeft(tester), greaterThan(140));
    await tester.tap(find.text('THREE'));
    expect(tapped, ['Three']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chosen block is lit', (tester) async {
    await panel(tester, const Size(1920, 1100));
    Color colourOf(String label) => tester
        .widget<Material>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Material))
              .first,
        )
        .color!;
    expect(colourOf('TWO'), lcarsLit);
    expect(colourOf('THREE'), isNot(lcarsLit));
  });

  testWidgets(
    'the first is the foot of the elbow, and the last block is bare',
    (tester) async {
      final tapped = await panel(tester, const Size(1920, 1100));
      // Above the column of blocks, on the elbow, and a touch there counts.
      expect(
        tester.getTopLeft(find.text('ONE')).dy,
        lessThan(tester.getTopLeft(find.text('TWO')).dy),
      );
      await tester.tap(find.text('ONE'));
      expect(tapped, ['One']);
      // Two of the three in the column under the elbow, and an empty foot:
      // numbered 02 and 03, with no 04.
      expect(find.text('02'), findsOneWidget);
      expect(find.text('03'), findsOneWidget);
      expect(find.text('04'), findsNothing);
    },
  );

  testWidgets('a small panel keeps its plain bar, whatever is asked', (
    tester,
  ) async {
    await panel(tester, const Size(800, 480));
    expect(find.text('ONE'), findsNothing);
    expect(insideLeft(tester), lessThan(40));
  });

  testWidgets('a widget that does not ask gets the plain bar', (tester) async {
    await panel(tester, const Size(1920, 1100), asks: false);
    expect(find.text('ONE'), findsNothing);
    expect(insideLeft(tester), lessThan(40));
  });

  testWidgets('the bar goes back to plain when the widget goes', (
    tester,
  ) async {
    await panel(tester, const Size(1920, 1100));
    expect(find.text('ONE'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LcarsPanel(
            theme: lcars,
            label: 'Station',
            child: const SizedBox.expand(key: Key('inside')),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('ONE'), findsNothing);
    expect(insideLeft(tester), lessThan(40));
  });
}

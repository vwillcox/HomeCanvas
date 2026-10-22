import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/widgets/on_screen_keyboard.dart';

void main() {
  Future<TextEditingController> pump(
    WidgetTester tester, {
    TextInputType type = TextInputType.text,
    ValueChanged<String>? onSubmitted,
    List<TextInputFormatter>? formatters,
  }) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => OnScreenKeyboard(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              TextField(
                controller: controller,
                keyboardType: type,
                onSubmitted: onSubmitted,
                inputFormatters: formatters,
              ),
              const Text('elsewhere'),
            ],
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('nothing shows until a field has focus', (tester) async {
    await pump(tester);
    expect(find.byIcon(Icons.keyboard_hide_outlined), findsNothing);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_hide_outlined), findsOneWidget);
    expect(find.text('q'), findsOneWidget);
  });

  testWidgets('types into the field, through its formatters', (tester) async {
    final c = await pump(
      tester,
      formatters: [LengthLimitingTextInputFormatter(3)],
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    for (final k in ['h', 'i', 'y', 'o']) {
      await tester.tap(find.text(k));
      await tester.pump();
    }
    expect(c.text, 'hiy');
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(c.text, 'hi');
    // Typing must not have taken the focus away from the field.
    expect(find.text('q'), findsOneWidget);
  });

  testWidgets('a number field gets a number pad, and enter submits', (
    tester,
  ) async {
    String? submitted;
    final c = await pump(
      tester,
      type: TextInputType.number,
      onSubmitted: (v) => submitted = v,
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('q'), findsNothing);
    for (final k in ['4', '2', '0', '7']) {
      await tester.tap(find.text(k).last);
      await tester.pump();
    }
    expect(c.text, '4207');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(submitted, '4207');
  });

  testWidgets('hiding lets go of the field', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_hide_outlined));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_hide_outlined), findsNothing);
  });

  testWidgets('fills the screen when what it holds takes no space', (
    tester,
  ) async {
    // As the app's Stack is with a full-screen video up: the page Offstage,
    // and the video Positioned.fill over it.
    await tester.pumpWidget(
      const MaterialApp(
        home: OnScreenKeyboard(
          child: Stack(
            children: [
              Offstage(child: SizedBox(width: 100, height: 100)),
              Positioned.fill(child: ColoredBox(color: Colors.black)),
            ],
          ),
        ),
      ),
    );
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(tester.getSize(find.byType(ColoredBox).last), screen);
  });
}

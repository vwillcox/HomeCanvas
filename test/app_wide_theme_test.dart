import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:immich_kiosk_pi/dashboard/dashboard_theme.dart';
import 'package:immich_kiosk_pi/look.dart';
import 'package:immich_kiosk_pi/theme.dart';
import 'package:immich_kiosk_pi/widgets/glass.dart';

DashboardTheme byId(String id) => kBuiltInThemes.firstWhere((t) => t.id == id);

void main() {
  group('the app theme, built from the kiosk\'s theme', () {
    test('Glass builds the dark app it always was', () {
      final app = buildTheme(byId('glass'));
      expect(app.brightness, Brightness.dark);
      expect(app.colorScheme.primary, byId('glass').accent);
      expect(app.scaffoldBackgroundColor, byId('glass').background.first);
    });

    test('a light theme builds a light app, in its own colours', () {
      final swiss = byId('swiss');
      final app = buildTheme(swiss);
      expect(app.brightness, Brightness.light);
      expect(app.colorScheme.primary, swiss.accent);
      expect(app.textTheme.bodyMedium!.color, swiss.textPrimary);
      expect(app.iconTheme.color, swiss.textPrimary);
    });

    test('a theme with a font sets it for the whole app', () {
      expect(buildTheme(byId('terminal')).textTheme.bodyMedium!.fontFamily,
          'ShareTechMono');
    });
  });

  group('colours by role', () {
    test('legible leaves a dark theme\'s colours alone', () {
      const pale = Color(0xFFFFD98A);
      expect(byId('glass').legible(pale), pale);
    });

    test('legible deepens a pale colour on a light theme, keeping its hue', () {
      const pale = Color(0xFFFFD98A);
      final deep = byId('frost').legible(pale);
      expect(HSLColor.fromColor(deep).lightness, lessThanOrEqualTo(0.401));
      expect(HSLColor.fromColor(deep).hue,
          closeTo(HSLColor.fromColor(pale).hue, 1));
    });

    test('text on the accent is whichever of black and white reads', () {
      expect(byId('glass').onAccent, const Color(0xFF0B0C10)); // pale blue
      expect(byId('swiss').onAccent, Colors.white); // signal red
    });

    test('the wash is white on a dark theme and dark on a light one', () {
      expect(byId('glass').wash(0.1).computeLuminance(),
          greaterThan(byId('swiss').wash(0.1).computeLuminance()));
    });
  });

  testWidgets('the shared parts draw in whatever theme is above them',
      (tester) async {
    final swiss = byId('swiss');
    await tester.pumpWidget(
      KioskLook(
        theme: swiss,
        child: MaterialApp(
          theme: buildTheme(swiss),
          home: const Scaffold(body: HeaderTitle(title: 'Settings')),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('Settings'));
    expect(text.style!.color, swiss.textPrimary);
  });

  testWidgets('without a theme above, they fall back to Glass',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HeaderTitle(title: 'Home'))),
    );
    final text = tester.widget<Text>(find.text('Home'));
    expect(text.style!.color, byId('glass').textPrimary);
  });
}

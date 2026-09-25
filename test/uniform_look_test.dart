import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:immich_kiosk_pi/dashboard/dashboard_model.dart';
import 'package:immich_kiosk_pi/dashboard/dashboard_theme.dart';
import 'package:immich_kiosk_pi/theme.dart';
import 'package:immich_kiosk_pi/widgets/glass.dart';

void main() {
  group('the Glass dashboard theme', () {
    final glass = kBuiltInThemes.firstWhere((t) => t.id == 'glass');

    test('uses the kiosk\'s own accent, so the two cannot drift apart', () {
      expect(glass.accent, buildTheme().colorScheme.primary);
    });

    test('draws the same glow as the home screen', () {
      final bg = glass.backgroundDecoration;
      expect(bg.gradient, isA<RadialGradient>());
      final g = bg.gradient! as RadialGradient;
      expect(g.center, const Alignment(-0.85, -1.1));
    });

    test('survives being written out and read back, glow and all', () {
      final back = DashboardTheme.fromJson(glass.toJson());
      expect(back.glow, glass.glow);
      expect(back.accent, glass.accent);
      expect(back.cornerRadius, glass.cornerRadius);
    });

    test('a theme without a glow keeps its plain background', () {
      final midnight = kBuiltInThemes.firstWhere((t) => t.id == 'midnight');
      expect(midnight.glow, isNull);
      expect(midnight.toJson().containsKey('glow'), isFalse);
      expect(midnight.backgroundDecoration.gradient, isA<LinearGradient>());
    });
  });

  group('the Aurora dashboard theme', () {
    final aurora = kBuiltInThemes.firstWhere((t) => t.id == 'aurora');

    test('is glass: see-through tiles, tight gaps, the first glow', () {
      final glass = kBuiltInThemes.firstWhere((t) => t.id == 'glass');
      expect(aurora.surface.a, lessThan(0.15));
      expect(aurora.gap, glass.gap);
      expect(aurora.backgroundDecoration.gradient, isA<RadialGradient>());
    });

    test('adds a second glow from the bottom right, fading to nothing', () {
      final g = aurora.glowEndDecoration!.gradient! as RadialGradient;
      final c = g.center as Alignment;
      expect(c.x, greaterThan(0));
      expect(c.y, greaterThan(0));
      expect(g.colors.last.a, 0);
    });

    test('lights the top of each tile, and only the top', () {
      final g = aurora.tileDecoration.gradient! as LinearGradient;
      expect(g.colors.first, isNot(g.colors.last));
      expect(g.colors.last, aurora.surface);
      expect(aurora.tileDecoration.color, isNull);
    });

    test('survives being written out and read back, sheen and all', () {
      final back = DashboardTheme.fromJson(aurora.toJson());
      expect(back.glowEnd, aurora.glowEnd);
      expect(back.sheen, aurora.sheen);
    });

    test('a theme without them is unchanged: one glow, flat tiles', () {
      final glass = kBuiltInThemes.firstWhere((t) => t.id == 'glass');
      expect(glass.glowEndDecoration, isNull);
      expect(glass.tileDecoration.gradient, isNull);
      expect(glass.tileDecoration.color, glass.surface);
      expect(glass.toJson().containsKey('sheen'), isFalse);
    });
  });

  group('the dashboard top bar', () {
    test('is on for a dashboard saved before it existed', () {
      expect(DashboardSettings.fromJson({}).topBar, isTrue);
    });

    test('stays off once switched off', () {
      final s = DashboardSettings(topBar: false);
      expect(DashboardSettings.fromJson(s.toJson()).topBar, isFalse);
    });
  });

  group('the shared header', () {
    Widget host(Widget child) => MaterialApp(
          home: Scaffold(backgroundColor: Colors.black, body: child),
        );

    testWidgets('shows a back button only when there is somewhere to go',
        (tester) async {
      await tester.pumpWidget(host(const ScreenHeader(title: 'Settings')));
      expect(find.byType(GlassIconButton), findsNothing);

      var backed = 0;
      await tester.pumpWidget(host(ScreenHeader(
        title: 'Settings',
        onBack: () => backed++,
      )));
      await tester.tap(find.byType(GlassIconButton));
      expect(backed, 1);
    });

    testWidgets('gathers its actions into one pill', (tester) async {
      await tester.pumpWidget(host(ScreenHeader(
        title: 'Home',
        actions: [
          PillIconButton(icon: Icons.refresh, onPressed: () {}),
          PillIconButton(icon: Icons.settings, onPressed: () {}),
        ],
      )));
      expect(find.byType(Glass), findsOneWidget);
      expect(
        find.descendant(
            of: find.byType(Glass), matching: find.byType(PillIconButton)),
        findsNWidgets(2),
      );
    });

    testWidgets('takes a theme\'s colours for its title', (tester) async {
      const ink = Color(0xFF1E1B16);
      await tester.pumpWidget(host(const HeaderTitle(
        title: 'Paper',
        subtitle: 'a light theme',
        colour: ink,
      )));
      final t = tester.widget<Text>(find.text('Paper'));
      expect(t.style!.color, ink);
    });
  });
}

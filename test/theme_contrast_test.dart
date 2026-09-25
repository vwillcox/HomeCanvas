import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:immich_kiosk_pi/dashboard/dashboard_theme.dart';

/// WCAG contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Every colour a tile can end up behind its text: the surface over each
/// background colour, over the glows, and under the sheen at its top.
List<Color> tileColours(DashboardTheme t) {
  final grounds = [
    ...t.background,
    if (t.glow != null) Color.alphaBlend(t.glow!, t.background.first),
    if (t.glowEnd != null) Color.alphaBlend(t.glowEnd!, t.background.first),
  ];
  return [
    for (final g in grounds) ...[
      Color.alphaBlend(t.surface, g),
      if (t.sheen > 0)
        Color.alphaBlend(
          Colors.white.withValues(alpha: t.sheen),
          Color.alphaBlend(t.surface, g),
        ),
    ],
  ];
}

void main() {
  // A new theme has to be readable, however good it looks: body text at
  // WCAG AA or better, secondary text and the accent at the large-text
  // minimum, since both are used big or as marks on a panel across a room.
  for (final t in kBuiltInThemes) {
    group('the ${t.name} theme', () {
      test('keeps its text readable on its tiles', () {
        for (final tile in tileColours(t)) {
          final secondary = Color.alphaBlend(t.textSecondary, tile);
          expect(contrast(t.textPrimary, tile), greaterThanOrEqualTo(7),
              reason: 'text on $tile');
          expect(contrast(secondary, tile), greaterThanOrEqualTo(3.5),
              reason: 'secondary text on $tile');
          expect(contrast(t.accent, tile), greaterThanOrEqualTo(3),
              reason: 'accent on $tile');
        }
      });

      test('survives being written out and read back', () {
        final back = DashboardTheme.fromJson(t.toJson());
        expect(back.id, t.id);
        expect(back.surface, t.surface);
        expect(back.glow, t.glow);
        expect(back.glowEnd, t.glowEnd);
        expect(back.sheen, t.sheen);
        expect(back.fontFamily, t.fontFamily);
      });
    });
  }

  test('every theme has an id of its own', () {
    final ids = kBuiltInThemes.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('Glass stays first, as the theme to fall back on', () {
    expect(kBuiltInThemes.first.id, 'glass');
  });
}

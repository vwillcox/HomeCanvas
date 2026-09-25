import 'package:flutter/material.dart';

import 'dashboard/dashboard_theme.dart';

/// Fonts to draw what the chosen font has no glyph for — emoji, mainly.
///
/// Flutter on the Pi does not reach for the system's emoji font by itself,
/// so it is named. Naming any fallback also replaces Flutter's own list of
/// Linux defaults — without them, text with no font of its own draws no
/// letters at all — so those are named too, in Flutter's order, with the
/// emoji font straight after the one the panel uses. A name that is not
/// installed costs nothing.
const fontFallback = [
  'Ubuntu',
  'Cantarell',
  'Noto Color Emoji',
  'DejaVu Sans',
  'Liberation Sans',
  'Arial',
];

/// The app's Material theme, drawn from the kiosk's [look] — Glass unless
/// another is chosen — with generous hit targets for a 10" DSI panel.
///
/// Material's own parts (dialogs, menus, switches, sliders, text fields,
/// snack bars) take their colours from here, so they follow the theme
/// without each screen having to dress them.
ThemeData buildTheme([DashboardTheme? look]) {
  final t = look ?? kBuiltInThemes.first;
  final brightness = t.isLight ? Brightness.light : Brightness.dark;
  final solid = t.solidSurface;
  // A raised surface for dialogs and menus: a step lighter than the tiles on
  // a dark theme, a step darker on a light one.
  final raised = Color.alphaBlend(
    t.wash(t.isLight ? 0.04 : 0.06),
    solid,
  );
  final scheme = ColorScheme.fromSeed(
    seedColor: t.accent,
    brightness: brightness,
  ).copyWith(
    primary: t.accent,
    onPrimary: t.onAccent,
    surface: t.background.first,
    onSurface: t.textPrimary,
    onSurfaceVariant: Color.alphaBlend(t.textSecondary, t.background.first),
    surfaceContainerLowest: t.background.first,
    surfaceContainerLow: solid,
    surfaceContainer: solid,
    surfaceContainerHigh: raised,
    surfaceContainerHighest: raised,
    outline: t.wash(0.3),
    outlineVariant: t.wash(0.14),
  );
  // The switch's knob: a deeper shade of the accent, as the kiosk's own look
  // pairs a pale blue track with a deep blue knob.
  final knob = HSLColor.fromColor(t.accent)
      .withLightness(t.isLight ? 0.35 : 0.45)
      .toColor();
  final text = ThemeData(brightness: brightness).textTheme.apply(
    bodyColor: t.textPrimary,
    displayColor: t.textPrimary,
    fontFamily: t.fontFamily,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: text,
    fontFamily: t.fontFamily,
    fontFamilyFallback: fontFallback,
    scaffoldBackgroundColor: t.background.first,
    canvasColor: t.background.first,
    visualDensity: VisualDensity.comfortable,
    appBarTheme: AppBarTheme(
      backgroundColor: solid,
      foregroundColor: t.textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w600,
        color: t.textPrimary,
        fontFamily: t.fontFamily,
      ),
      // Tall bar with big hit targets — the panel is driven by fingers.
      toolbarHeight: 96,
      actionsIconTheme: const IconThemeData(size: 36),
      iconTheme: const IconThemeData(size: 36),
    ),
    iconTheme: IconThemeData(size: 28, color: t.textPrimary),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        // In the theme's text colour — styleFrom otherwise applies a default
        // foreground that renders nearly invisible on these surfaces.
        foregroundColor: t.textPrimary,
        minimumSize: const Size(64, 64),
        padding: const EdgeInsets.all(14),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(72, 60),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontSize: 18),
      ),
    ),
    cardTheme: CardThemeData(
      color: solid,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: raised),
    popupMenuTheme: PopupMenuThemeData(color: raised),
    dividerTheme: DividerThemeData(color: t.wash(0.1)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? knob : Colors.grey,
      ),
    ),
  );
}

import 'package:flutter/material.dart';

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

/// Dark, touch-first theme with generous hit targets for a 10" DSI panel.
ThemeData buildTheme() {
  const seed = Color(0xFF4F9DFF);
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamilyFallback: fontFallback,
    scaffoldBackgroundColor: const Color(0xFF0E0F13),
    visualDensity: VisualDensity.comfortable,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF15171E),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      // Tall bar with big hit targets — the panel is driven by fingers.
      toolbarHeight: 96,
      actionsIconTheme: IconThemeData(size: 36),
      iconTheme: IconThemeData(size: 36),
    ),
    iconTheme: const IconThemeData(size: 28),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        // Keep icons white on the dark UI — styleFrom otherwise applies a
        // default foreground that renders nearly invisible on these surfaces.
        foregroundColor: Colors.white,
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
      color: const Color(0xFF1B1E27),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? seed : Colors.grey,
      ),
    ),
  );
}

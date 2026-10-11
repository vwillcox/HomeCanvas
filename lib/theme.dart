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

  final app = ThemeData(
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
  return t.isLcars ? _console(app, t) : app;
}

/// Material's parts as a starship's console draws them: every button a solid
/// pill with its lettering in black, every edge a line of flat colour, and
/// nothing with a shadow or a tint.
///
/// Over [app], which has the colours and the type right already; this
/// changes the shapes.
ThemeData _console(ThemeData app, DashboardTheme t) {
  const ink = Color(0xFF000000);
  final black = t.background.first;
  final lilac = t.block(1), blue = t.block(2);
  // Lit: a switch that is on, a segment that is chosen.
  final lit = Color.lerp(t.textPrimary, Colors.white, 0.55)!;
  // A block with nothing to do: its colour, most of the way to black.
  Color unlit(Color c) => Color.alphaBlend(c.withValues(alpha: 0.35), black);
  final label = TextStyle(
    fontFamily: t.fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
  );
  // A dialog, a menu, a sheet: black, with an edge to stand it off the
  // black behind.
  RoundedRectangleBorder edged(double radius, Color c) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: c, width: 3),
      );
  WidgetStateProperty<Color?> when(Color on, Color off, {Color? disabled}) =>
      WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? (disabled ?? unlit(off))
            : s.contains(WidgetState.selected)
            ? on
            : off,
      );

  return app.copyWith(
    colorScheme: app.colorScheme.copyWith(
      secondary: lilac,
      onSecondary: ink,
      tertiary: blue,
      onTertiary: ink,
      secondaryContainer: lit,
      onSecondaryContainer: ink,
      surfaceTint: Colors.transparent,
    ),
    splashColor: t.accent.withValues(alpha: 0.25),
    highlightColor: t.accent.withValues(alpha: 0.12),
    appBarTheme: app.appBarTheme.copyWith(
      backgroundColor: black,
      foregroundColor: t.accent,
      titleTextStyle: app.appBarTheme.titleTextStyle?.copyWith(
        color: t.accent,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.5,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: ink,
        disabledBackgroundColor: unlit(t.accent),
        disabledForegroundColor: ink,
        minimumSize: const Size(96, 56),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        shape: const StadiumBorder(),
        textStyle: label,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: lilac,
        foregroundColor: ink,
        disabledBackgroundColor: unlit(lilac),
        disabledForegroundColor: ink,
        elevation: 0,
        minimumSize: const Size(96, 56),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        shape: const StadiumBorder(),
        textStyle: label,
      ),
    ),
    // The quieter button beside a filled one — Cancel beside Save — is a
    // pill too, in the cooler colour.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        backgroundColor: blue,
        foregroundColor: ink,
        disabledBackgroundColor: unlit(blue),
        disabledForegroundColor: ink,
        minimumSize: const Size(96, 56),
        padding: const EdgeInsets.symmetric(horizontal: 26),
        shape: const StadiumBorder(),
        textStyle: label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.textPrimary,
        minimumSize: const Size(96, 56),
        padding: const EdgeInsets.symmetric(horizontal: 26),
        shape: const StadiumBorder(),
        side: BorderSide(color: lilac, width: 3),
        textStyle: label,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: when(lit, blue),
        foregroundColor: const WidgetStatePropertyAll(ink),
        iconColor: const WidgetStatePropertyAll(ink),
        side: WidgetStatePropertyAll(BorderSide(color: black, width: 3)),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: WidgetStatePropertyAll(label.copyWith(fontSize: 18)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.accent,
      foregroundColor: ink,
      elevation: 0,
      shape: const StadiumBorder(),
    ),
    // A switch is a short pill with a black key in it: lit when on.
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(ink),
      trackColor: when(t.accent, unlit(blue), disabled: unlit(lilac)),
      trackOutlineColor: when(t.accent, blue, disabled: unlit(lilac)),
      trackOutlineWidth: const WidgetStatePropertyAll(2),
      thumbIcon: const WidgetStatePropertyAll(null),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 14,
      activeTrackColor: t.accent,
      inactiveTrackColor: unlit(blue),
      thumbColor: lit,
      overlayColor: t.accent.withValues(alpha: 0.2),
      // A square end where the bar is cut, as the rails are.
      trackShape: const RectangularSliderTrackShape(),
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 13,
        elevation: 0,
        pressedElevation: 0,
      ),
      valueIndicatorColor: lit,
      valueIndicatorTextStyle: label.copyWith(color: ink, fontSize: 18),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.accent,
      linearTrackColor: unlit(blue),
      circularTrackColor: unlit(blue),
      linearMinHeight: 10,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: when(t.accent, Colors.transparent, disabled: unlit(lilac)),
      checkColor: const WidgetStatePropertyAll(ink),
      side: BorderSide(color: lilac, width: 2.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    radioTheme: RadioThemeData(fillColor: when(t.accent, lilac)),
    listTileTheme: ListTileThemeData(
      iconColor: lilac,
      textColor: t.textPrimary,
      titleTextStyle: TextStyle(
        fontFamily: t.fontFamily,
        fontSize: 21,
        letterSpacing: 0.6,
        color: t.textPrimary,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: t.fontFamily,
        fontSize: 17,
        letterSpacing: 0.4,
        height: 1.3,
        color: t.textSecondary,
      ),
    ),
    cardTheme: app.cardTheme.copyWith(
      color: black,
      elevation: 0,
      shape: edged(22, blue),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: black,
      elevation: 0,
      shape: edged(34, t.accent),
      titleTextStyle: TextStyle(
        fontFamily: t.fontFamily,
        fontSize: 30,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.5,
        color: t.accent,
      ),
      contentTextStyle: TextStyle(
        fontFamily: t.fontFamily,
        fontSize: 19,
        letterSpacing: 0.4,
        height: 1.35,
        color: t.textPrimary,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: black,
      modalBackgroundColor: black,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
        side: BorderSide(color: t.accent, width: 3),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: black,
      elevation: 0,
      shape: edged(20, lilac),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(black),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(edged(20, lilac)),
      ),
    ),
    // A drop-down's list is drawn on the canvas colour, and can be given no
    // edge: a step off black, so it can be told from the screen.
    canvasColor: t.solidSurface,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: black,
      labelStyle: TextStyle(color: t.textSecondary, letterSpacing: 0.8),
      floatingLabelStyle: TextStyle(color: t.accent, letterSpacing: 0.8),
      hintStyle: TextStyle(color: t.wash(0.4)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: blue, width: 2.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: blue, width: 2.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: t.accent, width: 3),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.accent,
      selectionColor: t.accent.withValues(alpha: 0.35),
      selectionHandleColor: t.accent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.accent,
      contentTextStyle: label.copyWith(color: ink, fontWeight: FontWeight.w500),
      actionTextColor: ink,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: const StadiumBorder(),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: ShapeDecoration(color: lit, shape: const StadiumBorder()),
      textStyle: label.copyWith(color: ink, fontSize: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: lilac,
      selectedColor: lit,
      disabledColor: unlit(lilac),
      labelStyle: label.copyWith(color: ink, fontSize: 17),
      secondaryLabelStyle: label.copyWith(color: ink, fontSize: 17),
      iconTheme: const IconThemeData(color: ink, size: 22),
      checkmarkColor: ink,
      deleteIconColor: ink,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      elevation: 0,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: t.accent,
      unselectedLabelColor: t.textSecondary,
      indicatorColor: t.accent,
      dividerColor: Colors.transparent,
      labelStyle: label,
      unselectedLabelStyle: label,
    ),
    dividerTheme: DividerThemeData(color: t.wash(0.16), thickness: 1),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(lilac.withValues(alpha: 0.7)),
      radius: const Radius.circular(6),
      thickness: const WidgetStatePropertyAll(8),
    ),
  );
}

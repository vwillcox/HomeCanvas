import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// How a theme draws its frames: the tile behind each widget, a screen's
/// edges, its buttons.
enum ThemeStyle {
  /// A panel behind each widget — glass, gloss or flat, by the colours.
  panels,

  /// A starship's console: black, with bars of flat colour swept round
  /// each panel's corner, block buttons and condensed capitals. Drawn by
  /// `widgets/lcars.dart`.
  lcars,
}

/// How a dashboard looks.
///
/// A theme is data, not code, so a new one is a JSON file rather than a
/// change to this app — drop it in `~/.config/homecanvas/themes/` and it
/// appears in the picker. Every theme but Glass is an add-on in the
/// catalogue, downloaded to that folder; `deploy/theme-template.json` is a
/// commented copy to start from.
class DashboardTheme {
  final String id;
  final String name;

  /// Painted behind everything. Two colours make a vertical gradient; one
  /// makes a flat background.
  final List<Color> background;

  /// The tile behind each widget, and its edge. A fully transparent surface
  /// with a transparent border gives a flat look with no panels at all.
  final Color surface;
  final Color border;

  final Color textPrimary;
  final Color textSecondary;

  /// Used for the things a glance should land on first — the time, now
  /// playing, a temperature.
  final Color accent;

  final double cornerRadius;

  /// Gap between tiles, in logical pixels.
  final double gap;

  /// Optional font for the whole dashboard. Null uses the app's own.
  final String? fontFamily;

  /// Widget tiles cast a soft shadow. Off suits flat and light themes.
  final bool shadow;

  /// A soft glow of colour from the top left, over [background] — the look of
  /// the kiosk's own home screen. Null for a plain background.
  final Color? glow;

  /// A second glow, from the bottom right. Null for none.
  final Color? glowEnd;

  /// Light along the top of each tile, as on a pane of glass catching it:
  /// how much white it starts with, 0 for none. Around 0.05 to 0.1 reads as
  /// glass; much more reads as a gradient.
  final double sheen;

  /// How the frames are drawn. Everything above is colour and measure;
  /// this is the one setting that changes the drawing itself.
  final ThemeStyle style;

  /// The colours an [ThemeStyle.lcars] theme's blocks are drawn in, taken in
  /// turn. Empty for a theme with panels, which needs none.
  final List<Color> palette;

  const DashboardTheme({
    required this.id,
    required this.name,
    required this.background,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    this.cornerRadius = 20,
    this.gap = 14,
    this.fontFamily,
    this.shadow = true,
    this.glow,
    this.glowEnd,
    this.sheen = 0,
    this.style = ThemeStyle.panels,
    this.palette = const [],
  });

  static Color _colour(Object? v, Color fallback) {
    if (v is! String) return fallback;
    var s = v.trim().replaceFirst('#', '');
    if (s.length == 6) s = 'ff$s';
    final n = int.tryParse(s, radix: 16);
    return n == null ? fallback : Color(n);
  }

  factory DashboardTheme.fromJson(Map<String, dynamic> j) {
    final bg = j['background'];
    final palette = j['palette'];
    return DashboardTheme(
      id: j['id'] as String? ?? 'custom',
      name: j['name'] as String? ?? 'Custom',
      background: bg is List
          ? bg.map((c) => _colour(c, const Color(0xFF101014))).toList()
          : [_colour(bg, const Color(0xFF101014))],
      surface: _colour(j['surface'], const Color(0x1AFFFFFF)),
      border: _colour(j['border'], const Color(0x22FFFFFF)),
      textPrimary: _colour(j['textPrimary'], Colors.white),
      textSecondary: _colour(j['textSecondary'], Colors.white70),
      accent: _colour(j['accent'], const Color(0xFF7DD3FC)),
      cornerRadius: (j['cornerRadius'] as num?)?.toDouble() ?? 20,
      gap: (j['gap'] as num?)?.toDouble() ?? 14,
      fontFamily: j['fontFamily'] as String?,
      shadow: j['shadow'] as bool? ?? true,
      glow: j['glow'] == null ? null : _colour(j['glow'], Colors.transparent),
      glowEnd: j['glowEnd'] == null
          ? null
          : _colour(j['glowEnd'], Colors.transparent),
      sheen: ((j['sheen'] as num?)?.toDouble() ?? 0).clamp(0.0, 0.5),
      style: ThemeStyle.values.firstWhere(
        (s) => s.name == j['style'],
        orElse: () => ThemeStyle.panels,
      ),
      palette: palette is List
          ? palette.map((c) => _colour(c, Colors.transparent)).toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'background': background
        .map(
          (c) =>
              '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
        )
        .toList(),
    'surface': _hex(surface),
    'border': _hex(border),
    'textPrimary': _hex(textPrimary),
    'textSecondary': _hex(textSecondary),
    'accent': _hex(accent),
    'cornerRadius': cornerRadius,
    'gap': gap,
    'fontFamily': fontFamily,
    'shadow': shadow,
    if (glow != null) 'glow': _hex(glow!),
    if (glowEnd != null) 'glowEnd': _hex(glowEnd!),
    if (sheen > 0) 'sheen': sheen,
    if (style != ThemeStyle.panels) 'style': style.name,
    if (palette.isNotEmpty) 'palette': palette.map(_hex).toList(),
  };

  static String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0')}';

  BoxDecoration get backgroundDecoration => glow != null
      ? BoxDecoration(
          color: background.first,
          // The same glow, in the same place, as the home screen's.
          gradient: RadialGradient(
            center: const Alignment(-0.85, -1.1),
            radius: 1.4,
            colors: [glow!, background.first],
            stops: const [0.0, 0.7],
          ),
        )
      : BoxDecoration(
          gradient: background.length > 1
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: background,
                )
              : null,
          color: background.length == 1 ? background.first : null,
        );

  /// The second glow, as a layer over [backgroundDecoration]: a
  /// decoration has room for one gradient. Fades to its own colour at no
  /// opacity rather than to the background, so the first glow shows through.
  BoxDecoration? get glowEndDecoration => glowEnd == null
      ? null
      : BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.95, 1.15),
            radius: 1.3,
            colors: [glowEnd!, glowEnd!.withValues(alpha: 0)],
            stops: const [0.0, 0.7],
          ),
        );

  /// Drawn as a starship's console rather than as panels.
  bool get isLcars => style == ThemeStyle.lcars;

  /// The [i]th of the [palette]'s colours, going round again past the end —
  /// so neighbouring blocks differ and the same block is always the same
  /// colour. The accent where a theme names no palette.
  Color block(int i) =>
      palette.isEmpty ? accent : palette[i.abs() % palette.length];

  /// A light theme — dark text on a pale background.
  bool get isLight => background.first.computeLuminance() > 0.4;

  /// Text and icons drawn on [accent]: whichever of near-black and white
  /// reads better on it.
  Color get onAccent {
    const dark = Color(0xFF0B0C10);
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (la > lb ? la + 0.05 : lb + 0.05) /
          (la > lb ? lb + 0.05 : la + 0.05);
    }

    return contrast(accent, dark) >= contrast(accent, Colors.white)
        ? dark
        : Colors.white;
  }

  /// The tile's colour as it lands on the background — for things that
  /// must be opaque, such as a dialog or a menu.
  Color get solidSurface => Color.alphaBlend(surface, background.first);

  /// [c] made readable on this theme: unchanged on a dark one; on a light
  /// one, deepened to at most 40% lightness, hue kept — so the pale yellows
  /// and blues chosen for dark screens (weather icons, a temperature's
  /// orange) still mean the same thing and can still be seen.
  Color legible(Color c) {
    if (!isLight) return c;
    final hsl = HSLColor.fromColor(c);
    return hsl.lightness <= 0.4 ? c : hsl.withLightness(0.4).toColor();
  }

  /// A faint wash of the text colour: a hairline, a pressed state, a track.
  /// White on a dark theme and near-black on a light one, so the same
  /// strength reads alike on both.
  Color wash(double alpha) => textPrimary.withValues(alpha: alpha);

  BoxDecoration get tileDecoration => tileDecorationWith();

  /// The tile's look, with the dashboard's own overrides applied over the
  /// theme's preferences.
  BoxDecoration tileDecorationWith({double? radius, bool? withShadow}) =>
      BoxDecoration(
        color: sheen > 0 ? null : surface,
        // The sheen: the top of the tile a little lighter, gone by the
        // middle, over the same surface.
        gradient: sheen > 0
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(
                    Colors.white.withValues(alpha: sheen),
                    surface,
                  ),
                  surface,
                ],
                stops: const [0, 0.45],
              )
            : null,
        borderRadius: BorderRadius.circular(radius ?? cornerRadius),
        border: Border.all(color: border),
        boxShadow: (withShadow ?? shadow)
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      );
}

/// The one theme the app ships: the kiosk's own look, and the one to fall
/// back on when the theme chosen is not on the panel. The rest — LCARS,
/// Paper, Terminal and the others — are add-ons, theme.json files in the
/// catalogue, downloaded from the Add-ons page.
const List<DashboardTheme> kBuiltInThemes = [
  // The kiosk's own look — the home screen, albums and settings — so the
  // dashboard can match them: the same near-black with a soft blue glow, and
  // tiles like the frosted cards everywhere else.
  DashboardTheme(
    id: 'glass',
    name: 'Glass',
    background: [Color(0xFF0B0C10)],
    glow: Color(0x29A6C8FF),
    surface: Color(0x12FFFFFF),
    border: Color(0x1CFFFFFF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0x99FFFFFF),
    accent: Color(0xFFA6C8FF),
    cornerRadius: 24,
    // Tight, like the photo wall: the tiles read as one panel of glass
    // rather than islands with a channel of background between each.
    gap: 10,
  ),
];

/// Glass plus every theme in the themes directory: those downloaded as
/// add-ons, and any made by hand.
///
/// A file whose id matches a built-in replaces it, so a shipped theme can be
/// adjusted without editing the app.
class ThemeRepository {
  ThemeRepository(this._directory);

  final String _directory;

  List<DashboardTheme> _custom = const [];

  static String defaultDirectory() {
    final home = Platform.environment['HOME'] ?? '.';
    return p.join(home, '.config', 'homecanvas', 'themes');
  }

  List<DashboardTheme> get all {
    final byId = {for (final t in kBuiltInThemes) t.id: t};
    for (final t in _custom) {
      byId[t.id] = t;
    }
    return byId.values.toList();
  }

  DashboardTheme byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);

  /// Reads every `.json` file in the themes directory. A malformed file is
  /// skipped and logged rather than taken as fatal — one bad theme should not
  /// cost you the dashboard.
  Future<void> load() async {
    final dir = Directory(_directory);
    if (!await dir.exists()) {
      _custom = const [];
      return;
    }
    final found = <DashboardTheme>[];
    await for (final entry in dir.list()) {
      if (entry is! File || p.extension(entry.path) != '.json') continue;
      try {
        final data = jsonDecode(await entry.readAsString());
        if (data is Map<String, dynamic>) {
          found.add(DashboardTheme.fromJson(data));
        }
      } catch (e) {
        debugPrint('Dashboard: skipping theme ${entry.path}: $e');
      }
    }
    _custom = found;
  }
}

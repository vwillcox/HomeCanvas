import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// How a dashboard looks.
///
/// A theme is data, not code, so a new one is a JSON file rather than a
/// change to this app — drop it in `~/.config/immich_kiosk_pi/themes/` and it
/// appears in the picker. The built-ins below are the same shape and double
/// as worked examples; `deploy/theme-template.json` is a commented copy to
/// start from.
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

/// Shipped themes. Each is a plain value, so any of them can be copied into a
/// JSON file and adjusted.
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
  // Glass after dark: the same frosted tiles, tight gaps and big corners,
  // over an inkier black lit from two corners at once — violet from the top
  // left, teal from the bottom right — with light catching the top of each
  // pane. The mint accent sits between the two glows.
  DashboardTheme(
    id: 'aurora',
    name: 'Aurora',
    background: [Color(0xFF07080E)],
    glow: Color(0x338E7BFF),
    glowEnd: Color(0x3833D6C0),
    surface: Color(0x14DDE3FF),
    border: Color(0x22E6EAFF),
    sheen: 0.07,
    textPrimary: Color(0xFFF6F7FF),
    textSecondary: Color(0x9EF6F7FF),
    accent: Color(0xFF8FF0DC),
    cornerRadius: 26,
    gap: 10,
  ),
  // Deep water: blue light from above, cyan from below, and very clear glass.
  DashboardTheme(
    id: 'abyss',
    name: 'Abyss',
    background: [Color(0xFF020A14)],
    glow: Color(0x2E1E90FF),
    glowEnd: Color(0x2600E5FF),
    surface: Color(0x12BFE7FF),
    border: Color(0x24BFE7FF),
    sheen: 0.05,
    textPrimary: Color(0xFFEAF8FF),
    textSecondary: Color(0x99EAF8FF),
    accent: Color(0xFF5CE1FF),
    cornerRadius: 28,
    gap: 12,
  ),
  // Black lacquer: solid tiles, not glass, with a strong gloss along the top
  // and a champagne-gold accent. Glossy rather than glassy.
  DashboardTheme(
    id: 'obsidian',
    name: 'Obsidian',
    background: [Color(0xFF050506), Color(0xFF111216)],
    surface: Color(0xF0191A1F),
    border: Color(0x2EFFFFFF),
    sheen: 0.10,
    textPrimary: Color(0xFFF4F1EA),
    textSecondary: Color(0x99F4F1EA),
    accent: Color(0xFFE9C46A),
    cornerRadius: 22,
  ),
  // Eighties neon: magenta and cyan light on deep purple, tiles edged in
  // pink and glossed, in a techno face that stays readable.
  DashboardTheme(
    id: 'synthwave',
    name: 'Synthwave',
    background: [Color(0xFF12002A)],
    glow: Color(0x40FF2E97),
    glowEnd: Color(0x3300E5FF),
    surface: Color(0xB3190733),
    border: Color(0x66FF6AD5),
    sheen: 0.08,
    textPrimary: Color(0xFFFDF0FF),
    textSecondary: Color(0xB3F3D9FF),
    accent: Color(0xFFFF6AD5),
    cornerRadius: 14,
    fontFamily: 'ChakraPetch',
  ),
  DashboardTheme(
    id: 'midnight',
    name: 'Midnight',
    background: [Color(0xFF0B0F1A), Color(0xFF141C2E)],
    surface: Color(0x14FFFFFF),
    border: Color(0x1FFFFFFF),
    textPrimary: Color(0xFFF2F5FA),
    textSecondary: Color(0x99F2F5FA),
    accent: Color(0xFF7DD3FC),
  ),
  DashboardTheme(
    id: 'ember',
    name: 'Ember',
    background: [Color(0xFF1A0F0B), Color(0xFF2E1710)],
    surface: Color(0x1AFFB08A),
    border: Color(0x33FFB08A),
    textPrimary: Color(0xFFFFF1E8),
    textSecondary: Color(0x99FFF1E8),
    accent: Color(0xFFFF8A4C),
    cornerRadius: 24,
  ),
  DashboardTheme(
    id: 'forest',
    name: 'Forest',
    background: [Color(0xFF0C1512), Color(0xFF14241E)],
    surface: Color(0x14A7F3D0),
    border: Color(0x26A7F3D0),
    textPrimary: Color(0xFFEAF6F0),
    textSecondary: Color(0x99EAF6F0),
    accent: Color(0xFF6EE7B7),
  ),
  // Warm and bookish: flat coffee-brown tiles, no edges or shadows, a
  // serif face and a caramel accent.
  DashboardTheme(
    id: 'espresso',
    name: 'Espresso',
    background: [Color(0xFF1C1410)],
    surface: Color(0xFF2A1F19),
    border: Color(0x00000000),
    textPrimary: Color(0xFFF3E6D8),
    textSecondary: Color(0x99F3E6D8),
    accent: Color(0xFFD9A066),
    cornerRadius: 10,
    gap: 12,
    fontFamily: 'Lora',
    shadow: false,
  ),
  // A green-screen terminal: phosphor on black, hairline boxes, a monospaced
  // face and the faintest glow, as off an old tube.
  DashboardTheme(
    id: 'terminal',
    name: 'Terminal',
    background: [Color(0xFF030805)],
    glow: Color(0x1439FF88),
    surface: Color(0x0A39FF88),
    border: Color(0x4D39FF88),
    textPrimary: Color(0xFFC8FFD9),
    textSecondary: Color(0x99C8FFD9),
    accent: Color(0xFF39FF88),
    cornerRadius: 2,
    gap: 12,
    fontFamily: 'ShareTechMono',
    shadow: false,
  ),
  // Terminal with the lights off: true black, no glow, boxes you only just
  // see, and a softer green that is easy on the eyes in a dark room — the
  // phosphor turned down rather than a different screen.
  DashboardTheme(
    id: 'terminal-night',
    name: 'Terminal Night',
    background: [Color(0xFF000000)],
    surface: Color(0x0529D66F),
    border: Color(0x2629D66F),
    textPrimary: Color(0xFF7FD69A),
    textSecondary: Color(0x8C7FD69A),
    accent: Color(0xFF29C765),
    cornerRadius: 2,
    gap: 12,
    fontFamily: 'ShareTechMono',
    shadow: false,
  ),
  // Deliberately plain and very high contrast: readable across a room, and
  // the safest choice on an always-on panel because so little of it is lit.
  DashboardTheme(
    id: 'nightstand',
    name: 'Nightstand',
    background: [Color(0xFF000000)],
    surface: Color(0x00000000),
    border: Color(0x00000000),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0x8AFFFFFF),
    accent: Color(0xFFFFB300),
    cornerRadius: 0,
    gap: 24,
    shadow: false,
  ),
  // Glass in daylight: frosted white panes on pale ice blue, a white bloom
  // from the top left, and light along each pane's top edge.
  DashboardTheme(
    id: 'frost',
    name: 'Frost',
    background: [Color(0xFFD5E1F2)],
    glow: Color(0x99FFFFFF),
    glowEnd: Color(0x5589B4FF),
    surface: Color(0x8CFFFFFF),
    border: Color(0xCCFFFFFF),
    sheen: 0.35,
    textPrimary: Color(0xFF1B2433),
    textSecondary: Color(0x991B2433),
    accent: Color(0xFF2F6FEB),
    cornerRadius: 26,
    gap: 12,
  ),
  DashboardTheme(
    id: 'paper',
    name: 'Paper',
    background: [Color(0xFFF6F4EF), Color(0xFFEAE6DD)],
    surface: Color(0xFFFFFFFF),
    border: Color(0x14000000),
    textPrimary: Color(0xFF1E1B16),
    textSecondary: Color(0x991E1B16),
    accent: Color(0xFFB4531F),
    cornerRadius: 16,
    shadow: false,
  ),
  // Sweets in a shop window: glossy near-white panes over a peach-to-pink
  // wash, a coral accent and a rounded face.
  DashboardTheme(
    id: 'sorbet',
    name: 'Sorbet',
    background: [Color(0xFFFFE3D6), Color(0xFFFFCFE6)],
    surface: Color(0xB3FFFFFF),
    border: Color(0xE6FFFFFF),
    sheen: 0.45,
    textPrimary: Color(0xFF3D1E2E),
    textSecondary: Color(0x993D1E2E),
    accent: Color(0xFFE0245E),
    cornerRadius: 30,
    fontFamily: 'Nunito',
  ),
  // International Typographic Style: flat white blocks on grey, square
  // corners, wide gutters, black type and one signal red. No gloss, no
  // glass, no shadow.
  DashboardTheme(
    id: 'swiss',
    name: 'Swiss',
    background: [Color(0xFFEDEDEA)],
    surface: Color(0xFFFFFFFF),
    border: Color(0x00000000),
    textPrimary: Color(0xFF111111),
    textSecondary: Color(0x8C111111),
    accent: Color(0xFFE30613),
    cornerRadius: 0,
    gap: 16,
    fontFamily: 'Inter',
    shadow: false,
  ),
];

/// Built-ins plus anything found in the themes directory.
///
/// A file whose id matches a built-in replaces it, so a shipped theme can be
/// adjusted without editing the app.
class ThemeRepository {
  ThemeRepository(this._directory);

  final String _directory;

  List<DashboardTheme> _custom = const [];

  static String defaultDirectory() {
    final home = Platform.environment['HOME'] ?? '.';
    return p.join(home, '.config', 'immich_kiosk_pi', 'themes');
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

import 'package:flutter/material.dart';

import 'package:home_canvas/dashboard/dashboard_theme.dart';

/// Themes for the tests to draw with.
///
/// The app ships one theme, Glass; every other is an add-on in the
/// catalogue (`widgets/theme_*/theme.json` in HomeCanvas-Widgets). These are
/// copies of them as they were when they moved out. What the tests need is a
/// theme of every kind — a console, light ones, a monospaced one, glossy and
/// flat — to draw the app's own screens and the widgets in, not the
/// catalogue's latest colours: the catalogue's own tests read its files.
const List<DashboardTheme> catalogueThemes = [
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
  // A starship's console: black, with flat bars of orange, lilac and blue
  // swept round the corner of every panel, and tall condensed capitals. The
  // frames are drawn, not coloured in — see ThemeStyle.lcars. The colours
  // and the rules are TT Launcher's LCARS skin's, so the two match.
  DashboardTheme(
    id: 'lcars',
    name: 'LCARS',
    style: ThemeStyle.lcars,
    background: [Color(0xFF000000)],
    // Not the tiles, which are black inside their bars: what a key on the
    // PIN pad or the player's sheet is made of, where something solid has
    // to stand off the black.
    surface: Color(0xFF15131C),
    border: Color(0x999999FF),
    textPrimary: Color(0xFFFFCC99),
    textSecondary: Color(0xFFAAAAFF),
    accent: Color(0xFFFF9900),
    palette: [
      Color(0xFFFF9900),
      Color(0xFFCC99CC),
      Color(0xFF9999FF),
      Color(0xFFFFCC99),
      Color(0xFFCC6666),
      Color(0xFF99CCFF),
      Color(0xFFFFCC66),
    ],
    cornerRadius: 22,
    // Panels sit against each other, so their side bars run on as one.
    gap: 4,
    fontFamily: 'Antonio',
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

/// Glass and every theme from the catalogue.
const List<DashboardTheme> testThemes = [...kBuiltInThemes, ...catalogueThemes];

/// The test theme called [id].
DashboardTheme testTheme(String id) => testThemes.firstWhere((t) => t.id == id);

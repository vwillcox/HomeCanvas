/// Shapes for the tests that ask whether a widget fits its tile — shared
/// with the add-ons' own tests, which are copied in under test/addons/.
library;

import 'dart:ui' show Size;

/// The panel's grid, with the tile's padding taken off, as the dashboard does.
Size tile(int w, int h) {
  const gap = 10.0;
  final cellW = (1900 - gap * 13) / 12;
  final cellH = (1080 - gap * 9) / 8;
  return Size(w * cellW + (w - 1) * gap - 16, h * cellH + (h - 1) * gap - 16);
}

/// Every shape a tile can reasonably be: the corners of the grid, strips,
/// columns, and the sizes these widgets are drawn at by default.
const shapes = [
  (1, 1),
  (2, 1),
  (1, 2),
  (2, 2),
  (3, 2),
  (3, 3),
  (4, 2),
  (4, 3),
  (5, 3),
  (4, 6),
  (1, 6),
  (6, 1),
  (12, 1),
  (1, 8),
  (6, 4),
  (12, 8),
];

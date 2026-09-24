import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Lays a widget out on a canvas of fixed height, shaped like the space it
/// was given, then scales the canvas to fill that space exactly.
///
/// For widgets whose text should fill their tile rather than sit at one size
/// in the middle of it. Everything inside is written in canvas units — a
/// 28-unit number is 28% of a 100-unit canvas's height — so a tall tile gets
/// big figures and a short one small figures, and the layout is the same
/// proportions either way. Because the canvas has the tile's own shape, the
/// fit is exact: no letterboxing, no blank bands.
///
/// [maxScale] stops a very large tile producing comically large type; past it
/// the canvas simply gets taller in units, and the widget's flexible parts
/// share out the extra room.
class FitCanvas extends StatelessWidget {
  const FitCanvas({
    super.key,
    required this.builder,
    this.designHeight = 100,
    this.maxScale = 4,
  });

  final Widget Function(BuildContext context, Size design) builder;
  final double designHeight;
  final double maxScale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (!c.hasBoundedWidth ||
            !c.hasBoundedHeight ||
            c.maxWidth <= 0 ||
            c.maxHeight <= 0) {
          return const SizedBox.shrink();
        }
        final design = canvasFor(
          c.biggest,
          designHeight: designHeight,
          maxScale: maxScale,
        );
        return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox.fromSize(
            size: design,
            child: builder(context, design),
          ),
        );
      },
    );
  }

  /// The canvas, in design units, for a space of [size] pixels.
  static Size canvasFor(
    Size size, {
    double designHeight = 100,
    double maxScale = 4,
  }) {
    final scale = math.min(size.height / designHeight, maxScale);
    return Size(size.width / scale, size.height / scale);
  }
}

/// How many columns and rows to split [count] equal items into, in [size].
///
/// Chooses whichever arrangement lets each item be largest when drawn at
/// [cellAspect] (width over height) — two devices on a wide, short strip go
/// side by side; on a tall, narrow tile they stack.
({int columns, int rows}) bestGrid(
  int count,
  Size size, {
  double cellAspect = 3,
}) {
  if (count <= 0 || size.isEmpty) return (columns: 1, rows: 1);
  var best = (columns: 1, rows: count);
  var bestHeight = -1.0;
  for (var columns = 1; columns <= count; columns++) {
    final rows = (count / columns).ceil();
    final cellW = size.width / columns;
    final cellH = size.height / rows;
    // The height an item of the wanted shape can have in this cell.
    final usable = math.min(cellH, cellW / cellAspect);
    if (usable > bestHeight + 0.01) {
      bestHeight = usable;
      best = (columns: columns, rows: rows);
    }
  }
  return best;
}

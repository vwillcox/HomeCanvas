import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A single dial carrying both speeds at once: download on the outer track,
/// upload on the inner one.
///
/// One dial rather than two because the pair is the interesting thing — a
/// connection is "200 down, 20 up", and reading that off two separate gauges
/// makes you do the comparison yourself. Sharing the scale means the
/// asymmetry of a domestic line is visible at a glance.
///
/// The scale is **logarithmic**. A linear dial calibrated for a 1 Gbit
/// connection leaves everything below about 50 Mbps squashed into the first
/// few degrees, so an upload of 20 and one of 2 look identical — which is
/// precisely when you are looking. Each power of ten gets equal sweep.
class SpeedGauge extends StatelessWidget {
  /// How far the dial reaches from the centre of a [size] box — for checking
  /// that it stays inside, whatever shape of box it is given.
  @visibleForTesting
  static double reachIn(Size size) => _GaugePainter.reach(size);

  const SpeedGauge({
    super.key,
    required this.downloadMbps,
    required this.uploadMbps,
    required this.maxMbps,
    required this.colour,
    required this.uploadColour,
    required this.trackColour,
    required this.textColour,
    required this.mutedColour,
    this.label = '',
    this.centreValue,
    this.centreUnit = 'Mbps',
  });

  final double downloadMbps;
  final double uploadMbps;

  /// Top of the scale. Rounded up to a power of ten internally.
  final double maxMbps;

  final Color colour;
  final Color uploadColour;
  final Color trackColour;
  final Color textColour;
  final Color mutedColour;

  /// Shown under the big number — usually the phase, e.g. "downloading".
  final String label;

  /// What the middle reads. Defaults to whichever speed is being measured.
  final double? centreValue;
  final String centreUnit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final side = math.min(c.maxWidth, c.maxHeight);
        final value = centreValue ?? downloadMbps;
        return SizedBox(
          width: side,
          height: side,
          child: CustomPaint(
            painter: _GaugePainter(
              downloadMbps: downloadMbps,
              uploadMbps: uploadMbps,
              maxMbps: maxMbps,
              download: colour,
              upload: uploadColour,
              track: trackColour,
              tick: mutedColour,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _format(value),
                      style: TextStyle(
                        color: textColour,
                        fontSize: side * 0.22,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                  SizedBox(height: side * 0.02),
                  Text(
                    centreUnit,
                    style: TextStyle(color: mutedColour, fontSize: side * 0.07),
                  ),
                  if (label.isNotEmpty) ...[
                    SizedBox(height: side * 0.02),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mutedColour,
                        fontSize: side * 0.06,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _format(double mbps) {
    if (mbps >= 100) return mbps.toStringAsFixed(0);
    if (mbps >= 10) return mbps.toStringAsFixed(1);
    return mbps.toStringAsFixed(2);
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.downloadMbps,
    required this.uploadMbps,
    required this.maxMbps,
    required this.download,
    required this.upload,
    required this.track,
    required this.tick,
  });

  final double downloadMbps;
  final double uploadMbps;
  final double maxMbps;
  final Color download;
  final Color upload;
  final Color track;
  final Color tick;

  /// A 270° dial with the gap at the bottom — the familiar speedometer shape,
  /// and the gap is where the text sits comfortably.
  /// Where the dial sits in a box of [size], and how big its parts are.
  ///
  /// From the shorter side. Beside the readout the dial sits in a row slot
  /// that forces its width, so its box can be wider than it is tall; sized
  /// from the width, the circle ran off the top and bottom of the tile.
  static ({Offset centre, double outer, double inner, double width}) dims(
    Size size,
  ) {
    final side = math.min(size.width, size.height);
    return (
      centre: Offset(size.width / 2, size.height / 2),
      outer: side * 0.42,
      inner: side * 0.305,
      width: side * 0.075,
    );
  }

  /// The furthest anything is drawn from the centre: the outer ring's edge,
  /// or the end of a decade tick, whichever reaches further.
  static double reach(Size size) {
    final d = dims(size);
    return math.max(d.outer + d.width / 2, d.outer + d.width * _tickOut) +
        tickStroke(d.width) / 2; // the tick's own round cap
  }

  static const double _tickOut = 0.85;

  /// A tick's thickness, from the ring's. Fixed at two pixels, a tick on a
  /// very small dial poked past the edge of its box.
  static double tickStroke(double ringWidth) =>
      (ringWidth * 0.14).clamp(1.0, 2.0);

  static const double _start = math.pi * 0.75;
  static const double _sweep = math.pi * 1.5;

  /// Where [mbps] falls on the dial, 0–1, on a log scale.
  ///
  /// Anchored at 1 Mbps: below that the exact figure stops mattering (the
  /// connection is broken either way), and log(0) is undefined.
  static double fraction(double mbps, double maxMbps) {
    final top = math.max(maxMbps, 10);
    if (mbps <= 1) return 0;
    final f = math.log(mbps) / math.log(top);
    return f.clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final d = dims(size);
    final centre = d.centre;
    final outer = d.outer;
    final inner = d.inner;
    final width = d.width;

    void arc(double radius, double fraction, Color colour, double strokeWidth) {
      final rect = Rect.fromCircle(center: centre, radius: radius);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = colour;
      canvas.drawArc(rect, _start, _sweep * fraction, false, paint);
    }

    // Tracks first, so a zero reading still shows the dial's shape.
    arc(outer, 1, track, width);
    arc(inner, 1, track, width * 0.8);

    arc(outer, fraction(downloadMbps, maxMbps), download, width);
    arc(inner, fraction(uploadMbps, maxMbps), upload, width * 0.8);

    _decadeTicks(canvas, centre, outer, width);
  }

  /// A tick at each power of ten, which on a log dial are evenly spaced and
  /// so double as the scale markings.
  void _decadeTicks(Canvas canvas, Offset centre, double radius, double width) {
    final paint = Paint()
      ..color = tick
      ..strokeWidth = tickStroke(width)
      ..strokeCap = StrokeCap.round;
    final top = math.max(maxMbps, 10);
    for (double decade = 10; decade <= top; decade *= 10) {
      final f = fraction(decade, maxMbps);
      final angle = _start + _sweep * f;
      final r1 = radius + width * 0.55;
      final r2 = radius + width * _tickOut;
      canvas.drawLine(
        centre + Offset(math.cos(angle) * r1, math.sin(angle) * r1),
        centre + Offset(math.cos(angle) * r2, math.sin(angle) * r2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.downloadMbps != downloadMbps ||
      old.uploadMbps != uploadMbps ||
      old.maxMbps != maxMbps ||
      old.download != download ||
      old.upload != upload;
}

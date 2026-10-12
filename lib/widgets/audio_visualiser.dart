import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../look.dart';
import '../services/audio_levels_service.dart';
import 'lcars.dart';
import 'pause_when_hidden.dart';
import '../l10n/l10n.dart';

/// The music, drawn.
///
/// Reads [AudioLevelsService] and paints either a spectrum or a waveform. The
/// important part is the bookkeeping rather than the picture: this widget owns
/// one viewer's claim on the capture, taken when it appears and given back when
/// it goes away, so the subprocess and the arithmetic behind it only exist
/// while there is something on screen that would show them.
///
/// [active] is the second half of that. The player stays laid out while a
/// track is paused, but paused audio produces a flat line, so the claim is
/// dropped and the capture stops until playing resumes.
/// The colours the spectrum runs through, bass first.
///
/// Pitch is the thing being mapped, so the sweep runs cool to warm across the
/// bars rather than colouring them all alike: the bass end stays close to the
/// player's own blue and the treble end lifts away from it, which makes the
/// shape of the music readable at a glance from across the room.
const List<Color> kVisualiserPalette = [
  Color(0xFF7C4DFF),
  Color(0xFF448AFF),
  Color(0xFF18E0E8),
  Color(0xFF4CE07A),
  Color(0xFFFFC24B),
  Color(0xFFFF5E8A),
];

class AudioVisualiser extends StatefulWidget {
  const AudioVisualiser({
    super.key,
    required this.style,
    this.palette = kVisualiserPalette,
    this.height = 96,
    this.active = true,
    this.onTap,
  });

  final VisualiserStyle style;

  /// Colour stops, spread evenly across the bars.
  final List<Color> palette;

  final double height;

  /// Called when the picture is touched, for cycling the style.
  ///
  /// Providing it also changes what [VisualiserStyle.off] looks like. Without
  /// a handler, off collapses to nothing — there is no reason to hold space
  /// for a picture nobody can bring back. With one, off leaves a slim dormant
  /// strip instead, because a control that disappears when you switch it off
  /// is a control you cannot switch on again.
  final VoidCallback? onTap;

  /// Whether audio is actually playing. False stops the capture but keeps the
  /// space, so the transport controls do not jump when the music pauses.
  final bool active;

  @override
  State<AudioVisualiser> createState() => _AudioVisualiserState();
}

class _AudioVisualiserState extends State<AudioVisualiser>
    with PauseWhenHidden {
  AudioLevelsService? _service;
  bool _holding = false;

  /// Only while it can be seen: the capture and its analysis run for as long
  /// as anything holds them, and a visualiser behind a video is holding one
  /// for nobody.
  bool get _wanted =>
      widget.active && widget.style != VisualiserStyle.off && shown;

  @override
  void onShownChanged(bool shown) => _sync();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<AudioLevelsService>();
    if (!identical(service, _service)) {
      _release();
      _service = service;
    }
    _sync();
  }

  @override
  void didUpdateWidget(AudioVisualiser old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_wanted) {
      if (!_holding) {
        _service?.attach();
        _holding = true;
      }
    } else {
      _release();
    }
  }

  void _release() {
    if (!_holding) return;
    _holding = false;
    _service?.detach();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AudioLevelsService>();
    final look = context.look;
    // A console draws it in its own blocks of colour rather than the sweep.
    final blocks = look.isLcars && look.palette.isNotEmpty
        ? look.palette
        : null;
    // Nothing to capture with — a machine that isn't the panel. Take the space
    // back rather than reserving it for a picture that will never come.
    if (!service.supported) return const SizedBox.shrink();

    if (widget.style == VisualiserStyle.off) {
      if (widget.onTap == null) return const SizedBox.shrink();
      return _tappable(
        label: tr('visualiser.visualiserOffTapToTurn', 'Visualiser off. Tap to turn it on.'),
        // Enough to hit with a thumb without pretending there is a picture.
        child: SizedBox(
          height: math.max(36, widget.height * 0.36),
          width: double.infinity,
          child: Center(
            child: Icon(
              Icons.graphic_eq,
              size: 22,
              color: (blocks ?? widget.palette).first.withValues(alpha: 0.45),
            ),
          ),
        ),
      );
    }

    return _tappable(
      label: widget.style == VisualiserStyle.wave
          ? tr('visualiser.visualiserWaveformTapToChange', 'Visualiser: waveform. Tap to change.')
          : tr('visualiser.visualiserBarsTapToChange', 'Visualiser: bars. Tap to change.'),
      child: RepaintBoundary(
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: switch ((widget.style, blocks)) {
              (VisualiserStyle.wave, null) => _WavePainter(
                wave: service.wave,
                palette: widget.palette,
              ),
              (VisualiserStyle.wave, final blocks?) => _ConsoleWavePainter(
                wave: service.wave,
                blocks: blocks,
              ),
              (_, null) => _BarsPainter(
                levels: service.levels,
                palette: widget.palette,
              ),
              (_, final blocks?) => _ConsoleBarsPainter(
                levels: service.levels,
                blocks: blocks,
              ),
            },
          ),
        ),
      ),
    );
  }

  /// Wrap the picture so a touch anywhere on it counts.
  ///
  /// Opaque hit testing: most of this band is empty space above short bars,
  /// and a tap target you have to land on a bar to hit would be useless.
  Widget _tappable({required String label, required Widget child}) {
    if (widget.onTap == null) return child;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: child,
      ),
    );
  }
}

/// Pick a colour from the stops, [t] running 0–1 across them.
Color _sample(List<Color> palette, double t) {
  if (palette.isEmpty) return Colors.white;
  if (palette.length == 1) return palette.first;
  final scaled = t.clamp(0.0, 1.0) * (palette.length - 1);
  final i = scaled.floor().clamp(0, palette.length - 2);
  return Color.lerp(palette[i], palette[i + 1], scaled - i)!;
}

/// A spectrum: one bar per band, bass on the left.
class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.levels, required this.palette});

  final List<double> levels;
  final List<Color> palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty || size.width <= 0) return;
    // A quarter of each slot goes to the gap. Narrow bars on a wall panel read
    // as noise from across the room; these stay chunky.
    final slot = size.width / levels.length;
    final width = slot * 0.72;
    final radius = Radius.circular(math.min(width / 2, 6));
    // A floor, so a silence is a row of dots rather than an empty rectangle
    // that looks like the widget has failed.
    final floor = math.min(4.0, size.height);
    final span = levels.length == 1 ? 1 : levels.length - 1;

    for (var i = 0; i < levels.length; i++) {
      final level = levels[i].clamp(0.0, 1.0);
      final height = math.max(floor, level * size.height);
      final left = i * slot + (slot - width) / 2;
      final top = size.height - height;
      final rect = Rect.fromLTWH(left, top, width, height);

      final base = _sample(palette, i / span);
      // Hotter at the tip and dimmer at the foot, so a tall bar reads as a
      // peak rather than a longer block of the same flat colour — and so the
      // quiet ones recede instead of drawing a hard bright line along the
      // bottom of the panel.
      final tip = Color.lerp(base, Colors.white, 0.10 + 0.30 * level)!;
      final foot = base.withValues(alpha: 0.30 + 0.35 * level);

      canvas.drawRRect(
        RRect.fromRectAndCorners(rect, topLeft: radius, topRight: radius),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(left, top),
            Offset(left, size.height),
            [tip, foot],
          ),
      );
    }
  }

  // The service hands back the same list every frame, so there is nothing
  // here to compare. It only notifies when the numbers actually moved, and it
  // stops notifying entirely during a silence — the throttling that matters
  // happens there, not here.
  @override
  bool shouldRepaint(_BarsPainter old) => true;
}

/// A waveform, mirrored about the centre line.
class _WavePainter extends CustomPainter {
  _WavePainter({required this.wave, required this.palette});

  final List<double> wave;
  final List<Color> palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (wave.length < 2 || size.width <= 0) return;
    final middle = size.height / 2;
    final scale = size.height / 2;
    final step = size.width / (wave.length - 1);

    // Drawn as a closed shape rather than a line: filled, the quiet passages
    // stay visible as a thin ribbon instead of vanishing into the background.
    final path = Path()..moveTo(0, middle);
    for (var i = 0; i < wave.length; i++) {
      path.lineTo(i * step, middle - wave[i].clamp(-1.0, 1.0).abs() * scale);
    }
    for (var i = wave.length - 1; i >= 0; i--) {
      path.lineTo(i * step, middle + wave[i].clamp(-1.0, 1.0).abs() * scale);
    }
    path.close();

    // The same sweep the bars use, laid across the width, so switching style
    // changes the shape rather than the whole look of the player. Built three
    // times at different strengths: a Paint's own colour is ignored once it
    // has a shader, so the transparency has to live in the stops.
    ui.Shader sweep(double alpha) => ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, 0),
          [for (final c in palette) c.withValues(alpha: alpha)],
          [for (var i = 0; i < palette.length; i++) i / (palette.length - 1)],
        );

    canvas.drawPath(path, Paint()..shader = sweep(0.5));
    canvas.drawPath(
      path,
      Paint()
        ..shader = sweep(1.0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    // The centre line keeps the band anchored when everything falls silent.
    canvas.drawLine(
      Offset(0, middle),
      Offset(size.width, middle),
      Paint()
        ..shader = sweep(0.30)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}

/// How tall one segment of a console's meter is, with the black line under
/// it, for a picture [height] tall: a dozen or so to a column.
double _segment(double height) => math.max(6.0, height / 12);

/// A console's spectrum: each band a column of flat segments, a black line
/// between one and the next, in the theme's colours four columns at a time.
/// No gradient and nothing rounded — a level is so many blocks lit.
class _ConsoleBarsPainter extends CustomPainter {
  _ConsoleBarsPainter({required this.levels, required this.blocks});

  final List<double> levels;
  final List<Color> blocks;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty || size.width <= 0) return;
    final slot = size.width / levels.length;
    final each = _segment(size.height);
    final rows = (size.height / each).floor();
    final paint = Paint();
    for (var i = 0; i < levels.length; i++) {
      // At least one, so a silence is a row of blocks rather than nothing.
      final lit = math.max(1, (levels[i].clamp(0.0, 1.0) * rows).round());
      final colour = blocks[(i ~/ 4) % blocks.length];
      for (var r = 0; r < lit; r++) {
        canvas.drawRect(
          Rect.fromLTWH(
            i * slot,
            size.height - (r + 1) * each + lcarsLine,
            slot - lcarsLine,
            each - lcarsLine,
          ),
          // The top block of a column is near-white: the peak.
          paint..color = r == lit - 1 && lit > 1 ? lcarsLit : colour,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ConsoleBarsPainter old) => true;
}

/// A console's waveform: flat columns standing up from a centre bar or
/// hanging down from it, as the sound swings either way, in the theme's
/// colours.
///
/// Signed, not mirrored, and not rounded to segments as the spectrum is.
/// The analyser scales the wave to fill the band whatever the volume, so a
/// column that only said how loud its samples were would be the same height
/// at every frame — a still block. Which way each swings is what moves.
class _ConsoleWavePainter extends CustomPainter {
  _ConsoleWavePainter({required this.wave, required this.blocks});

  final List<double> wave;
  final List<Color> blocks;

  static const _columns = 64;

  @override
  void paint(Canvas canvas, Size size) {
    if (wave.length < 2 || size.width <= 0) return;
    final columns = math.min(_columns, wave.length);
    final slot = size.width / columns;
    final middle = size.height / 2;
    final paint = Paint();
    for (var i = 0; i < columns; i++) {
      // The furthest swing of the samples this column covers, with its sign.
      final from = i * wave.length ~/ columns;
      final to = math.max(from + 1, (i + 1) * wave.length ~/ columns);
      var swing = 0.0;
      for (var j = from; j < to; j++) {
        final v = wave[j].clamp(-1.0, 1.0);
        if (v.abs() > swing.abs()) swing = v;
      }
      final reach = swing * (middle - lcarsLine);
      // The centre bar is always there, and anchors the band in a silence.
      canvas.drawRect(
        Rect.fromLTRB(
          i * slot,
          math.min(middle - lcarsLine / 2, middle - reach),
          (i + 1) * slot - lcarsLine,
          math.max(middle + lcarsLine / 2, middle - reach),
        ),
        paint..color = blocks[(i ~/ 8) % blocks.length],
      );
    }
  }

  @override
  bool shouldRepaint(_ConsoleWavePainter old) => true;
}

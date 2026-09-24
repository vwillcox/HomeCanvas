import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/config_service.dart';
import '../../services/sun_moon.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// Where the sun is in its arc, sunrise and sunset, how the days are
/// changing, and the moon's phase.
///
/// Worked out on the Pi from the weather's location, so it needs nothing
/// from the network once the location is known.
class SunMoonWidget extends StatefulWidget {
  const SunMoonWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<SunMoonWidget> createState() => _SunMoonWidgetState();
}

class _SunMoonWidgetState extends State<SunMoonWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Once a minute is as often as anything here changes.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final weather = context.watch<ConfigService>().config.weather;
    final lat = weather.latitude, lon = weather.longitude;
    if (lat == null || lon == null) {
      return TileMessage('Set a place in Settings → Weather', theme: t);
    }
    final now = DateTime.now();
    final today = SunMoon.sun(now, lat, lon);
    final yesterday = SunMoon.sun(
      now.subtract(const Duration(days: 1)),
      lat,
      lon,
    );
    final phase = SunMoon.moonPhase(now);
    final showMoon = widget.w.option('showMoon', true);

    final full = FitCanvas(
      designHeight: 120,
      maxScale: 3,
      builder: (context, size) {
        final wide = size.width >= 190;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TileLabel(
              icon: Icons.wb_twilight_rounded,
              text: showMoon ? SunMoon.phaseName(phase) : 'Sun',
              theme: t,
              size: 11,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ArcPainter(
                        progress: today.progress(now),
                        theme: t,
                      ),
                    ),
                  ),
                  if (showMoon)
                    Positioned(
                      right: 0,
                      top: 0,
                      width: 22,
                      height: 22,
                      child: CustomPaint(
                        painter: MoonPainter(phase: phase, theme: t),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _Times(
              today: today,
              yesterday: yesterday,
              theme: t,
              showLength: wide,
            ),
          ],
        );
      },
    );

    return LayoutBuilder(
      builder: (context, c) => c.maxHeight < 160
          // One row high: no room for an arc worth drawing, so the times,
          // big, beside the moon.
          ? _Strip(today: today, phase: phase, showMoon: showMoon, theme: t)
          : full,
    );
  }
}

/// Sunrise and sunset side by side, with the moon, for a one-row tile.
class _Strip extends StatelessWidget {
  const _Strip({
    required this.today,
    required this.phase,
    required this.showMoon,
    required this.theme,
  });

  final SunDay today;
  final double phase;
  final bool showMoon;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    Widget time(IconData icon, DateTime? at) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: const Color(0xFFFFD27A)),
        const SizedBox(width: 4),
        Text(
          _Times._hm(at),
          style: TextStyle(
            color: theme.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
    return FitCanvas(
      designHeight: 50,
      maxScale: 3,
      builder: (context, size) => Row(
        children: [
          if (showMoon) ...[
            SizedBox.square(
              dimension: 30,
              child: CustomPaint(
                painter: MoonPainter(phase: phase, theme: theme),
              ),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  time(Icons.north_east_rounded, today.sunrise),
                  const SizedBox(width: 18),
                  time(Icons.south_east_rounded, today.sunset),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Times extends StatelessWidget {
  const _Times({
    required this.today,
    required this.yesterday,
    required this.theme,
    required this.showLength,
  });

  final SunDay today;
  final SunDay yesterday;
  final DashboardTheme theme;
  final bool showLength;

  static String _hm(DateTime? t) => t == null
      ? '—'
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final length = today.dayLength;
    final change = length - yesterday.dayLength;
    final sign = change.isNegative ? '−' : '+';
    final changeText = change.inSeconds.abs() < 60
        ? '$sign${change.inSeconds.abs()} s'
        : '$sign${change.inMinutes.abs()} min';

    Widget time(String label, DateTime? at) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(color: theme.textSecondary, fontSize: 11),
          ),
          TextSpan(
            text: _hm(at),
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      maxLines: 1,
    );

    return LayoutBuilder(
      builder: (context, c) {
        // Too narrow for both on one line: one above the other.
        if (c.maxWidth < 150) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: time('Rise', today.sunrise),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: time('Set', today.sunset),
              ),
            ],
          );
        }
        return _row(time, length, changeText);
      },
    );
  }

  Widget _row(
    Widget Function(String, DateTime?) time,
    Duration length,
    String changeText,
  ) {
    // Each part gives way rather than overflowing: the day length first,
    // then the times themselves shrink.
    return Row(
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: time('Rise', today.sunrise),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: showLength
              ? Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${length.inHours} h ${(length.inMinutes % 60).toString().padLeft(2, '0')} · $changeText',
                      maxLines: 1,
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: time('Set', today.sunset),
          ),
        ),
      ],
    );
  }
}

/// The day as an arc from horizon to horizon: dashed for the whole of it,
/// solid gold for the part already gone, and the sun where it is now.
class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.progress, required this.theme});

  final double progress;
  final DashboardTheme theme;

  static const _sun = Color(0xFFFFD27A);

  Offset _at(Size s, double f) {
    // A half ellipse sitting on the horizon line at the bottom.
    final a = math.pi * (1 - f);
    return Offset(
      s.width / 2 + math.cos(a) * s.width * 0.46,
      s.height - math.sin(a) * s.height * 0.9,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = Paint()
      ..color = theme.textSecondary.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      horizon,
    );

    final dash = Paint()
      ..color = theme.textSecondary.withValues(alpha: 0.4)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    const steps = 40;
    for (var i = 0; i < steps; i += 2) {
      canvas.drawLine(_at(size, i / steps), _at(size, (i + 1) / steps), dash);
    }

    if (progress <= 0 || progress >= 1) return; // night: no sun on the arc
    final done = Path()..moveTo(_at(size, 0).dx, _at(size, 0).dy);
    for (var i = 1; i <= 60; i++) {
      final p = _at(size, progress * i / 60);
      done.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      done,
      Paint()
        ..color = _sun
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    final sun = _at(size, progress);
    canvas.drawCircle(
      sun,
      9,
      Paint()
        ..color = _sun.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(sun, 5.5, Paint()..color = _sun);
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress || old.theme != theme;
}

/// The moon as it looks tonight, in the northern hemisphere: lit from the
/// right while waxing, from the left while waning.
class MoonPainter extends CustomPainter {
  MoonPainter({required this.phase, required this.theme});

  final double phase;
  final DashboardTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final lit = theme.background.first.computeLuminance() > 0.5
        ? const Color(0xFF8C8A80)
        : const Color(0xFFEDEFF5);
    final dark = theme.textSecondary.withValues(alpha: 0.18);
    canvas.drawCircle(c, r, Paint()..color = dark);

    // The terminator is an ellipse whose width follows the phase: a full
    // circle at new and full moon, a straight line at the quarters.
    final waxing = phase < 0.5;
    final k = math.cos(2 * math.pi * phase); // 1 new, -1 full
    final path = Path()
      ..addArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        waxing ? math.pi : -math.pi,
      );
    final ellipse = Rect.fromCenter(
      center: c,
      width: 2 * r * k.abs(),
      height: 2 * r,
    );
    // Back up the terminator: bulging towards the lit side before the
    // quarter (a crescent), away from it after (a gibbous moon).
    final bulgeLit = k > 0;
    // From the bottom back to the top: a negative sweep goes round by the
    // right, a positive one by the left.
    path.arcTo(
      ellipse,
      math.pi / 2,
      (waxing == bulgeLit) ? -math.pi : math.pi,
      false,
    );
    path.close();
    canvas.drawPath(path, Paint()..color = lit);
  }

  @override
  bool shouldRepaint(MoonPainter old) =>
      old.phase != phase || old.theme != theme;
}

final sunMoonWidgetType = DashboardWidgetType(
  type: 'sun_moon',
  name: 'Sun & moon',
  description:
      'Sunrise and sunset, where the sun is now, how fast the days '
      'are changing, and the moon’s phase. Worked out on the panel from the '
      'place set in Settings → Weather.',
  glyph: '🌅',
  defaultWidth: 3,
  defaultHeight: 2,
  minWidth: 1,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'showMoon',
      label: 'Show the moon',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
  ],
  preview: const [
    PreviewLine('Waxing gibbous', scale: 0.1, muted: true),
    PreviewLine('◠', scale: 0.3, accent: true, centre: true),
    PreviewLine('Rise 06:52   ·   Set 18:59', scale: 0.12),
  ],
  build: (context, w) => SunMoonWidget(w: w),
);

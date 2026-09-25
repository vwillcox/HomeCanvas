import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/carbon_service.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// How clean the grid's electricity is now, the next day as bars, and the
/// greenest three hours to run the washing machine or the dishwasher.
class CarbonWidget extends StatefulWidget {
  const CarbonWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<CarbonWidget> createState() => _CarbonWidgetState();
}

class _CarbonWidgetState extends State<CarbonWidget> {
  Timer? _timer;

  String? get _outcode {
    final given = '${widget.w.config.options['postcode'] ?? ''}'.trim();
    return given.isEmpty
        ? context.read<CarbonService>().defaultOutcode
        : outwardCode(given);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    // Once a minute moves the "now" marker along; the service only fetches
    // when its half hour is up.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant CarbonWidget old) {
    super.didUpdateWidget(old);
    _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    final code = _outcode;
    if (code != null) unawaited(context.read<CarbonService>().ensure(code));
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final service = context.watch<CarbonService>();
    final code = _outcode;
    if (code == null) {
      return TileMessage(
        'Give a postcode in the widget settings, or set a postcode as the '
        'place in Settings → Weather.',
        theme: t,
      );
    }
    final forecast = service.forecast(code);
    if (forecast == null) {
      return TileMessage(
        service.error(code) ?? 'Fetching the grid forecast…',
        theme: t,
      );
    }
    final now = DateTime.now();
    final current = forecast.at(now);
    final day = forecast.nextDay(now);
    final best = forecast.greenest(now);
    final status = StatusColours.of(t);
    Color colourFor(String index) => switch (index) {
      'very low' || 'low' => status.good,
      'moderate' => t.accent,
      'high' => status.warn,
      _ => status.bad,
    };

    return LayoutBuilder(
      builder: (context, c) {
        final showBars = c.maxHeight > 150 && day.isNotEmpty;
        return FitCanvas(
          designHeight: showBars ? 170 : 90,
          maxScale: 3,
          builder: (context, size) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TileLabel(
                icon: Icons.bolt_rounded,
                text: forecast.region.isEmpty
                    ? 'Grid'
                    : 'Grid · ${forecast.region}',
                theme: t,
                size: 11,
              ),
              const SizedBox(height: 4),
              if (current != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '${current.grams}',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 34,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'g CO₂\nper kWh',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 9,
                        height: 1.2,
                      ),
                    ),
                    // Shrinks before crowding the reading off a short tile.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: StatusChip(
                            text: current.index.isEmpty
                                ? '—'
                                : '${current.index[0].toUpperCase()}${current.index.substring(1)}',
                            colour: colourFor(current.index),
                            size: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              if (showBars) ...[
                const SizedBox(height: 10),
                Expanded(
                  child: CustomPaint(
                    painter: _BarsPainter(
                      slots: day,
                      now: now,
                      best: best,
                      theme: t,
                      good: status.good,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    for (final label in ['now', '+12 h', '+24 h']) ...[
                      if (label != 'now') const Spacer(),
                      Text(
                        label,
                        style: TextStyle(color: t.textSecondary, fontSize: 8),
                      ),
                    ],
                  ],
                ),
              ] else
                const Spacer(),
              if (best != null) ...[
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Greenest ${_hm(best.from)}–${_hm(best.to)}',
                        style: TextStyle(
                          color: status.good,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: ' · ${best.average} g',
                        style: TextStyle(color: t.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.slots,
    required this.now,
    required this.best,
    required this.theme,
    required this.good,
  });

  final List<CarbonSlot> slots;
  final DateTime now;
  final ({DateTime from, DateTime to, int average})? best;
  final DashboardTheme theme;
  final Color good;

  @override
  void paint(Canvas canvas, Size size) {
    if (slots.isEmpty) return;
    final top = slots.map((s) => s.grams).reduce((a, b) => a > b ? a : b);
    final scale = top <= 0 ? 1.0 : size.height / (top * 1.05);
    final w = size.width / slots.length;
    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      final isNow =
          !now.isBefore(s.from) &&
          now.isBefore(s.from.add(const Duration(minutes: 30)));
      final inBest =
          best != null &&
          !s.from.isBefore(best!.from) &&
          s.from.isBefore(best!.to);
      final h = (s.grams * scale).clamp(1.0, size.height);
      final paint = Paint()
        ..color = isNow
            ? theme.accent
            : inBest
            ? good
            : theme.textSecondary.withValues(alpha: 0.35);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(i * w + w * 0.12, size.height - h, w * 0.76, h),
          topLeft: Radius.circular(w * 0.3),
          topRight: Radius.circular(w * 0.3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.slots != slots || old.now != now || old.theme != theme;
}

final carbonWidgetType = DashboardWidgetType(
  type: 'grid_carbon',
  category: WidgetCategory.house,
  name: 'Grid carbon',
  description:
      'How clean the electricity is right now in your region, the '
      'next day as bars, and the greenest three hours to run the washing '
      'machine or dishwasher. From National Grid ESO — no key needed.',
  glyph: '⚡',
  defaultWidth: 3,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'postcode',
      label: 'Postcode',
      defaultValue: '',
      help:
          'Leave empty to use the place in Settings → Weather, if that is a '
          'postcode. Only the first half is sent.',
    ),
  ],
  preview: const [
    PreviewLine('142 g CO₂/kWh', scale: 0.2, accent: true),
    PreviewLine('▁▂▃▅▆▅▃▂▁▂▃▄', scale: 0.16, centre: true),
    PreviewLine('Greenest 01:00–04:00', scale: 0.11),
  ],
  build: (context, w) => CarbonWidget(w: w),
);

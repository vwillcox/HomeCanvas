import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/rain_service.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// Whether it is about to rain: the next two hours in one sentence, and as
/// bars a quarter of an hour wide.
class RainWidget extends StatefulWidget {
  const RainWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<RainWidget> createState() => _RainWidgetState();
}

class _RainWidgetState extends State<RainWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // The sentence is about "now", which moves even when the forecast does
    // not.
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
    final service = context.watch<RainService>();
    final slots = service.slots;
    if (slots == null) {
      return TileMessage(
        service.error ?? 'Fetching the rain forecast…',
        theme: t,
      );
    }
    final now = DateTime.now();
    final s = rainSummary(slots, now);
    final ahead = slots
        .where((x) => x.from.add(const Duration(minutes: 15)).isAfter(now))
        .toList();

    return LayoutBuilder(
      builder: (context, c) {
        // Bars only when there is rain to draw: a dry forecast is a sentence,
        // not an empty chart.
        final showBars = c.maxHeight > 120 && ahead.any((x) => x.wet);
        return FitCanvas(
          designHeight: showBars ? 120 : 64,
          maxScale: 3,
          builder: (context, size) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    s.wet ? Icons.umbrella_rounded : Icons.wb_sunny_outlined,
                    size: 22,
                    color: s.wet ? t.accent : t.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        s.headline,
                        maxLines: 1,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (s.detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: Text(
                    s.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textSecondary, fontSize: 12),
                  ),
                ),
              if (showBars) ...[
                const SizedBox(height: 8),
                Expanded(
                  child: CustomPaint(
                    painter: _RainBars(slots: ahead, theme: t),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      'now',
                      style: TextStyle(color: t.textSecondary, fontSize: 8),
                    ),
                    const Spacer(),
                    Text(
                      '+${(ahead.length / 4 * 60).round()} min',
                      style: TextStyle(color: t.textSecondary, fontSize: 8),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A bar per quarter hour, scaled so light rain still shows and a downpour
/// fills the height: 4 mm an hour and up reaches the top.
class _RainBars extends CustomPainter {
  _RainBars({required this.slots, required this.theme});

  final List<RainSlot> slots;
  final DashboardTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / slots.length;
    final base = Paint()..color = theme.textSecondary.withValues(alpha: 0.15);
    canvas.drawRect(Rect.fromLTWH(0, size.height - 1, size.width, 1), base);
    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      if (!s.wet) continue;
      final f = (s.rate / 4).clamp(0.08, 1.0);
      final h = size.height * f;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(i * w + w * 0.1, size.height - h, w * 0.8, h),
          topLeft: Radius.circular(w * 0.2),
          topRight: Radius.circular(w * 0.2),
        ),
        Paint()..color = theme.accent.withValues(alpha: 0.5 + 0.5 * f),
      );
    }
  }

  @override
  bool shouldRepaint(_RainBars old) => old.slots != slots || old.theme != theme;
}

final rainWidgetType = DashboardWidgetType(
  type: 'rain',
  category: WidgetCategory.weather,
  name: 'Rain soon',
  description:
      'Whether it is about to rain: the next two hours in a '
      'sentence — "Rain from 14:20, light" — and as bars. For the place in '
      'Settings → Weather.',
  glyph: '☔',
  defaultWidth: 3,
  defaultHeight: 2,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  preview: const [
    PreviewLine('Rain from 14:20', scale: 0.2),
    PreviewLine('light · until about 15:05', scale: 0.1, muted: true),
    PreviewLine('▁▁▂▅▆▃▁▁', scale: 0.2, accent: true, centre: true),
  ],
  build: (context, w) => RainWidget(w: w),
);

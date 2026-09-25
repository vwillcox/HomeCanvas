import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/bin_schedule.dart';
import '../../services/bins_service.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// Which bins go out next, and when. From the evening before it says to put
/// them out; a tap says they are out, and it quietens down.
class BinsWidget extends StatefulWidget {
  const BinsWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<BinsWidget> createState() => _BinsWidgetState();
}

class _BinsWidgetState extends State<BinsWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final t = w.theme;
    final service = context.watch<BinsService>();
    final bins = BinsService.binsOf(w.config);
    if (bins.isEmpty) {
      return TileMessage(
        'Add your bins in the widget settings: a name, a colour, the date of '
        'one collection and how often they go.',
        theme: t,
      );
    }
    final now = DateTime.now();
    final next = BinCollection.next(
      bins,
      now,
      remindFrom: BinsService.hourOption(w.config, 'remindFrom', 17),
      collectedBy: BinsService.hourOption(w.config, 'collectedBy', 12),
    )!;
    final out = service.isOut(w.config.id, next.day);
    final status = StatusColours.of(t);
    final gap = daysBetween(now, next.day);

    final (String headline, Widget chip) = switch (next.stage) {
      _ when out => (
        next.stage == BinStage.today
            ? 'Collection today'
            : 'Put out for tomorrow',
        StatusChip(text: 'Out ✓', colour: status.good, size: 11),
      ),
      BinStage.today => (
        'Collection today',
        StatusChip(text: 'Today', colour: t.accent, size: 11),
      ),
      BinStage.tonight => (
        'Put out tonight',
        StatusChip(text: 'Tonight', colour: status.warn, size: 11),
      ),
      BinStage.later => (
        gap == 1
            ? 'Tomorrow'
            : gap < 7
            ? _days[next.day.weekday - 1]
            : '${_days[next.day.weekday - 1].substring(0, 3)} ${next.day.day} ${_months[next.day.month - 1]}',
        StatusChip(text: 'in $gap days', colour: t.textSecondary, size: 11),
      ),
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Only worth a tap when there is something to say they have done.
      onTap: next.stage == BinStage.later
          ? null
          : () => service.toggleOut(w.config.id, next.day),
      child: FitCanvas(
        designHeight: 120,
        maxScale: 3,
        builder: (context, size) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TileLabel(
              icon: Icons.delete_outline_rounded,
              text: 'Bins',
              theme: t,
              size: 11,
              trailing: chip,
            ),
            const SizedBox(height: 4),
            Text(
              headline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Each bin gets a share of the width, so three fit a
                  // narrow tile as well as a wide one.
                  for (final b in next.bins) ...[
                    Flexible(
                      child: _BinIcon(bin: b, theme: t, faded: out),
                    ),
                    const SizedBox(width: 14),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BinIcon extends StatelessWidget {
  const _BinIcon({required this.bin, required this.theme, required this.faded});

  final Bin bin;
  final DashboardTheme theme;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: faded ? 0.45 : 1,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: AspectRatio(
              aspectRatio: 0.78,
              child: CustomPaint(painter: _BinPainter(bin.colour)),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              bin.name,
              maxLines: 1,
              style: TextStyle(color: theme.textSecondary, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

/// A wheelie bin: body narrowing to the base, a lid, a wheel.
class _BinPainter extends CustomPainter {
  _BinPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final lid = HSLColor.fromColor(colour);
    final lidColour = lid
        .withLightness((lid.lightness + 0.12).clamp(0, 1))
        .toColor();
    final body = Path()
      ..moveTo(w * 0.1, h * 0.16)
      ..lineTo(w * 0.9, h * 0.16)
      ..lineTo(w * 0.82, h * 0.92)
      ..quadraticBezierTo(w * 0.8, h * 0.97, w * 0.74, h * 0.97)
      ..lineTo(w * 0.26, h * 0.97)
      ..quadraticBezierTo(w * 0.2, h * 0.97, w * 0.18, h * 0.92)
      ..close();
    canvas.drawPath(body, Paint()..color = colour);
    // A shadowed band near the bottom, so it reads as a solid thing.
    canvas.drawRect(
      Rect.fromLTRB(w * 0.19, h * 0.8, w * 0.81, h * 0.84),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(0, h * 0.04, w, h * 0.17),
        Radius.circular(h * 0.04),
      ),
      Paint()..color = lidColour,
    );
    canvas.drawCircle(
      Offset(w * 0.8, h * 0.92),
      w * 0.09,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_BinPainter old) => old.colour != colour;
}

final binsWidgetType = DashboardWidgetType(
  type: 'bins',
  category: WidgetCategory.house,
  name: 'Bin day',
  description:
      'Which bins go out next and when. From the evening before it '
      'says to put them out; tap it once they are out.',
  glyph: '🗑️',
  defaultWidth: 3,
  defaultHeight: 2,
  minWidth: 1,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'bins',
      label: 'Bins',
      kind: OptionKind.list,
      addLabel: 'Add a bin',
      help:
          'One row per bin. The date is any one collection of it — from '
          'the council’s calendar — written as 2026-10-01 or 1/10/2026.',
      fields: [
        WidgetOption(key: 'name', label: 'Name', defaultValue: 'Rubbish'),
        WidgetOption(
          key: 'colour',
          label: 'Colour',
          kind: OptionKind.colour,
          defaultValue: '#3A3E47',
        ),
        WidgetOption(
          key: 'first',
          label: 'A collection date',
          defaultValue: '',
        ),
        WidgetOption(
          key: 'everyWeeks',
          label: 'Every (weeks)',
          kind: OptionKind.number,
          defaultValue: 2,
        ),
      ],
    ),
    WidgetOption(
      key: 'remindFrom',
      label: 'Start reminding at (hour, the evening before)',
      kind: OptionKind.number,
      defaultValue: 17,
    ),
    WidgetOption(
      key: 'collectedBy',
      label: 'Collected by (hour, on the day)',
      kind: OptionKind.number,
      defaultValue: 12,
      help: 'After this the widget moves on to the next collection.',
    ),
    WidgetOption(
      key: 'speakAt',
      label: 'Say it out loud at',
      defaultValue: '',
      help:
          'A time the evening before, like 19:00, to hear which bins go '
          'out. Leave empty for no reminder.',
    ),
  ],
  preview: const [
    PreviewLine('Bins', scale: 0.1, muted: true),
    PreviewLine('Put out tonight', scale: 0.17),
    PreviewLine('Rubbish · Food', scale: 0.12, accent: true),
  ],
  build: (context, w) => BinsWidget(w: w),
);

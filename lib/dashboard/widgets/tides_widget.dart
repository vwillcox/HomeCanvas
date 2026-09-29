import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/dates.dart';
import '../../l10n/l10n.dart';
import '../../services/tides_service.dart';
import '../../time_format.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/shown_timers.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// How long until [d]: "2 h 10 min", "45 min".
String _until(Duration d) {
  final m = d.inMinutes.clamp(0, 100000);
  if (m < 60) return tr('widget.tides.inMinutes', 'in {m} min', {'m': m});
  return tr('widget.tides.inHours', 'in {h} h {m} min', {
    'h': m ~/ 60,
    'm': m % 60,
  });
}

/// Tide times and the sea's height through the day, at home or any place
/// on the coast.
class TidesWidget extends StatefulWidget {
  const TidesWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  @override
  State<TidesWidget> createState() => _TidesWidgetState();
}

class _TidesWidgetState extends State<TidesWidget>
    with PauseWhenHidden, ShownTimers {
  Timer? _timer;

  String get _place => widget.w.option('place', '').trim();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    // Moves "now" along the curve; the table itself is asked for rarely.
    _timer = everyWhileShown(const Duration(minutes: 1), _refresh);
  }

  @override
  void didUpdateWidget(covariant TidesWidget old) {
    super.didUpdateWidget(old);
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    unawaited(context.read<TidesService>().ensure(_place));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final service = context.watch<TidesService>();
    final place = _place;
    final table = service.table(place);
    if (table == null) {
      final String text;
      if (place.isEmpty && service.home() == null) {
        text = tr(
          'widget.tides.needsPlace',
          'Set a place in Settings → Weather, or a place on the coast in the widget settings.',
        );
      } else if (place.isNotEmpty && service.placeUnknown(place)) {
        text = tr('widget.tides.noSuchPlace', 'No place called “{place}”', {
          'place': place,
        });
      } else if (service.noSea(place)) {
        text = tr(
          'widget.tides.inland',
          'No sea here to have tides — set a place on the coast in the widget settings.',
        );
      } else {
        text =
            service.error(place) ??
            tr('widget.tides.loading', 'Working out the tides…');
      }
      return TileMessage(text, theme: t);
    }

    final now = DateTime.now();
    final feet = widget.w.option<String>('units', 'm') == 'ft';
    String height(double m) => feet
        ? '${(m * 3.2808).toStringAsFixed(1)} ft'
        : '${m.toStringAsFixed(1)} m';
    final next = table.after(now);
    final title = place.isEmpty
        ? tr('widget.tides.title', 'Tides')
        : tr('widget.tides.titleAt', 'Tides · {place}', {
            'place': service.placeName(place) ?? place,
          });
    final status = StatusColours.of(t);

    return LayoutBuilder(
      builder: (context, c) {
        // The curve needs some height; a strip gets just the next tide.
        final curve = c.maxHeight >= 150;
        final list = c.maxHeight >= 260;
        return FitCanvas(
          designHeight: curve ? (list ? 250 : 170) : 72,
          maxScale: (c.maxWidth / 320).clamp(1.0, 3.0),
          builder: (context, size) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TileLabel(
                icon: Icons.waves_outlined,
                text: title,
                theme: t,
                size: 11,
              ),
              const SizedBox(height: 4),
              if (next.isEmpty)
                Text(
                  tr('widget.tides.noneAhead', 'No more tides in the forecast'),
                  style: TextStyle(color: t.textSecondary, fontSize: 13),
                )
              else
                _Headline(
                  next: next.first,
                  rising: table.rising(now),
                  now: now,
                  height: height,
                  theme: t,
                  status: status,
                ),
              if (curve) ...[
                const SizedBox(height: 6),
                Expanded(
                  child: CustomPaint(
                    painter: _CurvePainter(
                      table: table,
                      now: now,
                      theme: t,
                      high: status.good,
                      low: t.accent,
                    ),
                  ),
                ),
              ],
              if (list && next.length > 1) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: Row(
                    children: [
                      for (final x in next.skip(1).take(4))
                        Expanded(
                          child: _TideCell(
                            x: x,
                            now: now,
                            height: height,
                            theme: t,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({
    required this.next,
    required this.rising,
    required this.now,
    required this.height,
    required this.theme,
    required this.status,
  });

  final Tide next;
  final bool rising;
  final DateTime now;
  final String Function(double) height;
  final DashboardTheme theme;
  final StatusColours status;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Row(
      children: [
        Icon(
          rising ? Icons.north_rounded : Icons.south_rounded,
          size: 30,
          color: rising ? status.good : t.accent,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                next.high
                    ? tr('widget.tides.highAt', 'High tide {time}', {
                        'time': hhmm(next.at),
                      })
                    : tr('widget.tides.lowAt', 'Low tide {time}', {
                        'time': hhmm(next.at),
                      }),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                [
                  rising
                      ? tr('widget.tides.rising', 'Coming in')
                      : tr('widget.tides.falling', 'Going out'),
                  _until(next.at.difference(now)),
                  height(next.metres),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TideCell extends StatelessWidget {
  const _TideCell({
    required this.x,
    required this.now,
    required this.height,
    required this.theme,
  });

  final Tide x;
  final DateTime now;
  final String Function(double) height;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final today = DateUtils.isSameDay(x.at, now);
    return Column(
      children: [
        Text(
          '${x.high ? '▲' : '▼'} ${today ? '' : '${weekdayShort(x.at)} '}${hhmm(x.at)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          height(x.metres),
          maxLines: 1,
          style: TextStyle(color: t.textSecondary, fontSize: 10),
        ),
      ],
    );
  }
}

/// The sea's height from six hours ago to eighteen ahead: the water
/// filled in, each tide marked with its time, and now.
class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.table,
    required this.now,
    required this.theme,
    required this.high,
    required this.low,
  });

  final TideTable table;
  final DateTime now;
  final DashboardTheme theme;
  final Color high;
  final Color low;

  static const _before = Duration(hours: 6);
  static const _after = Duration(hours: 18);

  @override
  void paint(Canvas canvas, Size size) {
    final from = now.subtract(_before);
    final to = now.add(_after);
    final pts = [
      for (final p in table.points)
        if (!p.$1.isBefore(from) && !p.$1.isAfter(to)) p,
    ];
    if (pts.length < 2) return;
    final tides = [
      for (final x in table.tides)
        if (!x.at.isBefore(from) && !x.at.isAfter(to)) x,
    ];
    var lo = pts.map((p) => p.$2).reduce(math.min);
    var hi = pts.map((p) => p.$2).reduce(math.max);
    if (hi - lo < 0.2) {
      lo -= 0.1;
      hi += 0.1;
    }
    // Room above for the high tides' times, below for the lows'.
    const label = 14.0;
    final top = label, bottom = size.height - label;
    final span = to.difference(from).inSeconds;
    double x(DateTime t) => size.width * t.difference(from).inSeconds / span;
    double y(double h) => bottom - (bottom - top) * (h - lo) / (hi - lo);

    final line = Path()..moveTo(x(pts.first.$1), y(pts.first.$2));
    for (final p in pts.skip(1)) {
      line.lineTo(x(p.$1), y(p.$2));
    }
    final fill = Path.from(line)
      ..lineTo(x(pts.last.$1), size.height)
      ..lineTo(x(pts.first.$1), size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [low.withValues(alpha: .35), low.withValues(alpha: .05)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = low
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    void text(String s, Offset centre, Color colour) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: colour,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final double dx = (centre.dx - tp.width / 2).clamp(
        0.0,
        math.max(0.0, size.width - tp.width).toDouble(),
      );
      tp.paint(canvas, Offset(dx, centre.dy - tp.height / 2));
    }

    for (final tide in tides) {
      final p = Offset(x(tide.at), y(tide.metres));
      canvas.drawCircle(p, 3, Paint()..color = tide.high ? high : low);
      text(
        hhmm(tide.at),
        Offset(p.dx, tide.high ? p.dy - 9 : p.dy + 9),
        theme.textSecondary,
      );
    }

    // Now: a line down, and the water's height on it.
    final nx = x(now);
    canvas.drawLine(
      Offset(nx, 0),
      Offset(nx, size.height),
      Paint()
        ..color = theme.textSecondary.withValues(alpha: .5)
        ..strokeWidth = 1,
    );
    final h = table.heightAt(now);
    if (h != null) {
      final p = Offset(nx, y(h));
      canvas.drawCircle(p, 5, Paint()..color = theme.textPrimary);
      canvas.drawCircle(p, 3, Paint()..color = low);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.table != table || old.now != now || old.theme != theme;
}

final tidesWidgetType = DashboardWidgetType(
  type: 'tides',
  category: WidgetCategory.gettingOut,
  name: 'Tides',
  description:
      'High and low tide times, whether the water is coming in or going out, '
      'and the sea’s height through the day — anywhere on the coast. From '
      'Open-Meteo’s tide model, no key needed. Modelled, not measured: fine '
      'for a walk on the beach, not for navigation.',
  glyph: '🌊',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  options: const [
    WidgetOption(
      key: 'place',
      label: 'Place',
      defaultValue: '',
      help:
          'A town on the coast — Walton-on-the-Naze, Whitstable, Cape May. '
          'The place in Settings → Weather otherwise, if it’s by the sea.',
    ),
    WidgetOption(
      key: 'units',
      label: 'Heights in',
      kind: OptionKind.choice,
      defaultValue: 'm',
      choices: {'m': 'Metres', 'ft': 'Feet'},
    ),
  ],
  preview: const [
    PreviewLine('↑ High tide 14:32', scale: .14, px: 18),
    PreviewLine('Coming in · in 2 h 10 min · 1.4 m', scale: .1, px: 13),
  ],
  build: (context, w) => TidesWidget(w: w),
);

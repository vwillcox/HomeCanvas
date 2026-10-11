// An example widget to start from: the sea's level at a place, hour by hour
// through today, as a curve with a mark at now.
//
// Change it, save it under a name of your own — lower-case letters, digits
// and underscores, ending .dart — and upload it in the editor under Custom
// widgets. The panel checks it, builds it into itself and restarts; if it
// does not check or build, the panel stays as it was and the editor shows
// you what the compiler said.
//
// Three things make a widget:
//
//   1. A Flutter widget, handed a DashboardWidgetContext: `w.theme` for
//      colours, `w.option(key, fallback)` for its settings.
//   2. A DashboardWidgetType describing it — the editor builds its palette
//      entry and its settings form from that.
//   3. A top-level `final widgetType = …`, which is what gets registered.
//      It must be called exactly that.
//
// Anything the app's own widgets use is yours to import, from
// `package:home_canvas/…` and the packages in its pubspec.
import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/tile_bits.dart';
import 'package:home_canvas/widgets/pause_when_hidden.dart';
import 'package:home_canvas/widgets/shown_timers.dart';

class TideCurveWidget extends StatefulWidget {
  const TideCurveWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<TideCurveWidget> createState() => _TideCurveWidgetState();
}

// PauseWhenHidden and ShownTimers stop the timer while the tile cannot be
// seen — behind a video, with the screen dark — and catch up when it can.
class _TideCurveWidgetState extends State<TideCurveWidget>
    with PauseWhenHidden, ShownTimers {
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  /// Today's levels in metres, one an hour from midnight.
  List<double> _levels = const [];
  String? _error;
  DateTime? _fetched;

  @override
  void initState() {
    super.initState();
    // Never fetch in build: it runs whenever anything on the dashboard
    // changes. Once the first frame is up, and then on a timer.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
    everyWhileShown(const Duration(minutes: 30), _fetch);
  }

  @override
  void didUpdateWidget(covariant TideCurveWidget old) {
    super.didUpdateWidget(old);
    // Its settings may have changed: another place is another fetch.
    if (old.w.option('latitude', 0.0) != widget.w.option('latitude', 0.0) ||
        old.w.option('longitude', 0.0) != widget.w.option('longitude', 0.0)) {
      _fetched = null;
      _fetch();
    }
  }

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }

  Future<void> _fetch() async {
    final last = _fetched;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 25)) {
      return;
    }
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        'https://marine-api.open-meteo.com/v1/marine',
        queryParameters: {
          'latitude': widget.w.option('latitude', 51.95),
          'longitude': widget.w.option('longitude', 1.29),
          'hourly': 'sea_level_height_msl',
          'forecast_days': 1,
          'timezone': 'auto',
        },
      );
      final hourly = r.data?['hourly'];
      final levels = hourly is Map ? hourly['sea_level_height_msl'] : null;
      if (!mounted) return;
      setState(() {
        _levels = [
          if (levels is List)
            for (final v in levels)
              if (v is num) v.toDouble(),
        ];
        _error = _levels.length < 2 ? 'No sea level for this place' : null;
        _fetched = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach the tide forecast');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    if (_levels.length < 2) {
      return TileMessage(_error ?? 'Fetching…', theme: t);
    }
    final now = DateTime.now();
    final hour = now.hour + now.minute / 60;
    final level = _levels[math.min(now.hour, _levels.length - 1)];
    final rising =
        now.hour + 1 < _levels.length && _levels[now.hour + 1] > level;
    return LayoutBuilder(
      builder: (context, c) {
        // Sized from the tile, so it reads at any size it is dragged to.
        final head = (c.maxHeight * 0.22).clamp(12.0, 34.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: head,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.w.option('place', 'Harwich'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: head * 0.55,
                        height: 1,
                      ),
                    ),
                  ),
                  Text(
                    '${rising ? '↑' : '↓'} ${level.toStringAsFixed(2)} m',
                    maxLines: 1,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: head * 0.7,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CustomPaint(painter: _TidePainter(_levels, hour, t)),
            ),
          ],
        );
      },
    );
  }
}

/// The day's levels as a filled curve, and a line down it at now.
class _TidePainter extends CustomPainter {
  _TidePainter(this.levels, this.hour, this.theme);

  final List<double> levels;
  final double hour;
  final DashboardTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.length < 2 || size.isEmpty) return;
    final low = levels.reduce(math.min);
    final high = levels.reduce(math.max);
    final range = high - low == 0 ? 1.0 : high - low;
    Offset at(int i) => Offset(
      i / (levels.length - 1) * size.width,
      size.height - 3 - (levels[i] - low) / range * (size.height - 6),
    );
    final curve = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < levels.length; i++) {
      curve.lineTo(at(i).dx, at(i).dy);
    }
    canvas
      ..drawPath(
        Path.from(curve)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close(),
        // Always the theme's colours: one of its own would look wrong in
        // every theme but the one it was written against.
        Paint()..color = theme.accent.withValues(alpha: 0.16),
      )
      ..drawPath(
        curve,
        Paint()
          ..color = theme.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, size.height / 50)
          ..strokeJoin = StrokeJoin.round,
      );
    final x = (hour / (levels.length - 1)).clamp(0.0, 1.0) * size.width;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = theme.textSecondary.withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_TidePainter old) =>
      old.levels != levels || old.hour != hour || old.theme != theme;
}

final widgetType = DashboardWidgetType(
  type: 'tide_curve', // saved in the dashboard: never rename it in place
  category: WidgetCategory.custom,
  name: 'Tide curve',
  description: 'The sea’s level at a place through today, as a curve.',
  glyph: '🌊', // shown in the editor's palette
  defaultWidth: 4,
  defaultHeight: 2,
  minWidth: 2,
  minHeight: 1,
  // It sizes its own text from the tile, so the dashboard need not shrink
  // it for a small one.
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'place',
      label: 'Place',
      defaultValue: 'Harwich',
      help: 'What to call it on the tile.',
    ),
    WidgetOption(
      key: 'latitude',
      label: 'Latitude',
      kind: OptionKind.number,
      defaultValue: 51.95,
    ),
    WidgetOption(
      key: 'longitude',
      label: 'Longitude',
      kind: OptionKind.number,
      defaultValue: 1.29,
      help: 'West is a minus number.',
    ),
  ],
  preview: const [
    PreviewLine('Harwich   ↑ 0.84 m', scale: 0.14),
    PreviewLine('▁▃▆█▆▃▁▃▆█', scale: 0.2),
  ],
  build: (context, w) => TideCurveWidget(w: w),
);

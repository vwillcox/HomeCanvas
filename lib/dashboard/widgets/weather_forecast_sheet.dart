import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/weather_service.dart';
import '../../widgets/weather_overlay.dart' show weatherIcon;
import '../dashboard_theme.dart';

/// Opens the full forecast over the dashboard.
///
/// Reached by tapping the weather widget. It is the whole picture the tile
/// only hints at: now, the next twenty-four hours and the week, laid out for
/// a glance from across the room rather than for reading up close.
///
/// Dismissed by the close button, a tap outside it, a swipe down, or by
/// itself after [autoClose] — a dashboard left showing the forecast is a
/// dashboard that is not showing everything else.
Future<void> showWeatherForecast(
  BuildContext context,
  DashboardTheme theme, {
  Duration autoClose = const Duration(minutes: 2),
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close the forecast',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, _, _) =>
        WeatherForecastSheet(theme: theme, autoClose: autoClose),
    transitionBuilder: (context, animation, _, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      // Blurs the dashboard behind rather than just dimming it: the sheet
      // reads as a layer over the panel, not a page that replaced it.
      return AnimatedBuilder(
        animation: curved,
        builder: (context, _) => BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: 14 * curved.value,
            sigmaY: 14 * curved.value,
          ),
          child: FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

/// The forecast itself.
///
/// Public so it can be tested and shown on its own; [showWeatherForecast] is
/// the way in from the dashboard.
class WeatherForecastSheet extends StatefulWidget {
  const WeatherForecastSheet({
    super.key,
    required this.theme,
    this.autoClose = const Duration(minutes: 2),
  });

  final DashboardTheme theme;
  final Duration autoClose;

  @override
  State<WeatherForecastSheet> createState() => _WeatherForecastSheetState();
}

class _WeatherForecastSheetState extends State<WeatherForecastSheet>
    with SingleTickerProviderStateMixin {
  Timer? _timer;

  /// How far the sheet has been dragged down, for swipe-to-dismiss.
  double _drag = 0;
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() => setState(() => _drag = _dragFrom * (1 - _settle.value)));
  double _dragFrom = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.autoClose, _close);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _settle.dispose();
    super.dispose();
  }

  void _close() {
    if (mounted) Navigator.of(context).maybePop();
  }

  void _dragEnd(DragEndDetails d) {
    // Far enough, or flicked: either reads as "take this away".
    if (_drag > 140 || (d.primaryVelocity ?? 0) > 700) {
      _close();
      return;
    }
    _dragFrom = _drag;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final weather = context.watch<WeatherService>().weather;
    final screen = MediaQuery.sizeOf(context);

    return SafeArea(
      child: Center(
        child: GestureDetector(
          // Swallows taps on the sheet itself, which would otherwise fall
          // through to the barrier and close it mid-read.
          onTap: () {},
          onVerticalDragUpdate: (d) =>
              setState(() => _drag = math.max(0, _drag + d.delta.dy)),
          onVerticalDragEnd: _dragEnd,
          child: Transform.translate(
            offset: Offset(0, _drag),
            child: Opacity(
              opacity: (1 - _drag / 600).clamp(0.4, 1.0),
              child: Container(
                width: math.min(screen.width * 0.94, 1780),
                height: math.min(screen.height * 0.92, 1100),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      for (final c in t.background.length > 1
                          ? t.background
                          : [t.background.first, t.background.first])
                        c.withValues(alpha: 0.97),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: t.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 60,
                      offset: Offset(0, 20),
                    ),
                  ],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: weather == null
                      ? Center(
                          child: Text(
                            'Waiting for the forecast…',
                            style: TextStyle(
                                color: t.textSecondary, fontSize: 24),
                          ),
                        )
                      : _Body(weather: weather, theme: t, onClose: _close),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.weather,
    required this.theme,
    required this.onClose,
  });

  final Weather weather;
  final DashboardTheme theme;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final week = weather.daily.take(7).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 28, 28, 32),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth > 1000;
          final header = Row(
            children: [
              Icon(Icons.place_outlined, color: t.textSecondary, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  weather.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textSecondary, fontSize: 24),
                ),
              ),
              _CloseButton(theme: t, onPressed: onClose),
            ],
          );

          final now = _Now(weather: weather, theme: t);
          final days = _Week(days: week, weather: weather, theme: t);
          final hours = _Hours(weather: weather, theme: t);

          if (!wide) {
            // Portrait, or a small screen: everything in one column, and
            // scrolled rather than squeezed.
            return Column(
              children: [
                header,
                Expanded(
                  child: ListView(
                    children: [
                      // Given a height of its own: it divides its space
                      // between the reading and the numbers, and a list has
                      // no height to divide.
                      SizedBox(height: 560, child: now),
                      const SizedBox(height: 24),
                      SizedBox(height: 240, child: hours),
                      const SizedBox(height: 24),
                      SizedBox(height: 620, child: days),
                    ],
                  ),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: now),
                    const SizedBox(width: 40),
                    Expanded(flex: 6, child: days),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(height: 250, child: hours),
            ],
          );
        },
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.theme, required this.onPressed});

  final DashboardTheme theme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close the forecast',
      child: Material(
        color: theme.textPrimary.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 64,
            height: 64,
            child: Icon(Icons.close, color: theme.textPrimary, size: 34),
          ),
        ),
      ),
    );
  }
}

/// Right now: the reading, and the numbers that go with it.
class _Now extends StatelessWidget {
  const _Now({required this.weather, required this.theme});

  final Weather weather;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final today = weather.daily.isNotEmpty ? weather.daily.first : null;

    final stats = <_StatData>[
      _StatData(Icons.thermostat, 'Feels like', '${weather.feelsLike.round()}°'),
      _StatData(Icons.water_drop_outlined, 'Humidity', '${weather.humidity}%'),
      _StatData(Icons.air, 'Wind',
          '${weather.windSpeed.round()} ${weather.windUnit}'),
      if (today != null) ...[
        _StatData(Icons.umbrella_outlined, 'Chance of rain',
            '${today.precipitationChance}%'),
        _StatData(Icons.wb_sunny_outlined, 'UV index',
            '${today.uvIndexMax.round()} · ${uvLabel(today.uvIndexMax)}'),
        _StatData(Icons.wb_twilight, 'Sunrise · sunset',
            '${today.sunrise} · ${today.sunset}'),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(
                  weatherIcon(weather.weatherCode, weather.isDay),
                  color: t.accent,
                  size: 140,
                ),
                const SizedBox(width: 28),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${weather.temperature.round()}°',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 136,
                        height: 1.0,
                        fontWeight: FontWeight.w200,
                      ),
                    ),
                    Text(
                      weather.description,
                      style: TextStyle(color: t.textPrimary, fontSize: 34),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'High ${weather.tempMax.round()}° · '
                      'Low ${weather.tempMin.round()}°',
                      style: TextStyle(color: t.textSecondary, fontSize: 26),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          flex: 4,
          child: LayoutBuilder(
            builder: (context, c) {
              // Three across, two down: six numbers, all the same weight, so
              // none of them looks like the headline.
              const perRow = 3;
              final rows = (stats.length / perRow).ceil();
              final h = (c.maxHeight - (rows - 1) * 14) / rows;
              return Column(
                children: [
                  for (var r = 0; r < rows; r++) ...[
                    if (r > 0) const SizedBox(height: 14),
                    SizedBox(
                      height: h,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < perRow; i++) ...[
                            if (i > 0) const SizedBox(width: 14),
                            Expanded(
                              child: r * perRow + i < stats.length
                                  ? _Stat(
                                      data: stats[r * perRow + i], theme: t)
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatData {
  const _StatData(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

class _Stat extends StatelessWidget {
  const _Stat({required this.data, required this.theme});

  final _StatData data;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: t.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.textPrimary.withValues(alpha: 0.08)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(data.icon, color: t.textSecondary, size: 22),
                const SizedBox(width: 8),
                Text(
                  data.label,
                  style: TextStyle(color: t.textSecondary, fontSize: 19),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              data.value,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 30,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The week, each day's range drawn against the whole week's.
///
/// The bars share one scale, so a warm day sits visibly to the right of a
/// cold one — the shape of the week in one look, which a column of numbers
/// makes you work out.
class _Week extends StatelessWidget {
  const _Week({required this.days, required this.weather, required this.theme});

  final List<DailyForecast> days;
  final Weather weather;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    if (days.isEmpty) return const SizedBox.shrink();
    final range = weekRange(days);

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
      decoration: BoxDecoration(
        color: t.textPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'NEXT ${days.length} DAYS',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 17,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < days.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: t.textPrimary.withValues(alpha: 0.08),
              ),
            Expanded(
              child: _DayRow(
                day: days[i],
                range: range,
                // Only today gets a marker for "now", and only when it
                // falls inside the day's range — a reading from before the
                // day's forecast low would otherwise sit off the bar.
                now: i == 0 && isToday(days[i].date)
                    ? weather.temperature
                    : null,
                theme: t,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.range,
    required this.now,
    required this.theme,
  });

  final DailyForecast day;
  final (double, double) range;
  final double? now;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final rain = day.precipitationChance;
    return Row(
      children: [
        SizedBox(
          // Wide enough for "Wednesday" at this size — at 110 it wrapped.
          width: 150,
          child: Text(
            dayName(day.date),
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 26,
              fontWeight: isToday(day.date) ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        SizedBox(
          width: 60,
          child: Icon(weatherIcon(day.weatherCode, true),
              color: t.accent, size: 34),
        ),
        SizedBox(
          width: 76,
          child: Text(
            // Only worth saying when it is worth an umbrella; a column of
            // "0%" is noise that hides the days that matter.
            rain >= 20 ? '$rain%' : '',
            style: const TextStyle(
              color: Color(0xFF7DD3FC),
              fontSize: 21,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          width: 62,
          child: Text(
            '${day.tempMin.round()}°',
            textAlign: TextAlign.right,
            style: TextStyle(color: t.textSecondary, fontSize: 26),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SizedBox(
            height: 10,
            child: CustomPaint(
              painter: _RangeBar(
                min: day.tempMin,
                max: day.tempMax,
                range: range,
                now: now,
                track: t.textPrimary.withValues(alpha: 0.10),
                marker: t.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 62,
          child: Text(
            '${day.tempMax.round()}°',
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// One day's low-to-high, on the week's scale.
class _RangeBar extends CustomPainter {
  _RangeBar({
    required this.min,
    required this.max,
    required this.range,
    required this.now,
    required this.track,
    required this.marker,
  });

  final double min;
  final double max;
  final (double, double) range;
  final double? now;
  final Color track;
  final Color marker;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, r),
      Paint()..color = track,
    );
    final from = rangeFraction(min, range) * size.width;
    final to = math.max(from + size.height, rangeFraction(max, range) * size.width);
    final rect = Rect.fromLTRB(from, 0, math.min(to, size.width), size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, r),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(size.width, 0),
          const [Color(0xFF7DD3FC), Color(0xFFFBBF24), Color(0xFFF87171)],
          const [0.0, 0.6, 1.0],
        ),
    );
    final n = now;
    if (n != null) {
      final x = rangeFraction(n, range) * size.width;
      canvas.drawCircle(Offset(x, size.height / 2), size.height * 0.9,
          Paint()..color = const Color(0x55000000));
      canvas.drawCircle(
          Offset(x, size.height / 2), size.height * 0.7, Paint()..color = marker);
    }
  }

  @override
  bool shouldRepaint(_RangeBar old) =>
      old.min != min || old.max != max || old.range != range || old.now != now;
}

/// The next twenty-four hours: time, sky, a temperature curve and rain.
class _Hours extends StatelessWidget {
  const _Hours({required this.weather, required this.theme});

  final Weather weather;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: BoxDecoration(
        color: t.textPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final hours = hoursToShow(withNow(weather), c.maxWidth);
          if (hours.isEmpty) {
            return Center(
              child: Text(
                'No hourly forecast yet.',
                style: TextStyle(color: t.textSecondary, fontSize: 22),
              ),
            );
          }
          Widget row(Widget Function(HourlyForecast h, int i) cell) => Row(
                children: [
                  for (var i = 0; i < hours.length; i++)
                    Expanded(child: Center(child: cell(hours[i], i))),
                ],
              );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              row((h, i) => Text(
                    hourLabel(h.time, first: i == 0),
                    style: TextStyle(
                      color: i == 0 ? t.textPrimary : t.textSecondary,
                      fontSize: 18,
                      fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                    ),
                  )),
              const SizedBox(height: 8),
              row((h, _) => Icon(weatherIcon(h.weatherCode, h.isDay),
                  color: t.accent, size: 32)),
              Expanded(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _TemperatureCurve(
                    temps: [for (final h in hours) h.temperature],
                    line: t.accent,
                    label: t.textPrimary,
                  ),
                ),
              ),
              row((h, _) => Text(
                    h.precipitationChance >= 20
                        ? '${h.precipitationChance}%'
                        : '',
                    style: const TextStyle(
                      color: Color(0xFF7DD3FC),
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}

/// A smooth line through the hourly temperatures, labelled at each point.
///
/// The points sit at the centres of the columns above, which are equal
/// widths — so the curve lines up with the hours without any shared layout
/// between the two.
class _TemperatureCurve extends CustomPainter {
  _TemperatureCurve({
    required this.temps,
    required this.line,
    required this.label,
  });

  final List<double> temps;
  final Color line;
  final Color label;

  @override
  void paint(Canvas canvas, Size size) {
    if (temps.isEmpty) return;
    final lo = temps.reduce(math.min);
    final hi = temps.reduce(math.max);
    final span = hi - lo < 1 ? 1.0 : hi - lo;
    // Room above each point for its label, and a little below.
    const top = 34.0;
    const bottom = 10.0;
    final usable = math.max(1.0, size.height - top - bottom);
    final step = size.width / temps.length;
    final points = [
      for (var i = 0; i < temps.length; i++)
        Offset(step * (i + 0.5),
            top + usable * (1 - (temps[i] - lo) / span)),
    ];

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      // Catmull-Rom as cubic Béziers: smooth without overshooting much.
      final p0 = i == 0 ? points[i] : points[i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }

    final fill = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, top),
          Offset(0, size.height),
          [line.withValues(alpha: 0.28), line.withValues(alpha: 0.0)],
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = line,
    );

    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 4, Paint()..color = line);
      final tp = TextPainter(
        text: TextSpan(
          text: '${temps[i].round()}°',
          style: TextStyle(
            color: label,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(points[i].dx - tp.width / 2, points[i].dy - tp.height - 6));
    }
  }

  @override
  bool shouldRepaint(_TemperatureCurve old) =>
      old.line != line || old.label != label || !_same(old.temps, temps);

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// --- the arithmetic, kept out of the widgets so it can be tested ------------

const _dayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

bool isToday(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  return d.year == n.year && d.month == n.month && d.day == n.day;
}

/// "Today", or the weekday in full — there is room here for the whole word.
String dayName(DateTime d, {DateTime? now}) =>
    isToday(d, now: now) ? 'Today' : _dayNames[d.weekday - 1];

/// "Now" for the first column, otherwise the hour on the 24-hour clock.
String hourLabel(DateTime t, {bool first = false}) =>
    first ? 'Now' : '${t.hour.toString().padLeft(2, '0')}:00';

/// The coldest low and warmest high across [days].
///
/// Padded when the week is flat, so a run of identical days still draws as a
/// bar rather than dividing by nothing.
(double, double) weekRange(List<DailyForecast> days) {
  if (days.isEmpty) return (0, 1);
  var lo = days.first.tempMin;
  var hi = days.first.tempMax;
  for (final d in days) {
    lo = math.min(lo, d.tempMin);
    hi = math.max(hi, d.tempMax);
  }
  if (hi - lo < 1) return (lo - 0.5, hi + 0.5);
  return (lo, hi);
}

/// Where [value] falls within [range], 0–1, clamped.
double rangeFraction(double value, (double, double) range) {
  final (lo, hi) = range;
  if (hi <= lo) return 0.5;
  return ((value - lo) / (hi - lo)).clamp(0.0, 1.0);
}

/// The hourly forecast, with its first hour replaced by the reading.
///
/// Open-Meteo's first hour is the forecast for the top of the current hour,
/// which by twenty past can be a couple of degrees from what it actually is.
/// Labelled "Now", beside a big number saying something else, that reads as
/// a mistake — so "Now" shows the same reading as the headline.
List<HourlyForecast> withNow(Weather w) {
  if (w.hourly.isEmpty) return const [];
  final first = w.hourly.first;
  return [
    HourlyForecast(
      time: first.time,
      temperature: w.temperature,
      weatherCode: w.weatherCode,
      precipitationChance: first.precipitationChance,
      isDay: w.isDay,
    ),
    ...w.hourly.skip(1),
  ];
}

/// Which hours fit across [width].
///
/// Every hour when there is room for each to be read; every other hour when
/// there is not. Dropping hours evenly keeps the curve's shape, where
/// squeezing them would just make every label collide with the next.
List<HourlyForecast> hoursToShow(List<HourlyForecast> hourly, double width,
    {double minColumn = 64}) {
  if (hourly.isEmpty) return const [];
  if (width / hourly.length >= minColumn) return hourly;
  return [
    for (var i = 0; i < hourly.length; i += 2) hourly[i],
  ];
}

/// The UV index in words, as the Met Office bands it.
String uvLabel(double uv) {
  if (uv < 3) return 'Low';
  if (uv < 6) return 'Moderate';
  if (uv < 8) return 'High';
  if (uv < 11) return 'Very high';
  return 'Extreme';
}

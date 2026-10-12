import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/weather_service.dart';
import '../../widgets/weather_overlay.dart' show weatherIcon;
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'tile_bits.dart';
import 'weather_forecast_sheet.dart';
import '../../l10n/l10n.dart';
import '../../l10n/dates.dart';
import '../../widgets/lcars.dart';

/// Current conditions, and optionally the next few days.
///
/// Reads the same [WeatherService] the corner overlay uses, so the location
/// and units stay in one place — Settings → Weather — rather than being
/// configured twice.
class DashboardWeatherWidget extends StatelessWidget {
  const DashboardWeatherWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<WeatherService>();
    return Refreshed(
      theme: w.theme,
      at: service.weather == null ? null : service.refreshedAt,
      child: _forecast(context, service),
    );
  }

  Widget _forecast(BuildContext context, WeatherService service) {
    final t = w.theme;
    final weather = service.weather;

    if (weather == null) {
      return Center(
        child: Text(
          service.error ?? tr(
            'widget.weather.waitingForTheForecast',
            'Waiting for the forecast…',
          ),
          style: TextStyle(color: t.textSecondary, fontSize: 16),
        ),
      );
    }

    // Stored as a choice, so it arrives as a string from the editor and as a
    // number from a config written before it became one.
    final days =
        (int.tryParse('${w.config.options['forecastDays'] ?? 3}') ?? 3)
            .clamp(0, 14);
    final showFeels = w.option('showFeelsLike', true);
    final showHighLow = w.option('showHighLow', true);
    final showCurrent = w.option('showCurrent', true);

    // Everything is laid out at a natural size and then scaled to fill by
    // FittedBox, rather than drawn at fixed point sizes. That is what lets
    // the same widget fill a large tile instead of sitting small in the
    // middle of one, and shrink to fit a small tile instead of overflowing —
    // the numbers below are proportions to each other, not sizes on screen.
    final current = t.isLcars
        ? _consoleCurrent(weather, showFeels: showFeels, showHighLow: showHighLow)
        : FittedBox(
      fit: BoxFit.contain,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                weatherIcon(weather.weatherCode, weather.isDay),
                color: t.accent,
                size: 64,
              ),
              const SizedBox(width: 16),
              Text(
                '${weather.temperature.round()}${weather.unit}',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 52,
                  height: 1.0,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            showFeels
                ? tr(
                  'widget.weather.feels',
                  '{description} · feels {feelsLike}{unit}',
                  {'description': weather.description, 'feelsLike': weather.feelsLike.round(), 'unit': weather.unit},
                )
                : weather.description,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textSecondary, fontSize: 17),
          ),
          if (showHighLow)
            Text(
              '${weather.tempMax.round()}° / ${weather.tempMin.round()}°',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary, fontSize: 16),
            ),
        ],
      ),
    );

    // With the current reading switched off, today is dropped from the
    // forecast too. Otherwise the panel still leads with "Today", which is
    // the very thing that was turned off — and on a tile paired with a
    // separate current-conditions widget, says it twice.
    final daily = showCurrent
        ? weather.daily
        : weather.daily.where((d) => !_isToday(d.date)).toList();

    final hasForecast = days > 0 && daily.isNotEmpty;

    final tile = LayoutBuilder(
      builder: (context, c) {
        if (!hasForecast) return Center(child: current);

        // Forecast only: one widget's code, two quite different panels — a
        // reading on one tile and a week's outlook on another.
        if (!showCurrent) {
          return _Forecast(
            days: daily.take(days).toList(),
            theme: t,
            // A long forecast on a wide tile reads better as columns; on a
            // narrow one, as rows down the tile.
            vertical: c.maxWidth / c.maxHeight < 0.9,
          );
        }

        // On a wide, short tile the forecast belongs beside the reading —
        // stacked, there is no height left for either. On anything squarer it
        // belongs underneath, which is how a forecast is usually read.
        final beside = c.maxWidth / c.maxHeight > 2.2;
        final forecast = _Forecast(
          days: daily.take(days).toList(),
          theme: t,
          vertical: beside,
        );

        if (beside) {
          return Row(
            children: [
              Expanded(flex: 5, child: Center(child: current)),
              const SizedBox(width: 12),
              Expanded(flex: 6, child: forecast),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: Center(child: current)),
            const SizedBox(height: 10),
            Expanded(flex: 2, child: forecast),
          ],
        );
      },
    );

    if (!w.option('openOnTap', true)) return tile;
    // The whole tile, not just the reading: a forecast-only tile is mostly
    // columns of days, and they should open the full picture too.
    return Semantics(
      button: true,
      label: tr(
        'widget.weather.showTheFullForecast',
        'Show the full forecast',
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showWeatherForecast(context, t),
        child: tile,
      ),
    );
  }


  /// The reading as a console shows it: the temperature heavy in the accent
  /// with what the sky is doing under it, and the other figures beside it
  /// as blocks capped on the left, each named.
  Widget _consoleCurrent(
    Weather weather, {
    required bool showFeels,
    required bool showHighLow,
  }) {
    final t = w.theme;
    final figures = [
      if (showFeels)
        (
          tr('widget.weather.lcars.feels', 'Feels'),
          '${weather.feelsLike.round()}°',
        ),
      if (showHighLow) ...[
        (
          tr('widget.weather.lcars.high', 'High'),
          '${weather.tempMax.round()}°',
        ),
        (tr('widget.weather.lcars.low', 'Low'), '${weather.tempMin.round()}°'),
      ],
    ];
    // Given all the room there is, so the reading grows to fill a large
    // tile as well as shrinking to fit a small one.
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: FittedBox(
          fit: BoxFit.contain,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${weather.temperature.round()}${weather.unit}',
                        style: TextStyle(
                          color: t.accent,
                          fontSize: 64,
                          height: 1.0,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        weatherIcon(weather.weatherCode, weather.isDay),
                        color: t.textPrimary,
                        size: 46,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lcarsCaps(weather.description),
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              if (figures.isNotEmpty) ...[
                const SizedBox(width: 18),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, f) in figures.indexed)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : lcarsLine),
                        child: LcarsReadout(
                          colour: t.block(i * 2 + 1),
                          name: f.$1,
                          value: f.$2,
                          width: 132,
                          height: 28,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  static String dayLabel(DateTime d) =>
      _isToday(d) ? tr('common.today', 'Today') : weekdayShort(d);
}

/// The next few days, as a row of columns or a column of rows.
///
/// Each day is scaled into its own share of the space, so three days on a
/// wide tile read comfortably large and seven on a narrow one still fit,
/// without either being given a fixed point size that suits only one shape.
class _Forecast extends StatelessWidget {
  const _Forecast({
    required this.days,
    required this.theme,
    required this.vertical,
  });

  final List<DailyForecast> days;
  final DashboardTheme theme;

  /// Laid out as rows down the side rather than columns along the bottom,
  /// which is what a tall, narrow share of a wide tile wants.
  final bool vertical;

  /// About what one day's column measures before it is scaled to fit: on
  /// any other theme, and on a console.
  static const _cell = Size(64, 86);
  static const _consoleCell = Size(104, 90);

  /// The days' columns side by side — or, where that leaves each one
  /// noticeably larger, in two rows: a week across a tile that is wide but
  /// not that wide is seven slivers in one row and seven readable days in
  /// two. The second row keeps the first's columns, so the days line up.
  static Widget _rows(List<Widget> cells, Size room, Size cell) {
    double scale(int across, int down) {
      final w = room.width / across / cell.width;
      final h = room.height / down / cell.height;
      return w < h ? w : h;
    }

    final across = (cells.length + 1) ~/ 2;
    if (cells.length < 4 || scale(across, 2) < scale(cells.length, 1) * 1.15) {
      return Row(children: cells);
    }
    return Column(
      children: [
        Expanded(child: Row(children: cells.sublist(0, across))),
        Expanded(
          child: Row(
            children: [
              ...cells.sublist(across),
              for (var i = cells.length; i < across * 2; i++)
                const Spacer(),
            ],
          ),
        ),
      ],
    );
  }

  /// A day on a console: its name on a bar of its own colour, then the
  /// sky and the high — and the low, where there is the width for it.
  Widget _consoleDay(int i, DailyForecast day) {
    final name = DashboardWeatherWidget.dayLabel(day.date);
    Widget icon(double size) => Icon(
      weatherIcon(day.weatherCode, true),
      color: theme.textSecondary,
      size: size,
    );
    Widget high(double size) => Text(
      '${day.tempMax.round()}°',
      style: TextStyle(
        color: theme.textPrimary,
        fontSize: size,
        height: 1.1,
        fontWeight: FontWeight.w700,
      ),
    );
    Widget low(double size) => Text(
      '${day.tempMin.round()}°',
      style: TextStyle(
        color: theme.textSecondary,
        fontSize: size,
        height: 1.1,
      ),
    );
    if (vertical) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LcarsReadout(
            colour: theme.block(i + 2),
            value: name,
            width: 86,
            height: 26,
          ),
          const SizedBox(width: 10),
          icon(24),
          const SizedBox(width: 8),
          high(20),
          const SizedBox(width: 6),
          low(20),
        ],
      );
    }
    // In a column the sky is the large thing, with the high over the low
    // beside it: nearly square, so it fills its share of a tile whichever
    // way that is longer.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _consoleCell.width,
          height: 22,
          color: theme.block(i + 2),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            lcarsCaps(name),
            maxLines: 1,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              color: lcarsInk,
              fontSize: 15,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon(56),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [high(25), low(22)],
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (theme.isLcars) {
      final cells = [
        for (final (i, day) in days.indexed)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(lcarsLine / 2),
              child: FittedBox(
                fit: BoxFit.contain,
                child: _consoleDay(i, day),
              ),
            ),
          ),
      ];
      if (vertical) return Column(children: cells);
      return LayoutBuilder(
        builder: (context, c) => _rows(cells, c.biggest, _consoleCell),
      );
    }
    final cells = [
      for (final day in days)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: FittedBox(
              fit: BoxFit.contain,
              child: vertical
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 58,
                          child: Text(
                            DashboardWeatherWidget.dayLabel(day.date),
                            style: TextStyle(
                                color: theme.textSecondary, fontSize: 17),
                          ),
                        ),
                        Icon(weatherIcon(day.weatherCode, true),
                            color: theme.textSecondary, size: 26),
                        const SizedBox(width: 10),
                        Text(
                          '${day.tempMax.round()}°',
                          style:
                              TextStyle(color: theme.textPrimary, fontSize: 20),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DashboardWeatherWidget.dayLabel(day.date),
                          style: TextStyle(
                              color: theme.textSecondary, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Icon(weatherIcon(day.weatherCode, true),
                            color: theme.textSecondary, size: 32),
                        const SizedBox(height: 4),
                        Text(
                          '${day.tempMax.round()}°',
                          style:
                              TextStyle(color: theme.textPrimary, fontSize: 18),
                        ),
                      ],
                    ),
            ),
          ),
        ),
    ];
    if (vertical) return Column(children: cells);
    return LayoutBuilder(
      builder: (context, c) => _rows(cells, c.biggest, _cell),
    );
  }
}

final weatherWidgetType = DashboardWidgetType(
  type: 'weather',
  category: WidgetCategory.weather,
  name: 'Weather',
  description:
      'Current conditions and a short forecast. Uses the location set in '
      'Settings → Weather.',
  glyph: '⛅',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 1,
  minHeight: 1,
  options: const [
    WidgetOption(
      key: 'forecastDays',
      label: 'Forecast',
      kind: OptionKind.choice,
      defaultValue: '3',
      choices: {
        '0': 'None',
        '3': '3 day',
        '5': '5 day',
        '7': '7 day',
        '8': '8 day',
        '10': '10 day',
        '14': '14 day',
      },
      help: 'A wider tile suits the longer forecasts.',
    ),
    WidgetOption(
      key: 'showCurrent',
      label: 'Show current conditions',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'Turn off for a forecast-only tile, so one widget can be a '
          'reading in one place and a week’s outlook in another. Today is '
          'left out of the forecast when this is off.',
    ),
    WidgetOption(
      key: 'showFeelsLike',
      label: 'Show what it feels like',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'showHighLow',
      label: 'Show today’s high and low',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'openOnTap',
      label: 'Tap for the full forecast',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'Now, the next 24 hours and the week, over the whole screen. '
          'Close it with the ×, a tap outside it or a swipe down; it closes '
          'itself after two minutes.',
    ),
  ],
  preview: const [
    PreviewLine('☁ 14°C', scale: 0.3, accent: true),
    PreviewLine('Light cloud · feels 12°C', scale: 0.1, muted: true),
    PreviewLine('Today 16°  Tue 15°  Wed 13°', scale: 0.1, muted: true),
  ],
  live: (config, data) {
    final weather = data.weather?.weather;
    if (weather == null) return const [];
    final days =
        (int.tryParse('${config.options['forecastDays'] ?? 3}') ?? 3).clamp(0, 7);
    final feels = config.options['showFeelsLike'] != false
        ? ' · feels ${weather.feelsLike.round()}${weather.unit}'
        : '';
    final showCurrent = config.options['showCurrent'] != false;
    if (!showCurrent) {
      return [
        for (final d in weather.daily.take(days == 0 ? 3 : days))
          PreviewLine(
              '${DashboardWeatherWidget.dayLabel(d.date)}   ${d.tempMax.round()}°',
              scale: 0.11,
              centre: true),
      ];
    }
    return [
      PreviewLine('${weather.temperature.round()}${weather.unit}',
          scale: 0.3, accent: true, centre: true),
      PreviewLine('${weather.description}$feels',
          scale: 0.1, muted: true, centre: true),
      if (config.options['showHighLow'] != false)
        PreviewLine(
            '${weather.tempMax.round()}° / ${weather.tempMin.round()}°',
            scale: 0.09, muted: true, centre: true),
      if (days > 0 && weather.daily.isNotEmpty)
        PreviewLine(
          weather.daily
              .take(days)
              .map((d) => '${d.tempMax.round()}°')
              .join('   '),
          scale: 0.1,
          muted: true,
          centre: true,
        ),
    ];
  },
  build: (context, w) => DashboardWeatherWidget(w: w),
);

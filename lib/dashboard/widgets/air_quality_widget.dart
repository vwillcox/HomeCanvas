import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/air_quality_service.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// Air quality, pollen by type, and UV, beside the weather.
class AirQualityWidget extends StatelessWidget {
  const AirQualityWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final service = context.watch<AirQualityService>();
    final air = service.current;
    if (air == null) {
      return TileMessage(
        service.error ?? 'Fetching the air quality…',
        theme: t,
      );
    }
    final status = StatusColours.of(t);
    final aqiColour = switch (air.aqiSeverity) {
      0 => status.good,
      1 => t.accent,
      2 => status.warn,
      _ => status.bad,
    };
    final showPollen = w.option('showPollen', true);

    final reading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          air.aqi == null ? '—' : '${air.aqi}',
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 46,
            height: 1,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 6),
        StatusChip(text: '${air.aqiWord} air', colour: aqiColour, size: 11),
        if (air.uv != null) ...[
          const SizedBox(height: 6),
          Text(
            'UV ${air.uv!.round()} · ${air.uvWord}',
            maxLines: 1,
            style: TextStyle(color: t.textSecondary, fontSize: 11),
          ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        // Beside each other on anything wider than it is tall; one above the
        // other on a tall, narrow tile.
        // Side by side only where the pollen has room beside the reading —
        // about 200 of the 120-high canvas's units, which is a tile at least
        // two thirds again as wide as it is tall.
        final stacked = c.maxWidth / c.maxHeight < 1.65;
        // On a tile this small the pollen would be too small to read; the
        // reading alone is the useful part.
        if (c.maxWidth < 220 || c.maxHeight < 140) {
          return FitCanvas(
            designHeight: 100,
            maxScale: 3,
            builder: (context, size) => Center(
              child: FittedBox(fit: BoxFit.scaleDown, child: reading),
            ),
          );
        }
        return FitCanvas(
          designHeight: stacked ? 190 : 120,
          maxScale: 3,
          builder: (context, size) {
            final pollen = showPollen
                ? _Pollen(readings: air.pollen, theme: t, status: status)
                : null;
            final body = stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: reading,
                      ),
                      if (pollen != null) ...[
                        const SizedBox(height: 14),
                        Expanded(child: pollen),
                      ],
                    ],
                  )
                : Row(
                    children: [
                      Flexible(
                        flex: 4,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: reading,
                        ),
                      ),
                      if (pollen != null) ...[
                        const SizedBox(width: 18),
                        Expanded(flex: 5, child: pollen),
                      ],
                    ],
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TileLabel(
                  icon: Icons.eco_rounded,
                  text: showPollen ? 'Air & pollen' : 'Air quality',
                  theme: t,
                  size: 11,
                ),
                const SizedBox(height: 8),
                Expanded(child: body),
              ],
            );
          },
        );
      },
    );
  }
}

class _Pollen extends StatelessWidget {
  const _Pollen({
    required this.readings,
    required this.theme,
    required this.status,
  });

  final List<PollenReading> readings;
  final DashboardTheme theme;
  final StatusColours status;

  Color _colour(Level l) => switch (l) {
    Level.none || Level.low => status.good,
    Level.moderate => status.warn,
    _ => status.bad,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final r in readings)
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.textPrimary, fontSize: 13),
                ),
              ),
              // The level and its meter give way together on a narrow tile.
              Flexible(
                flex: 4,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        r.level.word,
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 6),
                      for (var i = 1; i <= 4; i++)
                        Container(
                          width: 10,
                          height: 5,
                          margin: const EdgeInsets.only(left: 2),
                          decoration: BoxDecoration(
                            color: i <= r.level.bars
                                ? _colour(r.level)
                                : theme.textSecondary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

final airQualityWidgetType = DashboardWidgetType(
  type: 'air_quality',
  name: 'Air & pollen',
  description:
      'Air quality, today’s pollen for grass, trees and weeds, and '
      'UV, for the place set in Settings → Weather. From Open-Meteo, like the '
      'weather.',
  glyph: '🌿',
  defaultWidth: 3,
  defaultHeight: 2,
  minWidth: 1,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'showPollen',
      label: 'Show pollen',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'Off for just the air quality and UV.',
    ),
  ],
  preview: const [
    PreviewLine('18', scale: 0.3, accent: true),
    PreviewLine('Good air · UV 3', scale: 0.1, muted: true),
    PreviewLine('Grass low · Trees none', scale: 0.1),
  ],
  build: (context, w) => AirQualityWidget(w: w),
);

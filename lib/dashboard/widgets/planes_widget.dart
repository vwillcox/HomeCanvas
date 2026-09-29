import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/planes_service.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/shown_timers.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// "N", "NE", "E"… — which way to look, to the nearest eighth.
String _compass(double degrees) {
  final points = [
    tr('widget.planes.n', 'N'),
    tr('widget.planes.ne', 'NE'),
    tr('widget.planes.e', 'E'),
    tr('widget.planes.se', 'SE'),
    tr('widget.planes.s', 'S'),
    tr('widget.planes.sw', 'SW'),
    tr('widget.planes.w', 'W'),
    tr('widget.planes.nw', 'NW'),
  ];
  return points[((degrees % 360) / 45).round() % 8];
}

/// "12,300" in the panel's language's style.
String _thousands(int n) {
  try {
    return NumberFormat.decimalPattern(
      L10n.instance.language.intlCode,
    ).format(n);
  } catch (_) {
    return NumberFormat.decimalPattern('en_GB').format(n);
  }
}

/// The aircraft in the sky around home — who they are, where they're
/// flying from and to, and which way to look — from the open ADS-B network.
class PlanesWidget extends StatefulWidget {
  const PlanesWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  @override
  State<PlanesWidget> createState() => _PlanesWidgetState();
}

class _PlanesWidgetState extends State<PlanesWidget>
    with PauseWhenHidden, ShownTimers {
  Timer? _timer;

  int get _radius =>
      int.tryParse(widget.w.option<String>('radius', '10')) ?? 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = everyWhileShown(const Duration(seconds: 20), _refresh);
  }

  @override
  void didUpdateWidget(covariant PlanesWidget old) {
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
    unawaited(context.read<PlanesService>().ensure(_radius));
  }

  List<Plane> _shown(List<Plane> all) {
    final ground = widget.w.option('showGround', false);
    return [
      for (final p in all)
        if (ground || !p.onGround) p,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final service = context.watch<PlanesService>();
    if (service.home() == null) {
      return TileMessage(
        tr('widget.planes.needsPlace', 'Set a place in Settings → Weather.'),
        theme: t,
      );
    }
    final all = service.planes(_radius);
    if (all == null) {
      return TileMessage(
        service.error ?? tr('widget.planes.looking', 'Looking up…'),
        theme: t,
      );
    }
    final list = _shown(all);
    final max = widget.w.option('rows', 5).clamp(1, 12);
    final km = widget.w.option<String>('units', 'mi') == 'km';
    final status = StatusColours.of(t);

    return LayoutBuilder(
      builder: (context, c) {
        final fit = ((c.maxHeight - 30) / 52).floor().clamp(1, max);
        final rows = list.take(fit).toList();
        // Only the routes of the planes on show are looked up.
        unawaited(service.ensureRoutes(rows.map((p) => p.callsign)));
        return FitCanvas(
          designHeight: 26.0 + 44 * (rows.isEmpty ? 1 : rows.length),
          maxScale: (c.maxWidth / 320).clamp(1.0, 3.0),
          builder: (context, size) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TileLabel(
                icon: Icons.flight_outlined,
                text: tr(
                  'widget.planes.heading',
                  '{n, plural, =0{No planes} one{# plane} other{# planes}} within {distance}',
                  {
                    'n': list.length,
                    'distance': km
                        ? '${(_radius * 1.609).round()} km'
                        : '$_radius mi',
                  },
                ),
                theme: t,
                size: 11,
                trailing: service.error == null
                    ? null
                    : Icon(
                        Icons.cloud_off_outlined,
                        size: 13,
                        color: status.warn,
                      ),
              ),
              const SizedBox(height: 4),
              if (rows.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      tr(
                        'widget.planes.clear',
                        'Clear skies — nothing overhead just now',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.textSecondary, fontSize: 13),
                    ),
                  ),
                )
              else
                for (final p in rows)
                  Expanded(
                    child: _PlaneRow(
                      p: p,
                      route: service.route(p.callsign),
                      km: km,
                      theme: t,
                      status: status,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _PlaneRow extends StatelessWidget {
  const _PlaneRow({
    required this.p,
    required this.route,
    required this.km,
    required this.theme,
    required this.status,
  });

  final Plane p;
  final FlightRoute? route;
  final bool km;
  final DashboardTheme theme;
  final StatusColours status;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final r = route;
    final distance = km ? p.miles * 1.609 : p.miles;
    final unit = km ? 'km' : 'mi';
    final away =
        '${distance < 10 ? distance.toStringAsFixed(1) : distance.round()} $unit';
    final name = p.callsign.isNotEmpty
        ? p.callsign
        : (p.registration.isNotEmpty ? p.registration : p.hex.toUpperCase());
    final where = r == null
        ? [
            if (p.type.isNotEmpty) p.type,
            if (p.registration.isNotEmpty && p.callsign.isNotEmpty)
              p.registration,
          ].join(' · ')
        : '${r.from} → ${r.to}';
    final climb = p.climbFpm ?? 0;
    final colour = p.emergency ? status.bad : t.accent;
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 240;
        return Row(
          children: [
            // The plane, pointing the way it's flying.
            Transform.rotate(
              angle: (p.track ?? 0) * math.pi / 180,
              child: Icon(Icons.flight, size: 22, color: colour),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      name,
                      if (!narrow && r != null && r.airline.isNotEmpty)
                        r.airline,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.emergency ? status.bad : t.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (where.isNotEmpty)
                    Text(
                      where,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textSecondary, fontSize: 11),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!p.onGround && climb.abs() >= 300)
                        Icon(
                          climb > 0 ? Icons.north_east : Icons.south_east,
                          size: 12,
                          color: t.textSecondary,
                        ),
                      Text(
                        p.onGround
                            ? tr('widget.planes.ground', 'On the ground')
                            : '${_thousands(p.altitudeFt!)} ft',
                        maxLines: 1,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  // Which way to look, and how far.
                  Text(
                    '${_compass(p.bearing)} · $away',
                    maxLines: 1,
                    style: TextStyle(color: t.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

final planesWidgetType = DashboardWidgetType(
  type: 'planes',
  category: WidgetCategory.gettingOut,
  name: 'Planes overhead',
  description:
      'The aircraft in the sky around home: who they are, where they’re '
      'flying from and to, how high, and which way to look. From adsb.lol, '
      'the open network of volunteer ADS-B receivers, and adsbdb — no key '
      'needed.',
  glyph: '✈️',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  options: const [
    WidgetOption(
      key: 'radius',
      label: 'Within',
      kind: OptionKind.choice,
      defaultValue: '10',
      choices: {
        '5': '5 miles',
        '10': '10 miles',
        '20': '20 miles',
        '40': '40 miles',
      },
      help: 'Of the place in Settings → Weather.',
    ),
    WidgetOption(
      key: 'units',
      label: 'Distances in',
      kind: OptionKind.choice,
      defaultValue: 'mi',
      choices: {'mi': 'Miles', 'km': 'Kilometres'},
    ),
    WidgetOption(
      key: 'showGround',
      label: 'Show planes on the ground',
      kind: OptionKind.boolean,
      defaultValue: false,
      help: 'Near an airport, the ones taxiing and parked.',
    ),
    WidgetOption(
      key: 'rows',
      label: 'Planes to show',
      kind: OptionKind.number,
      defaultValue: 5,
    ),
  ],
  preview: const [
    PreviewLine('BAW743  Heraklion → London   4,200 ft', scale: .11, px: 14),
    PreviewLine('EZY82   Geneva → Gatwick    12,300 ft', scale: .11, px: 14),
  ],
  build: (context, w) => PlanesWidget(w: w),
);

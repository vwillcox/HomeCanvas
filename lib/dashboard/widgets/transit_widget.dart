import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/transitous_service.dart';
import '../../time_format.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/shown_timers.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// A colour for each kind of transport, for lines whose timetable gives
/// none of their own.
Color _modeColour(String mode) => Color(switch (mode) {
  'HIGHSPEED_RAIL' => 0xFFD7263D,
  'LONG_DISTANCE' || 'NIGHT_RAIL' => 0xFF2E5A88,
  'REGIONAL_RAIL' || 'REGIONAL_FAST_RAIL' => 0xFF3F7CAC,
  'SUBURBAN' => 0xFF1B998B,
  'SUBWAY' => 0xFF5B4B8A,
  'TRAM' => 0xFFE08E0B,
  'BUS' || 'COACH' => 0xFF6A994E,
  'FERRY' => 0xFF0096C7,
  _ => 0xFF6C757D,
});

Color? _hex(String? h) =>
    h == null ? null : Color(0xFF000000 | int.parse(h, radix: 16));

Color _inkOn(Color c) =>
    c.computeLuminance() > 0.45 ? const Color(0xFF111111) : Colors.white;

/// Departures from any stop Transitous knows — most of Europe's trains,
/// trams and buses and more besides — live where the operator shares it.
class TransitWidget extends StatefulWidget {
  const TransitWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  @override
  State<TransitWidget> createState() => _TransitWidgetState();
}

class _TransitWidgetState extends State<TransitWidget>
    with PauseWhenHidden, ShownTimers {
  Timer? _timer;

  String get _stop => widget.w.option('stop', '').trim();
  // Typed: indexing a map would otherwise make the setting `Object?`, and
  // an unset one null rather than the default.
  String get _modes =>
      kTransitModes[widget.w.option<String>('show', 'trains')] ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    // The service asks at most once a minute; this also moves "now" along.
    _timer = everyWhileShown(const Duration(seconds: 30), _refresh);
  }

  @override
  void didUpdateWidget(covariant TransitWidget old) {
    super.didUpdateWidget(old);
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted || _stop.isEmpty) return;
    unawaited(context.read<TransitousService>().ensure(_stop, _modes));
    setState(() {});
  }

  Set<String> _list(String key) => {
    for (final v in widget.w.option(key, '').split(','))
      if (v.trim().isNotEmpty) v.trim().toLowerCase(),
  };

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    if (_stop.isEmpty) {
      return TileMessage(
        tr(
          'widget.transit.setStop',
          'Set a station or stop in the widget settings — Amsterdam Centraal, Zürich HB, Berlin Hbf.',
        ),
        theme: t,
      );
    }
    final service = context.watch<TransitousService>();
    final stop = service.stop(_stop);
    if (stop == null) {
      return TileMessage(
        service.stopUnknown(_stop)
            ? tr('widget.transit.noSuchStop', 'No stop called “{stop}”', {
                'stop': _stop,
              })
            : service.stopError(_stop) ??
                  tr('widget.transit.finding', 'Finding {stop}…', {
                    'stop': _stop,
                  }),
        theme: t,
      );
    }
    final all = service.departures(stop.id, _modes);
    if (all == null) {
      return TileMessage(
        service.departuresError(stop.id, _modes) ??
            tr('widget.transit.asking', 'Asking for departures…'),
        theme: t,
      );
    }
    final now = DateTime.now();
    final walk = widget.w.option('walkMinutes', 0);
    final lines = _list('lines');
    final towards = _list('towards');
    final list = [
      for (final d in all)
        // Gone, or leaving before you could get there — unless cancelled,
        // which is worth seeing until its time.
        if ((d.expected.isAfter(now.add(Duration(minutes: walk))) ||
                (d.cancelled && d.scheduled.isAfter(now))) &&
            (lines.isEmpty || lines.contains(d.line.toLowerCase())) &&
            (towards.isEmpty ||
                towards.any((w) => d.headsign.toLowerCase().contains(w))))
          d,
    ];
    final max = widget.w.option('rows', 5).clamp(1, 12);
    final name = widget.w.option('name', '').trim();
    final status = StatusColours.of(t);
    final error = service.departuresError(stop.id, _modes);

    return LayoutBuilder(
      builder: (context, c) {
        final fit = ((c.maxHeight - 30) / 52).floor().clamp(1, max);
        final rows = list.take(fit).toList();
        return FitCanvas(
          designHeight: 26.0 + 44 * (rows.isEmpty ? 1 : rows.length),
          maxScale: (c.maxWidth / 320).clamp(1.0, 3.0),
          builder: (context, size) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TileLabel(
                icon: _modes == kTransitModes['trains']
                    ? Icons.train_outlined
                    : Icons.departure_board_outlined,
                text: name.isNotEmpty ? name : stop.name,
                theme: t,
                size: 11,
                trailing: error == null
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
                        'widget.transit.nothing',
                        'No departures in the next hour or so',
                      ),
                      style: TextStyle(color: t.textSecondary, fontSize: 13),
                    ),
                  ),
                )
              else
                for (final d in rows)
                  Expanded(
                    child: _DepartureRow(d: d, theme: t, status: status),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _DepartureRow extends StatelessWidget {
  const _DepartureRow({
    required this.d,
    required this.theme,
    required this.status,
  });

  final TransitDeparture d;
  final DashboardTheme theme;
  final StatusColours status;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final chip = _hex(d.colour) ?? _modeColour(d.mode);
    final ink = _hex(d.textColour) ?? _inkOn(chip);
    final late = d.lateMinutes;
    final (String text, Color colour) = d.cancelled
        ? (tr('widget.trains.cancelled', 'Cancelled'), status.bad)
        : late >= 2
        ? ('+$late ${tr('widget.transit.minShort', 'min')}', status.warn)
        : (
            d.realTime
                ? tr('widget.trains.onTime', 'On time')
                : tr('widget.transit.timetabled', 'Timetabled'),
            d.realTime ? status.good : t.textSecondary,
          );
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 240;
        // The smallest tile: when, and whether it's running.
        if (c.maxWidth < 170) {
          return Row(
            children: [
              Text(
                hhmm(d.scheduled),
                style: TextStyle(
                  color: d.cancelled ? t.textSecondary : t.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  decoration: d.cancelled ? TextDecoration.lineThrough : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  d.cancelled || late >= 2 ? text : d.line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: d.cancelled || late >= 2 ? colour : t.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Text(
              hhmm(d.scheduled),
              style: TextStyle(
                color: d.cancelled ? t.textSecondary : t.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                decoration: d.cancelled ? TextDecoration.lineThrough : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        // Shrinks, with an ellipsis, when the room runs short.
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: chip,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            d.line.isEmpty ? '—' : d.line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (!narrow) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 2,
                          child: Text(
                            d.headsign,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    [
                      if (narrow) d.headsign,
                      if (d.track.isNotEmpty)
                        tr('widget.transit.platform', 'Platform {track}', {
                          'track': d.track,
                        }),
                      if (!d.cancelled && late >= 2)
                        tr('widget.trains.expected', 'expected {time}', {
                          'time': hhmm(d.expected),
                        }),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textSecondary, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Live times, not just the timetable's.
                  if (d.realTime && !d.cancelled)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.sensors, size: 12, color: colour),
                    ),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colour,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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

final transitWidgetType = DashboardWidgetType(
  type: 'transit',
  category: WidgetCategory.gettingOut,
  name: 'Departures (Europe)',
  description:
      'The next trains, trams or buses from any station or stop across most '
      'of Europe — the Netherlands, Germany, Switzerland, France, Ireland, the '
      'Nordics and more — live where the operator shares it. From Transitous, '
      'the open journey planner — no key needed.',
  glyph: '🚆',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  options: const [
    WidgetOption(
      key: 'stop',
      label: 'Station or stop',
      defaultValue: '',
      help:
          'Its name as the operator writes it: Amsterdam Centraal, Zürich '
          'HB, Berlin Hbf, Dublin Connolly.',
    ),
    WidgetOption(
      key: 'show',
      label: 'Show',
      kind: OptionKind.choice,
      defaultValue: 'trains',
      choices: {
        'trains': 'Trains',
        'local': 'Metro, trams, buses and ferries',
        'all': 'Everything',
      },
    ),
    WidgetOption(
      key: 'name',
      label: 'Title',
      defaultValue: '',
      help: 'Optional — the stop’s own name is used otherwise.',
    ),
    WidgetOption(
      key: 'lines',
      label: 'Only these lines',
      defaultValue: '',
      help:
          'Optional, separated by commas, as the board writes them: '
          'Intercity, S3, 17.',
    ),
    WidgetOption(
      key: 'towards',
      label: 'Only towards',
      defaultValue: '',
      help:
          'Optional, separated by commas: part of the destination, such as '
          'Rotterdam, Utrecht.',
    ),
    WidgetOption(
      key: 'walkMinutes',
      label: 'Minutes to walk there',
      kind: OptionKind.number,
      defaultValue: 0,
      help:
          'Departures sooner than this are left off — you couldn’t make them.',
    ),
    WidgetOption(
      key: 'rows',
      label: 'Departures to show',
      kind: OptionKind.number,
      defaultValue: 5,
    ),
  ],
  preview: const [
    PreviewLine('09:28  Intercity  Alkmaar     On time', scale: .11, px: 14),
    PreviewLine('09:34  ICE 123    Frankfurt   +4 min', scale: .11, px: 14),
  ],
  build: (context, w) => TransitWidget(w: w),
);

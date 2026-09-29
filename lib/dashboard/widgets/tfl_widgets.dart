import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/tfl_service.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/shown_timers.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// Black text on the light line colours (Circle, Hammersmith & City,
/// Waterloo & City, Lioness), white on the rest.
Color _inkOn(Color c) =>
    c.computeLuminance() > 0.45 ? const Color(0xFF111111) : Colors.white;

// ------------------------------------------------------------------ lines

/// Which modes a London lines tile covers, from its settings.
List<String> _modes(DashboardWidgetContext w) => [
  if (w.option('tube', true)) 'tube',
  if (w.option('elizabeth', true)) 'elizabeth-line',
  if (w.option('overground', true)) 'overground',
  if (w.option('dlr', true)) 'dlr',
  if (w.option('tram', false)) 'tram',
];

/// Every line's status, each in TfL's colour — or, set to, only the ones
/// with trouble. Tap one to read why.
class TflLinesWidget extends StatefulWidget {
  const TflLinesWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  @override
  State<TflLinesWidget> createState() => _TflLinesWidgetState();
}

class _TflLinesWidgetState extends State<TflLinesWidget>
    with PauseWhenHidden, ShownTimers {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    // The service only asks TfL when its copy is two minutes old.
    _timer = everyWhileShown(const Duration(minutes: 1), _refresh);
  }

  @override
  void didUpdateWidget(covariant TflLinesWidget old) {
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
    unawaited(context.read<TflService>().ensureStatus(_modes(widget.w)));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final modes = _modes(widget.w);
    if (modes.isEmpty) {
      return TileMessage(
        tr('widget.tfl.pickModes', 'Pick which lines to show in the widget settings.'),
        theme: t,
      );
    }
    final service = context.watch<TflService>();
    final lines = service.status(modes);
    if (lines == null) {
      return TileMessage(
        service.statusError(modes) ??
            tr('widget.tfl.askingTfl', 'Asking TfL…'),
        theme: t,
      );
    }
    final status = StatusColours.of(t);
    final onlyTrouble = widget.w.option('onlyProblems', false);
    final shown = onlyTrouble ? lines.where((l) => !l.good).toList() : lines;
    final trouble = lines.where((l) => !l.good).length;

    final header = TileLabel(
      icon: Icons.subway_outlined,
      text: tr('widget.tfl.londonLines', 'London lines'),
      theme: t,
      size: 12,
      trailing: StatusChip(
        text: trouble == 0
            ? tr('widget.tfl.allGood', 'Good service')
            : tr(
                'widget.tfl.troubleCount',
                '{n, plural, one{# line with problems} other{# lines with problems}}',
                {'n': trouble},
              ),
        colour: trouble == 0
            ? status.good
            : lines.any((l) => l.serious)
            ? status.bad
            : status.warn,
        size: 11,
      ),
    );

    if (shown.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline, color: status.good, size: 30),
                    const SizedBox(width: 10),
                    Text(
                      tr('widget.tfl.goodServiceEverywhere',
                          'Good service on every line'),
                      style: TextStyle(color: t.textPrimary, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 6),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, i) => _LineRow(
              line: shown[i],
              theme: t,
              status: status,
            ),
          ),
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.theme,
    required this.status,
  });

  final TflLine line;
  final DashboardTheme theme;
  final StatusColours status;

  @override
  Widget build(BuildContext context) {
    final colour = line.good
        ? theme.textSecondary
        : line.serious
        ? status.bad
        : status.warn;
    final row = SizedBox(
      height: 34,
      child: Row(
        children: [
          // The line's own colour, as on the map.
          Container(
            width: 8,
            decoration: BoxDecoration(
              color: line.colour,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: theme.textSecondary.withValues(alpha: .25)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              line.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              // TfL's own wording, which is English; the good-service case
              // is the one worth saying in the panel's language.
              line.good ? tr('widget.tfl.goodService', 'Good service') : line.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: colour,
                fontSize: 13,
                fontWeight: line.good ? FontWeight.w400 : FontWeight.w700,
              ),
            ),
          ),
          if (line.reason.isNotEmpty) ...[
            const SizedBox(width: 4),
            Icon(Icons.info_outline, size: 14, color: colour),
          ],
        ],
      ),
    );
    if (line.reason.isEmpty) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            '${line.name} · ${line.status}',
            style: const TextStyle(fontSize: 22),
          ),
          content: SizedBox(
            width: 640,
            child: Text(line.reason, style: const TextStyle(fontSize: 18, height: 1.4)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                tr('common.close', 'Close'),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
      child: row,
    );
  }
}

final tflLinesWidgetType = DashboardWidgetType(
  type: 'tfl_lines',
  category: WidgetCategory.gettingOut,
  name: 'London lines',
  description:
      'Whether the Tube, Elizabeth line, Overground, DLR and trams are '
      'running, each line in its own colour. Tap a line with trouble to read '
      'why. From TfL — no key needed.',
  glyph: '🚇',
  defaultWidth: 3,
  defaultHeight: 4,
  minWidth: 2,
  minHeight: 2,
  options: const [
    WidgetOption(
      key: 'onlyProblems',
      label: 'Only show lines with problems',
      kind: OptionKind.boolean,
      defaultValue: false,
      help: 'With everything running, the tile just says so.',
    ),
    WidgetOption(key: 'tube', label: 'Tube', kind: OptionKind.boolean, defaultValue: true),
    WidgetOption(
      key: 'elizabeth',
      label: 'Elizabeth line',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'overground',
      label: 'Overground',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(key: 'dlr', label: 'DLR', kind: OptionKind.boolean, defaultValue: true),
    WidgetOption(key: 'tram', label: 'Trams', kind: OptionKind.boolean, defaultValue: false),
  ],
  preview: const [
    PreviewLine('Bakerloo          Good service', scale: .09, px: 14),
    PreviewLine('Central           Severe delays', scale: .09, px: 14),
    PreviewLine('Victoria          Good service', scale: .09, px: 14),
  ],
  build: (context, w) => TflLinesWidget(w: w),
);

// --------------------------------------------------------------- arrivals

/// The next trains or buses at one stop, soonest first.
class TflArrivalsWidget extends StatefulWidget {
  const TflArrivalsWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  @override
  State<TflArrivalsWidget> createState() => _TflArrivalsWidgetState();
}

class _TflArrivalsWidgetState extends State<TflArrivalsWidget>
    with PauseWhenHidden, ShownTimers {
  Timer? _timer;

  String get _stop => widget.w.option('stop', '').trim();
  String get _mode => widget.w.option('mode', 'any');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    // Arrivals change by the minute; the service asks at most every 30s.
    _timer = everyWhileShown(const Duration(seconds: 30), _refresh);
  }

  @override
  void didUpdateWidget(covariant TflArrivalsWidget old) {
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
    unawaited(context.read<TflService>().ensureArrivals(_stop, _mode));
    // The minutes count down between fetches too.
    setState(() {});
  }

  /// The lines asked for — "Victoria, 73" — or none to show every line.
  Set<String> get _lines => {
    for (final l in widget.w.option('lines', '').split(','))
      if (l.trim().isNotEmpty) l.trim().toLowerCase(),
  };

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    if (_stop.isEmpty) {
      return TileMessage(
        tr(
          'widget.tfl.setStop',
          'Set a stop in the widget settings — a station’s name, or the five-digit code on a bus stop’s sign.',
        ),
        theme: t,
      );
    }
    final service = context.watch<TflService>();
    final stop = service.stop(_stop, _mode);
    if (stop == null) {
      return TileMessage(
        service.stopError(_stop, _mode) ??
            tr('widget.tfl.findingStop', 'Finding {stop}…', {'stop': _stop}),
        theme: t,
      );
    }
    final all = service.arrivals(stop.id);
    if (all == null) {
      return TileMessage(
        service.arrivalsError(stop.id) ??
            tr('widget.tfl.askingTfl', 'Asking TfL…'),
        theme: t,
      );
    }
    final lines = _lines;
    final platform = widget.w.option('platform', '').trim().toLowerCase();
    final list = [
      for (final a in all)
        if ((lines.isEmpty ||
                lines.contains(a.line.toLowerCase()) ||
                lines.contains(a.lineId.toLowerCase())) &&
            (platform.isEmpty ||
                a.platform.toLowerCase().contains(platform) ||
                a.destination.toLowerCase().contains(platform)))
          a,
    ];
    final max = (widget.w.option('rows', 4)).clamp(1, 10);
    final name = widget.w.option('name', '').trim();
    final status = StatusColours.of(t);
    final error = service.arrivalsError(stop.id);

    return LayoutBuilder(
      builder: (context, c) {
        final fit = ((c.maxHeight - 30) / 52).floor().clamp(1, max);
        final rows = list.take(fit).toList();
        return FitCanvas(
          designHeight: 26.0 + 44 * (rows.isEmpty ? 1 : rows.length),
          // Grown to fill the height, but never so far that a row has
          // less than 280 across to fit its line, destination and time.
          maxScale: (c.maxWidth / 280).clamp(1.0, 3.0),
          builder: (context, size) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TileLabel(
                icon: _mode == 'bus'
                    ? Icons.directions_bus_outlined
                    : Icons.subway_outlined,
                text: name.isNotEmpty ? name : stop.name,
                theme: t,
                size: 11,
                // Older times on show: the last fetch failed.
                trailing: error == null
                    ? null
                    : Icon(Icons.cloud_off_outlined, size: 13, color: status.warn),
              ),
              const SizedBox(height: 4),
              if (rows.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      tr('widget.tfl.nothingDue', 'Nothing due in the next half hour'),
                      style: TextStyle(color: t.textSecondary, fontSize: 13),
                    ),
                  ),
                )
              else
                for (final a in rows)
                  Expanded(child: _ArrivalRow(a: a, theme: t, status: status)),
            ],
          ),
        );
      },
    );
  }
}

class _ArrivalRow extends StatelessWidget {
  const _ArrivalRow({
    required this.a,
    required this.theme,
    required this.status,
  });

  final TflArrival a;
  final DashboardTheme theme;
  final StatusColours status;

  @override
  Widget build(BuildContext context) {
    final colour = tflColour(a.lineId, a.mode);
    final minutes = (a.seconds / 60).floor();
    final bus = a.mode == 'bus';
    // A bus's platform is its stop letter; a train's says which way.
    final where = bus
        ? ''
        : a.platform
            .replaceFirst(RegExp(r'\s*-\s*Platform\s*', caseSensitive: false), ' · ')
            .trim();
    return LayoutBuilder(
      builder: (context, c) {
    // On the narrowest tile, the line and the minutes: what matters most.
    final narrow = c.maxWidth < 200;
    return Row(
      children: [
        // The line in its colour: a bus by its number, a train by its name.
        Flexible(
          flex: narrow ? 1 : 0,
          child: Container(
          constraints: BoxConstraints(minWidth: narrow ? 0 : 44),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(bus ? 4 : 10),
          ),
          child: Text(
            a.line,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _inkOn(colour),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          ),
        ),
        if (narrow) const Spacer() else ...[
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.destination,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.textPrimary, fontSize: 14),
              ),
              if (where.isNotEmpty)
                Text(
                  where,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.textSecondary, fontSize: 10),
                ),
            ],
          ),
        ),
        ],
        const SizedBox(width: 8),
        Text(
          minutes < 1
              ? tr('widget.tfl.due', 'Due')
              : tr('common.min', '{n} min', {'n': minutes}),
          style: TextStyle(
            color: minutes < 1 ? status.good : theme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
      },
    );
  }
}

final tflArrivalsWidgetType = DashboardWidgetType(
  type: 'tfl_arrivals',
  category: WidgetCategory.gettingOut,
  name: 'London arrivals',
  description:
      'The next Tube, Elizabeth line, Overground, DLR, tram or bus at your '
      'stop, counting down in minutes. From TfL — no key needed.',
  glyph: '🚌',
  defaultWidth: 3,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  options: const [
    WidgetOption(
      key: 'stop',
      label: 'Stop',
      defaultValue: '',
      help:
          'A station’s name (Oxford Circus), the five-digit code on a bus '
          'stop’s sign, or a TfL stop id like 940GZZLUOXC.',
    ),
    WidgetOption(
      key: 'mode',
      label: 'Look for',
      kind: OptionKind.choice,
      defaultValue: 'any',
      choices: {
        'any': 'Any station or stop',
        'rail': 'A station: Tube, Elizabeth line, Overground, DLR, tram',
        'bus': 'A bus stop',
      },
      help: 'Helps a name find the right one — a station and the bus stops '
          'outside it share a name.',
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
      help: 'Optional, separated by commas: Victoria, Central — or bus '
          'numbers, 73, N73. Leave empty for every line.',
    ),
    WidgetOption(
      key: 'platform',
      label: 'Only this way',
      defaultValue: '',
      help: 'Optional: a direction or platform (Northbound, Platform 2), or a '
          'destination (Brixton).',
    ),
    WidgetOption(
      key: 'rows',
      label: 'Arrivals to show',
      kind: OptionKind.number,
      defaultValue: 4,
    ),
  ],
  preview: const [
    PreviewLine('Victoria   Brixton        2 min', scale: .12, px: 15),
    PreviewLine('Central    Ealing Broadway  5 min', scale: .12, px: 15),
  ],
  build: (context, w) => TflArrivalsWidget(w: w),
);

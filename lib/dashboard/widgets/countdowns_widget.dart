import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/bin_schedule.dart' show Bin, dateOnly, daysBetween;
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// Something being counted down to.
@immutable
class Countdown {
  const Countdown(this.name, this.day, {this.yearly = false});

  final String name;
  final DateTime day;

  /// A birthday or Christmas: next year's once this year's has gone.
  final bool yearly;

  /// From a settings row. "25/12" repeats every year; "2026-10-31" or
  /// "31/10/2026" happens once.
  static Countdown? fromRow(Map<String, dynamic> row, DateTime today) {
    final name = '${row['name'] ?? ''}'.trim();
    final raw = '${row['date'] ?? ''}'.trim();
    if (name.isEmpty || raw.isEmpty) return null;
    final full = Bin.parseDay(raw);
    if (full != null) return Countdown(name, full);
    final m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})$').firstMatch(raw);
    if (m == null) return null;
    final day = int.parse(m[1]!), month = int.parse(m[2]!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    var next = _on(today.year, month, day);
    if (next.isBefore(dateOnly(today))) next = _on(today.year + 1, month, day);
    return Countdown(name, next, yearly: true);
  }

  /// 29 February in a year without one falls on the 28th, as birthdays do.
  static DateTime _on(int year, int month, int day) {
    final d = DateTime(year, month, day);
    return d.month == month ? d : DateTime(year, month + 1, 0);
  }

  /// The ones still to come, soonest first. Today's stays until tomorrow.
  static List<Countdown> upcoming(List<Object?> rows, DateTime now) {
    final today = dateOnly(now);
    return [
        for (final r in rows)
          if (r is Map) ?Countdown.fromRow(r.cast<String, dynamic>(), today),
      ].where((c) => !c.day.isBefore(today)).toList()
      ..sort((a, b) => a.day.compareTo(b.day));
  }
}

/// Days until the things being looked forward to.
class CountdownsWidget extends StatefulWidget {
  const CountdownsWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<CountdownsWidget> createState() => _CountdownsWidgetState();
}

class _CountdownsWidgetState extends State<CountdownsWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Days only change at midnight, but a minute is cheap and needs no
    // arithmetic about when midnight is.
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
    final now = DateTime.now();
    final max = (int.tryParse('${widget.w.config.options['show'] ?? 4}') ?? 4)
        .clamp(1, 12);
    final items = Countdown.upcoming(
      widget.w.config.options['events'] as List? ?? const [],
      now,
    ).take(max).toList();
    if (items.isEmpty) {
      return TileMessage(
        'Add dates in the widget settings — 25/12 for every year, or a full '
        'date like 31/10/2026 for once.',
        theme: t,
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        // One big line for a single countdown; a list for several.
        final perRow = (c.maxHeight / items.length);
        return FitCanvas(
          designHeight: 34.0 * items.length + 24,
          maxScale: perRow > 90 ? 4 : 3,
          builder: (context, size) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TileLabel(
                icon: Icons.flag_outlined,
                text: 'Coming up',
                theme: t,
                size: 11,
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _Row(
                    item: items[i],
                    days: daysBetween(now, items[i].day),
                    first: i == 0,
                    w: widget.w,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.days,
    required this.first,
    required this.w,
  });

  final Countdown item;
  final int days;
  final bool first;
  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final (String number, String unit) = switch (days) {
      0 => ('🎉', 'today'),
      1 => ('1', 'day'),
      _ => ('$days', 'days'),
    };
    return Row(
      children: [
        Expanded(
          child: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: first ? t.textPrimary : t.textSecondary,
              fontSize: first ? 15 : 13,
              fontWeight: first ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // The figure shrinks before it runs off a narrow tile.
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: number,
                      style: TextStyle(
                        color: first ? t.accent : t.textPrimary,
                        fontSize: first ? 24 : 18,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(color: t.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
                maxLines: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final countdownsWidgetType = DashboardWidgetType(
  type: 'countdowns',
  category: WidgetCategory.timeAndDay,
  name: 'Countdowns',
  description:
      'Days until the things you are looking forward to — '
      'birthdays, holidays, trips. The soonest first.',
  glyph: '🗓️',
  defaultWidth: 3,
  defaultHeight: 2,
  minWidth: 1,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'events',
      label: 'Dates',
      kind: OptionKind.list,
      addLabel: 'Add a date',
      help:
          'Day and month — 25/12 — for something every year; a full date '
          '— 31/10/2026 — for something once. Past ones drop off.',
      fields: [
        WidgetOption(key: 'name', label: 'What', defaultValue: ''),
        WidgetOption(key: 'date', label: 'When', defaultValue: ''),
      ],
    ),
    WidgetOption(
      key: 'show',
      label: 'How many to show',
      kind: OptionKind.number,
      defaultValue: 4,
    ),
  ],
  preview: const [
    PreviewLine('Sam’s birthday   5 days', scale: 0.14, accent: true),
    PreviewLine('Half term   22 days', scale: 0.12),
    PreviewLine('Christmas   91 days', scale: 0.12),
  ],
  build: (context, w) => CountdownsWidget(w: w),
);

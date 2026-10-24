import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/glowmarkt_service.dart';
import '../../services/home_assistant_service.dart';
import '../../widgets/lcars.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/shown_timers.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'tile_bits.dart';
import '../../time_format.dart';

/// A day of electricity, from a smart meter's running total for the day —
/// Hildebrand Glow's, which is what the Bright app shows.
///
/// The total starts again from nothing each day, but not at midnight: the
/// meter's readings reach it about half an hour late, so the day before's
/// total is still shown until about one in the morning. Today is what came
/// after the total last went down; yesterday is the most it reached before.
@immutable
class EnergyDay {
  const EnergyDay({
    required this.today,
    required this.hours,
    this.yesterday,
    this.costToday,
    this.costYesterday,
  });

  /// kWh so far today.
  final double today;

  /// kWh in each hour of today, 24 of them, by when the reading came in.
  final List<double> hours;

  final double? yesterday;
  final double? costToday;
  final double? costYesterday;

  static EnergyDay from(
    List<(DateTime, double)> usage,
    List<(DateTime, double)> cost,
    DateTime now,
  ) {
    final midnight = DateTime(now.year, now.month, now.day);
    final (today, before, fromNothing) = _split(usage, midnight);
    final (costNow, costBefore, _) = _split(cost, midnight);
    final hours = List<double>.filled(24, 0);
    // Seen to start again from nothing, the first reading is the first of
    // the day's use. Otherwise — Home Assistant only began keeping them
    // part way through — it is everything up to then, in no hour known.
    var last = fromNothing || today.isEmpty ? 0.0 : today.first.$2;
    for (final (at, v) in today) {
      final rise = v - last;
      if (rise > 0 && !at.isBefore(midnight)) {
        hours[math.min(23, at.difference(midnight).inHours)] += rise;
      }
      last = v;
    }
    return EnergyDay(
      today: today.isEmpty ? 0 : today.last.$2,
      hours: hours,
      yesterday: before,
      costToday: costNow.isEmpty ? null : costNow.last.$2,
      costYesterday: costBefore,
    );
  }

  /// [series] split where the day's total last went down: what came after
  /// it, the most it reached before, and whether it was seen to go down —
  /// or, if it has not gone down since [midnight], nothing yet for today
  /// and all of it for the day before.
  static (List<(DateTime, double)>, double?, bool) _split(
    List<(DateTime, double)> series,
    DateTime midnight,
  ) {
    if (series.isEmpty) return (const [], null, false);
    var reset = -1;
    for (var i = 1; i < series.length; i++) {
      if (series[i].$2 < series[i - 1].$2 && !series[i].$1.isBefore(midnight)) {
        reset = i;
      }
    }
    if (reset < 0) {
      // Not gone down today. Before the readings for today arrive, this is
      // still the day before's; once a day is fully under way, today's.
      final late = series.last.$1.isBefore(
        midnight.add(const Duration(hours: 2)),
      );
      if (late) {
        return (const [], series.map((s) => s.$2).reduce(math.max), false);
      }
      final today = [
        for (final s in series)
          if (!s.$1.isBefore(midnight)) s,
      ];
      return (today, null, false);
    }
    final before = series.sublist(0, reset).map((s) => s.$2).reduce(math.max);
    return (series.sublist(reset), before, true);
  }
}

/// Which stretch of time the widget shows.
enum EnergyView { day, week, month, year }

/// A stretch of electricity as the widget draws it: a bar for each part of
/// it, what it all came to, and the stretch before to set it against.
@immutable
class EnergyRange {
  const EnergyRange({
    required this.bars,
    required this.axis,
    required this.total,
    this.now,
    this.cost,
    this.before,
    this.costBefore,
  });

  /// kWh in each part; null where the meter's reading has not arrived.
  final List<double?> bars;

  /// Under the bars: an index, and what to letter there.
  final List<(int, String)> axis;

  /// The part we are in, or null when it is all past.
  final int? now;

  final double total;
  final double? cost;
  final double? before;
  final double? costBefore;

  static double _sum(Iterable<(DateTime, double)> r) =>
      r.fold(0.0, (a, b) => a + b.$2);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// The last seven days, today among them, from days of readings going
  /// back at least fourteen — the seven before are what it is set against.
  static EnergyRange week(
    List<(DateTime, double)> days,
    List<(DateTime, double)>? costs,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final shown = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    double? on(List<(DateTime, double)> r, DateTime d) {
      for (final (at, v) in r) {
        if (_sameDay(at, d)) return v;
      }
      return null;
    }

    final start = shown.first;
    final earlier = start.subtract(const Duration(days: 7));
    bool thisWeek((DateTime, double) r) => !r.$1.isBefore(start);
    bool lastWeek((DateTime, double) r) =>
        !r.$1.isBefore(earlier) && r.$1.isBefore(start);
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return EnergyRange(
      bars: [for (final d in shown) on(days, d)],
      axis: [for (final (i, d) in shown.indexed) (i, letters[d.weekday - 1])],
      now: 6,
      total: _sum(days.where(thisWeek)),
      cost: costs == null ? null : _sum(costs.where(thisWeek)),
      before: days.any(lastWeek) ? _sum(days.where(lastWeek)) : null,
      costBefore: costs == null || !costs.any(lastWeek)
          ? null
          : _sum(costs.where(lastWeek)),
    );
  }

  /// This month, a day at a time, against last month's whole total — from
  /// [lastDays], its days.
  static EnergyRange month(
    List<(DateTime, double)> days,
    List<(DateTime, double)>? costs,
    List<(DateTime, double)> lastDays,
    List<(DateTime, double)>? lastCosts,
    DateTime now,
  ) {
    final length = DateTime(now.year, now.month + 1, 0).day;
    final bars = List<double?>.filled(length, null);
    for (final (at, v) in days) {
      if (at.year == now.year && at.month == now.month) bars[at.day - 1] = v;
    }
    bool here((DateTime, double) r) =>
        r.$1.year == now.year && r.$1.month == now.month;
    final last = DateTime(now.year, now.month - 1);
    bool lastMonth((DateTime, double) r) =>
        r.$1.year == last.year && r.$1.month == last.month;
    return EnergyRange(
      bars: bars,
      axis: [
        for (final d in [1, 8, 15, 22, 29])
          if (d <= length) (d - 1, '$d'),
      ],
      now: now.day - 1,
      total: _sum(days.where(here)),
      cost: costs == null ? null : _sum(costs.where(here)),
      before: lastDays.any(lastMonth) ? _sum(lastDays.where(lastMonth)) : null,
      costBefore: lastCosts == null || !lastCosts.any(lastMonth)
          ? null
          : _sum(lastCosts.where(lastMonth)),
    );
  }

  /// The last twelve months, this one among them, against the twelve
  /// before.
  static EnergyRange year(
    List<(DateTime, double)> months,
    List<(DateTime, double)>? costs,
    List<(DateTime, double)> monthsBefore,
    List<(DateTime, double)>? costsBefore,
    DateTime now,
  ) {
    final shown = [
      for (var i = 11; i >= 0; i--) DateTime(now.year, now.month - i),
    ];
    double? on(DateTime m) {
      for (final (at, v) in months) {
        if (at.year == m.year && at.month == m.month) return v;
      }
      return null;
    }

    const letters = [
      'J',
      'F',
      'M',
      'A',
      'M',
      'J',
      'J',
      'A',
      'S',
      'O',
      'N',
      'D',
    ];
    return EnergyRange(
      bars: [for (final m in shown) on(m)],
      axis: [for (final (i, m) in shown.indexed) (i, letters[m.month - 1])],
      now: 11,
      total: _sum(months),
      cost: costs == null ? null : _sum(costs),
      before: monthsBefore.isEmpty ? null : _sum(monthsBefore),
      costBefore: costsBefore == null || costsBefore.isEmpty
          ? null
          : _sum(costsBefore),
    );
  }

  /// Today: half hours from Glowmarkt where they have come, or failing
  /// those Home Assistant's hours; its total from Home Assistant's meter,
  /// which is ahead of Glowmarkt's half hours, against yesterday's.
  static EnergyRange day(
    EnergyDay? ha,
    List<(DateTime, double)>? halves,
    List<(DateTime, double)>? days,
    List<(DateTime, double)>? dayCosts,
    double? today,
    double? costToday,
    DateTime now,
  ) {
    final midnight = DateTime(now.year, now.month, now.day);
    final yesterday = midnight.subtract(const Duration(days: 1));
    double? on(List<(DateTime, double)>? r, DateTime d) {
      for (final (at, v) in r ?? const <(DateTime, double)>[]) {
        if (_sameDay(at, d)) return v;
      }
      return null;
    }

    final fromGlow = [
      for (final (at, v) in halves ?? const <(DateTime, double)>[])
        if (_sameDay(at, now)) (at, v),
    ];
    final glowSum = _sum(fromGlow);
    final haSum = ha?.hours.fold(0.0, (a, b) => a + b) ?? 0;
    final List<double?> bars;
    final int slot;
    if (fromGlow.isNotEmpty && glowSum >= haSum) {
      bars = List<double?>.filled(48, null);
      for (final (at, v) in fromGlow) {
        bars[at.difference(midnight).inMinutes ~/ 30] = v;
      }
      slot = now.difference(midnight).inMinutes ~/ 30;
    } else {
      bars = [...?ha?.hours] + (ha == null ? List.filled(24, 0.0) : []);
      slot = now.hour;
    }
    final per = bars.length ~/ 24;
    return EnergyRange(
      bars: [for (final (i, b) in bars.indexed) i > slot ? null : b],
      axis: [
        for (final h in [0, 6, 12, 18]) (h * per, two(h)),
      ],
      now: slot,
      total: today ?? ha?.today ?? glowSum,
      cost: costToday ?? ha?.costToday,
      before: ha?.yesterday ?? on(days, yesterday),
      costBefore: ha?.costYesterday ?? on(dayCosts, yesterday),
    );
  }
}

class HaEnergyWidget extends StatefulWidget {
  const HaEnergyWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HaEnergyWidget> createState() => _HaEnergyWidgetState();
}

class _HaEnergyWidgetState extends State<HaEnergyWidget>
    with PauseWhenHidden, ShownTimers {
  late EnergyView _view = EnergyView.values.firstWhere(
    (v) => v.name == widget.w.option('view', 'day'),
    orElse: () => EnergyView.day,
  );
  final Map<EnergyView, EnergyRange> _ranges = {};
  EnergyDay? _haDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    // The meter is read every half hour at best; more often asks for
    // nothing new.
    everyWhileShown(const Duration(minutes: 5), _refresh);
  }

  /// An entity chosen in the settings, or the first whose id ends [like]
  /// it — Hildebrand Glow's names, so nothing need be chosen.
  String? _pick(HomeAssistantService ha, String key, String like) {
    final chosen = widget.w.option(key, '').trim();
    if (chosen.contains('.')) return chosen;
    for (final e in ha.all) {
      if (e.domain == 'sensor' && e.id.endsWith(like)) return e.id;
    }
    return null;
  }

  double? _state(HomeAssistantService ha, String key, String like) {
    final id = _pick(ha, key, like);
    final e = id == null ? null : ha.entity(id);
    return e == null ? null : double.tryParse(e.state);
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final ha = context.read<HomeAssistantService>();
    final glow = context.read<GlowmarktService>();
    final view = _view;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await ha.refresh();
    if (!mounted) return;

    Future<(List<(DateTime, double)>?, List<(DateTime, double)>?)> both(
      GlowPeriod p,
      DateTime from,
      DateTime to,
    ) async => (
      await glow.readings(p, from, to),
      await glow.readings(p, from, to, cost: true),
    );

    EnergyRange? range;
    switch (view) {
      case EnergyView.day:
        final usage = _pick(ha, 'usage', '_usage_today');
        final cost = _pick(ha, 'cost', '_cost_today');
        if (usage != null) {
          final history = await ha.history([
            usage,
            ?cost,
          ], today.subtract(const Duration(days: 1)));
          if (history.isNotEmpty) {
            _haDay = EnergyDay.from(
              history[usage] ?? const [],
              cost == null ? const [] : history[cost] ?? const [],
              now,
            );
          }
        }
        final halves = await glow.readings(GlowPeriod.halfHour, today, now);
        final (days, dayCosts) = await both(
          GlowPeriod.day,
          today.subtract(const Duration(days: 1)),
          now,
        );
        range = EnergyRange.day(
          _haDay,
          halves,
          days,
          dayCosts,
          _state(ha, 'usage', '_usage_today'),
          _state(ha, 'cost', '_cost_today'),
          now,
        );
      case EnergyView.week:
        final (days, costs) = await both(
          GlowPeriod.day,
          today.subtract(const Duration(days: 13)),
          now,
        );
        if (days != null) range = EnergyRange.week(days, costs, now);
      case EnergyView.month:
        final (days, costs) = await both(
          GlowPeriod.day,
          DateTime(now.year, now.month),
          now,
        );
        // Last month by its days: Glowmarkt's monthly totals are slow,
        // and sometimes never come.
        final (lastDays, lastCosts) = await both(
          GlowPeriod.day,
          DateTime(now.year, now.month - 1),
          DateTime(now.year, now.month).subtract(const Duration(seconds: 1)),
        );
        if (days != null) {
          range = EnergyRange.month(
            days,
            costs,
            lastDays ?? const [],
            lastCosts,
            now,
          );
        }
      case EnergyView.year:
        final start = DateTime(now.year, now.month - 11);
        final (months, costs) = await both(GlowPeriod.month, start, now);
        // The twelve months before, as one more question: Glowmarkt
        // answers no more than a year of months at once.
        final (before, costsBefore) = await both(
          GlowPeriod.month,
          DateTime(now.year, now.month - 23),
          start.subtract(const Duration(seconds: 1)),
        );
        if (months != null) {
          range = EnergyRange.year(
            months,
            costs,
            before ?? const [],
            costsBefore,
            now,
          );
        }
    }
    if (!mounted || range == null) return;
    setState(() => _ranges[view] = range!);
  }

  void _show(EnergyView view) {
    if (view == _view) return;
    setState(() => _view = view);
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final ha = context.watch<HomeAssistantService>();
    final glow = context.read<GlowmarktService>();
    if (!ha.configured && !glow.configured) {
      return TileMessage(
        tr(
          'widget.home_assistant.connectHomeAssistantInSettings',
          'Connect Home Assistant in Settings first — its address and a long-lived access token.',
        ),
        theme: t,
      );
    }
    if (_pick(ha, 'usage', '_usage_today') == null && !glow.configured) {
      return TileMessage(
        ha.all.isEmpty
            ? ha.error ??
                  tr(
                    'widget.home_assistant.askingHomeAssistant',
                    'Asking Home Assistant…',
                  )
            : tr(
                'widget.ha_energy.noMeter',
                'No smart meter in Home Assistant yet — add Hildebrand Glow (DCC) with your Bright login, or pick its sensors in the settings.',
              ),
        theme: t,
      );
    }
    final views = [
      EnergyView.day,
      // Longer than a day is Glowmarkt's: Home Assistant only has the
      // meter from the day it was set up.
      if (glow.configured) ...[
        EnergyView.week,
        EnergyView.month,
        EnergyView.year,
      ],
    ];
    final view = views.contains(_view) ? _view : EnergyView.day;
    // Today can be drawn before anything is fetched, from the meter's
    // figures as Home Assistant has them now.
    final range =
        _ranges[view] ??
        (view == EnergyView.day
            ? EnergyRange.day(
                _haDay,
                null,
                null,
                null,
                _state(ha, 'usage', '_usage_today'),
                _state(ha, 'cost', '_cost_today'),
                DateTime.now(),
              )
            : null);
    final rate = _state(ha, 'rate', '_meter_rate');
    final standing = _state(ha, 'standing', '_standing_charge');
    final names = {
      EnergyView.day: (
        tr('widget.ha_energy.today', 'Today'),
        tr('widget.ha_energy.yesterday', 'Yesterday'),
      ),
      EnergyView.week: (
        tr('widget.ha_energy.week', 'This week'),
        tr('widget.ha_energy.weekBefore', 'Week before'),
      ),
      EnergyView.month: (
        tr('widget.ha_energy.month', 'This month'),
        tr('widget.ha_energy.lastMonth', 'Last month'),
      ),
      EnergyView.year: (
        tr('widget.ha_energy.year', 'Twelve months'),
        tr('widget.ha_energy.yearBefore', 'Twelve before'),
      ),
    };
    final tabs = {
      EnergyView.day: tr('widget.ha_energy.tabDay', 'Day'),
      EnergyView.week: tr('widget.ha_energy.tabWeek', 'Week'),
      EnergyView.month: tr('widget.ha_energy.tabMonth', 'Month'),
      EnergyView.year: tr('widget.ha_energy.tabYear', 'Year'),
    };
    return LayoutBuilder(
      builder: (context, c) {
        final big = (math.min(
          c.maxHeight * 0.2,
          c.maxWidth * 0.12,
        )).clamp(18.0, 72.0);
        final small = (big * 0.36).clamp(11.0, 22.0);
        final chart = c.maxHeight > big * 4;
        final showTabs = views.length > 1 && c.maxHeight > big * 2.4;
        final (nowName, beforeName) = names[view]!;
        final figures = [
          if (range != null) ...[
            (nowName, _kwh(range.total)),
            if (range.cost != null)
              (tr('widget.ha_energy.cost', 'Cost'), _pounds(range.cost!)),
            if (range.before != null)
              (
                beforeName,
                _kwh(range.before!) +
                    (range.costBefore == null
                        ? ''
                        : ' · ${_pounds(range.costBefore!)}'),
              ),
          ] else
            (nowName, '—'),
        ];
        final tariff = [
          if (rate != null)
            tr('widget.ha_energy.rate', '{pence}p a kWh', {
              'pence': (rate * 100).toStringAsFixed(1),
            }),
          if (standing != null)
            tr('widget.ha_energy.standing', '{pence}p a day', {
              'pence': (standing * 100).toStringAsFixed(1),
            }),
        ].join(' · ');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTabs) ...[
              _Tabs(
                theme: t,
                labels: [for (final v in views) tabs[v]!],
                chosen: views.indexOf(view),
                height: (small * 2).clamp(26.0, 44.0),
                onTap: (i) => _show(views[i]),
              ),
              SizedBox(height: small * 0.6),
            ],
            if (t.isLcars)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final (i, (name, value)) in figures.indexed)
                    LcarsReadout(
                      colour: t.block(i),
                      name: name,
                      value: value,
                      width: math.min(
                        c.maxWidth,
                        math.max(c.maxWidth / figures.length - 8, 200),
                      ),
                      height: (big * 0.6).clamp(26.0, 44.0),
                    ),
                ],
              )
            else
              Wrap(
                spacing: big * 0.6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  for (final (i, (name, value)) in figures.indexed)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: t.textSecondary,
                            fontSize: small,
                          ),
                        ),
                        Text(
                          value,
                          style: TextStyle(
                            color: i == 0 ? t.accent : t.textPrimary,
                            fontSize: i == 0 ? big : big * 0.6,
                            fontWeight: FontWeight.w700,
                            height: 1.05,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            if (chart && range != null) ...[
              SizedBox(height: big * 0.3),
              Expanded(
                child: CustomPaint(
                  painter: _BarsPainter(
                    bars: range.bars,
                    now: range.now,
                    theme: t,
                  ),
                ),
              ),
              SizedBox(height: small * 0.3),
              SizedBox(
                height: small * 1.3,
                child: CustomPaint(
                  painter: _AxisPainter(
                    count: range.bars.length,
                    labels: range.axis,
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: small * 0.85,
                      fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                    ),
                  ),
                ),
              ),
            ] else
              const Spacer(),
            if (tariff.isNotEmpty || chart) ...[
              SizedBox(height: small * 0.4),
              Text(
                [
                  if (tariff.isNotEmpty) tariff,
                  tr('widget.ha_energy.behind', 'about half an hour behind'),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textSecondary, fontSize: small),
              ),
            ],
          ],
        );
      },
    );
  }

  static String _kwh(double v) => '${v.toStringAsFixed(v >= 100 ? 0 : 1)} kWh';
  static String _pounds(double v) =>
      v >= 1000 ? '£${v.round()}' : '£${v.toStringAsFixed(2)}';
}

/// Day, week, month, year: blocks on a console, words elsewhere.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.theme,
    required this.labels,
    required this.chosen,
    required this.height,
    required this.onTap,
  });

  final DashboardTheme theme;
  final List<String> labels;
  final int chosen;
  final double height;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, label) in labels.indexed) ...[
          if (i > 0) SizedBox(width: theme.isLcars ? lcarsLine : 8),
          Expanded(
            child: theme.isLcars
                ? LcarsBlock(
                    colour: i == chosen ? lcarsLit : theme.block(i + 2),
                    height: height,
                    ends: i == 0
                        ? LcarsEnds.start
                        : i == labels.length - 1
                        ? LcarsEnds.end
                        : LcarsEnds.none,
                    onTap: () => onTap(i),
                    child: Text(
                      lcarsCaps(label),
                      style: TextStyle(fontSize: height * 0.5),
                    ),
                  )
                : Material(
                    color: i == chosen
                        ? theme.accent
                        : theme.textSecondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(height / 2),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(height / 2),
                      onTap: () => onTap(i),
                      child: SizedBox(
                        height: height,
                        child: Center(
                          child: Text(
                            label,
                            style: TextStyle(
                              color: i == chosen
                                  ? theme.onAccent
                                  : theme.textPrimary,
                              fontSize: height * 0.42,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}

/// The bars: those gone in the quieter colour, the one we are in in the
/// accent, those to come — or not yet read — as a line along the bottom.
class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.bars, required this.now, required this.theme});

  final List<double?> bars;
  final int? now;
  final DashboardTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final top = bars.whereType<double>().fold(0.0, math.max);
    final scale = top <= 0 ? 0.0 : size.height / (top * 1.08);
    final w = size.width / bars.length;
    for (var i = 0; i < bars.length; i++) {
      final v = bars[i];
      final h = v == null ? 2.0 : (v * scale).clamp(2.0, size.height);
      final paint = Paint()
        ..color = i == now
            ? theme.accent
            : v == null
            ? theme.textSecondary.withValues(alpha: 0.15)
            : theme.isLcars
            ? theme.block(i * 4 ~/ bars.length + 1)
            : theme.textSecondary.withValues(alpha: 0.45);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(i * w + w * 0.12, size.height - h, w * 0.76, h),
          // Square on a console, as its bars are.
          topLeft: Radius.circular(theme.isLcars ? 0 : w * 0.25),
          topRight: Radius.circular(theme.isLcars ? 0 : w * 0.25),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      !listEquals(old.bars, bars) || old.now != now || old.theme != theme;
}

/// What is lettered under the bars, each under the bar it names.
class _AxisPainter extends CustomPainter {
  _AxisPainter({
    required this.count,
    required this.labels,
    required this.style,
  });

  final int count;
  final List<(int, String)> labels;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / count;
    for (final (i, text) in labels) {
      final p = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (i * w + (w - p.width) / 2).clamp(0.0, size.width - p.width);
      p.paint(canvas, Offset(x, 0));
    }
  }

  @override
  bool shouldRepaint(_AxisPainter old) =>
      old.count != count ||
      !listEquals(old.labels, labels) ||
      old.style != style;
}

const _meterHelp =
    'Leave empty to use Hildebrand Glow (DCC)’s, which is the Bright '
    'app’s data in Home Assistant.';

final haEnergyWidgetType = DashboardWidgetType(
  type: 'ha_energy',
  category: WidgetCategory.house,
  name: 'Electricity',
  description:
      'Electricity used and what it cost — today, this week, this month or '
      'the last twelve, each against the one before, as bars. From your '
      'smart meter: today through Home Assistant, and the longer views from '
      'Bright, with its login in Settings. About half an hour behind, as '
      'the meter is.',
  glyph: '🔌',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'view',
      label: 'Shows first',
      kind: OptionKind.choice,
      defaultValue: 'day',
      choices: {
        'day': 'Today',
        'week': 'This week',
        'month': 'This month',
        'year': 'The last twelve months',
      },
      help: 'Tap the widget’s Day, Week, Month and Year to change it.',
    ),
    WidgetOption(
      key: 'usage',
      label: 'Used today',
      kind: OptionKind.choice,
      choicesFrom: 'haEntities',
      defaultValue: '',
      help: _meterHelp,
    ),
    WidgetOption(
      key: 'cost',
      label: 'Cost today',
      kind: OptionKind.choice,
      choicesFrom: 'haEntities',
      defaultValue: '',
      help: _meterHelp,
    ),
    WidgetOption(
      key: 'rate',
      label: 'Unit rate',
      kind: OptionKind.choice,
      choicesFrom: 'haEntities',
      defaultValue: '',
      help: _meterHelp,
    ),
    WidgetOption(
      key: 'standing',
      label: 'Standing charge',
      kind: OptionKind.choice,
      choicesFrom: 'haEntities',
      defaultValue: '',
      help: _meterHelp,
    ),
  ],
  preview: const [
    PreviewLine('DAY  WEEK  MONTH  YEAR', scale: 0.1),
    PreviewLine('4.2 kWh  £1.83', scale: 0.2, accent: true),
    PreviewLine('▁▁▂▁▁▁▂▅▃▂▂▃▂▂▃▅▇▆▄', scale: 0.14),
  ],
  build: (context, w) => HaEnergyWidget(w: w),
);

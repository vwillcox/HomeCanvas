import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/home_assistant_service.dart';
import '../../widgets/lcars.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/shown_timers.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'tile_bits.dart';

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

class HaEnergyWidget extends StatefulWidget {
  const HaEnergyWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HaEnergyWidget> createState() => _HaEnergyWidgetState();
}

class _HaEnergyWidgetState extends State<HaEnergyWidget>
    with PauseWhenHidden, ShownTimers {
  EnergyDay? _day;

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

  Future<void> _refresh() async {
    if (!mounted) return;
    final ha = context.read<HomeAssistantService>();
    await ha.refresh();
    final usage = _pick(ha, 'usage', '_usage_today');
    if (usage == null || !mounted) return;
    final cost = _pick(ha, 'cost', '_cost_today');
    final now = DateTime.now();
    final history = await ha.history([
      usage,
      ?cost,
    ], DateTime(now.year, now.month, now.day - 1));
    if (!mounted || history.isEmpty) return;
    setState(() {
      _day = EnergyDay.from(
        history[usage] ?? const [],
        cost == null ? const [] : history[cost] ?? const [],
        now,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final ha = context.watch<HomeAssistantService>();
    if (!ha.configured) {
      return TileMessage(
        tr(
          'widget.home_assistant.connectHomeAssistantInSettings',
          'Connect Home Assistant in Settings first — its address and a long-lived access token.',
        ),
        theme: t,
      );
    }
    final usageId = _pick(ha, 'usage', '_usage_today');
    if (usageId == null) {
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
    double? now(String key, String like) {
      final id = _pick(ha, key, like);
      final e = id == null ? null : ha.entity(id);
      return e == null ? null : double.tryParse(e.state);
    }

    final day = _day;
    final today = now('usage', '_usage_today') ?? day?.today ?? 0;
    final cost = now('cost', '_cost_today') ?? day?.costToday;
    final rate = now('rate', '_meter_rate');
    final standing = now('standing', '_standing_charge');
    return LayoutBuilder(
      builder: (context, c) {
        final big = (math.min(
          c.maxHeight * 0.2,
          c.maxWidth * 0.12,
        )).clamp(18.0, 72.0);
        final small = (big * 0.36).clamp(11.0, 22.0);
        final chart = c.maxHeight > big * 3.2;
        final figures = [
          (tr('widget.ha_energy.today', 'Today'), _kwh(today)),
          if (cost != null)
            (tr('widget.ha_energy.cost', 'Cost'), _pounds(cost)),
          if (day?.yesterday != null)
            (
              tr('widget.ha_energy.yesterday', 'Yesterday'),
              _kwh(day!.yesterday!) +
                  (day.costYesterday == null
                      ? ''
                      : ' · ${_pounds(day.costYesterday!)}'),
            ),
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
            if (chart) ...[
              SizedBox(height: big * 0.3),
              Expanded(
                child: CustomPaint(
                  painter: _HoursPainter(
                    hours: day?.hours ?? List.filled(24, 0),
                    hour: DateTime.now().hour,
                    theme: t,
                  ),
                ),
              ),
              SizedBox(height: small * 0.3),
              Row(
                children: [
                  for (final h in ['00', '06', '12', '18'])
                    Expanded(
                      child: Text(
                        h,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: small * 0.85,
                        ),
                      ),
                    ),
                ],
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
  static String _pounds(double v) => '£${v.toStringAsFixed(2)}';
}

/// Today's hours as bars: those gone in the quieter colour, this one in the
/// accent, those to come as a line along the bottom.
class _HoursPainter extends CustomPainter {
  _HoursPainter({required this.hours, required this.hour, required this.theme});

  final List<double> hours;
  final int hour;
  final DashboardTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final top = hours.reduce(math.max);
    final scale = top <= 0 ? 0.0 : size.height / (top * 1.08);
    final w = size.width / 24;
    for (var i = 0; i < 24; i++) {
      final future = i > hour;
      final h = future ? 2.0 : (hours[i] * scale).clamp(2.0, size.height);
      final paint = Paint()
        ..color = i == hour
            ? theme.accent
            : future
            ? theme.textSecondary.withValues(alpha: 0.15)
            : theme.isLcars
            ? theme.block(i ~/ 6 + 1)
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
  bool shouldRepaint(_HoursPainter old) =>
      !listEquals(old.hours, hours) || old.hour != hour || old.theme != theme;
}

const _meterHelp =
    'Leave empty to use Hildebrand Glow (DCC)’s, which is the Bright '
    'app’s data in Home Assistant.';

final haEnergyWidgetType = DashboardWidgetType(
  type: 'ha_energy',
  category: WidgetCategory.house,
  name: 'Electricity',
  description:
      'Electricity used today and what it has cost, against yesterday, hour '
      'by hour — from your smart meter through Home Assistant, as the '
      'Bright app shows it. About half an hour behind, as the meter is.',
  glyph: '🔌',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
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
    PreviewLine('4.2 kWh  £1.83', scale: 0.2, accent: true),
    PreviewLine('▁▁▂▁▁▁▂▅▃▂▂▃▂▂▃▅▇▆▄', scale: 0.14),
    PreviewLine('32.4p a kWh · 47.3p a day', scale: 0.1),
  ],
  build: (context, w) => HaEnergyWidget(w: w),
);

import 'package:flutter/material.dart';

import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/rebuild_every_minute.dart';
import '../../widgets/shown_timers.dart';
import '../../l10n/l10n.dart';

const _days = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

/// What is for dinner, for [date]'s weekday; empty when nothing is planned.
String mealOn(Map<String, dynamic> options, DateTime date) =>
    '${options[_days[date.weekday - 1]] ?? ''}'.trim();

/// Which day counts as "tonight": today until [switchHour], then tomorrow —
/// once dinner is eaten, the question is what is for tomorrow.
DateTime tonight(DateTime now, int switchHour) {
  // A day on by the calendar, not 24 hours: on the Sunday the clocks go
  // back, midnight plus 24 hours is 11pm the same day.
  final after = now.hour >= switchHour ? 1 : 0;
  return DateTime(now.year, now.month, now.day + after);
}

/// The week's dinners, set in the editor: tonight's large, tomorrow's
/// underneath.
class MealsWidget extends StatefulWidget {
  const MealsWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<MealsWidget> createState() => _MealsWidgetState();
}

class _MealsWidgetState extends State<MealsWidget>
    with PauseWhenHidden, ShownTimers, RebuildEveryMinute {
  static String _dayName(DateTime d) =>
      '${_days[d.weekday - 1][0].toUpperCase()}${_days[d.weekday - 1].substring(1)}';

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final options = widget.w.config.options;
    final switchHour = (int.tryParse('${options['switchHour'] ?? 20}') ?? 20)
        .clamp(0, 23);
    final now = DateTime.now();
    final first = tonight(now, switchHour);
    final second = DateTime(first.year, first.month, first.day + 1);
    final a = mealOn(options, first), b = mealOn(options, second);
    if (_days.every((d) => '${options[d] ?? ''}'.trim().isEmpty)) {
      return TileMessage(
        tr(
          'widget.meals.fillInTheWeekS',
          'Fill in the week’s dinners in the widget settings.',
        ),
        theme: t,
      );
    }
    final isToday = first.day == now.day;

    return FitCanvas(
      designHeight: 100,
      maxScale: 3,
      builder: (context, size) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TileLabel(
            icon: Icons.restaurant_rounded,
            text: isToday ? tr('widget.meals.tonight', 'Tonight') : tr('widget.meals.tomorrow2', 'Tomorrow · {first}', {'first': _dayName(first)}),
            theme: t,
            size: 11,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  a.isEmpty ? tr('widget.meals.nothingPlanned', 'Nothing planned') : a,
                  maxLines: 2,
                  style: TextStyle(
                    color: a.isEmpty ? t.textSecondary : t.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: isToday ? tr('widget.meals.tomorrow', 'Tomorrow  ') : '${_dayName(second)}  ',
                  style: TextStyle(color: t.textSecondary, fontSize: 11),
                ),
                TextSpan(
                  text: b.isEmpty ? '—' : b,
                  style: TextStyle(color: t.textPrimary, fontSize: 13),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

final mealsWidgetType = DashboardWidgetType(
  type: 'meals',
  category: WidgetCategory.house,
  name: 'Meal plan',
  description:
      'The week’s dinners: tonight’s large, tomorrow’s underneath. '
      'After dinner time it moves on to tomorrow.',
  glyph: '🍽️',
  defaultWidth: 3,
  defaultHeight: 2,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(key: 'monday', label: 'Monday', defaultValue: ''),
    WidgetOption(key: 'tuesday', label: 'Tuesday', defaultValue: ''),
    WidgetOption(key: 'wednesday', label: 'Wednesday', defaultValue: ''),
    WidgetOption(key: 'thursday', label: 'Thursday', defaultValue: ''),
    WidgetOption(key: 'friday', label: 'Friday', defaultValue: ''),
    WidgetOption(key: 'saturday', label: 'Saturday', defaultValue: ''),
    WidgetOption(key: 'sunday', label: 'Sunday', defaultValue: ''),
    WidgetOption(
      key: 'switchHour',
      label: 'Move on to tomorrow at (hour)',
      kind: OptionKind.number,
      defaultValue: 20,
    ),
  ],
  preview: const [
    PreviewLine('Tonight', scale: 0.1, muted: true),
    PreviewLine('Lasagne', scale: 0.26),
    PreviewLine('Tomorrow  Fish and chips', scale: 0.1),
  ],
  build: (context, w) => MealsWidget(w: w),
);

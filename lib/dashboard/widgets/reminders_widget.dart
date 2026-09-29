import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/dates.dart';
import '../../l10n/l10n.dart';
import '../../services/reminders_service.dart';
import '../../time_format.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/rebuild_every_minute.dart';
import '../../widgets/shown_timers.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'tile_bits.dart';

/// Reminders sent from the phone app — "Remind me to put the bins out at
/// 7pm" — soonest first, said aloud when they fall due, and dismissed with
/// a tap.
class RemindersWidget extends StatefulWidget {
  const RemindersWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  @override
  State<RemindersWidget> createState() => _RemindersWidgetState();
}

class _RemindersWidgetState extends State<RemindersWidget>
    with PauseWhenHidden, ShownTimers, RebuildEveryMinute {
  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final service = context.watch<RemindersService?>();
    final all = service?.reminders ?? const <Reminder>[];
    final showUndated = widget.w.option('showUndated', true);
    final list = [
      for (final r in all)
        if (showUndated || r.due != null) r,
    ];
    if (list.isEmpty) {
      return TileMessage(
        tr(
          'widget.reminders.empty',
          'No reminders. Share one from the phone app: “Remind me to put the bins out at 7pm”.',
        ),
        theme: t,
      );
    }
    final status = StatusColours.of(t);
    final now = DateTime.now();
    final due = list.where((r) => r.fired).length;
    return LayoutBuilder(
      builder: (context, c) {
        // Sized to the room each reminder has: one fills the tile, a long
        // list comes down to the smallest readable size and scrolls. Held
        // back by the width too, so a tall narrow tile doesn't overflow.
        final each = (c.maxHeight - 30) / list.length;
        // A reminder can run to two lines and a sender: about 72 at the
        // smallest size, dividers included.
        final k = [each / 58, c.maxWidth / 300, 3.5]
            .reduce((a, b) => a < b ? a : b)
            .clamp(1.0, 3.5);
        final rows = [
          for (final r in list)
            _ReminderRow(
              r: r,
              now: now,
              theme: t,
              status: status,
              k: k,
              onDone: () => service?.remove(r.id),
            ),
        ];
        Widget divider() => Divider(
          height: 10 * k,
          thickness: 1,
          color: t.textSecondary.withValues(alpha: .15),
        );
        // A few fit whole: centred in the space. More scroll.
        final fits = each >= 72;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TileLabel(
              icon: Icons.alarm_outlined,
              text: tr('widget.reminders.title', 'Reminders'),
              theme: t,
              size: (12 * k).clamp(12.0, 20.0),
              trailing: due == 0
                  ? null
                  : StatusChip(
                      text: tr('widget.reminders.dueCount',
                          '{n, plural, one{# due} other{# due}}', {'n': due}),
                      colour: status.warn,
                      size: (11 * k).clamp(11.0, 18.0),
                    ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: fits
                  // Shrunk a touch rather than overflowing, should the
                  // words run longer than the estimate.
                  ? LayoutBuilder(
                      builder: (context, box) => Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: box.maxWidth,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < rows.length; i++) ...[
                                  if (i > 0) divider(),
                                  rows[i],
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => divider(),
                      itemBuilder: (context, i) => rows[i],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.r,
    required this.now,
    required this.theme,
    required this.status,
    required this.onDone,
    this.k = 1,
  });

  /// How much larger than its smallest it is drawn.
  final double k;

  final Reminder r;
  final DateTime now;
  final DashboardTheme theme;
  final StatusColours status;
  final VoidCallback onDone;

  /// "17:00", "Tomorrow 09:00", "Fri 14:00", "12 Oct" — when, as briefly as
  /// is clear.
  String _when() {
    final due = r.due;
    if (due == null) return tr('widget.reminders.someTime', 'Some time');
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(due.year, due.month, due.day);
    final days = day.difference(today).inDays;
    final time = r.allDay ? '' : ' ${hhmm(due)}';
    if (days == 0) {
      return r.allDay ? tr('common.today', 'Today') : hhmm(due);
    }
    if (days == 1) return '${tr('widget.calendar.tomorrow', 'Tomorrow')}$time';
    if (days > 1 && days < 7) return '${weekdayShort(due)}$time';
    return '${dayMonth(due)}$time';
  }

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final colour = r.fired ? status.warn : t.accent;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _confirm(context),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 2 * k),
        child: Row(
          children: [
            SizedBox(
              width: 92 * k,
              child: Text(
                r.fired ? tr('widget.reminders.now', 'Now') : _when(),
                maxLines: 2,
                style: TextStyle(
                  color: colour,
                  fontSize: 13 * k,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            SizedBox(width: 8 * k),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 15 * k,
                      fontWeight: r.fired ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (r.from.isNotEmpty)
                    Text(
                      tr('widget.reminders.from', 'from {name}', {'name': r.from}),
                      style: TextStyle(color: t.textSecondary, fontSize: 11 * k),
                    ),
                ],
              ),
            ),
            if (r.fired)
              Icon(
                Icons.notifications_active_outlined,
                color: status.warn,
                size: 20 * k,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r.text, style: const TextStyle(fontSize: 22)),
        content: Text(
          [
            _when(),
            if (r.from.isNotEmpty)
              tr('widget.reminders.from', 'from {name}', {'name': r.from}),
          ].join(' · '),
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('widget.reminders.keep', 'Keep'),
                style: const TextStyle(fontSize: 18)),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.check),
            label: Text(tr('widget.reminders.done', 'Done'),
                style: const TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
    if (done == true) onDone();
  }
}

final remindersWidgetType = DashboardWidgetType(
  type: 'reminders',
  category: WidgetCategory.timeAndDay,
  name: 'Reminders',
  description:
      'Reminders shared from the phone app — “Remind me to put the bins out '
      'at 7pm”, “Don’t forget the dentist tomorrow at 9:30”. Said aloud when '
      'they fall due; tap one when it’s done.',
  glyph: '⏰',
  defaultWidth: 3,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 2,
  // Sizes its own text to the room it has, so the dashboard's shrink for
  // smaller-than-default tiles would only make it small twice.
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'showUndated',
      label: 'Show reminders with no time',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: '“Remind me to call the plumber” has no time; it stays at the '
          'bottom of the list until it’s done.',
    ),
  ],
  preview: const [
    PreviewLine('19:00   Put the bins out', scale: .12, px: 15),
    PreviewLine('Tomorrow 09:30   Dentist', scale: .12, px: 15),
  ],
  build: (context, w) => RemindersWidget(w: w),
);

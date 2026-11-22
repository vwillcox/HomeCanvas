import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/feed_service.dart';
import '../dashboard_model.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import '../../time_format.dart';
import '../../l10n/dates.dart';
import '../../l10n/l10n.dart';
import '../../widgets/lcars.dart';
import 'tile_bits.dart';

/// One calendar feed and the colour its events are drawn in.
class _Source {
  const _Source(this.url, this.colour, this.name);
  final String url;
  final Color colour;
  final String name;
}

/// An event with the colour of whichever calendar it came from.
class _Entry {
  const _Entry(this.event, this.colour);
  final CalendarEvent event;
  final Color colour;
}

/// Upcoming events from one or more published iCalendar feeds, as a schedule
/// or as a month.
class DashboardCalendarWidget extends StatelessWidget {
  const DashboardCalendarWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  static Color? _colour(Object? v) {
    if (v is! String || v.isEmpty) return null;
    var s = v.trim().replaceFirst('#', '');
    if (s.length == 6) s = 'ff$s';
    final n = int.tryParse(s, radix: 16);
    return n == null ? null : Color(n);
  }

  /// The feeds a calendar tile [w] reads, each with its colour if it was
  /// given one.
  ///
  /// Falls back to the single `url` this widget originally took, so a
  /// dashboard built before it accepted several keeps working untouched.
  static List<({String url, Color? colour, String name})> feedsOf(
    DashboardWidgetConfig w,
  ) {
    final rows = (w.options['sources'] as List?)?.whereType<Map>() ?? [];
    if (rows.isNotEmpty) {
      return [
        for (final r in rows)
          if ('${r['url'] ?? ''}'.isNotEmpty)
            (
              url: '${r['url']}',
              colour: _colour(r['colour']),
              name: '${r['name'] ?? ''}',
            ),
      ];
    }
    final legacy = '${w.options['url'] ?? ''}';
    return legacy.isEmpty ? const [] : [(url: legacy, colour: null, name: '')];
  }

  /// The configured feeds.
  List<_Source> _sources(Color fallback) => [
    for (final f in feedsOf(w.config))
      _Source(f.url, f.colour ?? fallback, f.name),
  ];

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final sources = _sources(t.accent);
    if (sources.isEmpty) {
      return _Hint(
        text: tr(
          'widget.calendar.addACalendarLinkIn',
          'Add a calendar link in this widget’s settings.',
        ),
        colour: t.textSecondary,
      );
    }

    final feeds = context.watch<FeedService>();
    final entries = <_Entry>[];
    String? error;
    for (final s in sources) {
      for (final e in feeds.calendar(s.url)) {
        entries.add(_Entry(e, s.colour));
      }
      error ??= feeds.errorFor(s.url);
    }
    entries.sort((a, b) => a.event.start.compareTo(b.event.start));

    final month = w.option('view', 'schedule') == 'month';
    return month
        ? _MonthView(w: w, entries: entries)
        : _ScheduleView(w: w, entries: entries, error: error);
  }
}

class _ScheduleView extends StatelessWidget {
  const _ScheduleView({
    required this.w,
    required this.entries,
    required this.error,
  });

  final DashboardWidgetContext w;
  final List<_Entry> entries;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final days = w.option('days', 14);
    final horizon = DateTime.now().add(Duration(days: days));
    final from = DateTime.now().subtract(const Duration(hours: 12));
    final shown = entries
        .where(
          (e) => e.event.start.isAfter(from) && e.event.start.isBefore(horizon),
        )
        .take(w.option('maxEvents', 6))
        .toList();

    if (shown.isEmpty) {
      return _Hint(
        text:
            error ??
            tr(
              'widget.calendar.nothingInTheNextDays',
              'Nothing in the next {days} days.',
              {'days': days},
            ),
        colour: t.textSecondary,
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: shown.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final entry = shown[i];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 34,
              decoration: BoxDecoration(
                color: entry.colour,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    calendarWhen(entry.event),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textSecondary, fontSize: 13),
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

/// When an event is, as the schedule words it: "Today 14:00", "Tomorrow".
String calendarWhen(CalendarEvent e) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(e.start.year, e.start.month, e.start.day);
  final diff = day.difference(today).inDays;

  final String dayLabel;
  if (diff == 0) {
    dayLabel = tr('widget.calendar.today', 'Today');
  } else if (diff == 1) {
    dayLabel = tr('widget.calendar.tomorrow', 'Tomorrow');
  } else if (diff < 7) {
    dayLabel = weekdayShort(e.start);
  } else {
    // 28/09 in Britain, 09/28 in America.
    dayLabel = '${weekdayShort(e.start)} ${numericDayMonth(e.start)}';
  }

  if (e.allDay) {
    return tr('widget.calendar.allDay', '{dayLabel} · all day', {
      'dayLabel': dayLabel,
    });
  }
  final time = hhmm(e.start);
  final where = e.location == null ? '' : ' · ${e.location}';
  return '$dayLabel $time$where';
}

/// A month at a glance: a dot per event, in its calendar's colour.
///
/// Deliberately dots rather than titles — at the size a month grid gets on a
/// dashboard tile, a title is unreadable anyway, and what the month view is
/// for is seeing which days are busy.
class _MonthView extends StatelessWidget {
  const _MonthView({required this.w, required this.entries});

  final DashboardWidgetContext w;
  final List<_Entry> entries;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    // Monday-first, which is what a UK wall calendar does.
    final leading = first.weekday - 1;
    final cells = leading + daysInMonth;
    final weeks = (cells / 7).ceil();

    final byDay = <int, List<_Entry>>{};
    for (final e in entries) {
      if (e.event.start.year != now.year || e.event.start.month != now.month) {
        continue;
      }
      byDay.putIfAbsent(e.event.start.day, () => []).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tileCased(t, monthYear(now)),
          style: TextStyle(
            color: t.isLcars ? t.accent : t.textPrimary,
            fontSize: 16,
            fontWeight: t.isLcars ? FontWeight.w700 : FontWeight.w600,
            letterSpacing: t.isLcars ? 1 : null,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final (i, d) in weekdayLetters().indexed)
              Expanded(
                child: t.isLcars
                    // Each day of the week on a bar of its own colour, a
                    // black line from the next.
                    ? Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: lcarsLine / 2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        color: t.block(i),
                        child: Text(
                          d,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: lcarsInk,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : Text(
                        d,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: t.textSecondary, fontSize: 11),
                      ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Expanded(
          child: Column(
            children: [
              for (var week = 0; week < weeks; week++)
                Expanded(
                  child: Row(
                    children: [
                      for (var slot = 0; slot < 7; slot++)
                        Expanded(
                          child: _Day(
                            day: week * 7 + slot - leading + 1,
                            daysInMonth: daysInMonth,
                            today: now.day,
                            events: byDay[week * 7 + slot - leading + 1],
                            theme: w.theme,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.daysInMonth,
    required this.today,
    required this.events,
    required this.theme,
  });

  final int day;
  final int daysInMonth;
  final int today;
  final List<_Entry>? events;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    if (day < 1 || day > daysInMonth) return const SizedBox.shrink();
    final isToday = day == today;
    final list = events ?? const [];

    return LayoutBuilder(
      builder: (context, c) {
        // Titles need room to be worth showing. Below that, fall back to a
        // dot each — which is all a cell three millimetres tall can honestly
        // carry, and still answers "is that day busy?".
        final titleHeight = 11.0;
        final room = ((c.maxHeight - 16) / titleHeight).floor();
        final showTitles = c.maxHeight > 34 && room >= 1;
        final shown = showTitles
            ? list.take(room.clamp(1, 3)).toList()
            : const <_Entry>[];

        return Padding(
          padding: const EdgeInsets.all(1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: isToday
                      ? BoxDecoration(
                          color: theme.accent,
                          // Today is a block, on a console: square.
                          borderRadius: BorderRadius.circular(
                            theme.isLcars ? 0 : 20,
                          ),
                        )
                      : null,
                  child: Text(
                    '$day',
                    style: TextStyle(
                      // Against the accent fill, the background colour is the
                      // one guaranteed to contrast with it.
                      color: isToday
                          ? theme.background.first
                          : theme.textPrimary,
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
              if (shown.isNotEmpty)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final e in shown)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: e.colour.withValues(alpha: 0.22),
                              border: Border(
                                left: BorderSide(color: e.colour, width: 2),
                              ),
                              borderRadius: BorderRadius.circular(
                                theme.isLcars ? 0 : 3,
                              ),
                            ),
                            child: Text(
                              e.event.title,
                              maxLines: 1,
                              // Cropped rather than wrapped: a wrapped title
                              // would push the next day's events out of the
                              // cell entirely.
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: TextStyle(
                                color: theme.textPrimary,
                                fontSize: 9,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      if (list.length > shown.length)
                        Text(
                          tr('widget.calendar.more', '+{shown} more', {
                            'shown': list.length - shown.length,
                          }),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.textSecondary,
                            fontSize: 8,
                          ),
                        ),
                    ],
                  ),
                )
              else if (list.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final e in list.take(4))
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: e.colour,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text, required this.colour});
  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: colour, fontSize: 15),
    ),
  );
}

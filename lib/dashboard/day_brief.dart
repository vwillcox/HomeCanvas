import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

import '../l10n/l10n.dart';
import '../services/bin_schedule.dart';
import '../services/feed_service.dart' show CalendarEvent;
import '../services/parcels_service.dart';
import '../services/reminders_service.dart' show Reminder;
import '../services/timer_service.dart' show KioskTimer;
import '../services/weather_service.dart';
import '../time_format.dart';
import '../widgets/glass.dart' show greetingFor;
import 'widgets/parcels_view.dart' show parcelName;

/// What sort of thing a line of the day is.
enum BriefKind { event, reminder, parcel, bins, timer, rain, sunset }

/// One thing in the day: an event, a reminder, a parcel coming, the bins.
///
/// [at] is when it starts, or null for some time in the day — an all-day
/// event, bin day. [until] is when it ends; alone, it is a "by": a parcel
/// coming by noon.
@immutable
class BriefItem {
  const BriefItem(
    this.kind,
    this.text, {
    this.at,
    this.until,
    this.detail,
    this.colour,
  });

  final BriefKind kind;
  final String text;
  final DateTime? at;
  final DateTime? until;

  /// A word more: where, from whom, which carrier.
  final String? detail;

  /// Its calendar's colour, for an event.
  final Color? colour;

  /// When it sorts: its start, its "by", or the start of the day.
  DateTime? get time => at ?? until;

  /// Whether it is over by [now]. Something with no time to it lasts the day.
  bool over(DateTime now) {
    final end = until ?? at;
    return end != null && !end.isAfter(now);
  }
}

/// The day at a glance: the weather, then what is on today and tomorrow,
/// from every tile on the panel that knows something about it.
///
/// Pure: everything is handed in, so the day can be put together for any
/// moment in a test. [DayBriefSheet] gathers it from the panel's services.
class DayBrief {
  DayBrief({
    required this.now,
    required this.today,
    required this.tomorrow,
    this.weather,
  });

  final DateTime now;
  final Weather? weather;

  /// Today's things, all of it — what is over as well, so the day reads as
  /// a day — in order: those with no time first.
  final List<BriefItem> today;
  final List<BriefItem> tomorrow;

  /// Today's things still to come.
  List<BriefItem> get ahead => [
    for (final i in today)
      if (!i.over(now)) i,
  ];

  /// The next thing with a time to it, to be marked.
  BriefItem? get next {
    for (final i in today) {
      if (i.at != null && !i.over(now) && i.kind != BriefKind.sunset) return i;
    }
    return null;
  }

  static DayBrief gather({
    required DateTime now,
    Weather? weather,
    List<(CalendarEvent, Color)> events = const [],
    List<Reminder> reminders = const [],
    List<Parcel> parcels = const [],
    List<BinCollection> bins = const [],
    List<KioskTimer> timers = const [],
  }) {
    final day0 = DateTime(now.year, now.month, now.day);
    final day1 = DateTime(now.year, now.month, now.day + 1);
    final day2 = DateTime(now.year, now.month, now.day + 2);

    List<BriefItem> on(DateTime from, DateTime to) {
      bool inside(DateTime t) => !t.isBefore(from) && t.isBefore(to);
      final out = <BriefItem>[];

      for (final (e, colour) in events) {
        final end = e.end ?? e.start;
        // Overlapping the day at all: a holiday that started yesterday is
        // still on today.
        final overlaps =
            e.start.isBefore(to) &&
            (end.isAfter(from) || (end == e.start && inside(e.start)));
        if (!overlaps) continue;
        final timed = !e.allDay && inside(e.start);
        out.add(
          BriefItem(
            BriefKind.event,
            e.title,
            at: timed ? e.start : null,
            until: timed && e.end != null && inside(e.end!) ? e.end : null,
            detail: e.location,
            colour: colour,
          ),
        );
      }

      for (final r in reminders) {
        final due = r.due;
        if (due == null || !inside(due)) continue;
        out.add(
          BriefItem(
            BriefKind.reminder,
            r.text,
            at: r.allDay ? null : due,
            detail: r.from.isEmpty ? null : r.from,
          ),
        );
      }

      for (final p in parcels) {
        if (p.delivered) continue;
        final from = p.expected;
        final out_ = p.stage == ParcelStage.out;
        if (from == null || !inside(from)) {
          // Out for delivery with no day to it is coming today all the same.
          if (out_ && from == null && inside(now)) {
            out.add(
              BriefItem(
                BriefKind.parcel,
                parcelName(p),
                detail: tr('brief.outForDelivery', 'Out for delivery'),
              ),
            );
          }
          continue;
        }
        final timed = from.hour != 0 || from.minute != 0;
        out.add(
          BriefItem(
            BriefKind.parcel,
            parcelName(p),
            at: timed ? from : null,
            until: p.expectedTo,
            detail: p.carrier.name,
          ),
        );
      }

      for (final b in bins) {
        if (inside(b.day)) {
          out.add(
            BriefItem(
              BriefKind.bins,
              tr('brief.binDay', 'Bin day: {bins}', {'bins': b.names}),
            ),
          );
        } else if (from == day0 && b.day == day1) {
          out.add(
            BriefItem(
              BriefKind.bins,
              tr('brief.binsTonight', 'Bins out tonight: {bins}', {
                'bins': b.names,
              }),
            ),
          );
        }
      }
      return out;
    }

    final today = on(day0, day1);
    for (final t in timers) {
      if (t.finished || t.paused) continue;
      today.add(
        BriefItem(
          BriefKind.timer,
          t.label.isEmpty ? tr('brief.timer', 'Timer') : t.label,
          at: now.add(t.remaining(now)),
          detail: tr('brief.timerEnds', 'Timer'),
        ),
      );
    }
    if (weather != null) {
      final rain = rainWindow(weather, now);
      if (rain != null) {
        today.add(
          BriefItem(
            BriefKind.rain,
            tr('brief.rainLikely', 'Rain likely'),
            at: rain.from,
            until: rain.to,
            detail: '${rain.chance}%',
          ),
        );
      }
      final sunset = _clock(day0, weather.daily.firstOrNull?.sunset);
      if (sunset != null) {
        today.add(
          BriefItem(BriefKind.sunset, tr('brief.sunset', 'Sunset'), at: sunset),
        );
      }
    }

    return DayBrief(
      now: now,
      weather: weather,
      today: _sorted(today),
      tomorrow: _sorted(on(day1, day2)),
    );
  }

  /// Those with no time first, then by time; events before reminders
  /// before the rest at the same minute.
  static List<BriefItem> _sorted(List<BriefItem> items) => items
    ..sort((a, b) {
      final ta = a.time, tb = b.time;
      if (ta == null || tb == null) {
        if (ta != tb) return ta == null ? -1 : 1;
      } else {
        final c = ta.compareTo(tb);
        if (c != 0) return c;
      }
      return a.kind.index.compareTo(b.kind.index);
    });

  /// "16:28" on [day], as Open-Meteo gives a sunset.
  static DateTime? _clock(DateTime day, String? hhmm) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm ?? '');
    if (m == null) return null;
    return DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(m[1]!),
      int.parse(m[2]!),
    );
  }

  /// When rain is likely for the rest of today — the first hour it is at
  /// least even odds, to the hour it stops being — and how likely at most.
  static ({DateTime from, DateTime to, int chance})? rainWindow(
    Weather weather,
    DateTime now,
  ) {
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final hourStart = DateTime(now.year, now.month, now.day, now.hour);
    DateTime? from;
    DateTime? to;
    var chance = 0;
    for (final h in weather.hourly) {
      if (h.time.isBefore(hourStart) || !h.time.isBefore(midnight)) continue;
      final wet = h.precipitationChance >= 50;
      if (wet && to == null) {
        from ??= h.time;
        if (h.precipitationChance > chance) chance = h.precipitationChance;
      } else if (!wet && from != null && to == null) {
        to = h.time;
      }
    }
    if (from == null) return null;
    return (from: from, to: to ?? midnight, chance: chance);
  }

  /// The day, as said aloud: a few sentences, not the whole board.
  List<String> spoken() {
    final out = <String>[
      tr('brief.say.greeting', '{greeting}.', {'greeting': greetingFor(now)}),
    ];
    final w = weather;
    if (w != null) {
      final unit = w.unit.contains('F') ? 'Fahrenheit' : 'degrees';
      out.add(
        [
          tr('brief.say.now', 'It’s {temp} {unit} and {sky}.', {
            'temp': w.temperature.round(),
            'unit': unit,
            'sky': w.description.toLowerCase(),
          }),
          tr('brief.say.highLow', 'A high of {high}, and a low of {low}.', {
            'high': w.tempMax.round(),
            'low': w.tempMin.round(),
          }),
          switch (rainWindow(w, now)) {
            final r? when r.to.day != r.from.day || r.to.hour == 0 => tr(
              'brief.say.rainFrom',
              'Rain is likely from {time}.',
              {'time': saidTime(r.from)},
            ),
            final r? => tr(
              'brief.say.rainBetween',
              'Rain is likely between {from} and {to}.',
              {'from': saidTime(r.from), 'to': saidTime(r.to)},
            ),
            null => tr('brief.say.dry', 'It should stay dry.'),
          },
        ].join(' '),
      );
    }

    final ahead = [
      for (final i in this.ahead)
        if (i.kind != BriefKind.rain && i.kind != BriefKind.sunset) i,
    ];
    if (ahead.isEmpty) {
      out.add(tr('brief.say.nothingToday', 'Nothing else is on today.'));
    } else {
      out.add(
        [
          tr('brief.say.today', 'Still to come today:'),
          for (final i in ahead) _say(i),
        ].join(' '),
      );
    }
    if (tomorrow.isNotEmpty) {
      out.add(
        [
          tr('brief.say.tomorrow', 'Tomorrow:'),
          for (final i in tomorrow.take(4)) _say(i),
          if (tomorrow.length > 4)
            tr('brief.say.more', 'And {count} more.', {
              'count': tomorrow.length - 4,
            }),
        ].join(' '),
      );
    }
    return out;
  }

  static String _say(BriefItem i) {
    final at = i.at;
    final until = i.until;
    return switch (i.kind) {
      BriefKind.parcel when at != null && until != null => tr(
        'brief.say.parcelBetween',
        '{name} is due between {from} and {to}.',
        {'name': i.text, 'from': saidTime(at), 'to': saidTime(until)},
      ),
      BriefKind.parcel when until != null => tr(
        'brief.say.parcelBy',
        '{name} is due by {time}.',
        {'name': i.text, 'time': saidTime(until)},
      ),
      BriefKind.parcel when i.detail != null && at == null => tr(
        'brief.say.parcelDue',
        '{name} is coming, {how}.',
        {'name': i.text, 'how': i.detail!.toLowerCase()},
      ),
      BriefKind.reminder when at != null => tr(
        'brief.say.reminderAt',
        'At {time}, a reminder: {what}.',
        {'time': saidTime(at), 'what': i.text},
      ),
      BriefKind.reminder => tr('brief.say.reminder', 'A reminder: {what}.', {
        'what': i.text,
      }),
      BriefKind.timer => tr(
        'brief.say.timer',
        'The {name} timer ends at {time}.',
        {'name': i.text.toLowerCase(), 'time': saidTime(at!)},
      ),
      _ when at != null => tr('brief.say.at', 'At {time}, {what}.', {
        'time': saidTime(at),
        'what': i.text,
      }),
      _ => '${i.text}.',
    };
  }
}

/// A time as said: "3 pm", "10:15 am", "midday", "midnight".
String saidTime(DateTime t) {
  if (t.minute == 0 && t.hour == 12) return tr('brief.say.midday', 'midday');
  if (t.minute == 0 && t.hour == 0) return tr('brief.say.midnight', 'midnight');
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final half = t.hour < 12 ? 'am' : 'pm';
  return t.minute == 0 ? '$h $half' : '$h:${two(t.minute)} $half';
}

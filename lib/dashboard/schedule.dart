import 'package:flutter/foundation.dart';

/// When something is shown: between two times of day, on some days.
///
/// Empty times mean all day; empty days mean every day. A window that ends
/// before it starts runs past midnight — 22:00 to 06:30 is the night — and
/// then the days are the days it starts on, so "weekdays, 22:00 to 06:30"
/// covers Friday night into Saturday morning, as anyone would mean it.
@immutable
class Schedule {
  const Schedule({this.from = '', this.to = '', this.days = ''});

  final String from;
  final String to;

  /// "daily", "weekdays", "weekends", or days like "Mon Wed Fri".
  final String days;

  static const always = Schedule();

  bool get isAlways =>
      _minutes(from) == null && _minutes(to) == null && _everyDay;

  bool get _everyDay {
    final d = days.trim().toLowerCase();
    return d.isEmpty || d == 'daily' || d == 'every day';
  }

  static int? _minutes(String hhmm) {
    final m = RegExp(r'^\s*(\d{1,2})[:.](\d{2})\s*$').firstMatch(hhmm);
    if (m == null) return null;
    final h = int.parse(m[1]!), min = int.parse(m[2]!);
    if (h > 24 || min > 59) return null;
    return h * 60 + min;
  }

  static const _names = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  bool _onDay(int weekday) {
    if (_everyDay) return true;
    final d = days.trim().toLowerCase();
    if (d == 'weekdays') return weekday <= 5;
    if (d == 'weekends') return weekday >= 6;
    return RegExp(
      r'[a-z]{3}',
    ).allMatches(d).map((m) => m[0]!).contains(_names[weekday - 1]);
  }

  /// Whether this is showing at [now].
  bool activeAt(DateTime now) {
    final start = _minutes(from), end = _minutes(to);
    final t = now.hour * 60 + now.minute;
    if (start == null && end == null) return _onDay(now.weekday);
    final s = start ?? 0, e = end ?? 24 * 60;
    if (s <= e) return _onDay(now.weekday) && t >= s && t < e;
    // Past midnight: the evening part belongs to today, the early-morning
    // part to the day before.
    if (t >= s) return _onDay(now.weekday);
    if (t < e) return _onDay(now.subtract(const Duration(days: 1)).weekday);
    return false;
  }

  /// "Weekdays 06:00–09:00", "Every day", for the editor and the panel.
  String describe() {
    final d = _everyDay ? '' : days.trim();
    final hasTime = _minutes(from) != null || _minutes(to) != null;
    final time = hasTime
        ? '${_minutes(from) == null ? '00:00' : from.trim()}–${_minutes(to) == null ? '24:00' : to.trim()}'
        : '';
    if (d.isEmpty && time.isEmpty) return 'Always';
    return [if (d.isNotEmpty) d, if (time.isNotEmpty) time].join(' ');
  }

  static Schedule fromJson(Object? j) {
    if (j is! Map) return always;
    return Schedule(
      from: '${j['from'] ?? ''}',
      to: '${j['to'] ?? ''}',
      days: '${j['days'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {'from': from, 'to': to, 'days': days};
}

/// A page's own settings: a name, and when it is shown.
@immutable
class DashboardPage {
  const DashboardPage({this.name = '', this.schedule = Schedule.always});

  final String name;
  final Schedule schedule;

  static DashboardPage fromJson(Object? j) => j is Map
      ? DashboardPage(
          name: '${j['name'] ?? ''}'.trim(),
          schedule: Schedule.fromJson(j['schedule']),
        )
      : const DashboardPage();

  Map<String, dynamic> toJson() => {
    'name': name,
    'schedule': schedule.toJson(),
  };
}

/// Which of [count] pages are showing at [now]: those with no schedule, and
/// those whose schedule is on. If every page is scheduled and none is on,
/// all of them — an empty dashboard is never the right answer.
List<int> visiblePages(int count, List<DashboardPage> pages, DateTime now) {
  Schedule of(int i) => i < pages.length ? pages[i].schedule : Schedule.always;
  final shown = [
    for (var i = 0; i < count; i++)
      if (of(i).isAlways || of(i).activeAt(now)) i,
  ];
  return shown.isEmpty ? [for (var i = 0; i < count; i++) i] : shown;
}

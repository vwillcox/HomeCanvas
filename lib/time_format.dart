/// Times as the panel writes them, the same everywhere.
library;

/// [n] as two figures: "07".
String two(int n) => n.toString().padLeft(2, '0');

/// A time of day on the 24-hour clock: "07:05".
String hhmm(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

/// How far into a video, or how long one is: "04:09", or "1:02:09" past
/// the hour.
String playTime(Duration d) {
  final h = d.inHours;
  final m = two(d.inMinutes.remainder(60));
  final s = two(d.inSeconds.remainder(60));
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// A day as the ISO date APIs and saved files want: "2026-10-24".
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';

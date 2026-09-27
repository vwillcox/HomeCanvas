/// Times as the panel writes them, the same everywhere.
library;

String _two(int n) => n.toString().padLeft(2, '0');

/// A time of day on the 24-hour clock: "07:05".
String hhmm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// How far into a video, or how long one is: "04:09", or "1:02:09" past
/// the hour.
String playTime(Duration d) {
  final h = d.inHours;
  final m = _two(d.inMinutes.remainder(60));
  final s = _two(d.inSeconds.remainder(60));
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// When a parcel is coming, as a carrier puts it in an email or a text.
///
/// [from] is the day, at the start of the window if there is one, or at
/// midnight if there is only a day — "due Thursday". [to] is the end of the
/// window: "between 10:15 and 11:15", or alone, "by 10pm", with [from] at
/// midnight. This is the shape of `Parcel.expected` and `Parcel.expectedTo`.
typedef DeliveryWindow = ({DateTime from, DateTime? to});

/// The delivery day and window in [text], if it says.
///
/// What UK carriers write, roughly: DPD's "will be delivered today between
/// 10:15 and 11:15", Evri's "arriving Wednesday 4th November, 9am-1pm",
/// Royal Mail's "due to be delivered on Tuesday 3 November", Amazon's
/// "Arriving tomorrow by 10pm", Yodel's "due for delivery on 03/11/2026
/// between 08:00 and 18:00".
///
/// Only the lines about the delivery are read — an email has an order date
/// in it, and a "sent on" — unless the whole of it is a line or two. Dates
/// are British: day first.
DeliveryWindow? findDeliveryWindow(String text, DateTime now) {
  final clean = text
      // A link's digits are its own business, not a time or a date.
      .replaceAll(RegExp(r'https?://\S+'), ' ')
      .replaceAll(RegExp('[\u2013\u2014\u2212]'), '-')
      .replaceAll('\u00a0', ' ');
  final lines = clean
      .split(RegExp(r'[\n\r]+|(?<=[.!?])\s+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  for (final line in lines) {
    if (!_aboutDelivery.hasMatch(line)) continue;
    final found = _read(line, now);
    if (found != null) return found;
  }
  // A text that is only a line or two is about the parcel by being sent
  // as one.
  return clean.length <= 160 ? _read(clean, now) : null;
}

final _aboutDelivery = RegExp(
  r'\b(deliver\w*|arriv\w*|due|expected|estimated|eta|slot|coming|out for|on its way|on the way|drop(?:ping)? off)\b',
  caseSensitive: false,
);

const _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

const _monthWord =
    r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';

const _days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/// A time of day: 10:15, 10.15, 9am, 9.30pm, noon.
const _time = r'(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?';

DeliveryWindow? _read(String s, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  DateTime? day;

  // A date beats a weekday: "Thursday 5 November" is the 5th whatever day
  // the 5th is.
  final named =
      RegExp(
        '\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?$_monthWord\\b\\.?(?:,?\\s+(\\d{4}))?',
        caseSensitive: false,
      ).firstMatch(s) ??
      RegExp(
        '\\b$_monthWord\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b(?:,?\\s+(\\d{4}))?',
        caseSensitive: false,
      ).firstMatch(s);
  if (named != null) {
    final dayFirst = RegExp(r'^\d').hasMatch(named[0]!);
    final d = int.parse(dayFirst ? named[1]! : named[2]!);
    final word = (dayFirst ? named[2]! : named[1]!).toLowerCase();
    final m = _months.indexOf(word.substring(0, 3)) + 1;
    day = _date(d, m, int.tryParse(named[3] ?? ''), today);
  }
  if (day == null) {
    final iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').firstMatch(s);
    if (iso != null) {
      day = _date(
        int.parse(iso[3]!),
        int.parse(iso[2]!),
        int.parse(iso[1]!),
        today,
      );
    }
  }
  if (day == null) {
    final numeric = RegExp(
      r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b',
    ).firstMatch(s);
    if (numeric != null) {
      var y = int.tryParse(numeric[3] ?? '');
      if (y != null && y < 100) y += 2000;
      day = _date(int.parse(numeric[1]!), int.parse(numeric[2]!), y, today);
    }
  }
  if (day == null) {
    if (RegExp(r'\b(today|tonight)\b', caseSensitive: false).hasMatch(s)) {
      day = today;
    } else if (RegExp(r'\btomorrow\b', caseSensitive: false).hasMatch(s)) {
      day = today.add(const Duration(days: 1));
    } else {
      // Whole names only: "sun" and "sat" are words of their own.
      final weekday = RegExp(
        r'\b(mon|tues|wednes|thurs|fri|satur|sun)day\b',
        caseSensitive: false,
      ).firstMatch(s);
      if (weekday != null) {
        final want =
            _days.indexOf(weekday[1]!.toLowerCase().substring(0, 3)) + 1;
        // "Arriving Tuesday" on a Tuesday is today.
        day = today.add(Duration(days: (want - now.weekday) % 7));
      }
    }
  }

  final window = _window(s);
  if (day == null && window == null) return null;
  final on = day ?? today;
  if (window == null) return (from: on, to: null);
  final (start, end) = window;
  return (
    from: start == null ? on : on.add(Duration(minutes: start)),
    to: on.add(Duration(minutes: end)),
  );
}

/// Day [d] of month [m] — this year's unless [y] says, or next year's if
/// this year's went more than a week ago (an email about January, read in
/// December).
DateTime? _date(int d, int m, int? y, DateTime today) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  var date = DateTime(y ?? today.year, m, d);
  if (date.month != m) return null;
  if (y == null && today.difference(date).inDays > 7) {
    date = DateTime(today.year + 1, m, d);
  }
  return date;
}

/// The window in [s] as minutes into the day: a start and an end, or only
/// an end ("by 10pm").
(int?, int)? _window(String s) {
  int? minutes(String? h, String? m, String? half) {
    if (h == null) return null;
    var hour = int.parse(h);
    final min = int.tryParse(m ?? '') ?? 0;
    final p = (half ?? '').toLowerCase().replaceAll('.', '');
    if (p == 'pm' && hour < 12) hour += 12;
    if (p == 'am' && hour == 12) hour = 0;
    if (hour > 23 || min > 59) return null;
    return hour * 60 + min;
  }

  final span = RegExp(
    '\\b(?:between\\s+|from\\s+)?$_time\\s*(?:-|to|until|till|and)\\s*$_time',
    caseSensitive: false,
  );
  for (final m in span.allMatches(s)) {
    final firstHasClock = m[2] != null || m[3] != null;
    final secondHasClock = m[5] != null || m[6] != null;
    // Both bare numbers is a date or a count, not a time: "3-5 days".
    if (!firstHasClock && !secondHasClock) continue;
    // "9-1pm": the first takes the second's half of the day, unless that
    // would put it after the end — then it is the morning.
    var half1 = m[3];
    if (half1 == null && m[6] != null && m[2] == null) {
      final asSecond = minutes(m[1], null, m[6]);
      final end = minutes(m[4], m[5], m[6]);
      half1 = asSecond != null && end != null && asSecond < end ? m[6] : 'am';
    }
    final from = minutes(m[1], m[2], half1);
    final to = minutes(m[4], m[5], m[6]);
    if (from != null && to != null && to > from) return (from, to);
  }

  final by = RegExp(
    '\\b(?:by|before)\\s+(?:(noon|midday)|$_time)',
    caseSensitive: false,
  ).firstMatch(s);
  if (by != null) {
    if (by[1] != null) return (null, 12 * 60);
    // "by 8" alone is likelier a date than a time.
    if (by[3] == null && by[4] == null) return null;
    final to = minutes(by[2], by[3], by[4]);
    if (to != null) return (null, to);
  }
  return null;
}

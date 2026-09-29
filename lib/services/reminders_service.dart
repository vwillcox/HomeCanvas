import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Something to be reminded of, and when.
@immutable
class Reminder {
  const Reminder({
    required this.id,
    required this.text,
    required this.from,
    required this.created,
    this.due,
    this.allDay = false,
    this.fired = false,
  });

  final String id;

  /// What to do: "put the bins out".
  final String text;

  /// Who sent it, from the phone app.
  final String from;
  final DateTime created;

  /// When; null for "some time".
  final DateTime? due;

  /// A day was given but no time: due from the morning.
  final bool allDay;

  /// Already announced.
  final bool fired;

  Reminder copyWith({bool? fired}) => Reminder(
    id: id,
    text: text,
    from: from,
    created: created,
    due: due,
    allDay: allDay,
    fired: fired ?? this.fired,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'from': from,
    'created': created.toUtc().toIso8601String(),
    if (due != null) 'due': due!.toUtc().toIso8601String(),
    'allDay': allDay,
    'fired': fired,
  };

  static Reminder? fromJson(Object? j) {
    if (j is! Map) return null;
    final text = '${j['text'] ?? ''}'.trim();
    final created = DateTime.tryParse('${j['created'] ?? ''}');
    if (text.isEmpty || created == null) return null;
    return Reminder(
      id: '${j['id'] ?? created.microsecondsSinceEpoch}',
      text: text,
      from: '${j['from'] ?? ''}'.trim(),
      created: created.toLocal(),
      due: DateTime.tryParse('${j['due'] ?? ''}')?.toLocal(),
      allDay: j['allDay'] == true,
      fired: j['fired'] == true,
    );
  }
}

/// What a shared message asks to be reminded of, if it asks at all.
typedef ParsedReminder = ({String what, DateTime? due, bool allDay});

/// Reads [text] as a reminder — "Remind me to call Mum at 6pm",
/// "Reminder: dentist tomorrow at 9:30", "Don't forget the bins tonight",
/// "Remember to water the plants on Saturday" — or null if it isn't one.
///
/// A short message with a clock time in it counts too, without the asking:
/// "Book taxi at 3pm".
///
/// Times understood: at 5pm, at 17:30, at 5.30pm, at noon, at midnight, in
/// 20 minutes, in 2 hours; days: today, tonight, this morning / afternoon /
/// evening, tomorrow (morning…), on Friday, next Friday, on 12/10, on the
/// 12th. A time with no day is today, or tomorrow once today's has passed;
/// a day with no time is due from nine that morning.
ParsedReminder? parseReminder(String text, DateTime now) {
  final trigger = RegExp(
    r"^\s*(?:please\s+)?(?:remind\s+(?:me|us|everyone|you|\w+)\s+(?:to|about|that)\s+|reminder\s*[:\-–—]\s*|don['’]?t\s+forget\s+(?:to\s+)?|remember\s+to\s+)",
    caseSensitive: false,
  );
  final m = trigger.firstMatch(text);
  // Without "remind me" and the like, a short message with a clock time in
  // it — "Book taxi at 3pm", "Call the school in 20 minutes" — is still one.
  // Not a question, and not a day alone: "The parcel came today" is news.
  final asked = m != null;
  var what = (asked ? text.substring(m.end) : text).trim();
  if (what.isEmpty) return null;
  if (!asked &&
      (what.contains('?') || what.split(RegExp(r'\s+')).length > 15)) {
    return null;
  }

  DateTime? day;
  int? hour, minute;
  Duration? after;
  var defaultHour = 9;

  // Each phrase found is taken out of what's left, so "at 6pm" doesn't
  // stay in the reminder's words.
  String? take(RegExp re, void Function(RegExpMatch m) use) {
    final found = re.firstMatch(what);
    if (found == null) return null;
    use(found);
    what = '${what.substring(0, found.start)} ${what.substring(found.end)}'
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    return found[0];
  }

  final today = DateTime(now.year, now.month, now.day);

  take(
    RegExp(r'\bin\s+(\d+)\s*(minutes?|mins?|hours?|hrs?)\b', caseSensitive: false),
    (m) {
      final n = int.parse(m[1]!);
      after = m[2]!.toLowerCase().startsWith('h')
          ? Duration(hours: n)
          : Duration(minutes: n);
    },
  );

  take(RegExp(r'\b(?:at\s+)?(noon|midday|midnight)\b', caseSensitive: false), (m) {
    hour = m[1]!.toLowerCase() == 'midnight' ? 0 : 12;
    minute = 0;
  });
  take(
    RegExp(
      r'\bat\s+(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?(?![\d/])',
      caseSensitive: false,
    ),
    (m) {
      var h = int.parse(m[1]!);
      final min = int.tryParse(m[2] ?? '') ?? 0;
      final half = (m[3] ?? '').toLowerCase().replaceAll('.', '');
      if (half == 'pm' && h < 12) h += 12;
      if (half == 'am' && h == 12) h = 0;
      // "at 6" with no am/pm, early in the day's reckoning, means evening.
      if (half.isEmpty && h >= 1 && h <= 6) h += 12;
      if (h <= 23 && min <= 59) {
        hour = h;
        minute = min;
      }
    },
  );

  take(
    RegExp(
      r'\b(this\s+morning|this\s+afternoon|this\s+evening|tonight|today)\b',
      caseSensitive: false,
    ),
    (m) {
      day = today;
      final w = m[1]!.toLowerCase();
      if (w.contains('morning')) defaultHour = 9;
      if (w.contains('afternoon')) defaultHour = 14;
      if (w.contains('evening') || w == 'tonight') defaultHour = 19;
    },
  );
  take(
    RegExp(r'\btomorrow(?:\s+(morning|afternoon|evening|night))?\b', caseSensitive: false),
    (m) {
      day = today.add(const Duration(days: 1));
      defaultHour = switch ((m[1] ?? '').toLowerCase()) {
        'afternoon' => 14,
        'evening' || 'night' => 19,
        _ => 9,
      };
    },
  );
  const weekdays = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
  ];
  take(
    RegExp(
      r'\b(?:on\s+|next\s+|this\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
      caseSensitive: false,
    ),
    (m) {
      final want = weekdays.indexOf(m[1]!.toLowerCase()) + 1;
      var ahead = (want - now.weekday) % 7;
      // "Friday" on a Friday means next week's; "next Friday" always does.
      if (ahead == 0 || m[0]!.toLowerCase().startsWith('next')) {
        ahead = ahead == 0 ? 7 : ahead;
      }
      day = today.add(Duration(days: ahead));
    },
  );
  // 12/10 — day first, this being a British panel — or 12/10/2026.
  take(
    RegExp(r'\b(?:on\s+)?(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b', caseSensitive: false),
    (m) {
      final d = int.parse(m[1]!), mo = int.parse(m[2]!);
      var y = int.tryParse(m[3] ?? '') ?? now.year;
      if (y < 100) y += 2000;
      final date = DateTime(y, mo, d);
      if (date.month == mo && date.day == d) {
        // Without a year, a date already gone this year is next year's.
        day = m[3] == null && date.isBefore(today) ? DateTime(y + 1, mo, d) : date;
      }
    },
  );
  take(RegExp(r'\bon\s+the\s+(\d{1,2})(?:st|nd|rd|th)\b', caseSensitive: false), (m) {
    final d = int.parse(m[1]!);
    var date = DateTime(now.year, now.month, d);
    if (date.day != d) return;
    if (date.isBefore(today)) date = DateTime(now.year, now.month + 1, d);
    day = date;
  });

  if (!asked && hour == null && after == null) return null;

  // Whatever is left, tidied: no dangling "on"/"at", no full stop.
  what = what
      .replaceAll(RegExp(r'\s+(on|at|by|for)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[\s.!,;:]+$'), '')
      .trim();
  if (what.isEmpty) return null;
  what = what[0].toUpperCase() + what.substring(1);

  if (after != null) return (what: what, due: now.add(after!), allDay: false);
  if (hour != null) {
    var due = DateTime(
      (day ?? today).year,
      (day ?? today).month,
      (day ?? today).day,
      hour!,
      minute ?? 0,
    );
    if (day == null && !due.isAfter(now)) due = due.add(const Duration(days: 1));
    return (what: what, due: due, allDay: false);
  }
  if (day != null) {
    final due = DateTime(day!.year, day!.month, day!.day, defaultHour);
    // "Tonight" said at nine at night is now, not tomorrow.
    return (
      what: what,
      due: due.isBefore(now) && day == today ? now : due,
      allDay: defaultHour == 9,
    );
  }
  return (what: what, due: null, allDay: false);
}

/// Reminders sent from the phone app: kept on disk, announced on the panel
/// when they fall due, and shown by the Reminders widget until dismissed.
class RemindersService extends ChangeNotifier {
  RemindersService({String? file, DateTime Function()? clock, this.persist = true})
    : _file = File(file ?? defaultFile()),
      _clock = clock ?? DateTime.now;

  final bool persist;
  final File _file;
  final DateTime Function() _clock;
  List<Reminder> _items = [];
  int _seq = 0;
  Timer? _timer;

  /// Told when a reminder falls due — to wake the screen and say it.
  void Function(Reminder reminder)? onDue;

  static String defaultFile() {
    final home = Platform.environment['HOME'] ?? '.';
    return p.join(home, '.config', 'homecanvas', 'reminders.json');
  }

  static const maxReminders = 50;

  /// Soonest first; those with no time after, newest first.
  List<Reminder> get reminders => List.unmodifiable(_items);

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final data = jsonDecode(await _file.readAsString());
      if (data is! List) return;
      _items = [for (final j in data) ?Reminder.fromJson(j)];
      _tidy();
      notifyListeners();
    } catch (e) {
      debugPrint('Reminders: could not read ${_file.path}: $e');
    }
  }

  /// Checks twice a minute for any that have fallen due.
  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Reminder add(ParsedReminder r, {String from = ''}) {
    final now = _clock();
    final reminder = Reminder(
      id: '${now.microsecondsSinceEpoch}-${++_seq}',
      text: r.what.length > 200 ? '${r.what.substring(0, 199)}…' : r.what,
      from: from.trim(),
      created: now,
      due: r.due,
      allDay: r.allDay,
    );
    _items.add(reminder);
    _tidy();
    notifyListeners();
    unawaited(_save());
    return reminder;
  }

  bool remove(String id) {
    final before = _items.length;
    _items.removeWhere((r) => r.id == id);
    if (_items.length == before) return false;
    notifyListeners();
    unawaited(_save());
    return true;
  }

  /// Announces whatever has fallen due and not been announced.
  @visibleForTesting
  void check() {
    final now = _clock();
    var changed = false;
    for (var i = 0; i < _items.length; i++) {
      final r = _items[i];
      if (r.fired || r.due == null || r.due!.isAfter(now)) continue;
      _items[i] = r.copyWith(fired: true);
      changed = true;
      onDue?.call(r);
    }
    if (changed) {
      _tidy();
      notifyListeners();
      unawaited(_save());
    }
  }

  /// Sorted, and cleared of the stale: announced ones a day after they
  /// fell due, undated ones after a month, and never more than fifty.
  void _tidy() {
    final now = _clock();
    _items = _items.where((r) {
      if (r.due != null) {
        return r.due!.isAfter(now.subtract(const Duration(days: 1)));
      }
      return r.created.isAfter(now.subtract(const Duration(days: 30)));
    }).toList()
      ..sort((a, b) {
        if (a.due == null && b.due == null) return b.created.compareTo(a.created);
        if (a.due == null) return 1;
        if (b.due == null) return -1;
        return a.due!.compareTo(b.due!);
      });
    if (_items.length > maxReminders) _items = _items.sublist(0, maxReminders);
  }

  Future<void> _saving = Future.value();
  Future<void> get saved => _saving;

  Future<void> _save() =>
      persist ? _saving = _saving.then((_) => _write()) : _saving;

  Future<void> _write() async {
    try {
      await _file.parent.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode([for (final r in _items) r.toJson()]));
      await tmp.rename(_file.path);
    } catch (e) {
      debugPrint('Reminders: could not save: $e');
    }
  }
}

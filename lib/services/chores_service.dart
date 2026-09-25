import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:path/path.dart' as p;

import 'bin_schedule.dart' show Bin, dateOnly;

/// A chore, as set up in the widget's settings.
@immutable
class Chore {
  const Chore({
    required this.task,
    this.emoji = '',
    this.who = '',
    this.days = 'daily',
    this.stars = 1,
  });

  final String task;
  final String emoji;

  /// A person's name, or empty for anyone.
  final String who;

  /// "daily", "weekdays", "weekends", or days like "Mon Wed Fri".
  final String days;
  final int stars;

  bool get anyone => who.trim().isEmpty || who.trim().toLowerCase() == 'anyone';

  /// A key that stays the same while the chore does, to record it by.
  String get key =>
      '${task.trim().toLowerCase()}|${anyone ? '*' : who.trim().toLowerCase()}';

  static Chore? fromRow(Map<String, dynamic> row) {
    final task = '${row['task'] ?? ''}'.trim();
    if (task.isEmpty) return null;
    return Chore(
      task: task,
      emoji: '${row['emoji'] ?? ''}'.trim(),
      who: '${row['who'] ?? ''}'.trim(),
      days: '${row['days'] ?? 'daily'}'.trim(),
      stars: (int.tryParse('${row['stars'] ?? 1}') ?? 1).clamp(0, 100),
    );
  }

  static const _names = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  /// Whether it is due on [day].
  bool dueOn(DateTime day) {
    final d = days.toLowerCase();
    if (d.isEmpty || d == 'daily' || d == 'every day') return true;
    if (d == 'weekdays') return day.weekday <= 5;
    if (d == 'weekends') return day.weekday >= 6;
    final wanted = RegExp(r'[a-z]{3}').allMatches(d).map((m) => m[0]!).toSet();
    return wanted.contains(_names[day.weekday - 1]);
  }
}

@immutable
class ChorePerson {
  const ChorePerson(this.name, this.colour);
  final String name;
  final Color colour;

  static ChorePerson? fromRow(Map<String, dynamic> row) {
    final name = '${row['name'] ?? ''}'.trim();
    if (name.isEmpty) return null;
    return ChorePerson(
      name,
      Bin.parseColour('${row['colour'] ?? ''}') ?? const Color(0xFFA6C8FF),
    );
  }
}

/// A chore done: when, by whom, and the stars it earned then.
@immutable
class Done {
  const Done({
    required this.board,
    required this.day,
    required this.chore,
    required this.person,
    required this.stars,
  });

  /// The widget it was done on, so two chore boards keep separate records.
  final String board;
  final DateTime day;
  final String chore;
  final String person;
  final int stars;

  Map<String, dynamic> toJson() => {
    'board': board,
    'day':
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
    'chore': chore,
    'person': person,
    'stars': stars,
  };

  static Done? fromJson(Object? j) {
    if (j is! Map) return null;
    final day = DateTime.tryParse('${j['day'] ?? ''}');
    if (day == null) return null;
    return Done(
      board: '${j['board'] ?? ''}',
      day: dateOnly(day),
      chore: '${j['chore'] ?? ''}',
      person: '${j['person'] ?? ''}',
      stars: (j['stars'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The Monday a week starts on.
DateTime weekStart(DateTime day) =>
    dateOnly(day).subtract(Duration(days: day.weekday - 1));

/// Which chores are done, and the week's stars. Kept in a file beside the
/// config, so a restart does not lose a week's work.
class ChoresService extends ChangeNotifier {
  ChoresService({String? file, DateTime Function()? clock, this.persist = true})
    : _file = File(file ?? defaultFile()),
      _clock = clock ?? DateTime.now;

  static String defaultFile() {
    final home = Platform.environment['HOME'] ?? '.';
    return p.join(home, '.config', 'immich_kiosk_pi', 'chores.json');
  }

  /// Weeks of history kept; older ones are dropped.
  static const keepWeeks = 8;

  final bool persist;
  final File _file;
  final DateTime Function() _clock;
  List<Done> _log = [];

  DateTime get today => dateOnly(_clock());

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final data = jsonDecode(await _file.readAsString());
      if (data is List) _log = [for (final j in data) ?Done.fromJson(j)];
      notifyListeners();
    } catch (e) {
      debugPrint('Chores: could not read ${_file.path}: $e');
    }
  }

  /// Who did [chore] today on [board], or null if nobody yet.
  String? doneBy(String board, Chore chore) {
    final d = today;
    for (final x in _log) {
      if (x.board == board && x.chore == chore.key && x.day == d) {
        return x.person;
      }
    }
    return null;
  }

  /// Ticks [chore] as done by [person] today, or unticks it if they had.
  /// Someone else's tick is left alone — tapping a chore your sister did
  /// does not take her star away.
  void toggle(String board, Chore chore, String person) {
    final d = today;
    final i = _log.indexWhere(
      (x) => x.board == board && x.chore == chore.key && x.day == d,
    );
    if (i >= 0) {
      if (_log[i].person != person) return;
      _log.removeAt(i);
    } else {
      _log.add(
        Done(
          board: board,
          day: d,
          chore: chore.key,
          person: person,
          stars: chore.stars,
        ),
      );
    }
    final cutoff = weekStart(d).subtract(const Duration(days: 7 * keepWeeks));
    _log.removeWhere((x) => x.day.isBefore(cutoff));
    notifyListeners();
    unawaited(_save());
  }

  /// Stars [person] has earned on [board] this week, Monday onwards.
  int starsThisWeek(String board, String person) {
    final from = weekStart(today);
    return _log
        .where(
          (x) =>
              x.board == board && x.person == person && !x.day.isBefore(from),
        )
        .fold(0, (n, x) => n + x.stars);
  }

  Future<void> _saving = Future.value();
  Future<void> get saved => _saving;

  Future<void> _save() =>
      persist ? _saving = _saving.then((_) => _write()) : _saving;

  Future<void> _write() async {
    try {
      await _file.parent.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode([for (final x in _log) x.toJson()]));
      await tmp.rename(_file.path);
    } catch (e) {
      debugPrint('Chores: could not save: $e');
    }
  }
}

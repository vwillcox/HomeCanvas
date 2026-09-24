import 'package:flutter/material.dart';

/// One kind of bin and when it goes: from a first collection, every so many
/// weeks.
///
/// Set once, from the council's calendar. That covers every council's
/// pattern this side of a bank-holiday shuffle, and needs no scraping of a
/// council website that changes its layout every other year.
@immutable
class Bin {
  const Bin({
    required this.name,
    required this.colour,
    required this.first,
    this.everyWeeks = 1,
  });

  final String name;
  final Color colour;
  final DateTime first;
  final int everyWeeks;

  /// From a row of the widget's settings; null when the row is not usable yet
  /// — no name, or a date that does not parse.
  static Bin? fromRow(Map<String, dynamic> row) {
    final name = '${row['name'] ?? ''}'.trim();
    final first = parseDay('${row['first'] ?? ''}');
    if (name.isEmpty || first == null) return null;
    final every =
        int.tryParse('${row['everyWeeks'] ?? 1}') ??
        (row['everyWeeks'] is num ? (row['everyWeeks'] as num).toInt() : 1);
    return Bin(
      name: name,
      colour: parseColour('${row['colour'] ?? ''}') ?? const Color(0xFF6B7280),
      first: first,
      everyWeeks: every.clamp(1, 52),
    );
  }

  /// The first collection on or after [day].
  DateTime nextOnOrAfter(DateTime day) {
    final d = dateOnly(day);
    if (!d.isAfter(first)) return first;
    final period = everyWeeks * 7;
    final since = daysBetween(first, d);
    final periods = (since + period - 1) ~/ period;
    return DateTime(first.year, first.month, first.day + periods * period);
  }

  /// Accepts 2026-10-01, 1/10/2026 and 01-10-2026 — the second two the way a
  /// British council letter writes them, day first.
  static DateTime? parseDay(String s) {
    final t = s.trim();
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(t);
    if (iso != null) {
      return _valid(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
    }
    final uk = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$').firstMatch(t);
    if (uk != null) {
      return _valid(int.parse(uk[3]!), int.parse(uk[2]!), int.parse(uk[1]!));
    }
    return null;
  }

  static DateTime? _valid(int y, int m, int d) {
    final date = DateTime(y, m, d);
    return date.month == m && date.day == d ? date : null;
  }

  static Color? parseColour(String s) {
    final hex = s.replaceFirst('#', '').trim();
    if (hex.length == 6) {
      final v = int.tryParse(hex, radix: 16);
      return v == null ? null : Color(0xFF000000 | v);
    }
    if (hex.length == 8) {
      final v = int.tryParse(hex, radix: 16);
      return v == null ? null : Color(v);
    }
    return null;
  }
}

DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// Whole calendar days from [a] to [b], counted on the calendar rather than
/// the clock, so a clocks-change weekend is still seven days long.
int daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// What the bins widget should be saying.
enum BinStage {
  /// Nothing to do yet: the next collection is some days off.
  later,

  /// The evening before: put them out.
  tonight,

  /// Collection day.
  today,
}

@immutable
class BinCollection {
  const BinCollection(this.day, this.bins, this.stage);

  final DateTime day;
  final List<Bin> bins;
  final BinStage stage;

  /// The next collection after [now], and whether it wants doing.
  ///
  /// Collection day counts as "today" until [collectedBy] o'clock — after
  /// that the lorry has been and the widget moves on to the next one. The
  /// evening before counts as "tonight" from [remindFrom] o'clock.
  static BinCollection? next(
    List<Bin> bins,
    DateTime now, {
    int remindFrom = 17,
    int collectedBy = 12,
  }) {
    if (bins.isEmpty) return null;
    var from = dateOnly(now);
    if (now.hour >= collectedBy) from = from.add(const Duration(days: 1));
    DateTime? soonest;
    for (final b in bins) {
      final d = b.nextOnOrAfter(from);
      if (soonest == null || d.isBefore(soonest)) soonest = d;
    }
    final day = soonest!;
    final due = [
      for (final b in bins)
        if (b.nextOnOrAfter(from) == day) b,
    ];
    final gap = daysBetween(now, day);
    final stage = gap == 0
        ? BinStage.today
        : (gap == 1 && now.hour >= remindFrom
              ? BinStage.tonight
              : BinStage.later);
    return BinCollection(day, due, stage);
  }

  /// "Rubbish and food", "Rubbish, recycling and food".
  String get names {
    final n = [for (final b in bins) b.name.toLowerCase()];
    if (n.length == 1) return n.first;
    return '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';
  }
}

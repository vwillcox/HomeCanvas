import 'dart:async';

import 'package:flutter/foundation.dart';

import '../dashboard/dashboard_model.dart';
import 'bin_schedule.dart';
import 'config_service.dart';

/// The bins widgets' memory and voice.
///
/// Remembers who has already put the bins out, so the reminder stops, and
/// speaks the reminder at the time a widget asks for — whether or not the
/// dashboard is showing, which is the point of a reminder.
class BinsService extends ChangeNotifier {
  BinsService(this._config, {this.speak, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ConfigService _config;
  final Future<void> Function(String text)? speak;
  final DateTime Function() _clock;

  Timer? _timer;

  /// Widget id → the collection day its bins were put out for.
  final Map<String, DateTime> _out = {};

  /// Widget id → the collection day it last spoke about.
  final Map<String, DateTime> _spoken = {};

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => check());
  }

  bool isOut(String widgetId, DateTime day) => _out[widgetId] == dateOnly(day);

  void toggleOut(String widgetId, DateTime day) {
    final d = dateOnly(day);
    if (_out[widgetId] == d) {
      _out.remove(widgetId);
    } else {
      _out[widgetId] = d;
    }
    notifyListeners();
  }

  /// The bins a widget has been told about.
  static List<Bin> binsOf(DashboardWidgetConfig w) => [
    for (final row in (w.options['bins'] as List? ?? const []))
      if (row is Map) ?Bin.fromRow(row.cast<String, dynamic>()),
  ];

  static int hourOption(DashboardWidgetConfig w, String key, int fallback) =>
      int.tryParse('${w.options[key] ?? fallback}') ?? fallback;

  /// Speaks any reminder that is due. Public so tests can step the clock.
  @visibleForTesting
  void check() {
    final now = _clock();
    for (final w in _config.config.dashboard.widgets) {
      if (w.type != 'bins') continue;
      final at = '${w.options['speakAt'] ?? ''}'.trim();
      final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(at);
      if (m == null) continue;
      final hour = int.parse(m[1]!), minute = int.parse(m[2]!);
      // Within the half-minute this runs on, so a reminder is not missed for
      // landing between two checks.
      final target = DateTime(now.year, now.month, now.day, hour, minute);
      final late = now.difference(target);
      if (late.isNegative || late > const Duration(minutes: 5)) continue;

      final next = BinCollection.next(
        binsOf(w),
        now,
        remindFrom: 0,
        collectedBy: hourOption(w, 'collectedBy', 12),
      );
      if (next == null) continue;
      if (daysBetween(now, next.day) != 1) continue; // only the night before
      if (_spoken[w.id] == next.day || isOut(w.id, next.day)) continue;
      _spoken[w.id] = next.day;
      final names = next.names;
      unawaited(
        speak?.call(
          'Tomorrow is bin day: $names. Remember to put ${next.bins.length == 1 ? 'it' : 'them'} out tonight.',
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

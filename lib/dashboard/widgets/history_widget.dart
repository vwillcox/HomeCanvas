import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// Something that happened on this date.
@immutable
class HistoryEvent {
  const HistoryEvent(this.year, this.text, {this.thumbnail});

  final int year;
  final String text;
  final String? thumbnail;

  /// Wikipedia's "selected" events for a day, the editors' own pick.
  static List<HistoryEvent> fromWikipedia(Map<String, dynamic> json) => [
    for (final e in (json['selected'] as List? ?? const []).whereType<Map>())
      if (e['year'] is num && '${e['text'] ?? ''}'.trim().isNotEmpty)
        HistoryEvent(
          (e['year'] as num).toInt(),
          '${e['text']}'.trim(),
          thumbnail:
              (((e['pages'] as List?)?.firstOrNull as Map?)?['thumbnail']
                      as Map?)?['source']
                  as String?,
        ),
  ];
}

/// On this day in history, from Wikipedia: one event at a time, with how
/// many years ago, changing every little while.
class HistoryWidget extends StatefulWidget {
  const HistoryWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  /// Events to show instead of asking Wikipedia, for tests.
  @visibleForTesting
  static List<HistoryEvent>? debugEvents;

  @override
  State<HistoryWidget> createState() => _HistoryWidgetState();
}

class _HistoryWidgetState extends State<HistoryWidget> {
  /// A day's events, fetched once and shared by every tile.
  static final Map<String, List<HistoryEvent>> _byDay = {};
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      // Wikimedia asks every client to say who it is.
      headers: {'User-Agent': 'ImmichKioskPi/1.0 (home dashboard)'},
    ),
  );

  List<HistoryEvent> _events = const [];
  int _index = 0;
  String? _error;
  Timer? _timer;

  String get _today {
    final n = DateTime.now();
    return '${n.month.toString().padLeft(2, '0')}/${n.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 25), (_) => _next());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final day = _today;
    var events = HistoryWidget.debugEvents ?? _byDay[day];
    if (events == null) {
      try {
        final r = await _dio.get(
          'https://api.wikimedia.org/feed/v1/wikipedia/en/onthisday/selected/$day',
        );
        events = HistoryEvent.fromWikipedia(
          (r.data as Map).cast<String, dynamic>(),
        );
        _byDay
          ..clear()
          ..[day] = events;
      } catch (e) {
        if (mounted) setState(() => _error = 'Could not reach Wikipedia');
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      // A different order each day, but the same all day across tiles.
      _events = [...events!]..shuffle(Random(day.hashCode));
      _index = 0;
      _error = null;
    });
  }

  void _next() {
    if (!mounted) return;
    if (_events.isNotEmpty &&
        _byDay.keys.firstOrNull != _today &&
        HistoryWidget.debugEvents == null) {
      unawaited(_load()); // a new day
      return;
    }
    if (_events.length > 1) {
      setState(() => _index = (_index + 1) % _events.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    if (_events.isEmpty) {
      return TileMessage(_error ?? 'Asking Wikipedia…', theme: t);
    }
    final e = _events[_index];
    final ago = DateTime.now().year - e.year;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _next,
      child: FitCanvas(
        designHeight: 130,
        maxScale: 3,
        builder: (context, size) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: Column(
            key: ValueKey(_index),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TileLabel(
                icon: Icons.history_edu_rounded,
                // Not "On this day": that is the photo memories' name.
                text: 'In history',
                theme: t,
                size: 11,
                trailing: Text(
                  '${_index + 1} of ${_events.length}',
                  style: TextStyle(color: t.textSecondary, fontSize: 9),
                ),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${e.year}',
                      style: TextStyle(
                        color: t.accent,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: ago > 0 ? '  $ago years ago' : '',
                      style: TextStyle(color: t.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
                maxLines: 1,
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  e.text,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final historyWidgetType = DashboardWidgetType(
  type: 'history',
  category: WidgetCategory.reference,
  name: 'On this day in history',
  description:
      'Something that happened on this date, from Wikipedia — a '
      'new one every half minute, or tap for the next.',
  glyph: '📜',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 2,
  fitsItself: true,
  preview: const [
    PreviewLine('1981', scale: 0.2, accent: true),
    PreviewLine(
      'Sandra Day O’Connor became the first woman on the US Supreme Court',
      scale: 0.1,
    ),
  ],
  build: (context, w) => HistoryWidget(w: w),
);

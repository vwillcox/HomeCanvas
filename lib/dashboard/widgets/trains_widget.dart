import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/trains_service.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// The next trains from your station, as a station board shows them: time,
/// where to, platform, and whether it is on time, late or cancelled.
class TrainsWidget extends StatefulWidget {
  const TrainsWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  /// A client to use instead of the real one, for tests.
  @visibleForTesting
  static TrainsClient? debugClient;

  @override
  State<TrainsWidget> createState() => _TrainsWidgetState();
}

class _TrainsWidgetState extends State<TrainsWidget> {
  late final TrainsClient _client = TrainsWidget.debugClient ?? TrainsClient();
  Board? _board;
  String? _error;
  DateTime? _updated;
  Timer? _timer;
  bool _busy = false;

  /// Last boards by what was asked, so a tile paged back to — or drawn for
  /// the editor's preview — has something to show at once.
  static final Map<String, (Board, DateTime)> _last = {};

  String _opt(String key) => '${widget.w.config.options[key] ?? ''}'.trim();
  String get _key => '${_opt('from')}>${_opt('to')}';

  @override
  void initState() {
    super.initState();
    final cached = _last[_key];
    if (cached != null) {
      _board = cached.$1;
      _updated = cached.$2;
    }
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void didUpdateWidget(covariant TrainsWidget old) {
    super.didUpdateWidget(old);
    final was =
        '${old.w.config.options['from']}>${old.w.config.options['to']}'
        '|${old.w.config.options['token']}';
    if (was != '$_key|${_opt('token')}') unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy || !mounted || _opt('from').isEmpty) return;
    _busy = true;
    final key = _key;
    try {
      final board = await _client.board(
        token: _opt('token'),
        from: _opt('from'),
        to: _opt('to'),
      );
      _last[key] = (board, DateTime.now());
      if (mounted) {
        setState(() {
          _board = board;
          _updated = DateTime.now();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _busy = false;
    }
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    if (_opt('from').isEmpty) {
      return TileMessage(
        'Set your station in the widget settings — its three-letter code, '
        'like MDE for Maidstone East — and your Realtime Trains token.',
        theme: t,
      );
    }
    final board = _board;
    if (board == null) {
      return TileMessage(_error ?? 'Asking Realtime Trains…', theme: t);
    }
    final now = DateTime.now();
    final walk = int.tryParse(_opt('walkMinutes')) ?? 0;
    // Gone already, or leaving sooner than you could get there.
    final catchable = board.departures
        .where(
          (d) =>
              d.leaves.isAfter(now.add(Duration(minutes: walk))) ||
              (d.cancelled && d.scheduled.isAfter(now)),
        )
        .toList();
    final max = (int.tryParse(_opt('rows')) ?? 4).clamp(1, 10);
    final status = StatusColours.of(t);
    final to = _opt('toName').isNotEmpty ? _opt('toName') : _opt('to');
    final title = [
      board.station.isEmpty ? _opt('from').toUpperCase() : board.station,
      if (to.isNotEmpty) to,
    ].join(' → ');

    return LayoutBuilder(
      builder: (context, c) {
        // As many rows as fit at a readable size, up to the number asked for.
        final fit = ((c.maxHeight - 30) / 52).floor().clamp(1, max);
        final rows = catchable.take(fit).toList();
        return FitCanvas(
          designHeight: 26.0 + 44 * (rows.isEmpty ? 1 : rows.length),
          maxScale: 3,
          builder: (context, size) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TileLabel(
                icon: Icons.train_outlined,
                text: title,
                theme: t,
                size: 11,
                trailing: _updated == null
                    ? null
                    : Text(
                        _error != null
                            ? 'last at ${_hm(_updated!)}'
                            : _hm(_updated!),
                        style: TextStyle(
                          color: _error != null ? status.warn : t.textSecondary,
                          fontSize: 10,
                        ),
                      ),
              ),
              const SizedBox(height: 4),
              if (rows.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      'No more trains in the next two hours',
                      style: TextStyle(color: t.textSecondary, fontSize: 13),
                    ),
                  ),
                )
              else
                for (final d in rows)
                  Expanded(
                    child: _Row(d: d, theme: t, status: status),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.d, required this.theme, required this.status});

  final Departure d;
  final DashboardTheme theme;
  final StatusColours status;

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final (String text, Color colour) = d.cancelled
        ? ('Cancelled', status.bad)
        : d.late
        ? ('${d.lateMinutes} min late', status.warn)
        : d.atPlatform
        ? ('At platform', theme.accent)
        : ('On time', status.good);
    final sub = [
      if (d.late && d.expected != null) 'expected ${_hm(d.expected!)}',
      if (d.bus) 'replacement bus',
      if ((d.cancelled || d.late) && d.reason != null) d.reason!,
    ].join(' · ');

    return Row(
      children: [
        Text(
          _hm(d.scheduled),
          style: TextStyle(
            color: d.cancelled ? theme.textSecondary : theme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            decoration: d.cancelled ? TextDecoration.lineThrough : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.destination,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.textPrimary, fontSize: 14),
              ),
              if (sub.isNotEmpty)
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: d.late ? status.warn : theme.textSecondary,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Platform and status shrink together before crowding the row.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (d.platform != null && !d.cancelled) ...[
                  StatusChip(
                    text: 'Plat ${d.platform}',
                    colour: theme.accent,
                    size: 10,
                  ),
                  const SizedBox(width: 4),
                ],
                StatusChip(text: text, colour: colour, size: 10),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

final trainsWidgetType = DashboardWidgetType(
  type: 'trains',
  category: WidgetCategory.gettingOut,
  name: 'Train departures',
  description:
      'The next trains from your station, like the board on the '
      'platform: time, where to, platform, and whether it is on time. From '
      'Realtime Trains — it needs a free token from api-portal.rtt.io.',
  glyph: '🚆',
  defaultWidth: 5,
  defaultHeight: 3,
  minWidth: 3,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'from',
      label: 'From (station code)',
      defaultValue: '',
      help:
          'Three letters, as on a ticket: MDE for Maidstone East, COL for '
          'Colchester.',
    ),
    WidgetOption(
      key: 'to',
      label: 'Going to (station code)',
      defaultValue: '',
      help: 'Optional: only trains that call there.',
    ),
    WidgetOption(
      key: 'toName',
      label: 'Call it',
      defaultValue: '',
      help:
          'What to show for where you are going — London, Victoria. Leave '
          'empty for the code.',
    ),
    WidgetOption(
      key: 'walkMinutes',
      label: 'Minutes to get to the station',
      kind: OptionKind.number,
      defaultValue: 0,
      help:
          'Trains leaving sooner than this are left off — you would not '
          'make them.',
    ),
    WidgetOption(
      key: 'rows',
      label: 'Trains to show, at most',
      kind: OptionKind.number,
      defaultValue: 4,
    ),
    WidgetOption(
      key: 'token',
      label: 'Realtime Trains token',
      kind: OptionKind.secret,
      defaultValue: '',
      help:
          'Sign in at api-portal.rtt.io, request a token, and paste it '
          'here. Either kind it issues works.',
    ),
  ],
  preview: const [
    PreviewLine('07:48  London Victoria   On time', scale: 0.13),
    PreviewLine('08:12  London Victoria   7 min late', scale: 0.13),
    PreviewLine('08:48  London Victoria   Cancelled', scale: 0.13, muted: true),
  ],
  build: (context, w) => TrainsWidget(w: w),
);

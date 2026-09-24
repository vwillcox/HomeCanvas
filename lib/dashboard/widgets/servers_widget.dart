import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/system_stats.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// CPU, memory, disk and temperature for this Pi and any other machine
/// running Glances, with whether their containers are all up.
///
/// Polls only while it is on screen: nothing here is worth watching when
/// nobody is looking.
class ServersWidget extends StatefulWidget {
  const ServersWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  /// Figures to show instead of reading any machine, for tests.
  @visibleForTesting
  static List<MachineStats>? debugStats;

  @override
  State<ServersWidget> createState() => _ServersWidgetState();
}

class _ServersWidgetState extends State<ServersWidget> {
  final LocalStats _local = LocalStats();
  final Map<String, GlancesClient> _clients = {};
  List<MachineStats> _stats = const [];

  /// The last readings, by what was asked for, shared by every Servers tile.
  /// A tile paged back to — or drawn for the editor's preview — shows these
  /// at once rather than "Reading…" while it asks again.
  static final Map<String, List<MachineStats>> _last = {};

  String get _cacheKey => [
    _showThisPi,
    widget.w.option('thisPiName', ''),
    for (final m in _machines) '${m.name}@${m.address}',
  ].join('|');
  Timer? _timer;
  Timer? _second;
  bool _busy = false;

  bool get _showThisPi => widget.w.option('showThisPi', true);

  List<({String name, String address})> get _machines => [
    for (final row
        in (widget.w.config.options['machines'] as List? ?? const []))
      if (row is Map && '${row['address'] ?? ''}'.trim().isNotEmpty)
        (
          name: '${row['name'] ?? ''}'.trim().isEmpty
              ? '${row['address']}'.trim()
              : '${row['name']}'.trim(),
          address: '${row['address']}'.trim(),
        ),
  ];

  @override
  void initState() {
    super.initState();
    _stats = _last[_cacheKey] ?? const [];
    unawaited(_poll());
    // A second reading soon after the first, so this Pi's CPU — which needs
    // two readings to work out — appears promptly rather than after a full
    // interval.
    _second = Timer(const Duration(seconds: 2), () => unawaited(_poll()));
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _second?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_busy || !mounted) return;
    final fixed = ServersWidget.debugStats;
    if (fixed != null) {
      setState(() => _stats = fixed);
      return;
    }
    _busy = true;
    try {
      final reads = <Future<MachineStats>>[
        if (_showThisPi)
          _local.read(
            widget.w.option('thisPiName', '').trim().isEmpty
                ? Platform.localHostname
                : widget.w.option('thisPiName', '').trim(),
          ),
        for (final m in _machines)
          _clients
              .putIfAbsent(m.address, () => GlancesClient(m.address))
              .read(m.name),
      ];
      final stats = await Future.wait(reads);
      _last[_cacheKey] = stats;
      if (mounted) setState(() => _stats = stats);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    if (!_showThisPi && _machines.isEmpty) {
      return TileMessage(
        'Add a machine in the widget settings. It needs Glances running — '
        'on CasaOS, from its app store.',
        theme: t,
      );
    }
    if (_stats.isEmpty) return TileMessage('Reading…', theme: t);

    final status = StatusColours.of(t);
    final down = _stats.where((s) => !s.reachable).length;
    final stopped = _stats.fold<int>(0, (n, s) => n + s.stopped);
    final failing = _stats
        .where((s) => s.worstDisk == DiskState.failing)
        .length;
    final warning = _stats
        .where((s) => s.worstDisk == DiskState.warning)
        .length;
    final chip = down > 0
        ? (text: '$down not answering', colour: status.bad)
        : failing > 0
        ? (text: 'Disk failing', colour: status.bad)
        : warning > 0
        ? (text: 'Disk warning', colour: status.warn)
        : stopped > 0
        ? (text: '$stopped stopped', colour: status.warn)
        : (text: 'All up', colour: status.good);

    return LayoutBuilder(
      builder: (context, c) {
        final labelH = (c.maxHeight * 0.1).clamp(18.0, 34.0);
        final gapY = labelH * 0.5;
        final bodyH = c.maxHeight - labelH - gapY;
        final grid = bestGrid(
          _stats.length,
          Size(c.maxWidth, bodyH),
          cellAspect: 1.05,
        );
        final space = c.maxWidth * 0.05;
        final cellW = (c.maxWidth - space * (grid.columns - 1)) / grid.columns;
        final cellH = (bodyH - space * (grid.rows - 1)) / grid.rows;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: labelH,
              child: TileLabel(
                icon: Icons.dns_rounded,
                text: 'Servers',
                theme: t,
                size: labelH * 0.6,
                trailing: StatusChip(
                  text: chip.text,
                  colour: chip.colour,
                  size: labelH * 0.5,
                ),
              ),
            ),
            SizedBox(height: gapY),
            SizedBox(
              height: bodyH,
              child: Stack(
                children: [
                  for (var i = 0; i < _stats.length; i++)
                    Positioned(
                      left: (i % grid.columns) * (cellW + space),
                      top: (i ~/ grid.columns) * (cellH + space),
                      width: cellW,
                      height: cellH,
                      child: _Machine(
                        stats: _stats[i],
                        theme: t,
                        status: status,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Machine extends StatelessWidget {
  const _Machine({
    required this.stats,
    required this.theme,
    required this.status,
  });

  final MachineStats stats;
  final DashboardTheme theme;
  final StatusColours status;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final sub = [
      if (s.uptime != null) 'up ${shortUptime(s.uptime!)}',
      if (s.temperature != null) '${s.temperature!.round()}°C',
    ].join(' · ');

    // At most three drives; past that the tile would be all disks.
    final disks = s.disks.take(3).toList();
    return FitCanvas(
      designHeight: 150 + 30.0 * (disks.length > 1 ? disks.length - 1 : 0),
      maxScale: 3,
      builder: (context, size) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            s.reachable ? sub : s.error!,
            maxLines: 1,
            style: TextStyle(
              color: s.reachable ? theme.textSecondary : status.bad,
              fontSize: 12,
            ),
          ),
          if (s.reachable) ...[
            const Spacer(),
            _Bar(label: 'CPU', value: s.cpu, theme: theme, status: status),
            const Spacer(),
            _Bar(
              label: 'Memory',
              value: s.memory,
              theme: theme,
              status: status,
            ),
            const Spacer(),
            if (disks.isEmpty)
              _Bar(label: 'Disk', value: s.disk, theme: theme, status: status)
            else
              for (var i = 0; i < disks.length; i++) ...[
                if (i > 0) const Spacer(),
                _disk(disks[i], single: disks.length == 1),
              ],
            if (s.containers != null && s.containers!.isNotEmpty) ...[
              const Spacer(),
              Text(
                s.stopped > 0
                    ? '${s.stopped} container${s.stopped == 1 ? '' : 's'} stopped'
                    : '${s.running} container${s.running == 1 ? '' : 's'} running',
                maxLines: 1,
                style: TextStyle(
                  color: s.stopped > 0 ? status.warn : theme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}

extension on _Machine {
  /// A drive's bar: how full, how big, and — where SMART is on — its health
  /// as a dot, with the temperature or whatever is wrong with it.
  Widget _disk(DiskUse d, {required bool single}) {
    final h = d.health;
    final dot = h == null
        ? null
        : switch (h.state) {
            DiskState.healthy => status.good,
            DiskState.warning => status.warn,
            DiskState.failing => status.bad,
          };
    final detail = [
      sizeOf(d.used, d.size),
      if (h != null && h.state != DiskState.healthy)
        h.concern
      else if (h?.temperature != null)
        '${h!.temperature!.round()}°C',
    ].join(' · ');
    return _Bar(
      label: single && d.mount == '/' ? 'Disk' : d.label,
      value: d.percent,
      theme: theme,
      status: status,
      detail: detail,
      dot: dot,
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.value,
    required this.theme,
    required this.status,
    this.detail,
    this.dot,
  });

  final String label;
  final double? value;
  final DashboardTheme theme;
  final StatusColours status;

  /// Said quietly after the label: "6.6 of 8 TB · 34°C".
  final String? detail;

  /// A drive's SMART health, as a coloured dot before the label.
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final colour = v == null
        ? theme.textSecondary
        : v >= 90
        ? status.bad
        : v >= 75
        ? status.warn
        : theme.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (dot != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
            ],
            // One text for the label and its detail, filling the row, so the
            // figure always sits at the right edge and the words give way
            // before it does.
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: label,
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (detail != null && detail!.isNotEmpty)
                      TextSpan(
                        text: '  $detail',
                        style: TextStyle(
                          color: theme.textSecondary.withValues(alpha: 0.75),
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              v == null ? '—' : '${v.round()}%',
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (v ?? 0) / 100,
            minHeight: 6,
            backgroundColor: theme.textSecondary.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation(colour),
          ),
        ),
      ],
    );
  }
}

final serversWidgetType = DashboardWidgetType(
  type: 'servers',
  name: 'Servers',
  description:
      'CPU, memory, disk and temperature for this Pi and your other '
      'machines, and whether their containers are running. Other machines '
      'need Glances — on CasaOS, one click in its app store.',
  glyph: '🖥️',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 2,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'showThisPi',
      label: 'Show this Pi',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'thisPiName',
      label: 'Call this Pi',
      defaultValue: '',
      help: 'Leave empty for its network name.',
    ),
    WidgetOption(
      key: 'machines',
      label: 'Other machines',
      kind: OptionKind.list,
      addLabel: 'Add a machine',
      help:
          'Where its Glances answers, such as casaos.local or '
          'http://10.0.0.76:61208. The port can be left off.',
      fields: [
        WidgetOption(key: 'name', label: 'Name', defaultValue: ''),
        WidgetOption(key: 'address', label: 'Address', defaultValue: ''),
      ],
    ),
  ],
  preview: const [
    PreviewLine('tabletpi', scale: 0.14),
    PreviewLine('CPU 23% · Memory 61% · Disk 38%', scale: 0.1),
    PreviewLine('up 11 d · 52°C', scale: 0.09, muted: true),
  ],
  build: (context, w) => ServersWidget(w: w),
);

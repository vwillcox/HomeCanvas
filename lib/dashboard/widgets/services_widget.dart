import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/service_checks.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'tile_bits.dart';

/// A light per thing that should be up: green, amber when slow, red when it
/// does not answer. Tap one to check it again — or, for a computer that is
/// asleep and has its network address given, to wake it.
class ServicesWidget extends StatefulWidget {
  const ServicesWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<ServicesWidget> createState() => _ServicesWidgetState();
}

class _ServicesWidgetState extends State<ServicesWidget> {
  static const _checker = ServiceChecker();
  final Map<String, CheckResult> _results = {};
  final Set<String> _waking = {};
  Timer? _timer;
  int _interval = 0;

  List<ServiceTarget> get _targets => [
    for (final row
        in (widget.w.config.options['services'] as List? ?? const []))
      if (row is Map) ?ServiceTarget.fromRow(row.cast<String, dynamic>()),
  ];

  int get _everySeconds =>
      (int.tryParse('${widget.w.config.options['everySeconds'] ?? 60}') ?? 60)
          .clamp(15, 3600);

  @override
  void initState() {
    super.initState();
    unawaited(_checkAll());
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant ServicesWidget old) {
    super.didUpdateWidget(old);
    if (_interval != _everySeconds) _restartTimer();
    // A target added in the editor is checked straight away rather than
    // waiting its turn.
    if (_targets.any((t) => !_results.containsKey(t.target))) {
      unawaited(_checkAll());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    _interval = _everySeconds;
    _timer = Timer.periodic(Duration(seconds: _interval), (_) => _checkAll());
  }

  Future<void> _checkAll() async {
    await Future.wait(_targets.map(_checkOne));
  }

  Future<void> _checkOne(ServiceTarget t) async {
    final r = await _checker.check(t);
    if (!mounted) return;
    setState(() {
      _results[t.target] = r;
      if (r.state != CheckState.down) _waking.remove(t.target);
    });
  }

  Future<void> _tapped(ServiceTarget t) async {
    final r = _results[t.target];
    if (r?.state == CheckState.down && t.mac != null) {
      setState(() => _waking.add(t.target));
      try {
        await ServiceChecker.wake(t.mac!);
      } catch (_) {}
      // A computer takes a while to wake; look again when it plausibly has.
      for (final wait in const [10, 25, 45]) {
        await Future<void>.delayed(Duration(seconds: wait));
        if (!mounted || !_waking.contains(t.target)) return;
        await _checkOne(t);
      }
      if (mounted) setState(() => _waking.remove(t.target));
      return;
    }
    await _checkOne(t);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final targets = _targets;
    if (targets.isEmpty) {
      return TileMessage(
        'Add what to watch in the widget settings: a web address, a '
        'host:port, or just a machine’s name to ping.',
        theme: t,
      );
    }
    final status = StatusColours.of(t);
    final down = targets
        .where((x) => _results[x.target]?.state == CheckState.down)
        .length;
    final checked = targets.where((x) => _results.containsKey(x.target)).length;

    return LayoutBuilder(
      builder: (context, c) {
        final labelH = (c.maxHeight * 0.1).clamp(18.0, 34.0);
        final listH = c.maxHeight - labelH * 1.5;
        // Rows share the height; past a comfortable minimum the list scrolls
        // instead of shrinking into unreadability.
        final rowH = (listH / targets.length).clamp(30.0, 72.0);
        final font = rowH * 0.42;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: labelH,
              child: TileLabel(
                icon: Icons.monitor_heart_outlined,
                text: 'Services',
                theme: t,
                size: labelH * 0.6,
                trailing: checked == 0
                    ? null
                    : StatusChip(
                        text: down == 0 ? 'All up' : '$down down',
                        colour: down == 0 ? status.good : status.bad,
                        size: labelH * 0.5,
                      ),
              ),
            ),
            SizedBox(height: labelH * 0.5),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                physics: rowH * targets.length > listH
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                children: [
                  for (final target in targets)
                    _Row(
                      target: target,
                      result: _results[target.target],
                      waking: _waking.contains(target.target),
                      height: rowH,
                      font: font,
                      theme: t,
                      status: status,
                      onTap: () => _tapped(target),
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

class _Row extends StatelessWidget {
  const _Row({
    required this.target,
    required this.result,
    required this.waking,
    required this.height,
    required this.font,
    required this.theme,
    required this.status,
    required this.onTap,
  });

  final ServiceTarget target;
  final CheckResult? result;
  final bool waking;
  final double height;
  final double font;
  final DashboardTheme theme;
  final StatusColours status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final colour = switch (r?.state) {
      CheckState.up => status.good,
      CheckState.slow => status.warn,
      CheckState.down => waking ? status.warn : status.bad,
      _ => theme.textSecondary,
    };
    final right = waking
        ? 'waking…'
        : r == null
        ? 'checking…'
        : r.state == CheckState.down
        ? (target.mac != null ? 'tap to wake' : (r.detail ?? 'down'))
        : (r.latency != null ? formatLatency(r.latency!) : 'up');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Container(
              width: font * 0.55,
              height: font * 0.55,
              decoration: BoxDecoration(
                color: colour,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colour.withValues(alpha: 0.6),
                    blurRadius: font * 0.5,
                  ),
                ],
              ),
            ),
            SizedBox(width: font * 0.6),
            Expanded(
              child: Text(
                target.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.textPrimary, fontSize: font),
              ),
            ),
            Text(
              right,
              maxLines: 1,
              style: TextStyle(
                color: theme.textSecondary,
                fontSize: font * 0.82,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final servicesWidgetType = DashboardWidgetType(
  type: 'services',
  name: 'Services',
  description:
      'A light per thing that should be up — Immich, CasaOS, the '
      'router, the Mac mini — with how quickly it answers. Tap one to check '
      'again, or to wake a sleeping computer.',
  glyph: '🟢',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'services',
      label: 'What to watch',
      kind: OptionKind.list,
      addLabel: 'Add a service',
      help:
          'The address says how it is checked: https://… is asked for a '
          'page, host:port is connected to, and a plain name or address is '
          'pinged. Give a computer’s network (MAC) address to wake it with '
          'a tap when it is asleep.',
      fields: [
        WidgetOption(key: 'name', label: 'Name', defaultValue: ''),
        WidgetOption(key: 'target', label: 'Address', defaultValue: ''),
        WidgetOption(
          key: 'mac',
          label: 'MAC address, to wake it',
          defaultValue: '',
        ),
      ],
    ),
    WidgetOption(
      key: 'everySeconds',
      label: 'Check every',
      kind: OptionKind.choice,
      defaultValue: '60',
      choices: {'30': '30 seconds', '60': 'Minute', '300': '5 minutes'},
    ),
  ],
  preview: const [
    PreviewLine('● Immich          38 ms', scale: 0.12),
    PreviewLine('● CasaOS          12 ms', scale: 0.12),
    PreviewLine('● Mac mini        asleep', scale: 0.12, muted: true),
  ],
  build: (context, w) => ServicesWidget(w: w),
);

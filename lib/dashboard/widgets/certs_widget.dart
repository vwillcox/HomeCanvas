import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/cert_check.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'tile_bits.dart';

/// Days left on your sites' HTTPS certificates, soonest to expire first, so a
/// renewal that quietly failed is noticed before a browser notices it.
class CertsWidget extends StatefulWidget {
  const CertsWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  /// A checker to use instead of the network, for tests.
  @visibleForTesting
  static CertChecker? debugChecker;

  @override
  State<CertsWidget> createState() => _CertsWidgetState();
}

class _CertsWidgetState extends State<CertsWidget> {
  /// Results shared by every tile and kept across page flips; certificates
  /// change every few weeks, not every few seconds.
  static final Map<String, (CertInfo, DateTime)> _cache = {};
  static const _recheck = Duration(hours: 6);

  Timer? _timer;

  CertChecker get _checker => CertsWidget.debugChecker ?? const CertChecker();

  List<String> get _hosts => [
    for (final row in (widget.w.config.options['sites'] as List? ?? const []))
      if (row is Map && '${row['host'] ?? ''}'.trim().isNotEmpty)
        '${row['host']}'.trim(),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_checkAll());
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => _checkAll());
  }

  @override
  void didUpdateWidget(covariant CertsWidget old) {
    super.didUpdateWidget(old);
    unawaited(_checkAll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkAll() async {
    final now = DateTime.now();
    final stale = _hosts.where((h) {
      final c = _cache[h];
      return c == null || now.difference(c.$2) > _recheck;
    }).toList();
    if (stale.isEmpty) return;
    final results = await Future.wait(stale.map(_checker.check));
    for (var i = 0; i < stale.length; i++) {
      _cache[stale[i]] = (results[i], DateTime.now());
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final hosts = _hosts;
    if (hosts.isEmpty) {
      return TileMessage(
        'Add your sites in the widget settings — talktech.info, or '
        'host:port for one not on 443.',
        theme: t,
      );
    }
    final now = DateTime.now();
    final warnDays =
        (int.tryParse('${widget.w.config.options['warnDays'] ?? 14}') ?? 14)
            .clamp(1, 90);
    final rows = [for (final h in hosts) (h, _cache[h]?.$1)]
      ..sort((a, b) {
        final da = a.$2?.daysLeft(now) ?? -9999,
            db = b.$2?.daysLeft(now) ?? -9999;
        return da.compareTo(db);
      });
    final status = StatusColours.of(t);
    final worst = rows
        .map((r) => r.$2)
        .whereType<CertInfo>()
        .map(
          (c) => c.error != null || !c.trusted ? -1 : (c.daysLeft(now) ?? 999),
        )
        .fold<int>(9999, (a, b) => a < b ? a : b);

    return LayoutBuilder(
      builder: (context, c) {
        final labelH = (c.maxHeight * 0.1).clamp(18.0, 34.0);
        final listH = c.maxHeight - labelH * 1.5;
        final rowH = (listH / rows.length).clamp(30.0, 64.0);
        final font = rowH * 0.4;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: labelH,
              child: TileLabel(
                icon: Icons.lock_outline_rounded,
                text: 'Certificates',
                theme: t,
                size: labelH * 0.6,
                trailing: worst == 9999
                    ? null
                    : StatusChip(
                        text: worst < 0
                            ? 'Needs a look'
                            : worst < warnDays
                            ? 'Renew soon'
                            : 'All valid',
                        colour: worst < 0 || worst < 7
                            ? status.bad
                            : worst < warnDays
                            ? status.warn
                            : status.good,
                        size: labelH * 0.5,
                      ),
              ),
            ),
            SizedBox(height: labelH * 0.5),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                physics: rowH * rows.length > listH
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                children: [
                  for (final (host, info) in rows)
                    SizedBox(
                      height: rowH,
                      child: _Row(
                        host: host,
                        info: info,
                        now: now,
                        warnDays: warnDays,
                        font: font,
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

class _Row extends StatelessWidget {
  const _Row({
    required this.host,
    required this.info,
    required this.now,
    required this.warnDays,
    required this.font,
    required this.theme,
    required this.status,
  });

  final String host;
  final CertInfo? info;
  final DateTime now;
  final int warnDays;
  final double font;
  final DashboardTheme theme;
  final StatusColours status;

  @override
  Widget build(BuildContext context) {
    final i = info;
    final days = i?.daysLeft(now);
    final (String right, Color colour) = i == null
        ? ('checking…', theme.textSecondary)
        : i.error != null
        ? (i.error!, status.bad)
        : !i.trusted
        ? ('not trusted', status.bad)
        : days! < 0
        ? ('expired', status.bad)
        : (
            days == 1 ? '1 day' : '$days days',
            days < 7
                ? status.bad
                : days < warnDays
                ? status.warn
                : status.good,
          );
    return Row(
      children: [
        Container(
          width: font * 0.55,
          height: font * 0.55,
          decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
        ),
        SizedBox(width: font * 0.6),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: host,
                  style: TextStyle(color: theme.textPrimary, fontSize: font),
                ),
                if (i?.issuer != null)
                  TextSpan(
                    text: '  ${i!.issuer}',
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontSize: font * 0.7,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: font * 0.5),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              right,
              style: TextStyle(
                color: i == null ? theme.textSecondary : colour,
                fontSize: font * 0.9,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final certsWidgetType = DashboardWidgetType(
  type: 'certs',
  category: WidgetCategory.homeLab,
  name: 'Certificates',
  description:
      'Days left on your sites’ HTTPS certificates, the soonest to '
      'expire first — so a renewal that quietly failed is caught before '
      'visitors see a warning.',
  glyph: '🔒',
  defaultWidth: 4,
  defaultHeight: 2,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'sites',
      label: 'Sites',
      kind: OptionKind.list,
      addLabel: 'Add a site',
      help:
          'The address, like talktech.info — or host:port for one on '
          'another port.',
      fields: [WidgetOption(key: 'host', label: 'Address', defaultValue: '')],
    ),
    WidgetOption(
      key: 'warnDays',
      label: 'Warn when this many days are left',
      kind: OptionKind.number,
      defaultValue: 14,
    ),
  ],
  preview: const [
    PreviewLine('● talktech.info        68 days', scale: 0.13),
    PreviewLine('● immich.example       12 days', scale: 0.13, accent: true),
  ],
  build: (context, w) => CertsWidget(w: w),
);

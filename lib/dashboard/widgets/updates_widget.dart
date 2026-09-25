import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/home_assistant_service.dart';
import '../../services/immich_service.dart';
import '../../services/unifi_service.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'tile_bits.dart';

/// One thing with an update waiting.
@immutable
class PendingUpdate {
  const PendingUpdate(this.source, this.name, {this.from, this.to});

  /// "Immich", "Home Assistant", "UniFi".
  final String source;
  final String name;
  final String? from;
  final String? to;
}

/// Whether [latest] is a newer version than [current]: "v3.3.0" against
/// "3.2.2". Only the numbers are compared, so a "v" or a suffix does not
/// matter.
bool isNewer(String latest, String current) {
  List<int> parts(String v) => RegExp(
    r'\d+',
  ).allMatches(v.split('-').first).map((m) => int.parse(m[0]!)).toList();
  final a = parts(latest), b = parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// The updates waiting across the house's systems: Immich against its
/// latest release, Home Assistant's own update entities, and UniFi firmware.
class UpdatesWidget extends StatefulWidget {
  const UpdatesWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  /// Immich's latest release, when tests should not ask GitHub.
  @visibleForTesting
  static String? debugLatestImmich;

  /// The running Immich version, when tests should not ask the server.
  @visibleForTesting
  static String? debugRunningImmich;

  @override
  State<UpdatesWidget> createState() => _UpdatesWidgetState();
}

class _UpdatesWidgetState extends State<UpdatesWidget> {
  /// GitHub allows sixty unauthenticated requests an hour; the answer is
  /// kept for six, and shared by every tile.
  static (String, DateTime)? _latestImmich;
  static String? _runningImmich;
  static final Dio _github = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/vnd.github+json'},
    ),
  );

  Timer? _timer;

  bool _on(String key) => widget.w.option(key, true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    if (_on('homeAssistant')) {
      unawaited(context.read<HomeAssistantService>().refresh());
    }
    if (_on('immich')) await _checkImmich();
    if (mounted) setState(() {});
  }

  Future<void> _checkImmich() async {
    if (UpdatesWidget.debugLatestImmich != null) {
      _latestImmich = (UpdatesWidget.debugLatestImmich!, DateTime.now());
      _runningImmich = UpdatesWidget.debugRunningImmich;
      return;
    }
    try {
      _runningImmich = await context.read<ImmichService>().serverVersion();
    } catch (_) {}
    final cached = _latestImmich;
    if (cached != null &&
        DateTime.now().difference(cached.$2) < const Duration(hours: 6)) {
      return;
    }
    try {
      final r = await _github.get(
        'https://api.github.com/repos/immich-app/immich/releases/latest',
      );
      final tag = '${(r.data as Map)['tag_name'] ?? ''}';
      if (tag.isNotEmpty) _latestImmich = (tag, DateTime.now());
    } catch (_) {
      // GitHub unreachable or rate-limited: try again next time.
    }
  }

  List<PendingUpdate> _pending(BuildContext context) {
    final out = <PendingUpdate>[];
    final latest = _latestImmich?.$1, running = _runningImmich;
    if (_on('immich') &&
        latest != null &&
        running != null &&
        isNewer(latest, running)) {
      out.add(
        PendingUpdate(
          'Immich',
          'Immich server',
          from: running,
          to: latest.replaceFirst('v', ''),
        ),
      );
    }
    if (_on('homeAssistant')) {
      for (final e in context.watch<HomeAssistantService>().all) {
        if (e.domain != 'update' || e.state != 'on') continue;
        final a = e.attributes;
        out.add(
          PendingUpdate(
            'Home Assistant',
            '${a['title'] ?? a['friendly_name'] ?? e.id}'.replaceFirst(
              RegExp(r'\s*update$', caseSensitive: false),
              '',
            ),
            from: a['installed_version'] as String?,
            to: a['latest_version'] as String?,
          ),
        );
      }
    }
    if (_on('unifi')) {
      for (final d in context.watch<UnifiService>().updatableDevices) {
        out.add(
          PendingUpdate(
            'UniFi',
            d.name,
            from: d.firmwareVersion.isEmpty ? null : d.firmwareVersion,
          ),
        );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final pending = _pending(context);
    final status = StatusColours.of(t);

    return LayoutBuilder(
      builder: (context, c) {
        final labelH = (c.maxHeight * 0.1).clamp(18.0, 34.0);
        final label = SizedBox(
          height: labelH,
          child: TileLabel(
            icon: Icons.system_update_alt_rounded,
            text: 'Updates',
            theme: t,
            size: labelH * 0.6,
            trailing: StatusChip(
              text: pending.isEmpty
                  ? 'Up to date'
                  : '${pending.length} waiting',
              colour: pending.isEmpty ? status.good : status.warn,
              size: labelH * 0.5,
            ),
          ),
        );
        if (pending.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: status.good,
                          size: labelH * 1.2,
                        ),
                        SizedBox(width: labelH * 0.4),
                        Text(
                          'Everything is up to date',
                          style: TextStyle(
                            color: t.textSecondary,
                            fontSize: labelH * 0.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        final listH = c.maxHeight - labelH * 1.5;
        final rowH = (listH / pending.length).clamp(30.0, 62.0);
        final font = rowH * 0.38;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            label,
            SizedBox(height: labelH * 0.5),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                physics: rowH * pending.length > listH
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                children: [
                  for (final u in pending)
                    SizedBox(
                      height: rowH,
                      child: _Row(u: u, font: font, theme: t),
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
  const _Row({required this.u, required this.font, required this.theme});

  final PendingUpdate u;
  final double font;
  final DashboardTheme theme;

  IconData get _icon => switch (u.source) {
    'Immich' => Icons.photo_library_outlined,
    'Home Assistant' => Icons.home_outlined,
    _ => Icons.router_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final versions = [
      if (u.from != null) u.from!,
      if (u.to != null) u.to!,
    ].join(' → ');
    return Row(
      children: [
        Icon(_icon, size: font * 1.2, color: theme.textSecondary),
        SizedBox(width: font * 0.6),
        Expanded(
          child: Text(
            u.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.textPrimary, fontSize: font),
          ),
        ),
        if (versions.isNotEmpty) ...[
          SizedBox(width: font * 0.5),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                versions,
                style: TextStyle(
                  color: theme.textSecondary,
                  fontSize: font * 0.8,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

final updatesWidgetType = DashboardWidgetType(
  type: 'updates',
  category: WidgetCategory.homeLab,
  name: 'Updates',
  description:
      'Updates waiting across the house: Immich against its latest '
      'release, Home Assistant’s own updates, and UniFi firmware — in one '
      'list, or a tick when there are none.',
  glyph: '⬆️',
  defaultWidth: 4,
  defaultHeight: 2,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'immich',
      label: 'Immich',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'homeAssistant',
      label: 'Home Assistant',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'Uses the Home Assistant connection in Settings.',
    ),
    WidgetOption(
      key: 'unifi',
      label: 'UniFi firmware',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
  ],
  preview: const [
    PreviewLine('Updates · 2 waiting', scale: 0.11, muted: true),
    PreviewLine('Home Assistant Core   2026.9.1 → 2026.9.2', scale: 0.12),
    PreviewLine('USW Flex 2.5G 5   2.1.8', scale: 0.12),
  ],
  build: (context, w) => UpdatesWidget(w: w),
);

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/home_assistant_service.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// Home Assistant entities you pick — temperatures, who is home, what is
/// playing, switches — each as a small card. Switches and lights change with
/// a tap.
class HomeAssistantWidget extends StatefulWidget {
  const HomeAssistantWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeAssistantWidget> createState() => _HomeAssistantWidgetState();
}

class _HomeAssistantWidgetState extends State<HomeAssistantWidget> {
  Timer? _timer;

  List<({String id, String name})> get _picked => [
    for (final row
        in (widget.w.config.options['entities'] as List? ?? const []))
      if (row is Map && '${row['entity'] ?? ''}'.trim().contains('.'))
        (id: '${row['entity']}'.trim(), name: '${row['name'] ?? ''}'.trim()),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) unawaited(context.read<HomeAssistantService>().refresh());
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final ha = context.watch<HomeAssistantService>();
    final picked = _picked;
    if (!ha.configured) {
      return TileMessage(
        'Connect Home Assistant in Settings first — its address and a '
        'long-lived access token.',
        theme: t,
      );
    }
    if (picked.isEmpty) {
      return TileMessage(
        'Pick entities to show in the widget settings.',
        theme: t,
      );
    }
    if (ha.all.isEmpty) {
      return TileMessage(ha.error ?? 'Asking Home Assistant…', theme: t);
    }

    return LayoutBuilder(
      builder: (context, c) {
        final grid = bestGrid(picked.length, c.biggest, cellAspect: 2.1);
        final gap = math.min(c.maxWidth, c.maxHeight) * 0.035;
        final cellW = (c.maxWidth - gap * (grid.columns - 1)) / grid.columns;
        final cellH = (c.maxHeight - gap * (grid.rows - 1)) / grid.rows;
        return Stack(
          children: [
            for (var i = 0; i < picked.length; i++)
              Positioned(
                left: (i % grid.columns) * (cellW + gap),
                top: (i ~/ grid.columns) * (cellH + gap),
                width: cellW,
                height: cellH,
                child: _Card(
                  entity: ha.entity(picked[i].id),
                  id: picked[i].id,
                  name: picked[i].name,
                  theme: t,
                  onTap: (e) => ha.toggle(e),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.entity,
    required this.id,
    required this.name,
    required this.theme,
    required this.onTap,
  });

  final HaEntity? entity;
  final String id;
  final String name;
  final DashboardTheme theme;
  final void Function(HaEntity) onTap;

  IconData get _icon => switch (id.split('.').first) {
    'sensor' => switch ('${entity?.attributes['device_class'] ?? ''}') {
      'temperature' => Icons.thermostat_rounded,
      'humidity' => Icons.water_drop_outlined,
      'battery' => Icons.battery_std_rounded,
      'power' || 'energy' => Icons.bolt_rounded,
      _ => Icons.sensors_rounded,
    },
    'binary_sensor' => Icons.radio_button_checked_rounded,
    'person' || 'device_tracker' => Icons.person_outline_rounded,
    'media_player' => Icons.music_note_rounded,
    'light' => Icons.lightbulb_outline_rounded,
    'switch' || 'input_boolean' => Icons.toggle_on_outlined,
    'fan' => Icons.mode_fan_off_outlined,
    'climate' => Icons.thermostat_auto_rounded,
    'weather' => Icons.cloud_outlined,
    _ => Icons.home_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final e = entity;
    final status = StatusColours.of(theme);
    final lit = e != null && e.switchable && e.on;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: e != null && e.switchable ? () => onTap(e) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: lit
              ? theme.accent.withValues(alpha: 0.14)
              : theme.textSecondary.withValues(alpha: 0.07),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: FitCanvas(
          designHeight: 54,
          maxScale: 3,
          builder: (context, size) => Row(
            children: [
              Icon(
                _icon,
                size: 20,
                color: lit ? theme.accent : theme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isNotEmpty ? name : (e?.name ?? id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      e == null ? 'Not found' : e.display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: e == null || e.unavailable
                            ? status.warn
                            : theme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (e != null && e.switchable) ...[
                const SizedBox(width: 6),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 30,
                  height: 18,
                  padding: const EdgeInsets.all(2),
                  alignment: e.on
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: e.on
                        ? theme.accent
                        : theme.textSecondary.withValues(alpha: 0.3),
                  ),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final homeAssistantWidgetType = DashboardWidgetType(
  type: 'home_assistant',
  category: WidgetCategory.house,
  name: 'Home Assistant',
  description:
      'Home Assistant entities you pick — temperatures, who is '
      'home, what is playing — each as a small card. Lights and switches '
      'change with a tap; locks and doors are only ever shown.',
  glyph: '🏡',
  defaultWidth: 4,
  defaultHeight: 2,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'entities',
      label: 'Entities',
      kind: OptionKind.list,
      addLabel: 'Add an entity',
      help:
          'Picked from what your Home Assistant has. The name is optional '
          '— it defaults to Home Assistant’s own.',
      fields: [
        WidgetOption(
          key: 'entity',
          label: 'Entity',
          kind: OptionKind.choice,
          choicesFrom: 'haEntities',
          defaultValue: '',
        ),
        WidgetOption(key: 'name', label: 'Call it', defaultValue: ''),
      ],
    ),
  ],
  preview: const [
    PreviewLine('Living room  21.4 °C', scale: 0.14),
    PreviewLine('Humidity  54%', scale: 0.14),
  ],
  build: (context, w) => HomeAssistantWidget(w: w),
);

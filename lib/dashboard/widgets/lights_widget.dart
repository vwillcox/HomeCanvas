import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/bin_schedule.dart' show Bin;
import '../../services/govee_service.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// Govee lights and plugs: tap a card to switch it, drag along its bar for
/// brightness, tap a swatch for a colour.
class LightsWidget extends StatefulWidget {
  const LightsWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<LightsWidget> createState() => _LightsWidgetState();
}

class _LightsWidgetState extends State<LightsWidget> {
  Timer? _timer;

  String get _key => '${widget.w.config.options['apiKey'] ?? ''}'.trim();

  List<String> get _only => '${widget.w.config.options['only'] ?? ''}'
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toList();

  List<Color> get _swatches {
    final parsed = [
      for (final part in '${widget.w.config.options['swatches'] ?? ''}'.split(
        ',',
      ))
        ?Bin.parseColour(part.trim()),
    ];
    return parsed.isEmpty ? _defaultSwatches : parsed;
  }

  static const _defaultSwatches = [
    Color(0xFFFFB86B),
    Color(0xFFFF7AB6),
    Color(0xFF8AB4FF),
    Color(0xFF7EE2A8),
    Color(0xFFFFFFFF),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    // Local devices are cheap to ask; the cloud counts against a daily
    // allowance, so once a minute is the most this asks it.
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    unawaited(context.read<GoveeService>().refresh(apiKey: _key));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final service = context.watch<GoveeService>();
    final only = _only;
    final devices = service.devices
        .where(
          (d) =>
              only.isEmpty || only.any((o) => d.name.toLowerCase().contains(o)),
        )
        .toList();
    if (devices.isEmpty) {
      return TileMessage(
        service.error ??
            'No Govee lights found. Turn on LAN Control for each in the '
                'Govee app, or add a Govee API key in the widget settings.',
        theme: t,
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final grid = bestGrid(devices.length, c.biggest, cellAspect: 1.7);
        final gap = math.min(c.maxWidth, c.maxHeight) * 0.04;
        final cellW = (c.maxWidth - gap * (grid.columns - 1)) / grid.columns;
        final cellH = (c.maxHeight - gap * (grid.rows - 1)) / grid.rows;
        return Stack(
          children: [
            for (var i = 0; i < devices.length; i++)
              Positioned(
                left: (i % grid.columns) * (cellW + gap),
                top: (i ~/ grid.columns) * (cellH + gap),
                width: cellW,
                height: cellH,
                child: _Card(
                  device: devices[i],
                  theme: t,
                  swatches: _swatches,
                  service: service,
                  apiKey: _key,
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
    required this.device,
    required this.theme,
    required this.swatches,
    required this.service,
    required this.apiKey,
  });

  final GoveeDevice device;
  final DashboardTheme theme;
  final List<Color> swatches;
  final GoveeService service;
  final String apiKey;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final on = d.on ?? false;
    final glow = d.colour ?? const Color(0xFFFFD27A);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => service.setPower(d, !on, apiKey: apiKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: on
              ? glow.withValues(alpha: 0.14)
              : theme.textSecondary.withValues(alpha: 0.07),
          border: Border.all(
            color: on ? glow.withValues(alpha: 0.4) : Colors.transparent,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: FitCanvas(
          designHeight: 100,
          maxScale: 3,
          builder: (context, size) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    d.canColour || d.canDim
                        ? Icons.lightbulb_rounded
                        : Icons.power_rounded,
                    size: 16,
                    color: on ? glow : theme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _Switch(on: on, theme: theme),
                ],
              ),
              Text(
                !d.online
                    ? 'Offline'
                    : on
                    ? (d.brightness != null ? '${d.brightness}%' : 'On')
                    : 'Off',
                style: TextStyle(color: theme.textSecondary, fontSize: 10),
              ),
              const Spacer(),
              if (d.canDim && size.height >= 80)
                _Brightness(
                  value: on ? (d.brightness ?? 100) : 0,
                  colour: glow,
                  theme: theme,
                  onChanged: (v) => service.setBrightness(d, v, apiKey: apiKey),
                ),
              if (d.canColour && size.height >= 80) ...[
                const SizedBox(height: 8),
                // Shrinks to fit a narrow card rather than running off it.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final s in swatches) ...[
                        GestureDetector(
                          onTap: () => service.setColour(d, s, apiKey: apiKey),
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: s,
                              shape: BoxShape.circle,
                              border: d.colour?.toARGB32() == s.toARGB32() && on
                                  ? Border.all(
                                      color: theme.textPrimary,
                                      width: 2,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
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

class _Switch extends StatelessWidget {
  const _Switch({required this.on, required this.theme});

  final bool on;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 30,
      height: 18,
      padding: const EdgeInsets.all(2),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: on ? theme.accent : theme.textSecondary.withValues(alpha: 0.3),
      ),
      child: Container(
        width: 14,
        height: 14,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// A bar to drag along for brightness; lets go to send it, so a drag is one
/// change rather than a hundred.
class _Brightness extends StatefulWidget {
  const _Brightness({
    required this.value,
    required this.colour,
    required this.theme,
    required this.onChanged,
  });

  final int value;
  final Color colour;
  final DashboardTheme theme;
  final void Function(int) onChanged;

  @override
  State<_Brightness> createState() => _BrightnessState();
}

class _BrightnessState extends State<_Brightness> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        double at(Offset p) => (p.dx / c.maxWidth).clamp(0.01, 1.0);
        final shown = _dragging ?? widget.value / 100;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) =>
              setState(() => _dragging = at(d.localPosition)),
          onHorizontalDragUpdate: (d) =>
              setState(() => _dragging = at(d.localPosition)),
          onHorizontalDragEnd: (_) {
            final v = ((_dragging ?? shown) * 100).round();
            setState(() => _dragging = null);
            widget.onChanged(v);
          },
          onTapUp: (d) => widget.onChanged((at(d.localPosition) * 100).round()),
          child: SizedBox(
            height: 16,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  height: 10,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: widget.theme.textSecondary.withValues(
                          alpha: 0.18,
                        ),
                      ),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: shown.clamp(0.0, 1.0),
                        child: ColoredBox(color: widget.colour),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final lightsWidgetType = DashboardWidgetType(
  type: 'lights',
  category: WidgetCategory.house,
  name: 'Lights',
  description:
      'Govee lights and plugs. Tap one to switch it, drag along its '
      'bar for brightness, tap a colour. Works over the home network for '
      'devices with LAN Control turned on in the Govee app, or through '
      'Govee with an API key.',
  glyph: '💡',
  defaultWidth: 4,
  defaultHeight: 2,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'apiKey',
      label: 'Govee API key',
      kind: OptionKind.secret,
      defaultValue: '',
      help:
          'Optional. In the Govee Home app: Profile → Settings → Apply for '
          'API Key; it arrives by email. Not needed for devices with LAN '
          'Control turned on.',
    ),
    WidgetOption(
      key: 'only',
      label: 'Only these',
      defaultValue: '',
      help:
          'Names to show, separated by commas — "strip, lamp". Leave empty '
          'for every device found.',
    ),
    WidgetOption(
      key: 'swatches',
      label: 'Colours to offer',
      defaultValue: '#FFB86B, #FF7AB6, #8AB4FF, #7EE2A8, #FFFFFF',
    ),
  ],
  preview: const [
    PreviewLine('💡 LED strip        On', scale: 0.14),
    PreviewLine('🔌 Lamp plug        Off', scale: 0.14, muted: true),
  ],
  build: (context, w) => LightsWidget(w: w),
);

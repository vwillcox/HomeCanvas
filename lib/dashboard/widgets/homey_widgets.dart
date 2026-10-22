import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/homey_extras.dart';
import '../../services/homey_service.dart';
import '../../time_format.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/shown_timers.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';
import '../../widgets/lcars.dart';
import '../../map_text.dart';

/// What every Homey tile does besides drawing: asks the service to keep the
/// picture fresh, and to listen for changes to the devices it shows. The
/// socket brings the changes; the timer is for when it is down, and to bring
/// it back up.
mixin _HomeyTile<T extends StatefulWidget>
    on PauseWhenHidden<T>, ShownTimers<T> {
  /// The devices this tile shows, as far as is known yet.
  Iterable<String> watched(HomeyService homey);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    everyWhileShown(const Duration(seconds: 15), _sync);
  }

  @override
  void didUpdateWidget(covariant T old) {
    super.didUpdateWidget(old);
    _sync();
  }

  Future<void> _sync() async {
    if (!mounted) return;
    final homey = context.read<HomeyService>();
    final before = watched(homey).toSet();
    homey.watch(before);
    await homey.ensure();
    if (!mounted) return;
    for (final a in asks(homey).entries) {
      unawaited(homey.ask(a.key, keep: a.value));
    }
    // A room's devices are only known once the picture has arrived.
    final after = watched(homey).toSet();
    if (after.difference(before).isEmpty) return;
    homey.watch(after);
    await homey.ensure();
  }

  /// What else of the Homey this tile shows — `users/user` — and how long
  /// an answer keeps before it is asked for again.
  Map<String, Duration> asks(HomeyService homey) => const {};

  /// What to say instead of the tile, while there is nothing to draw.
  /// [devices] is whether the tile is about devices at all: one that is not
  /// has something to show from a Homey with none.
  Widget? notReady(
    HomeyService homey,
    DashboardTheme theme, {
    bool devices = true,
  }) {
    if (!homey.configured) {
      return TileMessage(
        tr(
          'widget.homey.needsKey',
          'Add your Homey’s address and API key on the panel: Settings → '
              'Home → Homey.',
        ),
        theme: theme,
      );
    }
    if (homey.all.isEmpty && (devices || homey.error != null)) {
      return TileMessage(
        homey.error ?? tr('widget.homey.asking', 'Asking Homey…'),
        theme: theme,
      );
    }
    return null;
  }
}

/// Equal cells, as many across and down as lets each be largest.
class _Grid extends StatelessWidget {
  const _Grid({required this.children, this.cellAspect = 2.1});

  final List<Widget> children;
  final double cellAspect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final grid = bestGrid(
          children.length,
          c.biggest,
          cellAspect: cellAspect,
        );
        final gap = math.min(c.maxWidth, c.maxHeight) * 0.035;
        final cellW = (c.maxWidth - gap * (grid.columns - 1)) / grid.columns;
        final cellH = (c.maxHeight - gap * (grid.rows - 1)) / grid.rows;
        return Stack(
          children: [
            for (var i = 0; i < children.length; i++)
              Positioned(
                left: (i % grid.columns) * (cellW + gap),
                top: (i ~/ grid.columns) * (cellH + gap),
                width: cellW,
                height: cellH,
                child: children[i],
              ),
          ],
        );
      },
    );
  }
}

IconData _iconFor(HomeyDevice? d, String? shown) =>
    switch ((shown ?? '').split('.').first) {
      'measure_temperature' || 'target_temperature' => Icons.thermostat_rounded,
      'measure_humidity' => Icons.water_drop_outlined,
      'measure_battery' || 'alarm_battery' => Icons.battery_std_rounded,
      'measure_power' || 'meter_power' => Icons.bolt_rounded,
      'alarm_contact' => Icons.sensor_door_outlined,
      'alarm_motion' => Icons.directions_walk_rounded,
      'alarm_water' => Icons.water_damage_outlined,
      'alarm_smoke' => Icons.local_fire_department_outlined,
      'locked' => Icons.lock_outline_rounded,
      _ => switch (d?.kind) {
        'light' => Icons.lightbulb_outline_rounded,
        'socket' => Icons.power_outlined,
        'fan' => Icons.mode_fan_off_outlined,
        'thermostat' || 'heater' => Icons.thermostat_auto_rounded,
        'speaker' || 'amplifier' => Icons.music_note_rounded,
        'tv' => Icons.tv_rounded,
        'sensor' => Icons.sensors_rounded,
        _ => Icons.home_outlined,
      },
    };

/// A small card: what it is, what it reads, and — for something a tap
/// switches — which way it is switched.
class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
    this.warn = false,
    this.on,
    this.tint,
    this.onTap,
  });

  /// One device, showing [capability] or its main reading.
  factory _Card.device(
    HomeyService homey,
    HomeyDevice? d,
    DashboardTheme theme, {
    String capability = '',
    String name = '',
  }) {
    final shown = d?.reading(capability);
    // A card showing what a socket draws is a reading, not a switch.
    final switches = d != null && d.switchable && shown == 'onoff';
    return _Card(
      icon: _iconFor(d, shown),
      label: name.isNotEmpty
          ? name
          : (d?.name ?? tr('widget.homey.device', 'Device')),
      value: d == null
          ? tr('widget.homey.notFound', 'Not found')
          : d.display(shown),
      theme: theme,
      warn: d == null || !d.available,
      on: switches ? d.on : null,
      onTap: switches ? () => homey.toggle(d) : null,
    );
  }

  final IconData icon;
  final String label;
  final String value;
  final DashboardTheme theme;
  final bool warn;

  /// Which way it is switched, or null for something that is only shown.
  final bool? on;

  /// Whether to colour it as something on — [on], unless said otherwise.
  final bool? tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final lit = tint ?? on ?? false;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: theme.isLcars
            ? lcarsCard(theme, lit: lit)
            : BoxDecoration(
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
                icon,
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
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: warn
                            ? StatusColours.of(theme).warn
                            : theme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              // In a narrow card the name matters more; the tint says it is on.
              if (on != null && size.width >= 110) ...[
                const SizedBox(width: 6),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 30,
                  height: 18,
                  padding: const EdgeInsets.all(2),
                  alignment: on! ? Alignment.centerRight : Alignment.centerLeft,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: on!
                        ? theme.accent
                        : theme.textSecondary.withValues(alpha: 0.3),
                  ),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      // A console's key is black, on a lit track.
                      color: theme.isLcars ? lcarsInk : Colors.white,
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

/// Homey devices you pick — temperatures, doors, what a socket is drawing,
/// lights — each as a small card, changing as the device does. Lights and
/// sockets switch with a tap.
class HomeyWidget extends StatefulWidget {
  const HomeyWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeyWidget> createState() => _HomeyWidgetState();
}

class _HomeyWidgetState extends State<HomeyWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile {
  List<({String id, String capability, String name})> get _picked => [
    for (final r in widget.w.rows('devices'))
      if (r.text('device').isNotEmpty)
        (
          id: '${r['device']}'.trim(),
          capability: r.text('capability'),
          name: r.text('name'),
        ),
  ];

  @override
  Iterable<String> watched(HomeyService homey) => _picked.map((p) => p.id);

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    final picked = _picked;
    if (homey.configured && picked.isEmpty) {
      return TileMessage(
        tr(
          'widget.homey.pick',
          'Pick devices in this widget’s settings in the editor.',
        ),
        theme: t,
      );
    }
    return notReady(homey, t) ??
        _Grid(
          children: [
            for (final p in picked)
              _Card.device(
                homey,
                homey.device(p.id),
                t,
                capability: p.capability,
                name: p.name,
              ),
          ],
        );
  }
}

/// Everything Homey has in one room, without picking it device by device,
/// and a card for the room itself that switches the lot.
class HomeyRoomWidget extends StatefulWidget {
  const HomeyRoomWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeyRoomWidget> createState() => _HomeyRoomWidgetState();
}

class _HomeyRoomWidgetState extends State<HomeyRoomWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile {
  String get _zone => widget.w.option('zone', '').trim();

  List<HomeyDevice> _devices(HomeyService homey) {
    final show = widget.w.option('show', 'all');
    return [
      for (final d in homey.devicesIn(
        _zone,
        below: widget.w.option('below', true),
      ))
        if (switch (show) {
          'lights' => d.kind == 'light',
          'switches' => d.switchable,
          _ => true,
        })
          d,
    ];
  }

  @override
  Iterable<String> watched(HomeyService homey) =>
      _devices(homey).map((d) => d.id);

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    if (homey.configured && _zone.isEmpty) {
      return TileMessage(
        tr(
          'widget.homey_room.pick',
          'Pick a room in this widget’s settings in the editor.',
        ),
        theme: t,
      );
    }
    final waiting = notReady(homey, t);
    if (waiting != null) return waiting;
    final devices = _devices(homey);
    if (devices.isEmpty) {
      return TileMessage(
        tr('widget.homey_room.empty', 'Homey has nothing in this room.'),
        theme: t,
      );
    }
    final switches = devices.where((d) => d.switchable).toList();
    final lit = switches.where((d) => d.on).length;
    return _Grid(
      children: [
        if (widget.w.option('master', true) && switches.isNotEmpty)
          _Card(
            icon: Icons.meeting_room_outlined,
            label:
                homey.zone(_zone)?.name ?? tr('widget.homey_room.room', 'Room'),
            value: lit == 0
                ? tr('widget.homey_room.allOff', 'All off')
                : tr('widget.homey_room.countOn', '{count} on', {'count': lit}),
            theme: t,
            on: lit > 0,
            // Something on: the lot off. Nothing on: the lot on.
            onTap: () => homey.switchAll(switches, lit == 0),
          ),
        for (final d in devices) _Card.device(homey, d, t),
      ],
    );
  }
}

/// Lights, each with a bar to drag for how bright — the ones picked, or
/// every light Homey has.
class HomeyLightsWidget extends StatefulWidget {
  const HomeyLightsWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeyLightsWidget> createState() => _HomeyLightsWidgetState();
}

class _HomeyLightsWidgetState extends State<HomeyLightsWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile {
  /// The lights to show, and what to call each.
  List<({String id, String name})> _lights(HomeyService homey) {
    final picked = [
      for (final r in widget.w.rows('lights'))
        if (r.text('light').isNotEmpty)
          (id: '${r['light']}'.trim(), name: r.text('name')),
    ];
    return picked.isNotEmpty
        ? picked
        : [for (final d in homey.lights) (id: d.id, name: '')];
  }

  @override
  Iterable<String> watched(HomeyService homey) =>
      _lights(homey).map((l) => l.id);

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    final waiting = notReady(homey, t);
    if (waiting != null) return waiting;
    final lights = _lights(homey);
    if (lights.isEmpty) {
      return TileMessage(
        tr('widget.homey_lights.none', 'Homey has no lights.'),
        theme: t,
      );
    }
    return _Grid(
      cellAspect: 3,
      children: [
        for (final l in lights)
          _Light(
            device: homey.device(l.id),
            name: l.name,
            theme: t,
            onToggle: homey.toggle,
            onDim: homey.dim,
          ),
      ],
    );
  }
}

class _Light extends StatelessWidget {
  const _Light({
    required this.device,
    required this.name,
    required this.theme,
    required this.onToggle,
    required this.onDim,
  });

  final HomeyDevice? device;
  final String name;
  final DashboardTheme theme;
  final void Function(HomeyDevice) onToggle;
  final void Function(HomeyDevice, double) onDim;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final lit = d != null && d.switchable && d.on;
    final toggle = d != null && d.switchable ? () => onToggle(d) : null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: theme.isLcars
          ? lcarsCard(theme, lit: lit)
          : BoxDecoration(
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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: toggle,
              child: SizedBox(
                width: 30,
                height: size.height,
                child: Icon(
                  lit
                      ? Icons.lightbulb_rounded
                      : Icons.lightbulb_outline_rounded,
                  size: 22,
                  color: lit ? theme.accent : theme.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: toggle,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name.isNotEmpty
                                ? name
                                : (d?.name ??
                                      tr('widget.homey.device', 'Device')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          d == null
                              ? tr('widget.homey.notFound', 'Not found')
                              : d.display('onoff'),
                          maxLines: 1,
                          style: TextStyle(
                            color: d == null || !d.available
                                ? StatusColours.of(theme).warn
                                : theme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (d != null && d.dimmable) ...[
                    const SizedBox(height: 4),
                    _Bar(
                      value: d.brightness,
                      theme: theme,
                      onChanged: (v) => onDim(d, v),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A bar to drag or touch, sent when the finger lifts: filled up to its
/// value, or — over a [gradient] — with a mark where the value is.
class _Bar extends StatefulWidget {
  const _Bar({
    required this.value,
    required this.theme,
    required this.onChanged,
    this.gradient,
  });

  /// From nothing to one, or null where there is nothing to mark.
  final double? value;
  final DashboardTheme theme;
  final ValueChanged<double> onChanged;
  final Gradient? gradient;

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final gradient = widget.gradient;
    return LayoutBuilder(
      builder: (context, c) {
        double at(Offset p) => (p.dx / c.maxWidth).clamp(0.01, 1.0);
        final shown = (_dragging ?? widget.value)?.clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) =>
              setState(() => _dragging = at(d.localPosition)),
          onHorizontalDragUpdate: (d) =>
              setState(() => _dragging = at(d.localPosition)),
          onHorizontalDragEnd: (_) {
            final v = _dragging;
            setState(() => _dragging = null);
            if (v != null) widget.onChanged(v);
          },
          onTapUp: (d) => widget.onChanged(at(d.localPosition)),
          child: SizedBox(
            height: 16,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(tileCorner(t, 5)),
                child: SizedBox(
                  height: 10,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (gradient != null)
                        DecoratedBox(
                          decoration: BoxDecoration(gradient: gradient),
                        )
                      else
                        ColoredBox(
                          color: t.textSecondary.withValues(alpha: 0.2),
                        ),
                      if (gradient == null)
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: shown ?? 0,
                          child: ColoredBox(color: t.accent),
                        )
                      else if (shown != null)
                        Align(
                          alignment: Alignment(shown * 2 - 1, 0),
                          child: Container(width: 4, color: Colors.black87),
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

/// For a tile of buttons: what each one last touched came to, shown for a
/// moment and then forgotten.
mixin _Flash<T extends StatefulWidget> on State<T> {
  final Map<String, bool> _result = {};
  final Map<String, Timer> _forget = {};

  /// How [id]'s last go went, or null when it has not been touched lately.
  bool? result(String id) => _result[id];

  Future<void> run(String id, Future<bool> Function() go) async {
    final went = await go();
    if (!mounted) return;
    setState(() => _result[id] = went);
    _forget[id]?.cancel();
    _forget[id] = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _result.remove(id));
    });
  }

  @override
  void dispose() {
    for (final t in _forget.values) {
      t.cancel();
    }
    super.dispose();
  }
}

/// Buttons that start flows — "Goodnight", "Movie time".
class HomeyFlowsWidget extends StatefulWidget {
  const HomeyFlowsWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeyFlowsWidget> createState() => _HomeyFlowsWidgetState();
}

class _HomeyFlowsWidgetState extends State<HomeyFlowsWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile, _Flash {
  List<({String id, String name})> get _picked => [
    for (final r in widget.w.rows('flows'))
      if (r.text('flow').isNotEmpty)
        (id: '${r['flow']}'.trim(), name: r.text('name')),
  ];

  // Flows are started, not watched.
  @override
  Iterable<String> watched(HomeyService homey) => const [];

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    final picked = _picked;
    if (homey.configured && picked.isEmpty) {
      return TileMessage(
        tr(
          'widget.homey_flows.pick',
          'Pick flows in this widget’s settings in the editor.',
        ),
        theme: t,
      );
    }
    return notReady(homey, t, devices: false) ??
        _Grid(
          children: [
            for (final p in picked)
              _Card(
                icon: Icons.play_circle_outline_rounded,
                label: p.name.isNotEmpty
                    ? p.name
                    : (homey.flow(p.id)?.name ??
                          tr('widget.homey_flows.flow', 'Flow')),
                value: homey.flow(p.id) == null
                    ? tr('widget.homey.notFound', 'Not found')
                    : switch (result(p.id)) {
                        true => tr('widget.homey_flows.started', 'Started'),
                        false => tr(
                          'widget.homey_flows.didNotStart',
                          'Did not start',
                        ),
                        null => tr('widget.homey_flows.start', 'Start'),
                      },
                theme: t,
                warn: homey.flow(p.id) == null || result(p.id) == false,
                onTap: homey.flow(p.id) == null
                    ? null
                    : () => run(p.id, () => homey.start(p.id)),
              ),
          ],
        );
  }
}

/// The rows of a list option naming devices, or — with none picked — every
/// device that [fits].
List<({String id, String name})> _pickedOr(
  DashboardWidgetContext w,
  String option,
  String field,
  HomeyService homey,
  bool Function(HomeyDevice) fits,
) {
  final picked = [
    for (final r in w.rows(option))
      if (r.text(field).isNotEmpty)
        (id: '${r[field]}'.trim(), name: r.text('name')),
  ];
  if (picked.isNotEmpty) return picked;
  final all = homey.all.where(fits).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return [for (final d in all) (id: d.id, name: '')];
}

/// A card's box, tinted when what it shows is on.
class _Box extends StatelessWidget {
  const _Box({
    required this.theme,
    required this.child,
    this.lit = false,
    this.designHeight = 54,
  });

  final DashboardTheme theme;
  final bool lit;
  final double designHeight;
  final Widget Function(BuildContext context, Size size) child;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    decoration: theme.isLcars
        ? lcarsCard(theme, lit: lit)
        : BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: lit
                ? theme.accent.withValues(alpha: 0.14)
                : theme.textSecondary.withValues(alpha: 0.07),
          ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: FitCanvas(designHeight: designHeight, maxScale: 3, builder: child),
  );
}

/// A card's top line: what it is, and how it stands.
class _Heading extends StatelessWidget {
  const _Heading(this.name, this.state, this.theme, {this.warn = false});

  final String name;
  final String state;
  final DashboardTheme theme;
  final bool warn;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Row(
      children: [
        Expanded(
          child: Text(
            tileCased(theme, name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // Never more than half the line, however much there is to say.
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: c.maxWidth / 2),
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              state,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: warn
                    ? StatusColours.of(theme).warn
                    : theme.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Lights that can be coloured: a bar from cool white to warm, and a row of
/// colours to touch.
class HomeyColourWidget extends StatefulWidget {
  const HomeyColourWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeyColourWidget> createState() => _HomeyColourWidgetState();
}

class _HomeyColourWidgetState extends State<HomeyColourWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile {
  List<({String id, String name})> _lights(HomeyService homey) => _pickedOr(
    widget.w,
    'lights',
    'light',
    homey,
    (d) => d.settable('light_hue') || d.settable('light_temperature'),
  );

  @override
  Iterable<String> watched(HomeyService homey) =>
      _lights(homey).map((l) => l.id);

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    final waiting = notReady(homey, t);
    if (waiting != null) return waiting;
    final lights = _lights(homey);
    if (lights.isEmpty) {
      return TileMessage(
        tr(
          'widget.homey_colour.none',
          'Homey has no lights that change colour.',
        ),
        theme: t,
      );
    }
    return _Grid(
      cellAspect: 2.6,
      children: [
        for (final l in lights)
          _ColourCard(
            homey: homey,
            device: homey.device(l.id),
            name: l.name,
            theme: t,
          ),
      ],
    );
  }
}

class _ColourCard extends StatelessWidget {
  const _ColourCard({
    required this.homey,
    required this.device,
    required this.name,
    required this.theme,
  });

  final HomeyService homey;
  final HomeyDevice? device;
  final String name;
  final DashboardTheme theme;

  /// Round the wheel: red, orange, yellow, green, cyan, blue, purple, pink.
  static const _hues = [0.0, 0.08, 0.15, 0.33, 0.5, 0.67, 0.78, 0.9];

  @override
  Widget build(BuildContext context) {
    final d = device;
    final coloured =
        d != null && d.capabilities['light_mode']?.value != 'temperature';
    final hue = d?.number('light_hue');
    return _Box(
      theme: theme,
      lit: d != null && d.on,
      designHeight: 76,
      child: (context, size) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: d == null ? null : () => homey.toggle(d),
            child: _Heading(
              name.isNotEmpty
                  ? name
                  : (d?.name ?? tr('widget.homey.device', 'Device')),
              d == null
                  ? tr('widget.homey.notFound', 'Not found')
                  : d.display('onoff'),
              theme,
              warn: d == null || !d.available,
            ),
          ),
          if (d != null && d.settable('light_temperature')) ...[
            const SizedBox(height: 4),
            _Bar(
              // Homey's nought is the coolest white; the bar's left.
              value: coloured ? null : d.number('light_temperature'),
              theme: theme,
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFCFE4FF),
                  Color(0xFFFFF4E0),
                  Color(0xFFFFB45E),
                ],
              ),
              onChanged: (v) => homey.warmth(d, v),
            ),
          ],
          if (d != null && d.settable('light_hue')) ...[
            const SizedBox(height: 5),
            SizedBox(
              height: 16,
              child: Row(
                children: [
                  for (final h in _hues)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => homey.colour(d, h),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: HSVColor.fromAHSV(
                              1,
                              h * 360,
                              0.85,
                              1,
                            ).toColor(),
                            borderRadius: BorderRadius.circular(5),
                            border:
                                coloured &&
                                    hue != null &&
                                    (hue - h).abs() < 0.03
                                ? Border.all(color: theme.textPrimary, width: 2)
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Fans: on and off, how fast where it says, and whether it turns its head.
class HomeyFanWidget extends StatefulWidget {
  const HomeyFanWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeyFanWidget> createState() => _HomeyFanWidgetState();
}

class _HomeyFanWidgetState extends State<HomeyFanWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile {
  List<({String id, String name})> _fans(HomeyService homey) =>
      _pickedOr(widget.w, 'fans', 'fan', homey, (d) => d.kind == 'fan');

  @override
  Iterable<String> watched(HomeyService homey) => _fans(homey).map((f) => f.id);

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    final waiting = notReady(homey, t);
    if (waiting != null) return waiting;
    final fans = _fans(homey);
    if (fans.isEmpty) {
      return TileMessage(
        tr('widget.homey_fan.none', 'Homey has no fans.'),
        theme: t,
      );
    }
    return _Grid(
      cellAspect: 3,
      children: [
        for (final f in fans)
          _FanCard(
            homey: homey,
            device: homey.device(f.id),
            name: f.name,
            theme: t,
          ),
      ],
    );
  }
}

class _FanCard extends StatelessWidget {
  const _FanCard({
    required this.homey,
    required this.device,
    required this.name,
    required this.theme,
  });

  final HomeyService homey;
  final HomeyDevice? device;
  final String name;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final lit = d != null && d.on;
    final turning = d?.capabilities['oscillating']?.value == true;
    final mode = d?.capabilities.entries
        .where((e) => e.key.split('.').first == 'workMode')
        .map((e) => e.value.value)
        .whereType<String>()
        .firstOrNull;
    return _Box(
      theme: theme,
      lit: lit,
      child: (context, size) => Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: d == null ? null : () => homey.toggle(d),
            child: SizedBox(
              width: 30,
              height: size.height,
              child: Icon(
                lit ? Icons.mode_fan_off_rounded : Icons.mode_fan_off_outlined,
                size: 22,
                color: lit ? theme.accent : theme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: d == null ? null : () => homey.toggle(d),
                  child: _Heading(
                    name.isNotEmpty
                        ? name
                        : (d?.name ?? tr('widget.homey.device', 'Device')),
                    d == null
                        ? tr('widget.homey.notFound', 'Not found')
                        : [d.display('onoff'), ?mode].join(' · '),
                    theme,
                    warn: d == null || !d.available,
                  ),
                ),
                if (d != null && d.settable('fan_speed')) ...[
                  const SizedBox(height: 4),
                  _Bar(
                    value: lit ? d.number('fan_speed') ?? 0 : 0,
                    theme: theme,
                    onChanged: (v) => homey.set(d, 'fan_speed', v),
                  ),
                ],
              ],
            ),
          ),
          if (d != null && d.settable('oscillating') && size.width >= 120) ...[
            const SizedBox(width: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => homey.set(d, 'oscillating', !turning),
              child: Container(
                width: 34,
                height: 28,
                // A block on a console: lit while it is turning.
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(tileCorner(theme, 9)),
                  color: theme.isLcars
                      ? (turning ? lcarsLit : theme.block(1))
                      : turning
                      ? theme.accent
                      : theme.textSecondary.withValues(alpha: 0.18),
                ),
                child: Icon(
                  Icons.swap_horiz_rounded,
                  size: 18,
                  color: theme.isLcars
                      ? lcarsInk
                      : turning
                      ? Colors.white
                      : theme.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Every room at once: how much is on in each, a tap to switch a room, and
/// one card to switch the whole house off.
class HomeyHouseWidget extends StatefulWidget {
  const HomeyHouseWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeyHouseWidget> createState() => _HomeyHouseWidgetState();
}

class _HomeyHouseWidgetState extends State<HomeyHouseWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile {
  @override
  Iterable<String> watched(HomeyService homey) =>
      homey.all.where((d) => d.switchable).map((d) => d.id);

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    final waiting = notReady(homey, t);
    if (waiting != null) return waiting;
    final everything = homey.all.where((d) => d.switchable).toList();
    // Each room by what is in it itself, so nothing is counted twice.
    final rooms =
        [
            for (final z in homey.zones)
              (
                zone: z,
                devices: homey
                    .devicesIn(z.id, below: false)
                    .where((d) => d.switchable)
                    .toList(),
              ),
          ].where((r) => r.devices.isNotEmpty).toList()
          ..sort((a, b) => a.zone.name.compareTo(b.zone.name));
    if (rooms.isEmpty) {
      return TileMessage(
        tr('widget.homey_house.none', 'Homey has nothing to switch.'),
        theme: t,
      );
    }
    String count(int lit) => lit == 0
        ? tr('widget.homey_room.allOff', 'All off')
        : tr('widget.homey_room.countOn', '{count} on', {'count': lit});
    final lit = everything.where((d) => d.on).length;
    return _Grid(
      children: [
        if (widget.w.option('everything', true))
          _Card(
            icon: Icons.power_settings_new_rounded,
            label: tr('widget.homey_house.everything', 'Everything'),
            value: count(lit),
            theme: t,
            tint: lit > 0,
            // Off, and only ever off: nobody wants the whole house lit.
            onTap: lit == 0 ? null : () => homey.switchAll(everything, false),
          ),
        for (final r in rooms)
          _Card(
            icon: Icons.meeting_room_outlined,
            label: r.zone.name,
            value: count(r.devices.where((d) => d.on).length),
            theme: t,
            on: r.devices.any((d) => d.on),
            onTap: () =>
                homey.switchAll(r.devices, !r.devices.any((d) => d.on)),
          ),
      ],
    );
  }
}

/// Buttons that set a mood: a room's lights as they were saved in Homey.
class HomeyMoodsWidget extends StatefulWidget {
  const HomeyMoodsWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeyMoodsWidget> createState() => _HomeyMoodsWidgetState();
}

class _HomeyMoodsWidgetState extends State<HomeyMoodsWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile, _Flash {
  @override
  Iterable<String> watched(HomeyService homey) => const [];

  @override
  Map<String, Duration> asks(HomeyService homey) => const {
    'moods/mood': Duration(minutes: 1),
  };

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    final waiting = notReady(homey, t, devices: false);
    if (waiting != null) return waiting;
    final data = homey.answer('moods/mood');
    final moods = <String, Map<dynamic, dynamic>>{
      if (data is Map)
        for (final m in data.values)
          if (m is Map && m['id'] is String) m['id'] as String: m,
    };
    final picked = [
      for (final r in widget.w.rows('moods'))
        if (r.text('mood').isNotEmpty)
          (id: '${r['mood']}'.trim(), name: r.text('name')),
    ];
    final shown = picked.isNotEmpty
        ? picked
        : [
            for (final m
                in moods.values.toList()
                  ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}')))
              (id: m['id'] as String, name: ''),
          ];
    if (shown.isEmpty) {
      return TileMessage(
        data == null
            ? tr('widget.homey.asking', 'Asking Homey…')
            : tr(
                'widget.homey_moods.none',
                'No moods yet. Make one in Homey’s app, in a room.',
              ),
        theme: t,
      );
    }
    return _Grid(
      children: [
        for (final p in shown)
          _Card(
            icon: Icons.auto_awesome_outlined,
            label:
                homey.zone('${moods[p.id]?['zone'] ?? ''}')?.name ??
                tr('widget.homey_moods.mood', 'Mood'),
            value: !moods.containsKey(p.id)
                ? tr('widget.homey.notFound', 'Not found')
                : switch (result(p.id)) {
                    true => tr('widget.homey_moods.set', 'Set'),
                    false => tr('widget.homey_moods.didNotSet', 'Did not set'),
                    null =>
                      p.name.isNotEmpty ? p.name : '${moods[p.id]!['name']}',
                  },
            theme: t,
            warn: !moods.containsKey(p.id) || result(p.id) == false,
            onTap: !moods.containsKey(p.id)
                ? null
                : () => run(p.id, () => homey.setMood(p.id)),
          ),
      ],
    );
  }
}

/// Only what wants attention: doors open, alarms going, batteries low,
/// devices Homey cannot reach. Quiet when there is nothing.
class HomeyAlertsWidget extends StatefulWidget {
  const HomeyAlertsWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeyAlertsWidget> createState() => _HomeyAlertsWidgetState();
}

class _HomeyAlertsWidgetState extends State<HomeyAlertsWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile {
  static const _most = 12;

  @override
  Iterable<String> watched(HomeyService homey) => homey.all.map((d) => d.id);

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    final waiting = notReady(homey, t);
    if (waiting != null) return waiting;
    final alerts = homeyAlerts(
      homey.all,
      battery: widget.w.option('battery', 20),
      offline: widget.w.option('offline', true),
    );
    if (alerts.isEmpty) {
      return FitCanvas(
        designHeight: 60,
        builder: (context, size) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 24,
              color: StatusColours.of(t).good,
            ),
            const SizedBox(height: 4),
            Text(
              tr('widget.homey_alerts.quiet', 'All quiet'),
              maxLines: 1,
              style: TextStyle(color: t.textSecondary, fontSize: 12),
            ),
          ],
        ),
      );
    }
    final more = alerts.length - _most;
    return _Grid(
      children: [
        for (final a in alerts.take(more > 0 ? _most - 1 : _most))
          _Card(
            icon: a.capability.isEmpty
                ? Icons.cloud_off_rounded
                : _iconFor(a.device, a.capability),
            label: a.device.name,
            value: a.text,
            theme: t,
            warn: true,
          ),
        if (more > 0)
          _Card(
            icon: Icons.more_horiz_rounded,
            label: tr('widget.homey_alerts.andMore', 'And'),
            value: tr('widget.homey_alerts.more', '{count} more', {
              'count': more + 1,
            }),
            theme: t,
            warn: true,
          ),
      ],
    );
  }
}

/// Temperatures: what each room is at, how damp, and — for a thermostat —
/// what it is set to, with a step up and down.
class HomeyClimateWidget extends StatefulWidget {
  const HomeyClimateWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeyClimateWidget> createState() => _HomeyClimateWidgetState();
}

class _HomeyClimateWidgetState extends State<HomeyClimateWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile {
  List<({String id, String name})> _picked(HomeyService homey) => _pickedOr(
    widget.w,
    'devices',
    'device',
    homey,
    (d) => d.has('measure_temperature') || d.has('target_temperature'),
  );

  @override
  Iterable<String> watched(HomeyService homey) =>
      _picked(homey).map((p) => p.id);

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    final waiting = notReady(homey, t);
    if (waiting != null) return waiting;
    final picked = _picked(homey);
    if (picked.isEmpty) {
      return TileMessage(
        tr(
          'widget.homey_climate.none',
          'Nothing on your Homey measures temperature yet.',
        ),
        theme: t,
      );
    }
    return _Grid(
      cellAspect: 2.6,
      children: [
        for (final p in picked)
          _ClimateCard(
            homey: homey,
            device: homey.device(p.id),
            name: p.name,
            theme: t,
          ),
      ],
    );
  }
}

class _ClimateCard extends StatelessWidget {
  const _ClimateCard({
    required this.homey,
    required this.device,
    required this.name,
    required this.theme,
  });

  final HomeyService homey;
  final HomeyDevice? device;
  final String name;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final target = d?.capabilities['target_temperature'];
    final set = target?.value;
    final sets = d != null && set is num && d.settable('target_temperature');
    void step(double by) {
      if (d == null || set is! num) return;
      final to = (set + by).clamp(target?.min ?? 5, target?.max ?? 35);
      homey.set(d, 'target_temperature', to);
    }

    Widget button(IconData icon, double by) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => step(by),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.textSecondary.withValues(alpha: 0.18),
        ),
        child: Icon(icon, size: 16, color: theme.textPrimary),
      ),
    );

    final reading = d == null
        ? tr('widget.homey.notFound', 'Not found')
        : d.has('measure_temperature')
        ? d.display('measure_temperature')
        : d.display('target_temperature');
    return _Box(
      theme: theme,
      child: (context, size) => Row(
        children: [
          Icon(Icons.thermostat_rounded, size: 20, color: theme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    name.isNotEmpty
                        ? name
                        : (d?.name ?? tr('widget.homey.device', 'Device')),
                    if (d != null && d.has('measure_humidity'))
                      d.display('measure_humidity'),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.textSecondary, fontSize: 10),
                ),
                Text(
                  reading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: d == null || !d.available
                        ? StatusColours.of(theme).warn
                        : theme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (sets && size.width >= 170) ...[
            button(Icons.remove_rounded, -0.5),
            SizedBox(
              width: 44,
              child: Text(
                '${set.toStringAsFixed(1)}°',
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  color: theme.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            button(Icons.add_rounded, 0.5),
          ],
        ],
      ),
    );
  }
}

/// What the house is drawing now, and what is drawing most of it.
class HomeyEnergyWidget extends StatefulWidget {
  const HomeyEnergyWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeyEnergyWidget> createState() => _HomeyEnergyWidgetState();
}

class _HomeyEnergyWidgetState extends State<HomeyEnergyWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile {
  List<HomeyDevice> _drawing(HomeyService homey) =>
      homey.all.where((d) => (d.number('measure_power') ?? 0) > 0).toList()
        ..sort(
          (a, b) =>
              b.number('measure_power')!.compareTo(a.number('measure_power')!),
        );

  @override
  Iterable<String> watched(HomeyService homey) =>
      homey.all.where((d) => d.has('measure_power')).map((d) => d.id);

  @override
  Map<String, Duration> asks(HomeyService homey) => const {
    'energy/live': Duration(seconds: 15),
  };

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    final waiting = notReady(homey, t);
    if (waiting != null) return waiting;
    final drawing = _drawing(homey);
    final live = homey.answer('energy/live');
    final said = live is Map && live['totalConsumed'] is Map
        ? (live['totalConsumed'] as Map)['W']
        : null;
    if (said is! num && !homey.all.any((d) => d.has('measure_power'))) {
      return TileMessage(
        tr(
          'widget.homey_energy.none',
          'Nothing on your Homey reports the power it draws yet.',
        ),
        theme: t,
      );
    }
    // Homey's own total where it has one; otherwise what the devices add
    // up to.
    final total = said is num
        ? said
        : drawing.fold<double>(0, (sum, d) => sum + d.number('measure_power')!);
    return _Grid(
      children: [
        _Card(
          icon: Icons.bolt_rounded,
          label: tr('widget.homey_energy.now', 'Drawing now'),
          value: homeyWatts(total),
          theme: t,
          tint: total > 0,
        ),
        for (final d in drawing.take(widget.w.option('count', 5).clamp(0, 11)))
          _Card(
            icon: _iconFor(d, ''),
            label: d.name,
            value: homeyWatts(d.number('measure_power')!),
            theme: t,
          ),
      ],
    );
  }
}

/// One of Homey's logs as a line: a temperature over the day, a week of
/// what a socket drew.
class HomeyHistoryWidget extends StatefulWidget {
  const HomeyHistoryWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeyHistoryWidget> createState() => _HomeyHistoryWidgetState();
}

class _HomeyHistoryWidgetState extends State<HomeyHistoryWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile {
  String get _log => widget.w.option('log', '').trim();
  String get _path =>
      homeyLogPath(_log, widget.w.option('range', 'last24Hours'));

  @override
  Iterable<String> watched(HomeyService homey) => const [];

  @override
  Map<String, Duration> asks(HomeyService homey) => _log.isEmpty
      ? const {}
      : {
          _path: const Duration(minutes: 5),
          'insights/log': const Duration(minutes: 30),
        };

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    if (homey.configured && _log.isEmpty) {
      return TileMessage(
        tr(
          'widget.homey_history.pick',
          'Pick what to chart in this widget’s settings in the editor.',
        ),
        theme: t,
      );
    }
    final waiting = notReady(homey, t, devices: false);
    if (waiting != null) return waiting;
    final points = homeyEntries(homey.answer(_path));
    final logs = homey.answer('insights/log');
    final about = (logs is Map ? logs.values : (logs is List ? logs : const []))
        .whereType<Map>()
        .where((l) => l['id'] == _log)
        .firstOrNull;
    final units = about?['units'] is String ? about!['units'] as String : '';
    final decimals = about?['decimals'] is num
        ? (about!['decimals'] as num).toInt().clamp(0, 2)
        : 1;
    final name = widget.w.option('name', '').trim();
    final title = name.isNotEmpty
        ? name
        : about == null
        ? ''
        : '${about['ownerName']} · ${about['title']}';
    if (points.length < 2) {
      return TileMessage(
        homey.answer(_path) == null
            ? tr('widget.homey.asking', 'Asking Homey…')
            : tr(
                'widget.homey_history.empty',
                'Homey has recorded nothing for this yet.',
              ),
        theme: t,
      );
    }
    final last = points.last.value;
    return LayoutBuilder(
      builder: (context, c) {
        final head = (c.maxHeight * 0.2).clamp(12.0, 30.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: head,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: head * 0.55,
                        height: 1,
                      ),
                    ),
                  ),
                  Text(
                    '${last.toStringAsFixed(decimals)}'
                    '${units.isEmpty || units == '%' ? units : ' $units'}',
                    maxLines: 1,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: head * 0.7,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CustomPaint(painter: _LinePainter(points, t.accent)),
            ),
          ],
        );
      },
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.points, this.colour);

  final List<({DateTime at, double value})> points;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.isEmpty) return;
    final from = points.first.at.millisecondsSinceEpoch;
    final span = math.max(1, points.last.at.millisecondsSinceEpoch - from);
    var low = points.first.value, high = low;
    for (final p in points) {
      low = math.min(low, p.value);
      high = math.max(high, p.value);
    }
    // A reading that never moved is a line across the middle.
    final range = high - low == 0 ? 1.0 : high - low;
    final floor = high - low == 0 ? low - 0.5 : low;
    Offset at(({DateTime at, double value}) p) => Offset(
      (p.at.millisecondsSinceEpoch - from) / span * size.width,
      size.height - 2 - (p.value - floor) / range * (size.height - 4),
    );
    final line = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (final p in points.skip(1)) {
      line.lineTo(at(p).dx, at(p).dy);
    }
    canvas.drawPath(
      Path.from(line)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = colour.withValues(alpha: 0.14),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size.height / 60)
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.points != points || old.colour != colour;
}

/// Who is home, who is out, and who has gone to bed — as Homey has it.
class HomeyPresenceWidget extends StatefulWidget {
  const HomeyPresenceWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeyPresenceWidget> createState() => _HomeyPresenceWidgetState();
}

class _HomeyPresenceWidgetState extends State<HomeyPresenceWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile {
  @override
  Iterable<String> watched(HomeyService homey) => const [];

  @override
  Map<String, Duration> asks(HomeyService homey) => const {
    'users/user': Duration(seconds: 30),
  };

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    final waiting = notReady(homey, t, devices: false);
    if (waiting != null) return waiting;
    final people = homeyPeople(homey.answer('users/user'));
    if (people.isEmpty) {
      return TileMessage(tr('widget.homey.asking', 'Asking Homey…'), theme: t);
    }
    return _Grid(
      children: [
        for (final p in people)
          _Card(
            icon: !p.present
                ? Icons.directions_walk_rounded
                : p.asleep
                ? Icons.bedtime_outlined
                : Icons.person_outline_rounded,
            label: p.name,
            value: p.state,
            theme: t,
            tint: p.present,
          ),
      ],
    );
  }
}

/// Homey's logic variables: each one's value, and a tap to flip a yes or no.
class HomeyVariablesWidget extends StatefulWidget {
  const HomeyVariablesWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeyVariablesWidget> createState() => _HomeyVariablesWidgetState();
}

class _HomeyVariablesWidgetState extends State<HomeyVariablesWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile {
  @override
  Iterable<String> watched(HomeyService homey) => const [];

  @override
  Map<String, Duration> asks(HomeyService homey) => const {
    'logic/variable': Duration(seconds: 15),
  };

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    final waiting = notReady(homey, t, devices: false);
    if (waiting != null) return waiting;
    final data = homey.answer('logic/variable');
    final all = <String, Map<dynamic, dynamic>>{
      if (data is Map)
        for (final v in data.values)
          if (v is Map && v['id'] is String) v['id'] as String: v,
    };
    final picked = [
      for (final r in widget.w.rows('variables'))
        if (r.text('variable').isNotEmpty)
          (id: '${r['variable']}'.trim(), name: r.text('name')),
    ];
    final shown = picked.isNotEmpty
        ? picked
        : [
            for (final v
                in all.values.toList()
                  ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}')))
              (id: v['id'] as String, name: ''),
          ];
    if (shown.isEmpty) {
      return TileMessage(
        data == null
            ? tr('widget.homey.asking', 'Asking Homey…')
            : tr(
                'widget.homey_variables.none',
                'No variables yet. Make one in Homey’s app, under Logic.',
              ),
        theme: t,
      );
    }
    return _Grid(
      children: [
        for (final p in shown)
          () {
            final v = all[p.id];
            final value = v?['value'];
            return _Card(
              icon: Icons.tune_rounded,
              label: p.name.isNotEmpty
                  ? p.name
                  : '${v?['name'] ?? tr('widget.homey_variables.variable', 'Variable')}',
              value: v == null
                  ? tr('widget.homey.notFound', 'Not found')
                  : value is bool
                  ? (value
                        ? tr('widget.homey_variables.yes', 'Yes')
                        : tr('widget.homey_variables.no', 'No'))
                  : '${value ?? '—'}',
              theme: t,
              warn: v == null,
              on: value is bool ? value : null,
              onTap: value is bool
                  ? () => homey.setVariable(p.id, !value)
                  : null,
            );
          }(),
      ],
    );
  }
}

/// Homey's timeline: what it has had to say lately, the newest first.
class HomeyTimelineWidget extends StatefulWidget {
  const HomeyTimelineWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeyTimelineWidget> createState() => _HomeyTimelineWidgetState();
}

class _HomeyTimelineWidgetState extends State<HomeyTimelineWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile {
  @override
  Iterable<String> watched(HomeyService homey) => const [];

  @override
  Map<String, Duration> asks(HomeyService homey) => const {
    'notifications/notification': Duration(minutes: 1),
  };

  static String _when(DateTime at) {
    final now = DateTime.now();
    return at.year == now.year && at.month == now.month && at.day == now.day
        ? hhmm(at)
        : '${at.day}/${at.month}';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    final waiting = notReady(homey, t, devices: false);
    if (waiting != null) return waiting;
    final data = homey.answer('notifications/notification');
    final notes = homeyTimeline(data);
    if (notes.isEmpty) {
      return TileMessage(
        data == null
            ? tr('widget.homey.asking', 'Asking Homey…')
            : tr('widget.homey_timeline.none', 'Nothing on Homey’s timeline.'),
        theme: t,
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        // As many lines as are comfortable to read, and no part of one.
        final row = (c.maxHeight / 6).clamp(26.0, 46.0);
        final fit = math.max(1, c.maxHeight ~/ row);
        final height = c.maxHeight / fit;
        return Column(
          children: [
            for (final n in notes.take(fit))
              SizedBox(
                height: height,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        n.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: row * 0.42,
                        ),
                      ),
                    ),
                    if (n.at != null && c.maxWidth > 160) ...[
                      SizedBox(width: row * 0.3),
                      Text(
                        _when(n.at!),
                        maxLines: 1,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: row * 0.36,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The Homey itself: what it is running, how long it has been up, and how
/// full its memory and storage are.
class HomeySystemWidget extends StatefulWidget {
  const HomeySystemWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HomeySystemWidget> createState() => _HomeySystemWidgetState();
}

class _HomeySystemWidgetState extends State<HomeySystemWidget>
    with PauseWhenHidden, ShownTimers, _HomeyTile {
  @override
  Iterable<String> watched(HomeyService homey) => const [];

  @override
  Map<String, Duration> asks(HomeyService homey) => const {
    'system/': Duration(seconds: 30),
    'system/memory': Duration(seconds: 30),
    'system/storage': Duration(minutes: 5),
  };

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final homey = context.watch<HomeyService>();
    final waiting = notReady(homey, t, devices: false);
    if (waiting != null) return waiting;
    final info = homey.answer('system/');
    if (info is! Map) {
      return TileMessage(tr('widget.homey.asking', 'Asking Homey…'), theme: t);
    }
    final memory = homey.answer('system/memory');
    final storage = homey.answer('system/storage');
    final uptime = info['uptime'];
    return _Grid(
      children: [
        _Card(
          icon: Icons.hub_outlined,
          label: '${info['homeyModelName'] ?? 'Homey'}',
          value: '${info['homeyVersion'] ?? '—'}',
          theme: t,
          tint: homey.live,
        ),
        _Card(
          icon: Icons.schedule_rounded,
          label: tr('widget.homey_system.uptime', 'Up for'),
          value: uptime is num ? homeyUptime(uptime) : '—',
          theme: t,
        ),
        _Card(
          icon: Icons.memory_rounded,
          label: tr('widget.homey_system.memory', 'Memory'),
          value: memory is Map
              ? homeyUsed(memory['total'], memory['free'])
              : homeyUsed(info['totalmem'], info['freemem']),
          theme: t,
        ),
        _Card(
          icon: Icons.storage_rounded,
          label: tr('widget.homey_system.storage', 'Storage'),
          value: storage is Map
              ? homeyUsed(storage['total'], storage['free'])
              : '—',
          theme: t,
        ),
      ],
    );
  }
}

const _whereTheKeyIs =
    'Your Homey’s address and API key are entered once, on the panel: '
    'Settings → Home → Homey.';

final homeyWidgetType = DashboardWidgetType(
  type: 'homey',
  category: WidgetCategory.homey,
  name: 'Homey devices',
  description:
      'Devices on your Homey that you pick — temperatures, doors, what a '
      'socket is drawing — each as a small card, changing as the device '
      'does. Lights and sockets switch with a tap; locks and doors are only '
      'ever shown. $_whereTheKeyIs',
  glyph: '🏠',
  defaultWidth: 4,
  defaultHeight: 2,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'devices',
      label: 'Devices',
      kind: OptionKind.list,
      addLabel: 'Add a device',
      help: 'Picked from what your Homey has.',
      fields: [
        WidgetOption(
          key: 'device',
          label: 'Device',
          kind: OptionKind.choice,
          choicesFrom: 'homeyDevices',
          defaultValue: '',
        ),
        WidgetOption(
          key: 'capability',
          label: 'Reading',
          defaultValue: '',
          help:
              'Optional — which of the device’s capabilities to show, by '
              'Homey’s name for it: measure_power, measure_humidity. Its '
              'main one otherwise.',
        ),
        WidgetOption(
          key: 'name',
          label: 'Call it',
          defaultValue: '',
          help: 'Optional — Homey’s own name for it otherwise.',
        ),
      ],
    ),
  ],
  preview: const [
    PreviewLine('Hall lamp  62%', scale: 0.14),
    PreviewLine('Front door  Closed', scale: 0.14),
  ],
  build: (context, w) => HomeyWidget(w: w),
);

final homeyRoomWidgetType = DashboardWidgetType(
  type: 'homey_room',
  category: WidgetCategory.homey,
  name: 'Homey room',
  description:
      'Everything Homey has in one room, each as a small card, with nothing '
      'to pick but the room — and a card for the room itself that switches '
      'the lot off, or on. $_whereTheKeyIs',
  glyph: '🛋️',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'zone',
      label: 'Room',
      kind: OptionKind.choice,
      choicesFrom: 'homeyZones',
      defaultValue: '',
    ),
    WidgetOption(
      key: 'show',
      label: 'Show',
      kind: OptionKind.choice,
      defaultValue: 'all',
      choices: {
        'all': 'Everything in it',
        'lights': 'Its lights',
        'switches': 'What a tap can switch',
      },
    ),
    WidgetOption(
      key: 'below',
      label: 'And the rooms inside it',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'Picking the house, or a floor, then shows every room of it.',
    ),
    WidgetOption(
      key: 'master',
      label: 'A card for the whole room',
      kind: OptionKind.boolean,
      defaultValue: true,
      help:
          'Says how many things are on, and switches them all off with a '
          'tap — or all on, when none is.',
    ),
  ],
  preview: const [
    PreviewLine('Lounge  2 on', scale: 0.14),
    PreviewLine('Lamp  40%    Fan  Off', scale: 0.14),
  ],
  build: (context, w) => HomeyRoomWidget(w: w),
);

final homeyLightsWidgetType = DashboardWidgetType(
  type: 'homey_lights',
  category: WidgetCategory.homey,
  name: 'Homey lights',
  description:
      'Your Homey’s lights, each with a bar to drag for how bright and a '
      'tap for on and off. $_whereTheKeyIs',
  glyph: '💡',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'lights',
      label: 'Lights',
      kind: OptionKind.list,
      addLabel: 'Add a light',
      help: 'Leave empty for every light your Homey has.',
      fields: [
        WidgetOption(
          key: 'light',
          label: 'Light',
          kind: OptionKind.choice,
          choicesFrom: 'homeyLights',
          defaultValue: '',
        ),
        WidgetOption(
          key: 'name',
          label: 'Call it',
          defaultValue: '',
          help: 'Optional — Homey’s own name for it otherwise.',
        ),
      ],
    ),
  ],
  preview: const [
    PreviewLine('💡 Lounge  50%', scale: 0.14),
    PreviewLine('▰▰▰▰▰▱▱▱▱▱', scale: 0.12),
  ],
  build: (context, w) => HomeyLightsWidget(w: w),
);

final homeyFlowsWidgetType = DashboardWidgetType(
  type: 'homey_flows',
  category: WidgetCategory.homey,
  name: 'Homey flows',
  description:
      'Buttons that start flows you have made in Homey — Goodnight, Movie '
      'time — with a tap. $_whereTheKeyIs',
  glyph: '▶️',
  defaultWidth: 3,
  defaultHeight: 2,
  minWidth: 1,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'flows',
      label: 'Flows',
      kind: OptionKind.list,
      addLabel: 'Add a flow',
      help:
          'Picked from the flows your Homey has. The API key needs to be '
          'allowed to see and start flows.',
      fields: [
        WidgetOption(
          key: 'flow',
          label: 'Flow',
          kind: OptionKind.choice,
          choicesFrom: 'homeyFlows',
          defaultValue: '',
        ),
        WidgetOption(
          key: 'name',
          label: 'Call it',
          defaultValue: '',
          help: 'Optional — the flow’s own name otherwise.',
        ),
      ],
    ),
  ],
  preview: const [
    PreviewLine('▶ Goodnight', scale: 0.14),
    PreviewLine('▶ Movie time', scale: 0.14),
  ],
  build: (context, w) => HomeyFlowsWidget(w: w),
);

/// A list option of devices picked from [list], each with a name of its own.
WidgetOption _picks(
  String key,
  String field, {
  required String label,
  required String one,
  required String add,
  required String list,
  required String help,
}) => WidgetOption(
  key: key,
  label: label,
  kind: OptionKind.list,
  addLabel: add,
  help: help,
  fields: [
    WidgetOption(
      key: field,
      label: one,
      kind: OptionKind.choice,
      choicesFrom: list,
      defaultValue: '',
    ),
    const WidgetOption(
      key: 'name',
      label: 'Call it',
      defaultValue: '',
      help: 'Optional — Homey’s own name for it otherwise.',
    ),
  ],
);

final homeyColourWidgetType = DashboardWidgetType(
  type: 'homey_colour',
  category: WidgetCategory.homey,
  name: 'Homey light colour',
  description:
      'Lights that change colour: a bar from cool white to warm, and a row '
      'of colours to touch. $_whereTheKeyIs',
  glyph: '🎨',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: [
    _picks(
      'lights',
      'light',
      label: 'Lights',
      one: 'Light',
      add: 'Add a light',
      list: 'homeyLights',
      help: 'Leave empty for every light that changes colour.',
    ),
  ],
  preview: const [
    PreviewLine('Lamp  40%', scale: 0.14),
    PreviewLine('🟥🟧🟨🟩🟦🟪', scale: 0.14),
  ],
  build: (context, w) => HomeyColourWidget(w: w),
);

final homeyFanWidgetType = DashboardWidgetType(
  type: 'homey_fan',
  category: WidgetCategory.homey,
  name: 'Homey fans',
  description:
      'Fans: a tap for on and off, a bar for how fast where the fan has '
      'one, and a button for turning its head. $_whereTheKeyIs',
  glyph: '🌀',
  defaultWidth: 3,
  defaultHeight: 1,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: [
    _picks(
      'fans',
      'fan',
      label: 'Fans',
      one: 'Fan',
      add: 'Add a fan',
      list: 'homeyDevices',
      help: 'Leave empty for every fan your Homey has.',
    ),
  ],
  preview: const [PreviewLine('🌀 Fan  On  ⇄', scale: 0.16)],
  build: (context, w) => HomeyFanWidget(w: w),
);

final homeyHouseWidgetType = DashboardWidgetType(
  type: 'homey_house',
  category: WidgetCategory.homey,
  name: 'Homey house',
  description:
      'Every room at once: how much is on in each, a tap to switch a room '
      'off or on, and one card that switches the whole house off. '
      '$_whereTheKeyIs',
  glyph: '🏘️',
  defaultWidth: 4,
  defaultHeight: 2,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'everything',
      label: 'A card for the whole house',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'Switches everything off with a tap — and only ever off.',
    ),
  ],
  preview: const [
    PreviewLine('Everything  3 on', scale: 0.14),
    PreviewLine('Lounge  2 on   Hall  1 on', scale: 0.14),
  ],
  build: (context, w) => HomeyHouseWidget(w: w),
);

final homeyMoodsWidgetType = DashboardWidgetType(
  type: 'homey_moods',
  category: WidgetCategory.homey,
  name: 'Homey moods',
  description:
      'Buttons that set a mood — a room’s lights as you saved them in '
      'Homey’s app. $_whereTheKeyIs',
  glyph: '✨',
  defaultWidth: 3,
  defaultHeight: 2,
  minWidth: 1,
  minHeight: 1,
  fitsItself: true,
  options: [
    _picks(
      'moods',
      'mood',
      label: 'Moods',
      one: 'Mood',
      add: 'Add a mood',
      list: 'homeyMoods',
      help: 'Leave empty for every mood your Homey has.',
    ),
  ],
  preview: const [
    PreviewLine('✨ Lounge  Evening', scale: 0.14),
    PreviewLine('✨ Lounge  Film', scale: 0.14),
  ],
  build: (context, w) => HomeyMoodsWidget(w: w),
);

final homeyAlertsWidgetType = DashboardWidgetType(
  type: 'homey_alerts',
  category: WidgetCategory.homey,
  name: 'Homey alerts',
  description:
      'Only what wants attention: doors and windows open, alarms going, '
      'batteries low, devices Homey cannot reach. Says "All quiet" when '
      'there is nothing. $_whereTheKeyIs',
  glyph: '🚨',
  defaultWidth: 3,
  defaultHeight: 2,
  minWidth: 1,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'battery',
      label: 'A battery is low at',
      kind: OptionKind.number,
      defaultValue: 20,
      help: 'Per cent.',
    ),
    WidgetOption(
      key: 'offline',
      label: 'Devices Homey cannot reach',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
  ],
  preview: const [
    PreviewLine('Back door  Open', scale: 0.14),
    PreviewLine('Hall sensor  Battery 12%', scale: 0.14),
  ],
  build: (context, w) => HomeyAlertsWidget(w: w),
);

final homeyClimateWidgetType = DashboardWidgetType(
  type: 'homey_climate',
  category: WidgetCategory.homey,
  name: 'Homey climate',
  description:
      'Temperatures: what each room is at and how damp, and for a '
      'thermostat what it is set to, with a step up and down. '
      '$_whereTheKeyIs',
  glyph: '🌡️',
  defaultWidth: 4,
  defaultHeight: 2,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: [
    _picks(
      'devices',
      'device',
      label: 'Thermostats and sensors',
      one: 'Device',
      add: 'Add one',
      list: 'homeyDevices',
      help: 'Leave empty for everything that measures temperature.',
    ),
  ],
  preview: const [
    PreviewLine('Lounge · 54%  20.5 °C', scale: 0.14),
    PreviewLine('−  21.0°  +', scale: 0.14),
  ],
  build: (context, w) => HomeyClimateWidget(w: w),
);

final homeyEnergyWidgetType = DashboardWidgetType(
  type: 'homey_energy',
  category: WidgetCategory.homey,
  name: 'Homey energy',
  description:
      'What the house is drawing now, and what is drawing most of it. '
      'Needs sockets or a meter that tell Homey their power. '
      '$_whereTheKeyIs',
  glyph: '⚡',
  defaultWidth: 3,
  defaultHeight: 2,
  minWidth: 1,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'count',
      label: 'How many of the biggest',
      kind: OptionKind.number,
      defaultValue: 5,
    ),
  ],
  preview: const [
    PreviewLine('⚡ Drawing now  850 W', scale: 0.14),
    PreviewLine('Kettle  620 W', scale: 0.14),
  ],
  build: (context, w) => HomeyEnergyWidget(w: w),
);

final homeyHistoryWidgetType = DashboardWidgetType(
  type: 'homey_history',
  category: WidgetCategory.homey,
  name: 'Homey history',
  description:
      'One of Homey’s logs as a line: a temperature over the day, a week '
      'of what a socket drew. $_whereTheKeyIs',
  glyph: '📈',
  defaultWidth: 4,
  defaultHeight: 2,
  minWidth: 2,
  minHeight: 1,
  options: const [
    WidgetOption(
      key: 'log',
      label: 'What to chart',
      kind: OptionKind.choice,
      choicesFrom: 'homeyLogs',
      defaultValue: '',
      help: 'From what Homey keeps under Insights.',
    ),
    WidgetOption(
      key: 'range',
      label: 'Over',
      kind: OptionKind.choice,
      defaultValue: 'last24Hours',
      choices: {
        'last6Hours': 'The last six hours',
        'last24Hours': 'The last day',
        'last7Days': 'The last week',
        'last31Days': 'The last month',
      },
    ),
    WidgetOption(
      key: 'name',
      label: 'Call it',
      defaultValue: '',
      help: 'Optional — Homey’s own name for it otherwise.',
    ),
  ],
  preview: const [
    PreviewLine('Weather · Temperature  19 °C', scale: 0.13),
    PreviewLine('▁▂▃▅▆▅▃▂', scale: 0.2),
  ],
  build: (context, w) => HomeyHistoryWidget(w: w),
);

final homeyPresenceWidgetType = DashboardWidgetType(
  type: 'homey_presence',
  category: WidgetCategory.homey,
  name: 'Homey who’s home',
  description:
      'Who is home, who is out and who has gone to bed, as Homey has it. '
      '$_whereTheKeyIs',
  glyph: '🧑‍🤝‍🧑',
  defaultWidth: 3,
  defaultHeight: 1,
  minWidth: 1,
  minHeight: 1,
  fitsItself: true,
  preview: const [PreviewLine('Vincent  Home', scale: 0.16)],
  build: (context, w) => HomeyPresenceWidget(w: w),
);

final homeyVariablesWidgetType = DashboardWidgetType(
  type: 'homey_variables',
  category: WidgetCategory.homey,
  name: 'Homey variables',
  description:
      'Homey’s logic variables: what each is, and a tap to flip one that '
      'is yes or no — "Guests staying". $_whereTheKeyIs',
  glyph: '🎚️',
  defaultWidth: 3,
  defaultHeight: 1,
  minWidth: 1,
  minHeight: 1,
  fitsItself: true,
  options: [
    _picks(
      'variables',
      'variable',
      label: 'Variables',
      one: 'Variable',
      add: 'Add a variable',
      list: 'homeyVariables',
      help: 'Leave empty for every variable your Homey has.',
    ),
  ],
  preview: const [PreviewLine('Guests staying  Yes', scale: 0.16)],
  build: (context, w) => HomeyVariablesWidget(w: w),
);

final homeyTimelineWidgetType = DashboardWidgetType(
  type: 'homey_timeline',
  category: WidgetCategory.homey,
  name: 'Homey timeline',
  description:
      'What Homey has had to say lately — its timeline, the newest first. '
      '$_whereTheKeyIs',
  glyph: '🗒️',
  defaultWidth: 4,
  defaultHeight: 2,
  minWidth: 2,
  minHeight: 1,
  preview: const [
    PreviewLine('Front door opened  18:42', scale: 0.13),
    PreviewLine('Washing finished  17:10', scale: 0.13),
  ],
  build: (context, w) => HomeyTimelineWidget(w: w),
);

final homeySystemWidgetType = DashboardWidgetType(
  type: 'homey_system',
  category: WidgetCategory.homey,
  name: 'Homey itself',
  description:
      'The Homey: what version it runs, how long it has been up, and how '
      'full its memory and storage are. $_whereTheKeyIs',
  glyph: '🧠',
  defaultWidth: 4,
  defaultHeight: 1,
  minWidth: 1,
  minHeight: 1,
  fitsItself: true,
  preview: const [PreviewLine('13.5.1 · up 3 d 4 h · 17%', scale: 0.14)],
  build: (context, w) => HomeySystemWidget(w: w),
);

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../look.dart';
import '../../services/home_assistant_service.dart';
import '../../widgets/lcars.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/shown_timers.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'tile_bits.dart';
import '../../map_text.dart';

/// Home Assistant as a starship's console, sized for a page of its own: a
/// rail down the left of Home Assistant's areas, and for the one chosen its
/// lights and switches as blocks to tap, its temperatures as readouts, and
/// the room's lights on or off at once.
///
/// The rooms are Home Assistant's own, so a light moved to another area in
/// Home Assistant moves here too; what is hidden there is left out here.
/// Drawn in LCARS whatever the dashboard's theme.
class HaBridgeWidget extends StatefulWidget {
  const HaBridgeWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<HaBridgeWidget> createState() => _HaBridgeWidgetState();
}

/// A room on the rail, or one of the rail's own groups.
class _Group {
  _Group(this.name, this.controls, this.readouts);

  final String name;
  final List<HaEntity> controls;
  final List<HaEntity> readouts;

  List<String> get lights => [
    for (final e in controls)
      if (e.domain == 'light') e.id,
  ];
}

class _HaBridgeWidgetState extends State<HaBridgeWidget>
    with PauseWhenHidden, ShownTimers {
  int _chosen = 0;

  /// The entities added under "Also show", each with what it is called.
  Map<String, String> get _extras => {
    for (final row in widget.w.rows('extras'))
      if (row.text('entity').contains('.'))
        '${row['entity']}'.trim(): row.text('name'),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    everyWhileShown(const Duration(seconds: 5), _refresh);
  }

  void _refresh() {
    if (!mounted) return;
    final ha = context.read<HomeAssistantService>();
    unawaited(ha.refresh());
    unawaited(ha.refreshAreas());
  }

  /// A reading worth a readout: a temperature, a humidity, a percentage.
  static bool _readout(HaEntity e) {
    if (e.domain != 'sensor' || e.unavailable) return false;
    final unit = '${e.attributes['unit_of_measurement'] ?? ''}';
    final kind = '${e.attributes['device_class'] ?? ''}';
    return unit == '°C' ||
        unit == '°F' ||
        kind == 'temperature' ||
        kind == 'humidity';
  }

  List<_Group> _groups(HomeAssistantService ha) {
    final groups = <_Group>[];
    final seen = <String>{};
    for (final area in ha.areas) {
      final here = [
        for (final id in area.entities)
          if (ha.entity(id) case final HaEntity e) e,
      ];
      final controls = [
        for (final e in here)
          if (e.switchable) e,
      ];
      final readouts = here.where(_readout).toList();
      if (controls.isEmpty && readouts.isEmpty) continue;
      seen.addAll(controls.map((e) => e.id));
      groups.add(_Group(area.name, controls, readouts));
    }
    final extras = [
      for (final id in _extras.keys)
        if (ha.entity(id) case final HaEntity e) e,
    ];
    if (extras.isNotEmpty) {
      groups.add(
        _Group(
          widget.w.option('extrasName', 'Systems'),
          [
            for (final e in extras)
              if (e.switchable) e,
          ],
          [
            for (final e in extras)
              if (!e.switchable) e,
          ],
        ),
      );
      seen.addAll(extras.where((e) => e.switchable).map((e) => e.id));
    }
    if (groups.length > 1) {
      groups.add(
        _Group(tr('widget.ha_bridge.everything', 'All decks'), [
          for (final g in groups)
            for (final e in g.controls) e,
        ], const []),
      );
    }
    return groups;
  }

  /// [e]'s name, less the room it is in where a name is left after it:
  /// "Living Room Lamp" is the lamp, but "Bedroom 1" stays itself, not "1".
  /// Anything added under "Also show" is called what it was given.
  String _name(HaEntity e, _Group g) {
    final given = _extras[e.id];
    if (given != null && given.isNotEmpty) return given;
    final name = e.name;
    final room = '${g.name} ';
    if (!name.toLowerCase().startsWith(room.toLowerCase())) return name;
    final rest = name.substring(room.length);
    return rest.contains(RegExp('[A-Za-z]')) ? rest : name;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final ha = context.watch<HomeAssistantService>();
    if (!ha.configured) {
      return TileMessage(
        tr(
          'widget.home_assistant.connectHomeAssistantInSettings',
          'Connect Home Assistant in Settings first — its address and a long-lived access token.',
        ),
        theme: t,
      );
    }
    final groups = _groups(ha);
    if (groups.isEmpty) {
      return TileMessage(
        ha.error ??
            tr(
              'widget.home_assistant.askingHomeAssistant',
              'Asking Home Assistant…',
            ),
        theme: t,
      );
    }
    final chosen = math.min(_chosen, groups.length - 1);
    // A console whatever the dashboard is dressed in: its own black, and
    // the LCARS theme for the blocks to take their colours from.
    final console = t.isLcars
        ? t
        : kBuiltInThemes.firstWhere((x) => x.isLcars, orElse: () => t);
    final page = KioskLook(
      theme: console,
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'Antonio'),
        child: LayoutBuilder(
          builder: (context, c) {
            final rail = (c.maxWidth * 0.2).clamp(140.0, 260.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: rail,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, g) in groups.indexed) ...[
                          if (i > 0) const SizedBox(height: lcarsLine),
                          LcarsRailBlock(
                            index: i,
                            label: g.name,
                            selected: i == chosen,
                            first: i == 0,
                            last: i == groups.length - 1,
                            onTap: () => setState(() => _chosen = i),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Deck(
                    group: groups[chosen],
                    console: console,
                    ha: ha,
                    nameOf: (e) => _name(e, groups[chosen]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (t.isLcars) return page;
    return ClipRRect(
      borderRadius: BorderRadius.circular(t.cornerRadius / 2),
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: Padding(padding: const EdgeInsets.all(12), child: page),
      ),
    );
  }
}

/// One room: its title bar, its readouts, its blocks, and its lights at once.
class _Deck extends StatelessWidget {
  const _Deck({
    required this.group,
    required this.console,
    required this.ha,
    required this.nameOf,
  });

  final _Group group;
  final DashboardTheme console;
  final HomeAssistantService ha;
  final String Function(HaEntity) nameOf;

  @override
  Widget build(BuildContext context) {
    final active = group.controls.where((e) => e.on).length;
    final now = TimeOfDay.now();
    final clock =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final lights = group.lights;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LcarsTextBar(
          title: lcarsCaps(group.name),
          note: tr('widget.ha_bridge.active', '{count} active · {time}', {
            'count': '$active',
            'time': clock,
          }).toUpperCase(),
        ),
        if (group.readouts.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, e) in group.readouts.indexed)
                LcarsReadout(
                  colour: console.block(i + 2),
                  name: lcarsCaps(nameOf(e)),
                  value: e.display,
                  width: 340,
                  height: 36,
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: _Blocks(
            group: group,
            console: console,
            ha: ha,
            nameOf: nameOf,
          ),
        ),
        if (lights.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: LcarsBlock(
                  colour: console.block(1),
                  ends: LcarsEnds.start,
                  height: 52,
                  onTap: () => ha.callService('light', 'turn_on', lights),
                  child: Text(
                    tr('widget.ha_bridge.lightsOn', 'Lights on').toUpperCase(),
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              ),
              const SizedBox(width: lcarsLine),
              Expanded(
                child: LcarsBlock(
                  colour: console.block(4),
                  ends: LcarsEnds.end,
                  height: 52,
                  onTap: () => ha.callService('light', 'turn_off', lights),
                  child: Text(
                    tr(
                      'widget.ha_bridge.lightsOff',
                      'Lights off',
                    ).toUpperCase(),
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The room's lights and switches, as many to a row as are a thumb wide and
/// as tall as the room allows: switched on, near-white; off, the console's
/// colour; out of reach, unlit and still.
class _Blocks extends StatelessWidget {
  const _Blocks({
    required this.group,
    required this.console,
    required this.ha,
    required this.nameOf,
  });

  final _Group group;
  final DashboardTheme console;
  final HomeAssistantService ha;
  final String Function(HaEntity) nameOf;

  @override
  Widget build(BuildContext context) {
    final controls = group.controls;
    if (controls.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          tr(
            'widget.ha_bridge.nothingToSwitch',
            'Nothing to switch here',
          ).toUpperCase(),
          style: TextStyle(color: console.textSecondary, fontSize: 24),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 10.0;
        final columns = math.max(1, (c.maxWidth / 230).floor());
        final rows = (controls.length / columns).ceil();
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        final height = ((c.maxHeight - gap * (rows - 1)) / rows).clamp(
          64.0,
          120.0,
        );
        return SingleChildScrollView(
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final e in controls)
                LcarsBlock(
                  colour: e.on ? lcarsLit : console.block(lcarsIndex(e.id)),
                  width: width,
                  height: height,
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.symmetric(horizontal: height * 0.38),
                  onTap: e.unavailable ? null : () => ha.toggle(e),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lcarsCaps(nameOf(e)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: height * 0.32, height: 1.05),
                      ),
                      Text(
                        lcarsCaps(e.display),
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: height * 0.2,
                          fontWeight: FontWeight.w400,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

final haBridgeWidgetType = DashboardWidgetType(
  type: 'ha_bridge',
  category: WidgetCategory.house,
  name: 'Home Assistant bridge',
  description:
      'Home Assistant as a starship’s console, for a page of its own: its '
      'rooms down the side, and each room’s lights and switches to tap, its '
      'temperatures, and all its lights on or off at once.',
  glyph: '🖖',
  defaultWidth: 12,
  defaultHeight: 8,
  minWidth: 6,
  minHeight: 4,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'extras',
      label: 'Also show',
      kind: OptionKind.list,
      addLabel: 'Add an entity',
      help:
          'Things in no room in Home Assistant — a power strip, the panel’s '
          'own screen — shown together on the rail under their own name.',
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
    WidgetOption(
      key: 'extrasName',
      label: 'Called',
      defaultValue: 'Systems',
      help: 'The name on the rail for what is added above.',
    ),
  ],
  preview: const [
    PreviewLine('LOUNGE   BEDROOM   HALLWAY', scale: 0.12, accent: true),
    PreviewLine('LOUNGE 1 · LAMP · SYNC BOX', scale: 0.1),
  ],
  build: (context, w) => HaBridgeWidget(w: w),
);

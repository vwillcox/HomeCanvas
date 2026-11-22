import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../look.dart';
import '../services/config_service.dart';
import '../services/home_assistant_service.dart';
import '../services/routines.dart';

/// Settings → Screen, under Voice control: the routines — one thing said
/// that does several, "I'm going to bed" — each to change, and more to add.
class RoutinesTile extends StatelessWidget {
  const RoutinesTile({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ConfigService>();
    final routines = service.config.routines;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.bedtime_outlined),
          title: Text(tr('settings.routines', 'Routines')),
          subtitle: Text(
            tr(
              'settings.routinesAbout',
              'One thing said after “{wake}” that does several — “I’m going to bed” puts the lights and the TV off. The TV and the lights answer by themselves too: “turn the TV on”, “lights off”.',
              {'wake': service.config.screen.wakeWord.phrase},
            ),
          ),
          isThreeLine: true,
          trailing: IconButton(
            icon: const Icon(Icons.add),
            tooltip: tr('settings.addARoutine', 'Add a routine'),
            onPressed: () => _edit(context, null),
          ),
        ),
        for (final r in routines)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: Text(r.name),
            subtitle: Text(_summary(r)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _edit(context, r),
          ),
      ],
    );
  }

  /// "“I'm going to bed”, “Goodnight” → lights off, TV off".
  static String _summary(HomeRoutine r) {
    final said = r.phrases.isEmpty
        ? tr('settings.routineNoPhrases', 'Nothing sets it off yet')
        : r.phrases.take(3).map((p) => '“$p”').join(', ') +
              (r.phrases.length > 3 ? '…' : '');
    final does = [
      for (final s in RoutineStep.values)
        if (r.steps.contains(s)) _stepName(s),
      if (r.lights.isNotEmpty)
        tr(
          'settings.routineLightsSetN',
          '{n, plural, one{# light set} other{# lights set}}',
          {'n': r.lights.fold<int>(0, (n, l) => n + l.targets.length)},
        ),
      if (r.otherLightsOff)
        tr('settings.routineOthersOffShort', 'the rest off'),
      if (r.ask.isNotEmpty)
        tr('settings.routineAsksN', '{count} for Home Assistant', {
          'count': '${r.ask.length}',
        }),
      for (final q in r.questions) '“${q.prompt}”',
    ];
    return does.isEmpty ? said : '$said → ${does.join(', ')}';
  }

  static String _stepName(RoutineStep s) => switch (s) {
    RoutineStep.lightsOff => tr('settings.routineLightsOff', 'lights off'),
    RoutineStep.lightsOn => tr('settings.routineLightsOn', 'lights on'),
    RoutineStep.tvOff => tr('settings.routineTvOff', 'TV off'),
    RoutineStep.tvOn => tr('settings.routineTvOn', 'TV on'),
    RoutineStep.artMatrixOff => tr(
      'settings.routineArtMatrixOff',
      'Art Matrix off',
    ),
    RoutineStep.artMatrixOn => tr(
      'settings.routineArtMatrixOn',
      'Art Matrix on',
    ),
    RoutineStep.musicOff => tr('settings.routineMusicOff', 'playing stopped'),
    RoutineStep.screenOff => tr('settings.routineScreenOff', 'screen off'),
  };

  Future<void> _edit(BuildContext context, HomeRoutine? existing) async {
    final service = context.read<ConfigService>();
    final r = existing ?? HomeRoutine(name: '');
    final name = TextEditingController(text: r.name);
    final phrases = TextEditingController(text: r.phrases.join('\n'));
    final asks = TextEditingController(text: r.ask.join('\n'));
    final reply = TextEditingController(text: r.reply);
    var tv = _Switch.of(r.steps, RoutineStep.tvOn, RoutineStep.tvOff);
    var lights = _Switch.of(
      r.steps,
      RoutineStep.lightsOn,
      RoutineStep.lightsOff,
    );
    var artMatrix = _Switch.of(
      r.steps,
      RoutineStep.artMatrixOn,
      RoutineStep.artMatrixOff,
    );
    // Only for a panel with one, or a routine that has it already: Bedtime
    // starts with it, set up or not.
    final showArtMatrix =
        service.config.artMatrix.enabled || artMatrix != _Switch.leave;
    var stopPlaying = r.steps.contains(RoutineStep.musicOff);
    var screenOff = r.steps.contains(RoutineStep.screenOff);
    // Copies, edited in the dialog and kept only on Save.
    final setLights = [for (final l in r.lights) l.copy()];
    final questions = [for (final q in r.questions) q.copy()];
    var othersOff = r.otherLightsOff;

    Widget field(
      String label,
      TextEditingController c, {
      String? hint,
      bool lines = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        minLines: lines ? 2 : 1,
        maxLines: lines ? 5 : 1,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );

    Widget choice(
      IconData icon,
      String label,
      _Switch value,
      void Function(_Switch) set,
    ) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      trailing: DropdownButton<_Switch>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (final s in _Switch.values)
            DropdownMenuItem(value: s, child: Text(s.label)),
        ],
        onChanged: (v) {
          if (v != null) set(v);
        },
      ),
    );

    final outcome = await showDialog<_Outcome>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            existing == null
                ? tr('settings.newRoutine', 'New routine')
                : tr('settings.routine', 'Routine'),
          ),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  field(
                    tr('settings.routineName', 'Name'),
                    name,
                    hint: tr('settings.routineNameHint', 'Bedtime'),
                  ),
                  field(
                    tr(
                      'settings.routinePhrases',
                      'What sets it off — one to a line',
                    ),
                    phrases,
                    hint: tr(
                      'settings.routinePhrasesHint',
                      'I’m going to bed\nGoodnight',
                    ),
                    lines: true,
                  ),
                  choice(
                    Icons.lightbulb_outline,
                    tr('settings.routineLights', 'The lights'),
                    lights,
                    (v) => setState(() => lights = v),
                  ),
                  choice(
                    Icons.tv,
                    tr('settings.routineTv', 'The TV'),
                    tv,
                    (v) => setState(() => tv = v),
                  ),
                  if (showArtMatrix)
                    choice(
                      Icons.grid_on,
                      tr('settings.routineArtMatrix', 'The Art Matrix'),
                      artMatrix,
                      (v) => setState(() => artMatrix = v),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.stop_circle_outlined),
                    title: Text(
                      tr(
                        'settings.routineStopPlaying',
                        'Stop the music, the radio and any video',
                      ),
                    ),
                    value: stopPlaying,
                    onChanged: (v) => setState(() => stopPlaying = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.brightness_2_outlined),
                    title: Text(
                      tr(
                        'settings.routineScreenOffTitle',
                        'Put this screen out',
                      ),
                    ),
                    subtitle: Text(
                      tr(
                        'settings.routineScreenOffAbout',
                        'A few seconds after, so the reply is seen. A touch brings it back.',
                      ),
                    ),
                    value: screenOff,
                    onChanged: (v) => setState(() => screenOff = v),
                  ),
                  _HomeAssistantParts(
                    lights: setLights,
                    questions: questions,
                    othersOff: othersOff,
                    onOthersOff: (v) => setState(() => othersOff = v),
                  ),
                  const SizedBox(height: 12),
                  field(
                    tr(
                      'settings.routineAsk',
                      'Also ask Home Assistant — one to a line',
                    ),
                    asks,
                    hint: tr(
                      'settings.routineAskHint',
                      'turn off the purifier\nactivate PC mode',
                    ),
                    lines: true,
                  ),
                  field(
                    tr('settings.routineReply', 'Reply, said out loud'),
                    reply,
                    hint: tr('settings.routineReplyHint', 'Goodnight'),
                  ),
                  Text(
                    tr(
                      'settings.routineLightsNote',
                      'The lights are every light Home Assistant’s Assist can see — choose which in Home Assistant, under Voice assistants → Expose.',
                    ),
                    style: TextStyle(
                      color: context.look.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(_Outcome.delete),
                child: Text(
                  tr('settings.delete', 'Delete'),
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(tr('settings.cancel', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(_Outcome.save),
              child: Text(tr('settings.save', 'Save')),
            ),
          ],
        ),
      ),
    );

    List<String> lines(TextEditingController c) => [
      for (final l in c.text.split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];

    final routines = service.config.routines;
    switch (outcome) {
      case null:
        return;
      case _Outcome.delete:
        routines.remove(existing);
      case _Outcome.save:
        r
          ..name = name.text.trim().isEmpty
              ? tr('settings.routine', 'Routine')
              : name.text.trim()
          ..phrases = lines(phrases)
          ..ask = lines(asks)
          ..lights = [
            for (final l in setLights)
              if (l.targets.isNotEmpty) l,
          ]
          ..otherLightsOff = othersOff
          ..questions = [
            for (final q in questions)
              if (q.prompt.trim().isNotEmpty && q.entity.contains('.'))
                q..prompt = q.prompt.trim(),
          ]
          ..reply = reply.text.trim()
          ..steps = {
            ?lights.step(RoutineStep.lightsOn, RoutineStep.lightsOff),
            ?tv.step(RoutineStep.tvOn, RoutineStep.tvOff),
            ?artMatrix.step(RoutineStep.artMatrixOn, RoutineStep.artMatrixOff),
            if (stopPlaying) RoutineStep.musicOff,
            if (screenOff) RoutineStep.screenOff,
          };
        if (existing == null) routines.add(r);
    }
    await service.save();
  }
}

enum _Outcome { save, delete }

/// Off, on, or left as it is — for the TV and for the lights.
enum _Switch {
  leave,
  off,
  on;

  static _Switch of(Set<RoutineStep> steps, RoutineStep on, RoutineStep off) =>
      steps.contains(off)
      ? _Switch.off
      : steps.contains(on)
      ? _Switch.on
      : _Switch.leave;

  RoutineStep? step(RoutineStep on, RoutineStep off) => switch (this) {
    _Switch.leave => null,
    _Switch.off => off,
    _Switch.on => on,
  };

  String get label => switch (this) {
    _Switch.leave => tr('settings.routineLeave', 'Leave alone'),
    _Switch.off => tr('settings.routineOff', 'Off'),
    _Switch.on => tr('settings.routineOn', 'On'),
  };
}

/// What Home Assistant can do in a routine besides what Assist is asked:
/// lights put on to a brightness and a white, every other light put off,
/// and questions asked out loud — "Do you want the heater on or off?" —
/// whose answer switches something.
class _HomeAssistantParts extends StatefulWidget {
  const _HomeAssistantParts({
    required this.lights,
    required this.questions,
    required this.othersOff,
    required this.onOthersOff,
  });

  final List<RoutineLights> lights;
  final List<RoutineQuestion> questions;
  final bool othersOff;
  final ValueChanged<bool> onOthersOff;

  @override
  State<_HomeAssistantParts> createState() => _HomeAssistantPartsState();
}

/// What there is in Home Assistant to choose from.
class _Choices {
  const _Choices({
    this.lights = const [],
    this.areas = const [],
    this.things = const [],
  });
  final List<HaChoice> lights;
  final List<HaArea> areas;

  /// What a question's answer can switch.
  final List<HaChoice> things;

  String nameOf(String target) {
    if (target.startsWith(RoutineLights.areaPrefix)) {
      final id = target.substring(RoutineLights.areaPrefix.length);
      final area = areas.where((a) => a.id == id).firstOrNull;
      return tr('settings.routineWholeRoom', 'all of {room}', {
        'room': area?.name ?? id,
      });
    }
    return lights.where((l) => l.id == target).firstOrNull?.name ?? target;
  }
}

class _HomeAssistantPartsState extends State<_HomeAssistantParts> {
  late final Future<_Choices> _choices = _load(
    context.read<HomeAssistantService?>(),
  );

  /// What a question can switch: whatever `homeassistant.turn_on` reaches
  /// that is worth asking about. Not locks, covers or alarms.
  static const _switchable = {
    'climate', 'fan', 'switch', 'water_heater', 'humidifier', //
    'input_boolean', 'light',
  };

  static Future<_Choices> _load(HomeAssistantService? ha) async {
    if (ha == null || !ha.configured) return const _Choices();
    await ha.refreshAreas();
    final found = await Future.wait([
      ha.entityChoices({'light'}),
      ha.entityChoices(_switchable),
    ]);
    return _Choices(lights: found[0], areas: ha.areas, things: found[1]);
  }

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    return FutureBuilder<_Choices>(
      future: _choices,
      builder: (context, snap) {
        final c = snap.data ?? const _Choices();
        final loading = snap.connectionState != ConnectionState.done;
        final none = !loading && c.lights.isEmpty && c.things.isEmpty;
        Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(),
            heading(tr('settings.routineSetLights', 'Lights to set')),
            for (final l in widget.lights) _lightsCard(c, l),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(tr('settings.routineAddLights', 'Add lights')),
                  onPressed: c.lights.isEmpty
                      ? null
                      : () async {
                          final picked = await _pick(c, const []);
                          if (picked == null || picked.isEmpty) return;
                          setState(
                            () => widget.lights.add(
                              RoutineLights(
                                targets: picked,
                                brightness: 80,
                                white: LightWhite.warm,
                              ),
                            ),
                          );
                        },
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.lightbulb_outline),
              title: Text(
                tr('settings.routineOthersOff', 'Turn every other light off'),
              ),
              subtitle: Text(
                tr(
                  'settings.routineOthersOffAbout',
                  'Every light Home Assistant shows that is on, but for those set above.',
                ),
              ),
              value: widget.othersOff,
              onChanged: widget.onOthersOff,
            ),
            const Divider(),
            heading(tr('settings.routineQuestions', 'Questions')),
            Text(
              tr(
                'settings.routineQuestionsAbout',
                'Asked out loud once the rest is done. Answer “on” or “off” — no need for “{wake}” first — or touch the answer on the screen. Saying nothing leaves it as it is.',
                {
                  'wake': context
                      .read<ConfigService>()
                      .config
                      .screen
                      .wakeWord
                      .phrase,
                },
              ),
              style: TextStyle(color: look.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 8),
            for (final q in widget.questions) _questionCard(c, q),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(tr('settings.routineAddQuestion', 'Add a question')),
              onPressed: c.things.isEmpty
                  ? null
                  : () => setState(
                      () => widget.questions.add(
                        RoutineQuestion(prompt: '', entity: ''),
                      ),
                    ),
            ),
            if (none)
              Text(
                tr(
                  'settings.routineNoHomeAssistant',
                  'Lights and questions need Home Assistant, set up and answering, under Home Assistant in these settings.',
                ),
                style: TextStyle(color: look.textSecondary, fontSize: 14),
              ),
            const Divider(),
          ],
        );
      },
    );
  }

  Widget _lightsCard(_Choices c, RoutineLights l) {
    final brightness = l.brightness;
    return Card(
      key: ObjectKey(l),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.targets.map(c.nameOf).join(', '),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: tr('settings.routineChooseLights', 'Choose lights'),
                  onPressed: () async {
                    final picked = await _pick(c, l.targets);
                    if (picked == null) return;
                    setState(() {
                      if (picked.isEmpty) {
                        widget.lights.remove(l);
                      } else {
                        l.targets = picked;
                      }
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: tr('settings.delete', 'Delete'),
                  onPressed: () => setState(() => widget.lights.remove(l)),
                ),
              ],
            ),
            Row(
              children: [
                Text(tr('settings.routineBrightness', 'Brightness')),
                Expanded(
                  child: Slider(
                    value: (brightness ?? 0).toDouble(),
                    max: 100,
                    divisions: 20,
                    onChanged: (v) =>
                        setState(() => l.brightness = v < 5 ? null : v.round()),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    brightness == null
                        ? tr('settings.routineAsItWas', 'As it was')
                        : '$brightness%',
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(tr('settings.routineColour', 'Colour')),
                const Spacer(),
                DropdownButton<LightWhite?>(
                  value: l.white,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(
                      child: Text(tr('settings.routineAsItWas', 'As it was')),
                    ),
                    for (final w in LightWhite.values)
                      DropdownMenuItem(value: w, child: Text(_white(w))),
                  ],
                  onChanged: (v) => setState(() => l.white = v),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _white(LightWhite w) => switch (w) {
    LightWhite.warm => tr('settings.routineWarmWhite', 'Warm white'),
    LightWhite.neutral => tr('settings.routineNeutralWhite', 'Neutral white'),
    LightWhite.cool => tr('settings.routineCoolWhite', 'Cool white'),
  };

  Widget _questionCard(_Choices c, RoutineQuestion q) {
    final known = c.things.any((t) => t.id == q.entity);
    return Card(
      key: ObjectKey(q),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: q.prompt,
                    style: const TextStyle(fontSize: 18),
                    decoration: InputDecoration(
                      labelText: tr('settings.routineQuestion', 'Asked'),
                      hintText: tr(
                        'settings.routineQuestionHint',
                        'Do you want the heater on or off?',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => q.prompt = v,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: tr('settings.delete', 'Delete'),
                  onPressed: () => setState(() => widget.questions.remove(q)),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  tr('settings.routineAnswerSwitches', 'The answer switches'),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: known ? q.entity : null,
                    hint: Text(
                      q.entity.isEmpty
                          ? tr('settings.routineChoose', 'Choose…')
                          : q.entity,
                    ),
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final t in c.things)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text(
                            t.area.isEmpty ? t.name : '${t.name} · ${t.area}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      final t = c.things.where((t) => t.id == v).firstOrNull;
                      if (t == null) return;
                      setState(() {
                        q.entity = t.id;
                        q.name = t.name.toLowerCase();
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Rooms and lights to tick; what was ticked, or null for Cancel.
  Future<List<String>?> _pick(_Choices c, List<String> chosen) {
    final picked = {...chosen};
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          Widget tick(String target, String title, String? subtitle) =>
              CheckboxListTile(
                value: picked.contains(target),
                title: Text(title),
                subtitle: subtitle == null || subtitle.isEmpty
                    ? null
                    : Text(subtitle),
                onChanged: (v) => setState(
                  () => v == true ? picked.add(target) : picked.remove(target),
                ),
              );
          return AlertDialog(
            title: Text(tr('settings.routineChooseLights', 'Choose lights')),
            content: SizedBox(
              width: 520,
              height: 480,
              child: ListView(
                children: [
                  for (final a in c.areas)
                    if (a.entities.any((e) => e.startsWith('light.')))
                      tick(
                        '${RoutineLights.areaPrefix}${a.id}',
                        tr('settings.routineWholeRoomTitle', 'All of {room}', {
                          'room': a.name,
                        }),
                        tr(
                          'settings.routineWholeRoomAbout',
                          'Every light in it, as Home Assistant has them',
                        ),
                      ),
                  const Divider(),
                  for (final l in c.lights) tick(l.id, l.name, l.area),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(tr('settings.cancel', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop([
                  // Rooms first, then lights, in the order offered.
                  for (final a in c.areas)
                    if (picked.contains('${RoutineLights.areaPrefix}${a.id}'))
                      '${RoutineLights.areaPrefix}${a.id}',
                  for (final l in c.lights)
                    if (picked.contains(l.id)) l.id,
                  // Kept: chosen before, and gone from Home Assistant since.
                  for (final t in chosen)
                    if (picked.contains(t) &&
                        !c.lights.any((l) => l.id == t) &&
                        !c.areas.any(
                          (a) => '${RoutineLights.areaPrefix}${a.id}' == t,
                        ))
                      t,
                ]),
                child: Text(tr('settings.done', 'Done')),
              ),
            ],
          );
        },
      ),
    );
  }
}

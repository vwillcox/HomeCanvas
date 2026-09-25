import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/chores_service.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// Chores and rewards: a column per person with today's chores to tap off,
/// stars for each, and the week's total towards a reward.
class ChoresWidget extends StatelessWidget {
  const ChoresWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  List<ChorePerson> get _people => [
    for (final r in (w.config.options['people'] as List? ?? const []))
      if (r is Map) ?ChorePerson.fromRow(r.cast<String, dynamic>()),
  ];

  List<Chore> get _chores => [
    for (final r in (w.config.options['chores'] as List? ?? const []))
      if (r is Map) ?Chore.fromRow(r.cast<String, dynamic>()),
  ];

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final service = context.watch<ChoresService>();
    final people = _people;
    final chores = _chores;
    if (people.isEmpty || chores.isEmpty) {
      return TileMessage(
        'Add the people and their chores in the widget settings — and a '
        'weekly star goal with a reward, if you like.',
        theme: t,
      );
    }
    final today = service.today;
    final goal = int.tryParse('${w.config.options['goal'] ?? 0}') ?? 0;
    final reward = '${w.config.options['reward'] ?? ''}'.trim();

    return LayoutBuilder(
      builder: (context, c) {
        final gap = math.min(c.maxWidth, c.maxHeight) * 0.03;
        final colW = (c.maxWidth - gap * (people.length - 1)) / people.length;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < people.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              SizedBox(
                width: colW,
                child: _Column(
                  board: w.config.id,
                  person: people[i],
                  chores: [
                    for (final ch in chores)
                      if (ch.dueOn(today) &&
                          (ch.anyone ||
                              ch.who.toLowerCase() ==
                                  people[i].name.toLowerCase()))
                        ch,
                  ],
                  goal: goal,
                  reward: reward,
                  service: service,
                  theme: t,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.board,
    required this.person,
    required this.chores,
    required this.goal,
    required this.reward,
    required this.service,
    required this.theme,
  });

  final String board;
  final ChorePerson person;
  final List<Chore> chores;
  final int goal;
  final String reward;
  final ChoresService service;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final stars = service.starsThisWeek(board, person.name);
    final reached = goal > 0 && stars >= goal;
    final left = chores.where((c) => service.doneBy(board, c) == null).length;

    return LayoutBuilder(
      builder: (context, c) {
        final headH = math.min(c.maxHeight * 0.2, 70.0);
        final listH = c.maxHeight - headH - 6;
        final rowH = chores.isEmpty
            ? 0.0
            : (listH / chores.length).clamp(34.0, 84.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: headH,
              child: FitCanvas(
                designHeight: 44,
                maxScale: 3,
                builder: (context, size) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: person.colour,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            person.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        // The count shrinks before the row runs out of room.
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            // Drawn with icons, not emoji: the panel may have
                            // no emoji font, and the star is the point.
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  reached
                                      ? Icons.celebration_rounded
                                      : Icons.star_rounded,
                                  size: 14,
                                  color: reached
                                      ? person.colour
                                      : const Color(0xFFFFD27A),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '$stars${goal > 0 && !reached ? '/$goal' : ''}',
                                  style: TextStyle(
                                    color: reached
                                        ? person.colour
                                        : theme.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (goal > 0)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (stars / goal).clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: theme.textSecondary.withValues(
                            alpha: 0.15,
                          ),
                          valueColor: AlwaysStoppedAnimation(person.colour),
                        ),
                      ),
                    if (reached && reward.isNotEmpty)
                      Text(
                        reward,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: person.colour,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else
                      Text(
                        chores.isEmpty
                            ? 'Nothing today'
                            : left == 0
                            ? 'All done today!'
                            : '$left to do today',
                        maxLines: 1,
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 9,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                physics: rowH * chores.length > listH
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                children: [
                  for (final ch in chores)
                    SizedBox(
                      height: rowH,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: rowH * 0.1),
                        child: _ChoreTile(
                          chore: ch,
                          doneBy: service.doneBy(board, ch),
                          person: person,
                          theme: theme,
                          onTap: () => service.toggle(board, ch, person.name),
                        ),
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

class _ChoreTile extends StatelessWidget {
  const _ChoreTile({
    required this.chore,
    required this.doneBy,
    required this.person,
    required this.theme,
    required this.onTap,
  });

  final Chore chore;
  final String? doneBy;
  final ChorePerson person;
  final DashboardTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = doneBy != null;
    final mine = doneBy == person.name;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: done
              ? person.colour.withValues(alpha: mine ? 0.22 : 0.08)
              : theme.textSecondary.withValues(alpha: 0.08),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: FitCanvas(
          designHeight: 30,
          maxScale: 3,
          // Too narrow for words: just the chore's picture (or its name,
          // shrunk), with the tile's colour saying whether it is done.
          builder: (context, size) => size.width < 64
              ? Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      chore.emoji.isNotEmpty ? chore.emoji : chore.task,
                      maxLines: 1,
                      style: TextStyle(color: theme.textPrimary, fontSize: 15),
                    ),
                  ),
                )
              : Row(
                  children: [
                    if (chore.emoji.isNotEmpty) ...[
                      Text(chore.emoji, style: const TextStyle(fontSize: 15)),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        chore.task,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: done ? theme.textSecondary : theme.textPrimary,
                          fontSize: 12,
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: done
                            ? Text(
                                mine ? '✓' : '✓ ${doneBy!}',
                                style: TextStyle(
                                  color: mine
                                      ? person.colour
                                      : theme.textSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (
                                    var i = 0;
                                    i < chore.stars.clamp(1, 3);
                                    i++
                                  )
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 11,
                                      color: Color(0xFFFFD27A),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

final choresWidgetType = DashboardWidgetType(
  type: 'chores',
  category: WidgetCategory.house,
  name: 'Chores & rewards',
  description:
      'A column per person with today’s chores to tap off. Each '
      'earns stars; a weekly goal unlocks a reward. "Anyone" chores appear '
      'for everybody and go to whoever does them. Resets each Monday.',
  glyph: '⭐',
  defaultWidth: 6,
  defaultHeight: 4,
  minWidth: 2,
  minHeight: 2,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'people',
      label: 'People',
      kind: OptionKind.list,
      addLabel: 'Add a person',
      fields: [
        WidgetOption(key: 'name', label: 'Name', defaultValue: ''),
        WidgetOption(
          key: 'colour',
          label: 'Colour',
          kind: OptionKind.colour,
          defaultValue: '#A6C8FF',
        ),
      ],
    ),
    WidgetOption(
      key: 'chores',
      label: 'Chores',
      kind: OptionKind.list,
      addLabel: 'Add a chore',
      help:
          'Who: a name, or empty for anyone. Days: daily, weekdays, '
          'weekends, or days like Mon Wed Fri.',
      fields: [
        WidgetOption(key: 'task', label: 'Chore', defaultValue: ''),
        WidgetOption(
          key: 'emoji',
          label: 'Picture (an emoji)',
          defaultValue: '',
        ),
        WidgetOption(key: 'who', label: 'Who', defaultValue: ''),
        WidgetOption(key: 'days', label: 'Days', defaultValue: 'daily'),
        WidgetOption(
          key: 'stars',
          label: 'Stars',
          kind: OptionKind.number,
          defaultValue: 1,
        ),
      ],
    ),
    WidgetOption(
      key: 'goal',
      label: 'Stars a week for the reward',
      kind: OptionKind.number,
      defaultValue: 20,
      help: '0 for no goal.',
    ),
    WidgetOption(key: 'reward', label: 'The reward', defaultValue: ''),
  ],
  preview: const [
    PreviewLine('Sam ⭐ 12/20     Jo ⭐ 15/20', scale: 0.12),
    PreviewLine('🛏️ Make bed ✓     🐟 Feed fish', scale: 0.12),
  ],
  build: (context, w) => ChoresWidget(w: w),
);

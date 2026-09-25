import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/bin_schedule.dart' show dateOnly, daysBetween;
import '../../services/immich_service.dart';
import '../../widgets/remote_image.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// Someone's next birthday.
@immutable
class NextBirthday {
  const NextBirthday(this.person, this.day, this.turning);

  final Person person;
  final DateTime day;

  /// The age they will be.
  final int turning;

  /// The next birthday on or after [today] for everyone with a birth date,
  /// soonest first. A 29 February birthday falls on the 28th in other years.
  static List<NextBirthday> upcoming(List<Person> people, DateTime today) {
    final d = dateOnly(today);
    final out = <NextBirthday>[];
    for (final p in people) {
      final b = p.birthDate;
      if (b == null) continue;
      DateTime on(int year) {
        final x = DateTime(year, b.month, b.day);
        return x.month == b.month ? x : DateTime(year, b.month + 1, 0);
      }

      var next = on(d.year);
      if (next.isBefore(d)) next = on(d.year + 1);
      out.add(NextBirthday(p, next, next.year - b.year));
    }
    out.sort((a, b) => a.day.compareTo(b.day));
    return out;
  }
}

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Today 🎂", "Tomorrow", "Sat", "14 Oct" — how far off a birthday is.
String birthdayWhen(int days, DateTime d) => switch (days) {
  0 => 'Today 🎂',
  1 => 'Tomorrow',
  < 7 => _dayNames[d.weekday - 1],
  _ => '${d.day} ${_monthNames[d.month - 1]}',
};

/// Birthdays coming up, from the people Immich recognises in your photos —
/// with their faces.
class BirthdaysWidget extends StatefulWidget {
  const BirthdaysWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  /// People to use instead of asking Immich, for tests.
  @visibleForTesting
  static List<Person>? debugPeople;

  @override
  State<BirthdaysWidget> createState() => _BirthdaysWidgetState();
}

class _BirthdaysWidgetState extends State<BirthdaysWidget> {
  /// Shared by every tile; people and their birthdays change rarely.
  static (List<Person>, DateTime)? _cache;
  List<Person>? _people = _cache?.$1;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(hours: 1), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (BirthdaysWidget.debugPeople != null) {
      setState(() => _people = BirthdaysWidget.debugPeople);
      return;
    }
    final c = _cache;
    if (c != null &&
        DateTime.now().difference(c.$2) < const Duration(hours: 6)) {
      setState(() => _people = c.$1);
      return;
    }
    try {
      final people = await context.read<ImmichService>().people();
      _cache = (people, DateTime.now());
      if (mounted) setState(() => _people = people);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach Immich');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final people = _people;
    if (people == null) {
      return TileMessage(_error ?? 'Asking Immich…', theme: t);
    }
    final now = DateTime.now();
    final max = (int.tryParse('${widget.w.config.options['show'] ?? 4}') ?? 4)
        .clamp(1, 12);
    final list = NextBirthday.upcoming(people, now).take(max).toList();
    if (list.isEmpty) {
      return TileMessage(
        'No birthdays yet. In Immich, open a person and set their date of '
        'birth — they appear here.',
        theme: t,
      );
    }
    final media = context.read<ImmichService>();

    return LayoutBuilder(
      builder: (context, c) {
        final labelH = (c.maxHeight * 0.1).clamp(18.0, 34.0);
        final listH = c.maxHeight - labelH * 1.4;
        final rowH = math.min(listH / list.length, 96.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: labelH,
              child: TileLabel(
                icon: Icons.cake_outlined,
                text: 'Birthdays',
                theme: t,
                size: labelH * 0.6,
              ),
            ),
            SizedBox(height: labelH * 0.4),
            for (final b in list)
              SizedBox(
                height: rowH,
                child: FitCanvas(
                  designHeight: 44,
                  maxScale: 3,
                  builder: (context, size) {
                    final days = daysBetween(now, b.day);
                    return Row(
                      children: [
                        ClipOval(
                          child: SizedBox.square(
                            dimension: 34,
                            child: BirthdaysWidget.debugPeople != null
                                ? ColoredBox(
                                    color: t.accent.withValues(alpha: 0.3),
                                  )
                                : RemoteImage(
                                    url: media.personThumbUrl(b.person.id),
                                    headers: media.authHeaders,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b.person.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: 15,
                                  fontWeight: days == 0
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                              Text(
                                'turns ${b.turning}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.textSecondary,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              birthdayWhen(days, b.day),
                              style: TextStyle(
                                color: days <= 1 ? t.accent : t.textSecondary,
                                fontSize: 13,
                                fontWeight: days <= 1
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

final birthdaysWidgetType = DashboardWidgetType(
  type: 'birthdays',
  category: WidgetCategory.photosAndMedia,
  name: 'Birthdays',
  description:
      'Birthdays coming up, with faces, from the people Immich '
      'recognises in your photos. Set a date of birth on a person in Immich '
      'and they appear here.',
  glyph: '🎂',
  defaultWidth: 3,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'show',
      label: 'How many to show',
      kind: OptionKind.number,
      defaultValue: 4,
    ),
  ],
  preview: const [
    PreviewLine('🎂 Sam — Tomorrow · turns 9', scale: 0.13),
    PreviewLine('Jo — 14 Oct · turns 41', scale: 0.12, muted: true),
  ],
  build: (context, w) => BirthdaysWidget(w: w),
);

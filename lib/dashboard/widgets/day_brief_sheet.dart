import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/dates.dart';
import '../../look.dart';
import '../../l10n/l10n.dart';
import '../../services/article_reader.dart';
import '../../services/bin_schedule.dart';
import '../../services/bins_service.dart';
import '../../services/config_service.dart';
import '../../services/feed_service.dart';
import '../../services/parcels_service.dart';
import '../../services/reminders_service.dart';
import '../../services/timer_service.dart';
import '../../services/weather_service.dart';
import '../../time_format.dart';
import '../../widgets/glass.dart' show greetingFor;
import '../../widgets/lcars.dart';
import '../../widgets/weather_overlay.dart' show weatherIcon;
import '../dashboard_theme.dart';
import '../day_brief.dart';
import 'calendar_view.dart';
import 'tile_bits.dart';

/// The day, put together from every tile on the panel that knows something
/// about it, as of [now]. [listen] as in `Provider.of`: true in a build.
DayBrief gatherDayBrief(
  BuildContext context,
  DateTime now, {
  bool listen = true,
}) {
  T? of<T>() => Provider.of<T?>(context, listen: listen);
  final widgets = of<ConfigService>()?.config.dashboard.widgets ?? const [];
  final feeds = of<FeedService>();
  final events = <(CalendarEvent, Color)>[];
  final bins = <BinCollection>[];
  final seen = <String>{};
  for (final w in widgets) {
    if (w.type == 'calendar' && feeds != null) {
      for (final s in DashboardCalendarWidget.feedsOf(w)) {
        if (!seen.add(s.url)) continue;
        for (final e in feeds.calendar(s.url)) {
          events.add((e, s.colour ?? const Color(0xFF9999FF)));
        }
      }
    } else if (w.type == 'bins') {
      final next = BinCollection.next(
        BinsService.binsOf(w),
        now,
        remindFrom: BinsService.hourOption(w, 'remindFrom', 17),
        collectedBy: BinsService.hourOption(w, 'collectedBy', 12),
      );
      if (next != null) bins.add(next);
    }
  }
  return DayBrief.gather(
    now: now,
    weather: of<WeatherService>()?.weather,
    events: events,
    reminders: of<RemindersService>()?.reminders ?? const [],
    parcels: of<ParcelsService>()?.parcels ?? const [],
    bins: bins,
    timers: of<TimerService>()?.timers ?? const [],
  );
}

bool _open = false;

/// Opens the day over whatever is showing, in the dashboard's look — and
/// reads it out, when [read]. Asked for again while it is up, it only
/// reads.
Future<void> showDayBrief(BuildContext context, {bool read = false}) async {
  if (_open) {
    if (read) DayBriefSheet.readNow.value++;
    return;
  }
  // The look the kiosk is in now: the dashboard's theme, as every screen
  // wears it.
  final theme = context.look;
  _open = true;
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: tr('brief.close', 'Close'),
      barrierColor: Colors.black.withValues(alpha: theme.isLcars ? 0.7 : 0.45),
      // A console's sheet is there at once; its rows light in steps.
      transitionDuration: theme.isLcars
          ? Duration.zero
          : const Duration(milliseconds: 320),
      pageBuilder: (context, _, _) => DayBriefSheet(theme: theme, read: read),
      transitionBuilder: (context, animation, _, child) {
        if (theme.isLcars) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return AnimatedBuilder(
          animation: curved,
          builder: (context, _) => BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: 14 * curved.value,
              sigmaY: 14 * curved.value,
            ),
            child: FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.05),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  } finally {
    _open = false;
  }
}

/// The day at a glance: the weather and tomorrow down one side, today as
/// a line of times down the other — what is over dimmed, now marked, the
/// next thing lit — and a button to have it read out.
class DayBriefSheet extends StatefulWidget {
  const DayBriefSheet({
    super.key,
    required this.theme,
    this.read = false,
    this.autoClose = const Duration(minutes: 3),
  });

  final DashboardTheme theme;
  final bool read;

  /// Put away by itself after this, unless it is being read out: a panel
  /// left showing it is not showing everything else.
  final Duration autoClose;

  /// Asked for again by voice while it is up: read it from the start.
  static final readNow = ValueNotifier<int>(0);

  @override
  State<DayBriefSheet> createState() => _DayBriefSheetState();
}

class _DayBriefSheetState extends State<DayBriefSheet> {
  DateTime _now = DateTime.now();
  Timer? _minute;
  Timer? _step;
  Timer? _close;

  /// How many of its rows are lit so far: they come on one at a time.
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _reader = context.read<ArticleReader?>();
    _minute = Timer.periodic(
      const Duration(minutes: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
    _step = Timer.periodic(const Duration(milliseconds: 60), (t) {
      if (!mounted || _shown > 40) return t.cancel();
      setState(() => _shown++);
    });
    _wait();
    DayBriefSheet.readNow.addListener(_read);
    if (widget.read) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _read());
    }
  }

  @override
  void dispose() {
    DayBriefSheet.readNow.removeListener(_read);
    _minute?.cancel();
    _step?.cancel();
    _close?.cancel();
    final reader = _reader;
    if (reader != null && reader.active && reader.title == _title) {
      unawaited(reader.stop());
    }
    super.dispose();
  }

  ArticleReader? _reader;

  static String get _title => tr('brief.title', 'Your day');

  void _wait() {
    _close?.cancel();
    _close = Timer(widget.autoClose, () {
      if (!mounted) return;
      final reader = _reader;
      if (reader != null && reader.active && reader.title == _title) {
        return _wait();
      }
      _putAway();
    });
  }

  void _putAway() {
    if (!mounted) return;
    // This sheet only: a screen opened over it since — a recipe from a
    // share — stays where it is, and the sheet goes from underneath it.
    final route = ModalRoute.of(context);
    if (route == null) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else if (route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  void _read() {
    if (!mounted) return;
    _wait();
    final brief = gatherDayBrief(context, DateTime.now(), listen: false);
    unawaited(_reader?.say(title: _title, paragraphs: brief.spoken()));
  }

  void _stop() {
    _wait();
    unawaited(_reader?.stop());
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final brief = gatherDayBrief(context, _now);
    final reader = context.watch<ArticleReader?>();
    final reading = reader != null && reader.active && reader.title == _title;
    final screen = MediaQuery.sizeOf(context);

    return SafeArea(
      child: Center(
        child: GestureDetector(
          // Taps on the sheet are not taps on the barrier behind it.
          onTap: _wait,
          child: Container(
            width: math.min(screen.width * 0.95, 1800),
            height: math.min(screen.height * 0.93, 1120),
            decoration: t.isLcars
                ? BoxDecoration(color: t.background.first)
                : BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        for (final c
                            in t.background.length > 1
                                ? t.background
                                : [t.background.first, t.background.first])
                          c.withValues(alpha: 0.97),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: t.border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 60,
                        offset: Offset(0, 20),
                      ),
                    ],
                  ),
            padding: const EdgeInsets.fromLTRB(36, 26, 28, 30),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    theme: t,
                    now: _now,
                    reading: reading,
                    onRead: reading ? _stop : _read,
                    onClose: () => Navigator.of(context).maybePop(),
                  ),
                  SizedBox(height: t.isLcars ? 18 : 22),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 5,
                                child: _Lit(
                                  on: _shown > 0,
                                  theme: t,
                                  child: _WeatherPanel(brief: brief, theme: t),
                                ),
                              ),
                              SizedBox(height: t.isLcars ? 8 : 20),
                              Expanded(
                                flex: 4,
                                child: _Tomorrow(
                                  brief: brief,
                                  theme: t,
                                  shown: _shown - 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: t.isLcars ? 10 : 28),
                        Expanded(
                          flex: 7,
                          child: _Today(brief: brief, theme: t, shown: _shown),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// On once its turn comes: at once on a console, which lights in steps;
/// faded in elsewhere.
class _Lit extends StatelessWidget {
  const _Lit({required this.on, required this.theme, required this.child});

  final bool on;
  final DashboardTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) => theme.isLcars
      ? Visibility.maintain(visible: on, child: child)
      : AnimatedOpacity(
          opacity: on ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          child: child,
        );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.theme,
    required this.now,
    required this.reading,
    required this.onRead,
    required this.onClose,
  });

  final DashboardTheme theme;
  final DateTime now;
  final bool reading;
  final VoidCallback onRead;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final readText = reading
        ? tr('brief.stopReading', 'Stop reading')
        : tr('brief.readAloud', 'Read it to me');
    final readIcon = reading ? Icons.stop_rounded : Icons.record_voice_over;
    if (t.isLcars) {
      return Row(
        children: [
          Expanded(
            child: LcarsTextBar(
              title: greetingFor(now),
              note: [_title, longDate(now)].join(' · '),
            ),
          ),
          const SizedBox(width: 12),
          LcarsBlock(
            colour: reading ? lcarsLit : t.block(1),
            onTap: onRead,
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(readIcon, color: lcarsInk, size: 28),
                const SizedBox(width: 12),
                Text(
                  lcarsCaps(readText),
                  style: const TextStyle(
                    color: lcarsInk,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: tr('brief.close', 'Close'),
            child: LcarsBlock(
              colour: t.block(4),
              onTap: onClose,
              width: 104,
              height: 60,
              child: const Icon(Icons.close, size: 34, color: lcarsInk),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greetingFor(now),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$_title  ·  ${longDate(now)}',
                style: TextStyle(color: t.textSecondary, fontSize: 22),
              ),
            ],
          ),
        ),
        Material(
          color: reading ? t.accent : t.textPrimary.withValues(alpha: 0.08),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onRead,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    readIcon,
                    size: 28,
                    color: reading ? inkOn(t.accent) : t.textPrimary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    readText,
                    style: TextStyle(
                      color: reading ? inkOn(t.accent) : t.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Semantics(
          button: true,
          label: tr('brief.close', 'Close'),
          child: Material(
            color: t.textPrimary.withValues(alpha: 0.08),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onClose,
              child: SizedBox(
                width: 64,
                height: 64,
                child: Icon(Icons.close, color: t.textPrimary, size: 34),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String get _title => tr('brief.title', 'Your day');
}

/// A panel of the sheet: a console's frame, named on its bar, or a card.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.theme,
    required this.label,
    required this.child,
    this.down = false,
  });

  final DashboardTheme theme;
  final String label;
  final Widget child;
  final bool down;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    if (t.isLcars) {
      return LcarsPanel(
        theme: t,
        label: label,
        down: down,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, down ? 4 : 10, 6, down ? 10 : 4),
          child: child,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 18, 22, 18),
      decoration: BoxDecoration(
        color: t.textPrimary.withValues(alpha: t.isLight ? 0.04 : 0.06),
        borderRadius: BorderRadius.circular(t.cornerRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _WeatherPanel extends StatelessWidget {
  const _WeatherPanel({required this.brief, required this.theme});

  final DayBrief brief;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final w = brief.weather;
    final label = w == null || w.label.isEmpty
        ? tr('brief.weather', 'Weather')
        : w.label;
    if (w == null) {
      return _Panel(
        theme: t,
        label: label,
        child: Center(
          child: Text(
            tr('brief.waitingForWeather', 'Waiting for the weather…'),
            style: TextStyle(color: t.textSecondary, fontSize: 24),
          ),
        ),
      );
    }
    final rain = DayBrief.rainWindow(w, brief.now);
    final sunset = brief.today
        .where((i) => i.kind == BriefKind.sunset)
        .firstOrNull;
    final small = TextStyle(color: t.textSecondary, fontSize: 24, height: 1.3);
    return _Panel(
      theme: t,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        weatherIcon(w.weatherCode, w.isDay),
                        size: 96,
                        color: t.accent,
                      ),
                      const SizedBox(width: 20),
                      Text(
                        '${w.temperature.round()}°',
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 104,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tileCased(t, w.description),
                    style: TextStyle(
                      color: t.accent,
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr('brief.highLow', 'High {high}° · low {low}°', {
                      'high': w.tempMax.round(),
                      'low': w.tempMin.round(),
                    }),
                    style: small.copyWith(color: t.textPrimary),
                  ),
                  const SizedBox(height: 10),
                  _Fact(
                    icon: rain == null
                        ? Icons.wb_sunny_outlined
                        : Icons.umbrella,
                    text: rain == null
                        ? tr('brief.dryToday', 'Dry for the rest of the day')
                        : tr('brief.rainWindow', 'Rain likely {from}–{to}', {
                            'from': hhmm(rain.from),
                            'to': rain.to.hour == 0 ? '00:00' : hhmm(rain.to),
                          }),
                    style: small,
                    colour: t.textSecondary,
                  ),
                  if (sunset?.at case final at?)
                    _Fact(
                      icon: Icons.wb_twilight,
                      text: tr('brief.sunsetAt', 'Sunset {time}', {
                        'time': hhmm(at),
                      }),
                      style: small,
                      colour: t.textSecondary,
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 118,
            child: _Hours(weather: w, theme: t),
          ),
        ],
      ),
    );
  }
}

/// The next few hours: when, the sky, how warm, and the chance of rain
/// where there is one worth saying.
class _Hours extends StatelessWidget {
  const _Hours({required this.weather, required this.theme});

  final Weather weather;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day, now.hour);
    final hours = weather.hourly
        .where((h) => !h.time.isBefore(from))
        .take(8)
        .toList();
    if (hours.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (final (i, h) in hours.indexed)
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    i == 0
                        ? tileCased(t, tr('brief.nowShort', 'Now'))
                        : two(h.time.hour),
                    style: TextStyle(
                      color: i == 0 ? t.accent : t.textSecondary,
                      fontSize: 20,
                      fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    weatherIcon(h.weatherCode, h.isDay),
                    size: 30,
                    color: t.textPrimary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${h.temperature.round()}°',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    h.precipitationChance >= 20
                        ? '${h.precipitationChance}%'
                        : '',
                    style: TextStyle(
                      color: h.precipitationChance >= 50
                          ? t.accent
                          : t.textSecondary,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.text,
    required this.style,
    required this.colour,
  });

  final IconData icon;
  final String text;
  final TextStyle style;
  final Color colour;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 26, color: colour),
        const SizedBox(width: 10),
        Text(text, style: style),
      ],
    ),
  );
}

IconData _icon(BriefKind k) => switch (k) {
  BriefKind.event => Icons.event,
  BriefKind.reminder => Icons.notifications_active_outlined,
  BriefKind.parcel => Icons.local_shipping_outlined,
  BriefKind.bins => Icons.delete_outline,
  BriefKind.timer => Icons.timer_outlined,
  BriefKind.rain => Icons.umbrella,
  BriefKind.sunset => Icons.wb_twilight,
};

/// When, in a few characters: "10:15", "by 12:00", "All day".
String _when(BriefItem i) {
  if (i.at case final at?) return hhmm(at);
  if (i.until case final until?) {
    return tr('brief.by', 'by {time}', {'time': hhmm(until)});
  }
  return tr('brief.allDay', 'All day');
}

/// What else there is to say: where, which carrier, until when.
String _more(BriefItem i) => [
  if (i.detail case final d? when d.isNotEmpty) d,
  if (i.at != null && i.until != null)
    tr('brief.until', 'until {time}', {'time': hhmm(i.until!)}),
].join('  ·  ');

class _Today extends StatelessWidget {
  const _Today({required this.brief, required this.theme, required this.shown});

  final DayBrief brief;
  final DashboardTheme theme;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final items = brief.today;
    final ahead = brief.ahead.where((i) => i.kind != BriefKind.sunset).length;
    final label = ahead == 0
        ? tr('brief.today', 'Today')
        : tr('brief.todayAhead', 'Today · {count} to come', {'count': ahead});
    if (items.isEmpty) {
      return _Panel(
        theme: t,
        label: label,
        child: Center(
          child: Text(
            tr('brief.clearDay', 'A clear day: nothing on, nothing due.'),
            style: TextStyle(color: t.textSecondary, fontSize: 28),
          ),
        ),
      );
    }
    final next = brief.next;
    // Now goes before the first thing not over, once something is.
    final nowAt = items.indexWhere((i) => i.time != null && !i.over(brief.now));
    final rows = <Widget>[];
    for (final (n, i) in items.indexed) {
      if (n == nowAt && n > 0 && items[n - 1].time != null) {
        rows.add(_NowLine(theme: t, now: brief.now));
      }
      rows.add(
        _Lit(
          on: shown > n + 1,
          theme: t,
          child: _Line(
            item: i,
            theme: t,
            index: n,
            past: i.over(brief.now),
            next: identical(i, next),
            big: true,
          ),
        ),
      );
    }
    return _Panel(
      theme: t,
      label: label,
      child: ListView(padding: EdgeInsets.zero, children: rows),
    );
  }
}

class _Tomorrow extends StatelessWidget {
  const _Tomorrow({
    required this.brief,
    required this.theme,
    required this.shown,
  });

  final DayBrief brief;
  final DashboardTheme theme;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final day = DateTime(brief.now.year, brief.now.month, brief.now.day + 1);
    final forecast = brief.weather?.daily
        .where(
          (d) =>
              d.date.year == day.year &&
              d.date.month == day.month &&
              d.date.day == day.day,
        )
        .firstOrNull;
    final label = [
      tr('brief.tomorrow', 'Tomorrow'),
      if (forecast != null)
        '${forecast.tempMax.round()}° / ${forecast.tempMin.round()}°  '
            '${forecast.description}',
    ].join('  ·  ');
    return _Panel(
      theme: t,
      label: label,
      down: true,
      child: brief.tomorrow.isEmpty
          ? Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr('brief.nothingTomorrow', 'Nothing on yet'),
                style: TextStyle(color: t.textSecondary, fontSize: 24),
              ),
            )
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final (n, i) in brief.tomorrow.indexed)
                  _Lit(
                    on: shown > n,
                    theme: t,
                    child: _Line(
                      item: i,
                      theme: t,
                      index: n + 3,
                      past: false,
                      next: false,
                      big: false,
                    ),
                  ),
              ],
            ),
    );
  }
}

/// One thing in the day: when, what, and a word more.
class _Line extends StatelessWidget {
  const _Line({
    required this.item,
    required this.theme,
    required this.index,
    required this.past,
    required this.next,
    required this.big,
  });

  final BriefItem item;
  final DashboardTheme theme;
  final int index;
  final bool past;
  final bool next;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final h = big ? 78.0 : 58.0;
    final font = big ? 30.0 : 24.0;
    final more = _more(item);
    final when = _when(item);
    final colour = item.colour ?? t.block(index);
    final Widget time = t.isLcars
        ? Container(
            width: big ? 156 : 126,
            height: h - 12,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 14),
            decoration: BoxDecoration(
              color: next ? lcarsLit : colour,
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular((h - 12) / 2),
              ),
            ),
            child: Text(
              lcarsCaps(when),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: lcarsInk,
                fontSize: font * 0.85,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          )
        : SizedBox(
            width: big ? 132 : 112,
            child: Text(
              when,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: next ? t.accent : t.textSecondary,
                fontSize: font * 0.85,
                fontWeight: next ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          );
    return Opacity(
      opacity: past ? 0.38 : 1,
      child: SizedBox(
        height: h,
        child: Row(
          children: [
            time,
            SizedBox(width: t.isLcars ? 18 : 10),
            // A calendar's colour, or the room for one: the icons in a
            // line either way.
            if (!t.isLcars) ...[
              Container(
                width: 6,
                height: h * 0.55,
                decoration: BoxDecoration(
                  color: item.colour ?? Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Icon(
              _icon(item.kind),
              size: font * 0.95,
              color: next ? t.accent : t.textSecondary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: next && t.isLcars ? t.accent : t.textPrimary,
                      fontSize: font,
                      fontWeight: next ? FontWeight.w700 : FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
                  if (more.isNotEmpty)
                    Text(
                      more,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: font * 0.66,
                        height: 1.2,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where now is, between what is over and what is not.
class _NowLine extends StatelessWidget {
  const _NowLine({required this.theme, required this.now});

  final DashboardTheme theme;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final bar = Container(
      height: t.isLcars ? 6 : 2,
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(width: t.isLcars ? 156 : 132, child: bar),
          const SizedBox(width: 12),
          Text(
            tileCased(t, tr('brief.now', 'Now {time}', {'time': hhmm(now)})),
            style: TextStyle(
              color: t.accent,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: t.isLcars ? 1 : 0,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: bar),
        ],
      ),
    );
  }
}

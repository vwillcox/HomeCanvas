import 'dart:async';

import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/dates.dart';
import '../../l10n/l10n.dart';
import '../../look.dart';
import '../../screens/link_viewer_screen.dart';
import '../../services/parcels_service.dart';
import '../../services/share_inbox_service.dart';
import '../../services/side_browser.dart';
import '../../time_format.dart';
import '../../widgets/lcars.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'tile_bits.dart';

/// The parcels the house is waiting for: shared from a phone as a tracking
/// link or number, looked up with a tracking service if the tile has one,
/// and each a touch away from its details and its carrier's page.
class ParcelsWidget extends StatelessWidget {
  const ParcelsWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final service = context.watch<ParcelsService>();
    final parcels = service.parcels;
    if (parcels.isEmpty) {
      return TileMessage(
        tr(
          'widget.parcels.nothingComing',
          'No parcels on the way. Share a tracking link to the panel from '
              'your phone.',
        ),
        theme: t,
      );
    }
    final tracking = service.tracking;
    return LayoutBuilder(
      builder: (context, c) {
        final labelH = (c.maxHeight * 0.1).clamp(18.0, 34.0);
        final bodyH = c.maxHeight - labelH * 1.4;
        // A page to itself, or near enough: room for the list and, beside
        // it, a parcel's own tracking page.
        final desk =
            c.maxWidth >= 1000 &&
            c.maxHeight >= 460 &&
            c.maxWidth >= c.maxHeight * 1.3;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: labelH,
              child: TileLabel(
                icon: Icons.local_shipping_outlined,
                text: tr('widget.parcels.parcels', 'Parcels'),
                theme: t,
                size: labelH * 0.6,
                trailing: _summary(
                  service,
                  t,
                  labelH * 0.5,
                  // A narrow tile's heading has room for a word or two.
                  short: c.maxWidth < 460,
                ),
              ),
            ),
            SizedBox(height: labelH * 0.4),
            Expanded(
              child: desk
                  ? _ParcelDesk(parcels: parcels, theme: t, tracking: tracking)
                  : parcels.length == 1
                  ? _OneParcel(
                      parcel: parcels.single,
                      theme: t,
                      tracking: tracking,
                      height: bodyH,
                    )
                  : _ParcelList(
                      parcels: parcels,
                      theme: t,
                      tracking: tracking,
                      height: bodyH,
                    ),
            ),
          ],
        );
      },
    );
  }

  static Widget _summary(
    ParcelsService s,
    DashboardTheme t,
    double size, {
    required bool short,
  }) {
    final status = StatusColours.of(t);
    final error = s.serviceError;
    if (error != null) {
      return StatusChip(
        text: short
            ? tr('widget.parcels.keyRefusedShort', 'Key refused')
            : tr('widget.parcels.keyRefused', 'Tracking key refused'),
        colour: status.bad,
        size: size,
      );
    }
    final list = s.parcels;
    final out = list.where((p) => p.stage == ParcelStage.out).length;
    final collect = list.where((p) => p.stage == ParcelStage.pickup).length;
    final (text, colour) = out > 0
        ? (
            short
                ? tr('widget.parcels.outShort', '{count} out', {'count': out})
                : tr('widget.parcels.outCount', '{count} out for delivery', {
                    'count': out,
                  }),
            t.accent,
          )
        : collect > 0
        ? (
            tr('widget.parcels.collectCount', '{count} to collect', {
              'count': collect,
            }),
            status.warn,
          )
        : s.coming > 0
        ? (
            short
                ? tr('widget.parcels.comingShort', '{count} coming', {
                    'count': s.coming,
                  })
                : tr('widget.parcels.comingCount', '{count} on the way', {
                    'count': s.coming,
                  }),
            t.accent,
          )
        : (tr('widget.parcels.allHere', 'All here'), status.good);
    return StatusChip(text: text, colour: colour, size: size);
  }
}

/// What the parcel is called: what the sender said, or its carrier.
String parcelName(Parcel p) =>
    p.label ??
    (p.carrier == Carrier.unknown
        ? tr('widget.parcels.aParcel', 'A parcel')
        : tr('widget.parcels.carrierParcel', '{carrier} parcel', {
            'carrier': p.carrier.name,
          }));

/// Where it has got to, in a few words.
String parcelStage(Parcel p, {required bool tracking}) {
  if (p.number == null && !p.delivered) {
    // An Amazon order's link: nothing a tracking service can look up.
    return tr('widget.parcels.tapToLook', 'Tap to look');
  }
  return switch (p.stage) {
    ParcelStage.waiting =>
      !tracking
          ? tr('widget.parcels.notTracked', 'On its way')
          : p.error != null
          ? tr('widget.parcels.cannotLook', 'Could not look it up')
          : p.checkedAt == null
          ? tr('widget.parcels.lookingItUp', 'Looking it up…')
          : tr('widget.parcels.noNewsYet', 'No news yet'),
    ParcelStage.ordered => tr('widget.parcels.labelCreated', 'Label created'),
    ParcelStage.transit => tr('widget.parcels.onItsWay', 'On its way'),
    ParcelStage.out => tr('widget.parcels.outForDelivery', 'Out for delivery'),
    ParcelStage.pickup => tr(
      'widget.parcels.readyToCollect',
      'Ready to collect',
    ),
    ParcelStage.failed => tr('widget.parcels.missedYou', 'Missed you'),
    ParcelStage.delivered => tr('widget.parcels.delivered', 'Delivered'),
    ParcelStage.problem => tr('widget.parcels.needsALook', 'Needs a look'),
  };
}

/// The colour its stage is drawn in.
Color parcelColour(Parcel p, DashboardTheme t) {
  final status = StatusColours.of(t);
  return switch (p.stage) {
    ParcelStage.out => t.accent,
    ParcelStage.delivered => status.good,
    ParcelStage.pickup || ParcelStage.failed => status.warn,
    ParcelStage.problem => status.bad,
    _ => p.error != null ? status.warn : t.textPrimary,
  };
}

/// When it came, or when it should: "14:02", "Due tomorrow", "Due today,
/// 10:15–11:15".
String? parcelWhen(Parcel p, DateTime now) {
  if (p.delivered) {
    final at = p.deliveredAt ?? p.latest?.at;
    return at == null ? null : Refreshed.clock(at, now);
  }
  final from = p.expected;
  if (from == null) return null;
  final day = _dayWord(from, now);
  final to = p.expectedTo;
  final window = to != null && _sameDay(from, to) && to.isAfter(from);
  final when = !window
      ? day
      : from.hour != 0 || from.minute != 0
      ? '$day, ${hhmm(from)}–${hhmm(to)}'
      // Only an end: Amazon's "by 10pm".
      : tr('widget.parcels.dayBy', '{day}, by {time}', {
          'day': day,
          'time': hhmm(to),
        });
  return tr('widget.parcels.due', 'Due {when}', {'when': when});
}

/// What the card says as a parcel's window opens: "Due now, until 11:15",
/// "Due today, by 22:00", "Due today".
String parcelDueNow(Parcel p) {
  final from = p.expected;
  final to = p.expectedTo;
  if (from != null && to != null && to.isAfter(from)) {
    return from.hour != 0 || from.minute != 0
        ? tr('widget.parcels.dueNowUntil', 'Due now, until {time}', {
            'time': hhmm(to),
          })
        : tr('widget.parcels.dueTodayBy', 'Due today, by {time}', {
            'time': hhmm(to),
          });
  }
  return tr('widget.parcels.dueToday', 'Due today');
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dayWord(DateTime d, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final days = DateTime(d.year, d.month, d.day).difference(today).inDays;
  if (days == 0) return tr('widget.parcels.today', 'today');
  if (days == 1) return tr('widget.parcels.tomorrow', 'tomorrow');
  if (days > 1 && days < 7) return weekdayName(d);
  return weekdayDayMonth(d);
}

/// The carrier's mark: its letters on its colour.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.carrier,
    required this.size,
    required this.theme,
  });

  final Carrier carrier;
  final double size;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final colour = carrier.colour;
    return Container(
      width: size * 1.5,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(theme.isLcars ? 0 : size * 0.22),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: size * 0.12),
        child: FittedBox(
          child: Text(
            carrier.short,
            style: TextStyle(
              color: inkOn(colour),
              fontSize: size * 0.42,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Four steps — sent, on its way, out, here — lit as far as it has come.
/// Blocks on a console, which shows a state rather than moving to it.
class _Steps extends StatelessWidget {
  const _Steps({
    required this.parcel,
    required this.theme,
    required this.height,
    this.labels = false,
  });

  final Parcel parcel;
  final DashboardTheme theme;
  final double height;
  final bool labels;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final lit = parcelColour(parcel, t) == t.textPrimary
        ? t.accent
        : parcelColour(parcel, t);
    final step = parcel.number == null && !parcel.delivered
        ? -1
        : parcel.stage == ParcelStage.waiting && parcel.checkedAt == null
        ? -1
        : parcel.stage.step;
    final names = [
      tr('widget.parcels.stepSent', 'Sent'),
      tr('widget.parcels.stepOnItsWay', 'On its way'),
      parcel.stage == ParcelStage.pickup
          ? tr('widget.parcels.stepToCollect', 'To collect')
          : tr('widget.parcels.stepOut', 'Out'),
      tr('widget.parcels.stepHere', 'Here'),
    ];
    final gap = t.isLcars ? lcarsLine * 1.5 : height * 0.6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: i <= step
                        ? lit
                        : t.textSecondary.withValues(
                            alpha: t.isLcars ? 0.3 : 0.18,
                          ),
                    borderRadius: t.isLcars
                        ? (i == 0
                              ? BorderRadius.horizontal(
                                  left: Radius.circular(height / 2),
                                )
                              : i == 3
                              ? BorderRadius.horizontal(
                                  right: Radius.circular(height / 2),
                                )
                              : null)
                        : BorderRadius.circular(height / 2),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (labels) ...[
          SizedBox(height: height * 0.5),
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(
                  child: Text(
                    tileCased(t, names[i]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: i == 0
                        ? TextAlign.left
                        : i == 3
                        ? TextAlign.right
                        : TextAlign.center,
                    style: TextStyle(
                      color: i == step ? lit : t.textSecondary,
                      fontSize: height * 1.5,
                      fontWeight: i == step ? FontWeight.w700 : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// A single parcel, given the whole tile.
class _OneParcel extends StatelessWidget {
  const _OneParcel({
    required this.parcel,
    required this.theme,
    required this.tracking,
    required this.height,
  });

  final Parcel parcel;
  final DashboardTheme theme;
  final bool tracking;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final p = parcel;
    final now = DateTime.now();
    // About eight units of it go on the tile with the carrier's latest
    // word, under six without.
    final unit = (height / 8.5).clamp(10.0, 40.0);
    final when = parcelWhen(p, now);
    final latest = p.latest;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showParcel(context, p.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Badge(carrier: p.carrier, size: unit * 1.4, theme: t),
              SizedBox(width: unit * 0.6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      parcelName(p),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: unit * 0.95,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [
                        if (p.label != null) p.carrier.name,
                        if (p.number != null) p.number!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: unit * 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          shrinkInRow(
            Text(
              tileCased(t, parcelStage(p, tracking: tracking)),
              maxLines: 1,
              style: TextStyle(
                color: parcelColour(p, t),
                fontSize: unit * 1.6,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
          if (when != null)
            Text(
              when,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textPrimary, fontSize: unit * 0.8),
            ),
          SizedBox(height: unit * 0.6),
          _Steps(parcel: p, theme: t, height: unit * 0.4),
          if (latest != null && height >= unit * 8) ...[
            SizedBox(height: unit * 0.6),
            Text(
              [
                if (latest.at != null) Refreshed.clock(latest.at!, now),
                latest.text,
                if (latest.location != null) latest.location!,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: unit * 0.6,
                height: 1.25,
              ),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }
}

/// Several parcels, a row each, the nearest to the door first.
class _ParcelList extends StatelessWidget {
  const _ParcelList({
    required this.parcels,
    required this.theme,
    required this.tracking,
    required this.height,
    this.chosen,
    this.onTap,
  });

  final List<Parcel> parcels;
  final DashboardTheme theme;
  final bool tracking;
  final double height;

  /// The one shown beside the list, on a page-sized tile.
  final String? chosen;

  /// Instead of opening the parcel over everything.
  final void Function(Parcel)? onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final now = DateTime.now();
    // Rows share the height up to a comfortable size, and scroll beyond it
    // rather than shrinking into something too small to tap.
    final rowH = (height / parcels.length).clamp(46.0, 86.0);
    final font = rowH * 0.3;
    final choosing = onTap != null;
    return ListView(
      padding: EdgeInsets.zero,
      physics: rowH * parcels.length > height
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      children: [
        for (final p in parcels)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap != null ? onTap!(p) : showParcel(context, p.id),
            child: Container(
              height: rowH,
              padding: EdgeInsets.symmetric(
                horizontal: choosing ? font * 0.5 : 0,
              ),
              decoration: p.id == chosen
                  ? BoxDecoration(
                      color: t.accent.withValues(
                        alpha: t.isLcars ? 0.24 : 0.14,
                      ),
                      borderRadius: t.isLcars
                          ? null
                          : BorderRadius.circular(rowH * 0.2),
                    )
                  : null,
              child: Opacity(
                opacity: p.delivered ? 0.6 : 1,
                child: Row(
                  children: [
                    _Badge(carrier: p.carrier, size: font * 1.7, theme: t),
                    SizedBox(width: font * 0.6),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            parcelName(p),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: font * 1.15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            [
                              tileCased(t, parcelStage(p, tracking: tracking)),
                              ?parcelWhen(p, now),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: parcelColour(p, t),
                              fontSize: font * 0.9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: font * 0.6),
                    SizedBox(
                      width: rowH * 1.1,
                      child: _Steps(parcel: p, theme: t, height: font * 0.35),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

bool _sheetOpen = false;

/// Opens parcel [id] over whatever is on screen: where it has got to, what
/// the carrier has said, its tracking page, and the buttons to say it has
/// come or take it off the list.
///
/// From the tile, and from the card a shared parcel pops up with. Asked for
/// again while one is open, it stays as it is.
Future<void> showParcel(BuildContext context, String id) async {
  if (_sheetOpen) return;
  _sheetOpen = true;
  final theme = context.look;
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: tr('widget.parcels.close', 'Close'),
      barrierColor: Colors.black.withValues(alpha: 0.55),
      // A console puts its panel up whole; others ease it in.
      transitionDuration: theme.isLcars
          ? Duration.zero
          : const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) => ParcelSheet(id: id, theme: theme),
      transitionBuilder: (context, animation, _, child) => theme.isLcars
          ? child
          : FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            ),
    );
  } finally {
    _sheetOpen = false;
  }
}

/// One parcel, at length. Public so it can be tested on its own.
class ParcelSheet extends StatefulWidget {
  const ParcelSheet({
    super.key,
    required this.id,
    required this.theme,
    this.autoClose = const Duration(minutes: 2),
  });

  final String id;
  final DashboardTheme theme;
  final Duration autoClose;

  @override
  State<ParcelSheet> createState() => _ParcelSheetState();
}

class _ParcelSheetState extends State<ParcelSheet> {
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _wait();
  }

  /// Put away by itself, in time: a panel left on one parcel is not
  /// showing everything else.
  void _wait() {
    _timer?.cancel();
    _timer = Timer(widget.autoClose, _close);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _close() {
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

  Future<void> _openPage(Parcel p) async {
    // Not closed underneath the page, nor timed out while it is up.
    _timer?.cancel();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LinkViewerScreen(url: p.url, title: parcelName(p)),
      ),
    );
    if (mounted) _wait();
  }

  Future<void> _check(ParcelsService s, Parcel p) async {
    setState(() => _checking = true);
    _wait();
    try {
      await s.checkDue(only: p.id, asked: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final service = context.watch<ParcelsService>();
    final p = service.byId(widget.id);
    if (p == null) {
      // Taken off the list — here, or as it aged out.
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
      return const SizedBox.shrink();
    }
    final tracking = service.tracking;
    final radius = t.isLcars ? 0.0 : t.cornerRadius;
    final status = StatusColours.of(t);
    final from = p.from;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 900),
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  // Solid: a tile may be glass, and whatever was on screen
                  // would show through it.
                  color: t.background.first,
                  borderRadius: BorderRadius.circular(radius),
                  border: t.isLcars
                      ? Border(
                          left: BorderSide(color: p.carrier.colour, width: 14),
                        )
                      : Border.all(
                          color: t.textSecondary.withValues(alpha: 0.2),
                        ),
                ),
                padding: const EdgeInsets.fromLTRB(32, 26, 20, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _Badge(carrier: p.carrier, size: 56, theme: t),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tileCased(t, parcelName(p)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                [
                                  p.carrier.name,
                                  if (p.number != null) p.number!,
                                  if (from != null)
                                    tr(
                                      'widget.parcels.fromName',
                                      'from {name}',
                                      {'name': from},
                                    ),
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.textSecondary,
                                  fontSize: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          iconSize: 40,
                          tooltip: tr('widget.parcels.close', 'Close'),
                          icon: Icon(Icons.close, color: t.textSecondary),
                          onPressed: _close,
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    Expanded(
                      child: _ParcelStory(
                        parcel: p,
                        theme: t,
                        tracking: tracking,
                        serviceError: service.serviceError,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 14,
                      runSpacing: 12,
                      children: [
                        _SheetButton(
                          theme: t,
                          icon: Icons.open_in_new,
                          text: tr(
                            'widget.parcels.trackingPage',
                            'Tracking page',
                          ),
                          colour: p.carrier.colour,
                          onTap: () => _openPage(p),
                        ),
                        if (!p.delivered)
                          _SheetButton(
                            theme: t,
                            icon: Icons.event,
                            text: tr('widget.parcels.when', 'When?'),
                            colour: t.block(4),
                            onTap: () {
                              _wait();
                              showParcelDue(context, p.id, t);
                            },
                          ),
                        if (tracking && p.number != null && !p.delivered)
                          _SheetButton(
                            theme: t,
                            icon: Icons.refresh,
                            text: _checking
                                ? tr('widget.parcels.checking', 'Checking…')
                                : tr('widget.parcels.checkNow', 'Check now'),
                            colour: t.block(1),
                            onTap: _checking ? null : () => _check(service, p),
                          ),
                        _SheetButton(
                          theme: t,
                          icon: p.delivered
                              ? Icons.undo
                              : Icons.check_circle_outline,
                          text: p.delivered
                              ? tr('widget.parcels.notHereYet', 'Not here yet')
                              : tr('widget.parcels.itsHere', 'It’s here'),
                          colour: status.good,
                          onTap: () {
                            _wait();
                            service.setDelivered(p.id, !p.delivered);
                          },
                        ),
                        _SheetButton(
                          theme: t,
                          icon: Icons.delete_outline,
                          text: tr('widget.parcels.remove', 'Remove'),
                          colour: status.bad,
                          onTap: () => service.remove(p.id),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where a parcel has got to, at length: its stage, when it is due, the
/// steps, and what the carrier has said. On the sheet, and in the frame on
/// a page-sized tile.
class _ParcelStory extends StatelessWidget {
  const _ParcelStory({
    required this.parcel,
    required this.theme,
    required this.tracking,
    this.serviceError,
  });

  final Parcel parcel;
  final DashboardTheme theme;
  final bool tracking;
  final String? serviceError;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final p = parcel;
    final now = DateTime.now();
    final when = parcelWhen(p, now);
    final error = serviceError ?? p.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tileCased(t, parcelStage(p, tracking: tracking)),
          style: TextStyle(
            color: parcelColour(p, t),
            fontSize: 44,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        if (when != null)
          Text(when, style: TextStyle(color: t.textPrimary, fontSize: 24)),
        const SizedBox(height: 18),
        _Steps(parcel: p, theme: t, height: 14, labels: true),
        if (error != null) ...[
          const SizedBox(height: 14),
          Text(
            error,
            style: TextStyle(color: StatusColours.of(t).warn, fontSize: 18),
          ),
        ],
        const SizedBox(height: 18),
        Expanded(child: _events(p, t, now)),
      ],
    );
  }

  /// What the carrier has said, newest first.
  Widget _events(Parcel p, DashboardTheme t, DateTime now) {
    if (p.events.isEmpty) {
      final added = Refreshed.clock(p.added, now);
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          tr('widget.parcels.addedAt', 'Added {time}', {'time': added}),
          style: TextStyle(color: t.textSecondary, fontSize: 20),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: p.events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final e = p.events[i];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                e.at == null ? '' : Refreshed.clock(e.at!, now),
                style: TextStyle(
                  color: i == 0 ? parcelColour(p, t) : t.textSecondary,
                  fontSize: 20,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.text,
                    style: TextStyle(
                      color: i == 0 ? t.textPrimary : t.textSecondary,
                      fontSize: 21,
                      fontWeight: i == 0 ? FontWeight.w600 : null,
                    ),
                  ),
                  if (e.location != null)
                    Text(
                      e.location!,
                      style: TextStyle(color: t.textSecondary, fontSize: 17),
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

/// A page-sized tile: the list down one side and, beside it, the chosen
/// parcel in a frame — its story, or its carrier's own tracking page shown
/// right there in the frame.
///
/// The page is a real Firefox window laid exactly over the hole the frame
/// leaves for it ([SideBrowser]); the frame's buttons steer it. It stays
/// until it is closed — with Close page, or by going somewhere else: another
/// page of the dashboard, another screen — and never goes by itself. While
/// something is drawn over the tile (a dialog, a shared item's card, the
/// page overview) it steps out of the way and comes back after; if the tile
/// moves, it follows. Without labwc and Firefox, the page opens in a window
/// of its own as it does elsewhere.
class _ParcelDesk extends StatefulWidget {
  const _ParcelDesk({
    required this.parcels,
    required this.theme,
    required this.tracking,
  });

  final List<Parcel> parcels;
  final DashboardTheme theme;
  final bool tracking;

  @override
  State<_ParcelDesk> createState() => _ParcelDeskState();
}

class _ParcelDeskState extends State<_ParcelDesk> {
  final _hole = GlobalKey();
  final _side = SideBrowser.instance;

  String? _chosen;

  /// The parcel whose page is in the frame.
  String? _pageFor;
  bool _embed = false;
  bool _opening = false;
  bool _checking = false;

  /// As of the last build: nothing in front of the tile.
  bool _inView = true;
  Size _screen = Size.zero;
  int? _view;

  Timer? _watch;
  Rect? _movedTo;

  @override
  void initState() {
    super.initState();
    _side.addListener(_changed);
    _side.available().then((yes) {
      if (mounted) setState(() => _embed = yes);
    });
  }

  @override
  void dispose() {
    _watch?.cancel();
    _side.removeListener(_changed);
    unawaited(_side.close(owner: this));
    super.dispose();
  }

  bool get _pageUp => _side.isOwnedBy(this);

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (!_pageUp && !_opening) {
        _watch?.cancel();
        _watch = null;
        _pageFor = null;
      }
    });
  }

  /// Where the hole is on the screen, or null if it is not there to be
  /// seen whole and at its own size: drawn smaller in the page overview,
  /// larger when brought close, or partly off the screen mid-swipe.
  Rect? _holeOnScreen() {
    final box = _hole.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    if ((rect.width - box.size.width).abs() > 1 ||
        (rect.height - box.size.height).abs() > 1) {
      return null;
    }
    final screen = (Offset.zero & _screen).inflate(1);
    if (!screen.contains(rect.topLeft) || !screen.contains(rect.bottomRight)) {
      return null;
    }
    return _covered(box, rect) ? null : rect;
  }

  /// Whether anything is drawn over the hole — a dialog, the page overview,
  /// a shared item's card — which the page, kept on top, would otherwise
  /// hide in turn. Asked of the kiosk's own hit testing, at the middle and
  /// near each corner: whatever is on top there is what a touch would reach.
  bool _covered(RenderBox box, Rect rect) {
    final view = _view;
    if (view == null) return false;
    final inner = rect.deflate(6);
    for (final point in [
      inner.center,
      inner.topLeft,
      inner.topRight,
      inner.bottomLeft,
      inner.bottomRight,
    ]) {
      final hits = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hits, point, view);
      if (!hits.path.any((e) => identical(e.target, box))) return true;
    }
    return false;
  }

  void _choose(Parcel p) {
    setState(() => _chosen = p.id);
    if (_embed) unawaited(_openPage(p));
  }

  Future<void> _openPage(Parcel p) async {
    final rect = _embed && _inView ? _holeOnScreen() : null;
    if (rect == null) return _openApart(p);
    setState(() {
      _pageFor = p.id;
      _opening = true;
    });
    final shown = await _side.show(p.url, rect, owner: this);
    if (!mounted) return;
    setState(() => _opening = false);
    if (!shown) {
      setState(() => _pageFor = null);
      return _openApart(p);
    }
    _watch ??= Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _keepUp(),
    );
  }

  Future<void> _openApart(Parcel p) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LinkViewerScreen(url: p.url, title: parcelName(p)),
    ),
  );

  /// Keeps the page with the tile: away while the tile cannot be seen, back
  /// when it can, and after it if it moves.
  void _keepUp() {
    if (!mounted || (!_pageUp && !_opening)) {
      _watch?.cancel();
      _watch = null;
      return;
    }
    if (_opening) return;
    final rect = _inView ? _holeOnScreen() : null;
    if (rect == null) {
      _movedTo = null;
      unawaited(_side.hide());
      return;
    }
    final at = SideBrowser.snap(rect);
    if (_side.rect != null && at != _side.rect) {
      // Once it has settled, not at every frame of the move.
      if (_movedTo == at) {
        _movedTo = null;
        final p = context.read<ParcelsService>().byId(_pageFor ?? '');
        final url = _side.url ?? p?.url;
        if (p != null && url != null) {
          _opening = true;
          _side
              .show(url, rect, owner: this)
              .whenComplete(
                () => mounted ? setState(() => _opening = false) : null,
              );
        }
      } else {
        _movedTo = at;
      }
      return;
    }
    _movedTo = null;
    if (_side.hidden) unawaited(_side.reveal());
  }

  Future<void> _check(ParcelsService s, Parcel p) async {
    setState(() => _checking = true);
    try {
      await s.checkDue(only: p.id, asked: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final service = context.watch<ParcelsService>();
    final card = context.select<ShareInboxService?, bool>(
      (s) => s?.current != null,
    );
    _inView =
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled &&
        !card;
    _screen = MediaQuery.sizeOf(context);
    _view = View.maybeOf(context)?.viewId;
    if (_pageUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _keepUp());
    }
    final parcels = widget.parcels;
    final p = service.byId(_chosen ?? '') ?? parcels.first;
    return LayoutBuilder(
      builder: (context, c) {
        final listW = (c.maxWidth * 0.3).clamp(340.0, 600.0);
        // The list as tall as it needs, to four parcels or so; the week
        // ahead under it, the rest of the way down.
        final listH = (parcels.length * 86.0).clamp(46.0, c.maxHeight * 0.42);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: listW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: listH,
                    child: _ParcelList(
                      parcels: parcels,
                      theme: t,
                      tracking: widget.tracking,
                      height: listH,
                      chosen: p.id,
                      onTap: _choose,
                    ),
                  ),
                  SizedBox(height: t.isLcars ? 16 : 20),
                  Expanded(
                    child: _WeekAhead(
                      parcels: parcels,
                      theme: t,
                      chosen: p.id,
                      onTap: _choose,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: t.isLcars ? 24 : 20),
            Expanded(child: _frame(p, service)),
          ],
        );
      },
    );
  }

  Widget _frame(Parcel p, ParcelsService service) {
    final t = widget.theme;
    final status = StatusColours.of(t);
    final page = (_pageUp || _opening) && _pageFor == p.id;
    final steerable = page && _side.steerable;
    final edge = p.carrier.colour;
    final from = p.from;

    final header = Row(
      children: [
        _Badge(carrier: p.carrier, size: 46, theme: t),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tileCased(t, parcelName(p)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                [
                  ?parcelWhen(p, DateTime.now()),
                  // On a console the number is lettered on the bar.
                  if (!t.isLcars) ...[
                    p.carrier.name,
                    if (p.number != null) p.number!,
                  ],
                  if (from != null)
                    tr('widget.parcels.fromName', 'from {name}', {
                      'name': from,
                    }),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.expected != null && !p.delivered
                      ? parcelColour(p, t) == t.textPrimary
                            ? t.accent
                            : parcelColour(p, t)
                      : t.textSecondary,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (page) ...[
          _SheetButton(
            theme: t,
            dense: true,
            icon: Icons.arrow_back,
            text: tr('widget.parcels.back', 'Back'),
            colour: t.block(2),
            onTap: steerable ? _side.back : null,
          ),
          const SizedBox(width: 10),
          _SheetButton(
            theme: t,
            dense: true,
            icon: Icons.refresh,
            text: tr('widget.parcels.reload', 'Reload'),
            colour: t.block(3),
            onTap: steerable ? _side.reload : null,
          ),
          const SizedBox(width: 10),
          _SheetButton(
            theme: t,
            dense: true,
            icon: Icons.close,
            text: tr('widget.parcels.closePage', 'Close page'),
            colour: edge,
            onTap: () => _side.close(owner: this),
          ),
        ] else
          _SheetButton(
            theme: t,
            dense: true,
            icon: Icons.public,
            text: tr('widget.parcels.trackingPage', 'Tracking page'),
            colour: edge,
            onTap: () => _openPage(p),
          ),
      ],
    );

    final hole = Container(
      key: _hole,
      color: t.isLcars
          ? Colors.black
          : t.isLight
          ? Colors.white
          : const Color(0xFF15141A),
      padding: page ? EdgeInsets.zero : const EdgeInsets.all(24),
      alignment: page ? Alignment.center : null,
      child: page
          ? Text(
              _side.hidden
                  ? ''
                  : tr(
                      'widget.parcels.openingPage',
                      'Opening the tracking page…',
                    ),
              style: TextStyle(color: t.textSecondary, fontSize: 20),
            )
          : _ParcelStory(
              parcel: p,
              theme: t,
              tracking: widget.tracking,
              serviceError: service.serviceError,
            ),
    );

    final where = page ? _host(_side.url ?? p.url) : null;
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!p.delivered) ...[
          _SheetButton(
            theme: t,
            dense: true,
            icon: Icons.event,
            text: tr('widget.parcels.when', 'When?'),
            colour: t.block(4),
            onTap: () => showParcelDue(context, p.id, t),
          ),
          const SizedBox(width: 10),
        ],
        if (widget.tracking && p.number != null && !p.delivered) ...[
          _SheetButton(
            theme: t,
            dense: true,
            icon: Icons.sync,
            text: _checking
                ? tr('widget.parcels.checking', 'Checking…')
                : tr('widget.parcels.checkNow', 'Check now'),
            colour: t.block(1),
            onTap: _checking ? null : () => _check(service, p),
          ),
          const SizedBox(width: 10),
        ],
        _SheetButton(
          theme: t,
          dense: true,
          icon: p.delivered ? Icons.undo : Icons.check_circle_outline,
          text: p.delivered
              ? tr('widget.parcels.notHereYet', 'Not here yet')
              : tr('widget.parcels.itsHere', 'It’s here'),
          colour: status.good,
          onTap: () {
            service.setDelivered(p.id, !p.delivered);
          },
        ),
        const SizedBox(width: 10),
        _SheetButton(
          theme: t,
          dense: true,
          icon: Icons.delete_outline,
          text: tr('widget.parcels.remove', 'Remove'),
          colour: status.bad,
          onTap: () {
            if (_pageFor == p.id) unawaited(_side.close(owner: this));
            service.remove(p.id);
          },
        ),
      ],
    );
    final footer = LayoutBuilder(
      builder: (context, c) => Row(
        children: [
          Expanded(
            child: Text(
              where == null
                  ? ''
                  : _side.loading
                  ? '$where · ${tr('widget.parcels.loading', 'Loading…')}'
                  : where,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textSecondary, fontSize: 18),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: c.maxWidth * 0.86),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: buttons,
            ),
          ),
        ],
      ),
    );

    if (t.isLcars) {
      // A panel of its own inside the tile's, as a console nests them: the
      // carrier and number lettered on its bar, the page in the bay it
      // frames, a rule in the carrier's colour above and below.
      final rule = Container(height: lcarsLine * 2, color: edge);
      return LcarsPanel(
        theme: t,
        label: [p.carrier.short, if (p.number != null) p.number!].join(' '),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 12),
              rule,
              Expanded(child: hole),
              rule,
              const SizedBox(height: 12),
              footer,
            ],
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: t.textPrimary.withValues(alpha: t.isLight ? 0.04 : 0.06),
        borderRadius: BorderRadius.circular(t.cornerRadius),
        border: Border.all(color: t.textSecondary.withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 14),
          Expanded(
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border.all(
                  color: t.textSecondary.withValues(alpha: 0.18),
                ),
              ),
              child: hole,
            ),
          ),
          const SizedBox(height: 14),
          footer,
        ],
      ),
    );
  }

  /// The site, as an address bar would put it at a glance.
  static String _host(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}

/// The next seven days, a row each, with the parcels due on it: an arrivals
/// board, under the list on a page-sized tile. Those due later, and those
/// with no day yet, go last; one overdue stays on today's row, still due.
class _WeekAhead extends StatelessWidget {
  const _WeekAhead({
    required this.parcels,
    required this.theme,
    required this.chosen,
    required this.onTap,
  });

  final List<Parcel> parcels;
  final DashboardTheme theme;
  final String chosen;
  final void Function(Parcel) onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final now = DateTime.now();
    final coming = parcels.where((p) => !p.delivered).toList();
    DateTime day(int i) => DateTime(now.year, now.month, now.day + i);
    final rows = <(String, List<Parcel>, bool)>[
      for (var i = 0; i < 7; i++)
        (
          i == 0
              ? tr('widget.parcels.today', 'today')
              : i == 1
              ? tr('widget.parcels.tomorrow', 'tomorrow')
              : '${weekdayShort(day(i))} ${day(i).day}',
          [
            for (final p in coming)
              if (p.expected case final e?)
                if (_sameDay(e, day(i)) || (i == 0 && e.isBefore(day(0)))) p,
          ],
          i == 0,
        ),
    ];
    final later = [
      for (final p in coming)
        if (p.expected case final e? when !e.isBefore(day(7))) p,
    ];
    final undated = [
      for (final p in coming)
        if (p.expected == null) p,
    ];
    if (later.isNotEmpty) {
      rows.add((tr('widget.parcels.later', 'later'), later, false));
    }
    if (undated.isNotEmpty) {
      rows.add((tr('widget.parcels.noDayYet', 'no day yet'), undated, false));
    }

    final board = LayoutBuilder(
      builder: (context, c) {
        final rowH = c.maxHeight / rows.length;
        final font = (rowH * 0.38).clamp(12.0, 22.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, (label, due, today)) in rows.indexed)
              SizedBox(
                height: rowH,
                child: _dayRow(i, label, due, today, rowH, font),
              ),
          ],
        );
      },
    );

    if (t.isLcars) {
      return LcarsPanel(
        theme: t,
        down: true,
        label: tr('widget.parcels.weekAhead', 'The week ahead'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 0, 6),
          child: board,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      decoration: BoxDecoration(
        color: t.textPrimary.withValues(alpha: t.isLight ? 0.04 : 0.06),
        borderRadius: BorderRadius.circular(t.cornerRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('widget.parcels.weekAhead', 'The week ahead'),
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(child: board),
        ],
      ),
    );
  }

  Widget _dayRow(
    int i,
    String label,
    List<Parcel> due,
    bool today,
    double rowH,
    double font,
  ) {
    final t = theme;
    final name = tileCased(t, label[0].toUpperCase() + label.substring(1));
    final dayLabel = t.isLcars
        ? Container(
            width: font * 5.6,
            margin: EdgeInsets.symmetric(vertical: rowH * 0.08),
            padding: EdgeInsets.only(right: font * 0.5),
            alignment: Alignment.centerRight,
            decoration: BoxDecoration(
              color: today ? lcarsLit : t.block(i + 1),
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(rowH),
              ),
            ),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: lcarsInk,
                fontSize: font * 0.9,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        : SizedBox(
            width: font * 5.6,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: today ? t.accent : t.textSecondary,
                fontSize: font,
                fontWeight: today ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          );
    return Row(
      children: [
        dayLabel,
        SizedBox(width: font * 0.6),
        Expanded(
          child: due.isEmpty
              ? Text(
                  '—',
                  style: TextStyle(
                    color: t.textSecondary.withValues(alpha: 0.4),
                    fontSize: font,
                  ),
                )
              : Row(
                  children: [
                    for (final p in due.take(3))
                      Flexible(child: _chip(p, rowH, font)),
                    if (due.length > 3)
                      Text(
                        ' +${due.length - 3}',
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: font,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _chip(Parcel p, double rowH, double font) {
    final t = theme;
    final from = p.expected;
    final to = p.expectedTo;
    final time = from == null
        ? ''
        : from.hour != 0 || from.minute != 0
        ? hhmm(from)
        : to != null
        ? tr('widget.parcels.byTime', 'by {time}', {'time': hhmm(to)})
        : '';
    final picked = p.id == chosen;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(p),
      child: Container(
        margin: EdgeInsets.only(right: font * 0.4),
        padding: EdgeInsets.symmetric(
          horizontal: font * 0.35,
          vertical: rowH * 0.1,
        ),
        decoration: picked
            ? BoxDecoration(
                color: t.accent.withValues(alpha: t.isLcars ? 0.24 : 0.14),
                borderRadius: BorderRadius.circular(t.isLcars ? 0 : font),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Badge(carrier: p.carrier, size: font * 1.3, theme: t),
            SizedBox(width: font * 0.4),
            Flexible(
              child: Text(
                [if (time.isNotEmpty) time, parcelName(p)].join(' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textPrimary, fontSize: font),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _dueOpen = false;

/// Asks when parcel [id] is coming — read off its carrier's page, or an
/// email nobody shared — and sets it. Over a page in a frame, the page
/// steps aside until this is put away.
Future<void> showParcelDue(
  BuildContext context,
  String id,
  DashboardTheme theme,
) async {
  if (_dueOpen) return;
  _dueOpen = true;
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: tr('widget.parcels.close', 'Close'),
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: theme.isLcars
          ? Duration.zero
          : const Duration(milliseconds: 200),
      pageBuilder: (context, _, _) => DuePicker(id: id, theme: theme),
      transitionBuilder: (context, animation, _, child) => theme.isLcars
          ? child
          : FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            ),
    );
  } finally {
    _dueOpen = false;
  }
}

enum _Part { any, morning, afternoon, evening, slot }

/// When parcel [id] is coming: a day this week, and a part of it or the
/// carrier's own slot. Public so it can be tested on its own.
class DuePicker extends StatefulWidget {
  const DuePicker({super.key, required this.id, required this.theme});

  final String id;
  final DashboardTheme theme;

  @override
  State<DuePicker> createState() => _DuePickerState();
}

class _DuePickerState extends State<DuePicker> {
  static const _parts = {
    _Part.morning: (8 * 60, 12 * 60),
    _Part.afternoon: (12 * 60, 17 * 60),
    _Part.evening: (17 * 60, 21 * 60),
  };

  late DateTime _today;
  late DateTime _day;
  _Part _part = _Part.any;
  int _start = 10 * 60;
  int _length = 60;

  /// Whether anything was touched: Done on a day the picker cannot show —
  /// Amazon's "by 10pm" — leaves it as it was.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _day = _today;
    final p = context.read<ParcelsService>().byId(widget.id);
    final from = p?.expected;
    if (p == null || from == null) return;
    final on = DateTime(from.year, from.month, from.day);
    if (!on.isBefore(_today) && on.difference(_today).inDays < 7) _day = on;
    final to = p.expectedTo;
    if (to == null) return;
    final s = from.hour * 60 + from.minute;
    final e = to.hour * 60 + to.minute;
    _part =
        _parts.entries
            .where((x) => x.value == (s, e))
            .map((x) => x.key)
            .firstOrNull ??
        (s > 0 && e > s ? _Part.slot : _Part.any);
    if (_part == _Part.slot) {
      _start = s;
      _length = e - s;
    }
  }

  DeliveryWindow get _window {
    DateTime at(int minutes) => _day.add(Duration(minutes: minutes));
    return switch (_part) {
      _Part.any => (from: _day, to: null),
      _Part.slot => (from: at(_start), to: at(_start + _length)),
      final part => (from: at(_parts[part]!.$1), to: at(_parts[part]!.$2)),
    };
  }

  void _set(DeliveryWindow? due) {
    context.read<ParcelsService>().setDue(widget.id, due);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final service = context.watch<ParcelsService>();
    final p = service.byId(widget.id);
    if (p == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Navigator.of(context).maybePop(),
      );
      return const SizedBox.shrink();
    }
    final w = _window;
    final preview = parcelWhen(
      Parcel(
        id: '',
        carrier: p.carrier,
        url: p.url,
        added: p.added,
        expected: w.from,
        expectedTo: w.to,
      ),
      DateTime.now(),
    );
    var colour = 0;
    Widget choice(String text, bool on, VoidCallback tap) => _Choice(
      text: text,
      on: on,
      onTap: () {
        _changed = true;
        tap();
      },
      theme: t,
      colour: colour++,
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(
        tileCased(t, text),
        style: TextStyle(
          color: t.textSecondary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: t.isLcars ? 1 : 0,
        ),
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _Badge(carrier: p.carrier, size: 48, theme: t),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                tileCased(
                  t,
                  tr('widget.parcels.whenComing', 'When is {name} coming?', {
                    'name': parcelName(p),
                  }),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              iconSize: 40,
              tooltip: tr('widget.parcels.close', 'Close'),
              icon: Icon(Icons.close, color: t.textSecondary),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
        heading(tr('widget.parcels.day', 'Day')),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < 7; i++)
              choice(
                i == 0
                    ? tr('widget.parcels.todayCap', 'Today')
                    : i == 1
                    ? tr('widget.parcels.tomorrowCap', 'Tomorrow')
                    : weekdayName(_today.add(Duration(days: i))),
                _day == DateTime(_today.year, _today.month, _today.day + i),
                () => setState(
                  () => _day = DateTime(
                    _today.year,
                    _today.month,
                    _today.day + i,
                  ),
                ),
              ),
          ],
        ),
        heading(tr('widget.parcels.time', 'Time')),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            choice(
              tr('widget.parcels.anyTime', 'Any time'),
              _part == _Part.any,
              () => setState(() => _part = _Part.any),
            ),
            choice(
              tr('widget.parcels.morning', 'Morning'),
              _part == _Part.morning,
              () => setState(() => _part = _Part.morning),
            ),
            choice(
              tr('widget.parcels.afternoon', 'Afternoon'),
              _part == _Part.afternoon,
              () => setState(() => _part = _Part.afternoon),
            ),
            choice(
              tr('widget.parcels.evening', 'Evening'),
              _part == _Part.evening,
              () => setState(() => _part = _Part.evening),
            ),
            choice(
              tr('widget.parcels.slot', 'A time slot'),
              _part == _Part.slot,
              () => setState(() => _part = _Part.slot),
            ),
          ],
        ),
        if (_part == _Part.slot) ...[
          heading(tr('widget.parcels.from', 'From')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var h = 7; h <= 20; h++)
                choice(
                  '${h.toString().padLeft(2, '0')}:'
                  '${(_start % 60).toString().padLeft(2, '0')}',
                  _start ~/ 60 == h,
                  () => setState(() => _start = h * 60 + _start % 60),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in const [0, 15, 30, 45])
                choice(
                  ':${m.toString().padLeft(2, '0')}',
                  _start % 60 == m,
                  () => setState(() => _start = _start ~/ 60 * 60 + m),
                ),
              const SizedBox(width: 24),
              for (final hours in const [1, 2, 4])
                choice(
                  hours == 1
                      ? tr('widget.parcels.anHour', 'An hour')
                      : tr('widget.parcels.hours', '{count} hours', {
                          'count': hours,
                        }),
                  _length == hours * 60,
                  () => setState(() => _length = hours * 60),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                preview ?? '',
                style: TextStyle(
                  color: t.accent,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (p.expected != null) ...[
              _SheetButton(
                theme: t,
                icon: Icons.event_busy,
                text: tr('widget.parcels.notKnown', 'Not known'),
                colour: t.block(2),
                onTap: () => _set(null),
              ),
              const SizedBox(width: 12),
            ],
            _SheetButton(
              theme: t,
              icon: Icons.check,
              text: tr('widget.parcels.done', 'Done'),
              colour: StatusColours.of(t).good,
              onTap: () => _changed || p.expected == null
                  ? _set(w)
                  : Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ],
    );

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: t.background.first,
                  borderRadius: BorderRadius.circular(
                    t.isLcars ? 0 : t.cornerRadius,
                  ),
                  border: t.isLcars
                      ? Border(
                          left: BorderSide(color: p.carrier.colour, width: 14),
                        )
                      : Border.all(
                          color: t.textSecondary.withValues(alpha: 0.2),
                        ),
                ),
                padding: const EdgeInsets.fromLTRB(32, 22, 22, 26),
                child: SingleChildScrollView(child: body),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One choice of several: a block on a console, lit when chosen; a pill
/// elsewhere, filled.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.text,
    required this.on,
    required this.onTap,
    required this.theme,
    required this.colour,
  });

  final String text;
  final bool on;
  final VoidCallback onTap;
  final DashboardTheme theme;
  final int colour;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    if (t.isLcars) {
      return TileBlock(
        colour: t.block(colour),
        lit: on,
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        onTap: onTap,
        child: Text(
          lcarsCaps(text),
          style: const TextStyle(
            color: lcarsInk,
            fontSize: 21,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return Material(
      color: on ? t.accent : t.textPrimary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          child: Text(
            text,
            style: TextStyle(
              color: on ? inkOn(t.accent) : t.textPrimary,
              fontSize: 20,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// A button on the sheet: a block on a console, a tinted pill elsewhere.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.theme,
    required this.icon,
    required this.text,
    required this.colour,
    required this.onTap,
    this.dense = false,
  });

  final DashboardTheme theme;
  final IconData icon;
  final String text;
  final Color colour;
  final VoidCallback? onTap;

  /// Smaller, for a row of them along the frame's edge.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final iconSize = dense ? 22.0 : 26.0;
    final font = dense ? 19.0 : 22.0;
    if (t.isLcars) {
      return Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: TileBlock(
          colour: colour,
          height: dense ? 52 : 64,
          padding: EdgeInsets.symmetric(horizontal: dense ? 18 : 24),
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: lcarsInk, size: iconSize),
              const SizedBox(width: 10),
              Text(
                lcarsCaps(text),
                style: TextStyle(
                  color: lcarsInk,
                  fontSize: font,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: colour.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(32),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 20 : 26,
              vertical: dense ? 12 : 16,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: t.textPrimary, size: iconSize),
                const SizedBox(width: 10),
                Text(
                  text,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: font,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final parcelsWidgetType = DashboardWidgetType(
  type: 'parcels',
  category: WidgetCategory.house,
  name: 'Parcels',
  description:
      'Parcels on their way: share a tracking link or number to the panel '
      'from the phone app — a Royal Mail, DPD, Evri or Yodel email, a '
      'courier’s page — and it goes on this list. With a tracking service '
      'set below, each is looked up every half an hour and pops up when it '
      'is out for delivery or has come. Tap one for its story and its '
      'carrier’s page.',
  glyph: '📦',
  defaultWidth: 4,
  defaultHeight: 4,
  minWidth: 2,
  minHeight: 2,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'service',
      label: 'Tracking service',
      kind: OptionKind.choice,
      defaultValue: 'none',
      choices: {
        'none': 'None — links only',
        '17track': '17TRACK',
        'ship24': 'Ship24',
      },
      help:
          'Looks each parcel up with its carrier: Royal Mail, DPD, Evri, '
          'Yodel and hundreds more. Each needs a free account and its API '
          'key — 17TRACK gives 200 parcels once, Ship24 10 a month. Without '
          'one, a parcel is its carrier’s tracking page, a touch away.',
    ),
    WidgetOption(
      key: 'apiKey',
      label: 'API key',
      kind: OptionKind.secret,
      help:
          '17TRACK: Settings → Security in its API console. Ship24: API '
          'keys in its dashboard.',
    ),
    WidgetOption(
      key: 'postcode',
      label: 'Delivery postcode',
      help:
          'Ship24 says more about some carriers’ parcels with it — DPD’s '
          'for one. It goes to the tracking service and nowhere else.',
    ),
    WidgetOption(
      key: 'tell',
      label: 'Pop up when a parcel is out for delivery or has come',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'keepDays',
      label: 'Keep delivered parcels for',
      kind: OptionKind.choice,
      defaultValue: '2',
      choices: {'1': 'A day', '2': 'Two days', '7': 'A week'},
    ),
  ],
  preview: const [
    PreviewLine('DPD · Out for delivery', scale: 0.12, accent: true),
    PreviewLine('Royal Mail · Due tomorrow', scale: 0.12),
    PreviewLine('Evri · Delivered', scale: 0.12, muted: true),
  ],
  build: (context, w) => ParcelsWidget(w: w),
);

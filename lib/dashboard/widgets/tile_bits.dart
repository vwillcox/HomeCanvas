import 'package:flutter/material.dart';

import '../../l10n/dates.dart';
import '../../l10n/l10n.dart';
import '../../look.dart';
import '../../widgets/lcars.dart';
import '../dashboard_theme.dart';

/// Good, warning and bad, in shades that read on the theme's background.
///
/// The pastel versions that sit well on the dark themes all but vanish on
/// Paper's near-white, so a light theme gets deeper ones.
class StatusColours {
  const StatusColours._(this.good, this.warn, this.bad);

  final Color good;
  final Color warn;
  final Color bad;

  static StatusColours of(DashboardTheme t) {
    final light = t.background.first.computeLuminance() > 0.5;
    return light
        ? const StatusColours._(
            Color(0xFF1F8A4C),
            Color(0xFFB26A00),
            Color(0xFFC0392B),
          )
        : const StatusColours._(
            Color(0xFF7EE2A8),
            Color(0xFFFFD27A),
            Color(0xFFFF8A8A),
          );
  }
}

/// A small heading for a tile: an icon, a name, and something on the right —
/// usually a [StatusChip]. Sized by the caller, in whatever units it is
/// drawing in.
class TileLabel extends StatelessWidget {
  const TileLabel({
    super.key,
    required this.icon,
    required this.text,
    required this.theme,
    this.size = 14,
    this.trailing,
  });

  final IconData icon;
  final String text;
  final DashboardTheme theme;
  final double size;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    if (theme.isLcars) {
      // A console's text bar, at a tile's size: a cap carrying the icon,
      // the name in the accent, and a bar running on to whatever is at the
      // far end.
      final seed = lcarsIndex(text);
      final bar = size * 1.35;
      return LayoutBuilder(
        builder: (context, c) => Row(
          children: [
            Container(
              width: bar * 1.5,
              height: bar,
              alignment: Alignment.center,
              padding: EdgeInsets.only(left: bar * 0.15),
              decoration: BoxDecoration(
                color: theme.block(seed),
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(bar / 2),
                ),
              ),
              child: Icon(icon, size: size, color: lcarsInk),
            ),
            SizedBox(width: size * 0.4),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: c.hasBoundedWidth ? c.maxWidth * 0.55 : 400,
              ),
              child: Text(
                lcarsCaps(text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.accent,
                  fontSize: size * 1.15,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: size * 0.06,
                ),
              ),
            ),
            SizedBox(width: size * 0.4),
            Expanded(
              child: Container(height: bar, color: theme.block(seed + 2)),
            ),
            if (trailing != null) ...[
              const SizedBox(width: lcarsLine),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: c.hasBoundedWidth ? c.maxWidth * 0.45 : 300,
                ),
                child: FittedBox(fit: BoxFit.scaleDown, child: trailing),
              ),
            ],
          ],
        ),
      );
    }
    return Row(
      children: [
        Icon(icon, size: size * 1.2, color: theme.textSecondary),
        SizedBox(width: size * 0.45),
        Expanded(
          child: Text(
            // A console letters its headings in capitals.
            theme.isLcars ? text.toUpperCase() : text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: size,
              letterSpacing: theme.isLcars ? size * 0.06 : null,
            ),
          ),
        ),
        // Shrinks rather than pushing the row off the edge of a narrow tile.
        if (trailing != null) ...[
          SizedBox(width: size * 0.5),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(fit: BoxFit.scaleDown, child: trailing),
            ),
          ),
        ],
      ],
    );
  }
}

/// A rounded pill of state: "Put out tonight", "All up".
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.text,
    required this.colour,
    this.size = 12,
  });

  final String text;
  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (context.look.isLcars) {
      // A block of the colour itself, lettered in black, rounded where it
      // ends a row.
      return Container(
        padding: EdgeInsets.fromLTRB(
          size * 0.6,
          size * 0.22,
          size * 0.85,
          size * 0.22,
        ),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 1),
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(size * 2),
          ),
        ),
        child: Text(
          lcarsCaps(text),
          maxLines: 1,
          style: TextStyle(
            color: lcarsInk,
            fontSize: size,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: size * 0.05,
          ),
        ),
      );
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * 0.75,
        vertical: size * 0.2,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 2),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          color: colour,
          fontSize: size,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A plain message for a tile with nothing to show yet, in the theme's
/// quieter colour — "Add your bins in the widget settings".
class TileMessage extends StatelessWidget {
  const TileMessage(this.text, {super.key, required this.theme});

  final String text;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(
            theme.isLcars ? lcarsCaps(text) : text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 15,
              height: 1.35,
              letterSpacing: theme.isLcars ? 0.8 : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// How far through something is: the theme's bar, or on a console a row of
/// segments.
class TileProgress extends StatelessWidget {
  const TileProgress({
    super.key,
    required this.theme,
    required this.value,
    this.height = 5,
    this.colour,
  });

  final DashboardTheme theme;

  /// 0 to 1. Null for one that is only busy.
  final double? value;
  final double height;

  /// The accent unless given.
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (theme.isLcars && v != null) {
      return LcarsSegments(
        theme: theme,
        value: v,
        height: height * 1.6,
        colour: colour,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(theme.isLcars ? 0 : height / 2),
      child: LinearProgressIndicator(
        value: v,
        minHeight: height,
        backgroundColor: theme.textSecondary.withValues(alpha: 0.18),
        valueColor: AlwaysStoppedAnimation(colour ?? theme.accent),
      ),
    );
  }
}

/// The card something sits on inside a tile, as a console draws it: no
/// plate, only a bar down its left — near-white while the thing is on, or
/// in [glow] where its own colour says more.
BoxDecoration lcarsCard(DashboardTheme theme, {required bool lit, Color? glow}) =>
    BoxDecoration(
      border: Border(
        left: BorderSide(
          color: lit ? (glow ?? lcarsLit) : theme.block(2),
          width: 8,
        ),
      ),
    );

/// A corner of [radius], or a square one on a console, whose pictures and
/// cards are square as its blocks are.
double tileCorner(DashboardTheme theme, double radius) =>
    theme.isLcars ? 0 : radius;

/// Words as the theme letters them: capitals on a console.
String tileCased(DashboardTheme theme, String s) =>
    theme.isLcars ? lcarsCaps(s) : s;

/// A button inside a tile as a console draws one: a block of [colour] with
/// its [child] in black. For the widgets to use where another theme has a
/// tinted chip or a round key.
class TileBlock extends StatelessWidget {
  const TileBlock({
    super.key,
    required this.colour,
    required this.child,
    this.onTap,
    this.lit = false,
    this.ends = LcarsEnds.both,
    this.width,
    this.height = 44,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
  });

  final Color colour;
  final Widget child;
  final VoidCallback? onTap;

  /// Chosen, or switched on: near-white, whatever [colour] is.
  final bool lit;
  final LcarsEnds ends;
  final double? width;
  final double height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => LcarsBlock(
    colour: lit ? lcarsLit : colour,
    // Shown at full strength with nothing to press, too: a tile's blocks
    // are as often a readout as a button.
    onTap: onTap ?? () {},
    ends: ends,
    width: width,
    height: height,
    padding: padding,
    child: child,
  );
}

/// Says when what [child] shows was fetched: "Updated 09:14".
///
/// On a console it is lettered on the bar of the panel the tile sits in (see
/// [LcarsBarNote]) and takes nothing from the tile. Elsewhere, and in a
/// panel drawn without its bars, it is a small line under [child], left out
/// of a tile too short to spare the room.
///
/// A time rather than "5 min ago", which would have to be drawn again every
/// minute to stay true.
class Refreshed extends StatefulWidget {
  const Refreshed({
    super.key,
    required this.theme,
    required this.at,
    required this.child,
  });

  final DashboardTheme theme;

  /// Null for nothing fetched yet, and nothing said.
  final DateTime? at;
  final Widget child;

  /// The oldest of [times], so that of several things fetched, one that has
  /// stopped answering shows.
  static DateTime? oldest(Iterable<DateTime?> times) {
    DateTime? oldest;
    for (final at in times) {
      if (at != null && (oldest == null || at.isBefore(oldest))) oldest = at;
    }
    return oldest;
  }

  /// [at] as a time of day, with the day before it when that isn't [now]'s:
  /// "09:14", "Sun 21:40".
  static String clock(DateTime at, DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(at.hour)}:${two(at.minute)}';
    final today =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return today ? time : '${weekdayShort(at)} $time';
  }

  @override
  State<Refreshed> createState() => _RefreshedState();
}

class _RefreshedState extends State<Refreshed> {
  /// The bar of the console panel this tile is in, where there is one.
  ValueNotifier<String?>? _bar;

  @override
  void dispose() {
    _bar?.value = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final at = widget.at;
    final updated = at == null
        ? null
        : tr('dashboard.updated', 'Updated {time}', {
            'time': Refreshed.clock(at, DateTime.now()),
          });
    final bar = _bar = t.isLcars ? LcarsBarNote.maybeOf(context) : null;
    bar?.value = updated;
    if (updated == null || bar != null) return widget.child;
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxHeight < 150) return widget.child;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: widget.child),
            const SizedBox(height: 4),
            Text(
              t.isLcars ? lcarsCaps(updated) : updated,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 11,
                height: 1.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }
}

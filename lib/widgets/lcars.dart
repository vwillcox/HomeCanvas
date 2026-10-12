import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../dashboard/dashboard_theme.dart';
import '../look.dart';
import 'pause_when_hidden.dart';

/// The drawing behind a theme whose style is [ThemeStyle.lcars]: a starship's
/// console, in flat blocks of colour on black.
///
/// The rules, which are TT Launcher's LCARS skin's, so the two read as one
/// family:
///
///  * a **panel** ([LcarsPanel]) is a bar down the left that sweeps round a
///    corner into a bar across, cut into three lengths, with the panel's
///    name lettered on it in black. Panels sit against each other with a
///    thin black line between, so their side bars run on as one column;
///  * a **block** ([LcarsBlock]) is a button: flat colour, its mark in black,
///    near-white while it is chosen. A row of them is one strip, rounded
///    only at its two ends;
///  * a **text bar** ([LcarsTextBar]) heads a screen: an end cap, the title
///    in the accent, and a bar carrying the small print;
///  * a **rail** ([LcarsRailBlock]) lists places to go as square blocks of
///    uneven height, each named in its bottom corner.
///
/// There is no frame round the screen: the panels are the frame.
///
/// What moves, moves as a console does — in steps, a block lit or unlit,
/// never a fade or a slide:
///
///  * a panel **comes up** a length at a time when it is first shown, and
///    again when the screen wakes;
///  * now and then one short length of a panel's bars **blinks**;
///  * a readout **flashes** near-white as its figure changes;
///  * a row of segments **counts** to a new value rather than jumping;
///  * a block flashes flat under a finger, with no ripple.
///
/// Each is a timer and a handful of repaints, not a frame sixty times a
/// second: the panel is on all day, and between one step and the next it
/// draws nothing at all. All of it stops while the kiosk cannot be seen
/// (see [PauseWhenHidden]) and where animations are switched off.

/// The black a block's lettering and icons are drawn in.
const lcarsInk = Color(0xFF000000);

/// The near-white a block turns while it is chosen or switched on.
const lcarsLit = Color(0xFFFFF4E6);

/// The black line between two blocks, and between a panel's bars and what
/// is inside it.
const lcarsLine = 3.0;

/// How dim a bar is while it is unlit.
const _unlit = 0.4;

/// A number from [s] that is the same every time, for picking a block's
/// colour by what it is called. Not `hashCode`, which may differ from one
/// run to the next.
int lcarsIndex(String s) {
  var n = 0;
  for (final c in s.codeUnits) {
    n = (n * 31 + c) & 0x7fffffff;
  }
  return n;
}

/// Capitals, as everything on the console is lettered.
String lcarsCaps(String s) => s.toUpperCase();

/// A panel: a bar down the left that sweeps round the top corner into a bar
/// across the top — or, with [down], round the bottom corner and across the
/// bottom — with its [label] lettered on the bar, and the [child] on black
/// inside.
///
/// The bar across and the sweep of the corner are as heavy as the panel has
/// room for. The bar down the side is the same on every panel, so panels
/// one above the other line up into a single column.
class LcarsPanel extends StatefulWidget {
  const LcarsPanel({
    super.key,
    required this.theme,
    required this.child,
    this.label,
    this.down = false,
    this.scale = 1,
    this.square = false,
    this.framed = true,
    this.heavy = false,
  });

  final DashboardTheme theme;
  final Widget child;

  /// Lettered on the bar, and what the panel's colours are picked from, so
  /// each keeps its own.
  final String? label;
  final bool down;

  /// How far the room round the child is shrunk, with the child, for a
  /// small tile. The bars are not.
  final double scale;

  /// Corners turned square rather than swept — the dashboard's own switch.
  final bool square;

  /// Whether to draw the bars, or only leave the room they take.
  final bool framed;

  /// The heaviest bar whatever the size, with lettering to read from across
  /// a room: a group of settings rather than a tile.
  final bool heavy;

  /// The bar down the side.
  static const side = 20.0;

  /// How heavy a panel of [size] is drawn: 0, 1 or 2.
  static int weightFor(Size size) => size.width >= 420 && size.height >= 260
      ? 2
      : size.width >= 260 && size.height >= 190
      ? 1
      : 0;

  static double railFor(int weight) => const [20.0, 24.0, 30.0][weight];

  /// Every length of the bars lit: the elbow, the two lengths after it and
  /// the foot of the side bar, a bit each.
  static const allLit = 0xF;

  @override
  State<LcarsPanel> createState() => LcarsPanelState();
}

class LcarsPanelState extends State<LcarsPanel>
    with PauseWhenHidden<LcarsPanel> {
  /// Between one length coming up and the next.
  static const _beat = Duration(milliseconds: 70);

  /// How long a length stays unlit when it blinks.
  static const _blink = Duration(milliseconds: 160);

  final _lit = ValueNotifier<int>(0);
  Timer? _timer;
  bool _still = false;

  // By the panel's name, so each keeps its own rhythm and no two blink
  // together.
  late final _seed = lcarsIndex(widget.label ?? '');
  late final _chance = Random(_seed);

  /// Which lengths of the bars are lit, a bit each.
  @visibleForTesting
  ValueListenable<int> get lit => _lit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _run();
  }

  @override
  void didUpdateWidget(LcarsPanel old) {
    super.didUpdateWidget(old);
    if (old.framed != widget.framed) _run();
  }

  @override
  void onShownChanged(bool shown) {
    // Dark while it cannot be seen, so it comes up again when it can.
    if (!shown && !_still) _lit.value = 0;
    _run();
  }

  void _run() {
    _timer?.cancel();
    _timer = null;
    if (_still) {
      _lit.value = LcarsPanel.allLit;
    } else if (!shown || !widget.framed) {
      return;
    } else if (_lit.value == LcarsPanel.allLit) {
      _idle();
    } else {
      // Panels start a moment apart, so a page comes up as a ripple.
      _comeUp(_lit.value == 0 ? _beat * (_seed % 4) : _beat);
    }
  }

  void _comeUp(Duration wait) {
    _timer = Timer(wait, () {
      _lit.value = _lit.value << 1 | 1;
      _lit.value == LcarsPanel.allLit ? _idle() : _comeUp(_beat);
    });
  }

  void _idle() {
    _timer = Timer(Duration(seconds: 14 + _chance.nextInt(30)), () {
      // One of the short lengths; never the elbow, which carries the name.
      _lit.value = LcarsPanel.allLit & ~(2 << _chance.nextInt(3));
      _timer = Timer(_blink, () {
        _lit.value = LcarsPanel.allLit;
        _idle();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LcarsPanel(:theme, :child, :label, :down, :scale, :square) = widget;
    final LcarsPanel(:framed, :heavy) = widget;
    return LayoutBuilder(
      builder: (context, c) {
        // A panel that takes its height from what is inside it is judged
        // on its width alone.
        final size = Size(
          c.maxWidth,
          c.hasBoundedHeight ? c.maxHeight : double.infinity,
        );
        final weight = heavy ? 2 : LcarsPanel.weightFor(size);
        final rail = heavy ? 38.0 : LcarsPanel.railFor(weight);
        final across = rail + lcarsLine;
        final inside = Padding(
          padding: EdgeInsets.fromLTRB(
            LcarsPanel.side + lcarsLine + (heavy ? 4 : 8 * scale),
            (down ? 0 : across) + (heavy ? 4 : 5 * scale),
            heavy ? 0 : 10 * scale,
            (down ? across : 0) + (heavy ? 4 : 5 * scale),
          ),
          child: child,
        );
        if (!framed) return inside;
        final seed = lcarsIndex(label ?? '');
        // The bars and what is inside them are painted apart, so a length
        // that blinks is drawn again without the widget, and the widget
        // without the bars.
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _PanelPainter(
                    lit: _lit,
                    first: theme.block(seed),
                    second: theme.block(seed + 2),
                    third: theme.block(seed + 4),
                    rail: rail,
                    outer: square ? 0 : const [26.0, 38.0, 54.0][weight],
                    inner: square ? 0 : const [10.0, 14.0, 20.0][weight],
                    down: down,
                    label: label == null ? null : lcarsCaps(label),
                    fontFamily: theme.fontFamily,
                  ),
                ),
              ),
            ),
            RepaintBoundary(child: ClipRect(child: inside)),
          ],
        );
      },
    );
  }
}

class _PanelPainter extends CustomPainter {
  _PanelPainter({
    required this.lit,
    required this.first,
    required this.second,
    required this.third,
    required this.rail,
    required this.outer,
    required this.inner,
    required this.down,
    this.label,
    this.fontFamily,
  }) : super(repaint: lit);

  /// Which lengths are lit, a bit each: the elbow, the second length, the
  /// third, and the foot of the side bar.
  final ValueListenable<int> lit;
  final Color first;
  final Color second;
  final Color third;
  final double rail;
  final double outer;
  final double inner;
  final bool down;
  final String? label;
  final String? fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const s = LcarsPanel.side;
    if (w <= s * 2 || h <= rail * 1.5) return;
    final paint = Paint()..isAntiAlias = true;
    final on = lit.value;
    Color shade(Color c, int bit) =>
        on & bit == 0 ? c.withValues(alpha: c.a * _unlit) : c;

    // Drawn as the upward elbow. The downward one is the same shape turned
    // over.
    canvas.save();
    if (down) {
      canvas
        ..translate(0, h)
        ..scale(1, -1);
    }
    final foot = (h * 0.3).clamp(0.0, 56.0);
    final barEnd = h - foot - lcarsLine;
    final sweep = outer.clamp(0.0, h / 2);
    final bend = inner.clamp(0.0, (h - rail - foot - lcarsLine).clamp(0.0, h));
    final firstEnd = w * 0.58, secondEnd = w * 0.8;

    final elbow = Path()..moveTo(0, barEnd);
    if (sweep > 0) {
      elbow
        ..lineTo(0, sweep)
        ..arcToPoint(Offset(sweep, 0), radius: Radius.circular(sweep));
    } else {
      elbow.lineTo(0, 0);
    }
    elbow
      ..lineTo(firstEnd, 0)
      ..lineTo(firstEnd, rail)
      ..lineTo(s + bend, rail);
    if (bend > 0) {
      elbow.arcToPoint(
        Offset(s, rail + bend),
        radius: Radius.circular(bend),
        clockwise: false,
      );
    }
    elbow
      ..lineTo(s, barEnd)
      ..close();
    canvas.drawPath(elbow, paint..color = shade(first, 1));
    canvas.drawRect(
      Rect.fromLTRB(firstEnd + lcarsLine, 0, secondEnd, rail),
      paint..color = shade(second, 2),
    );
    // The last length ends in a half-round cap.
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        secondEnd + lcarsLine,
        0,
        w,
        rail,
        topRight: Radius.circular(rail / 2),
        bottomRight: Radius.circular(rail / 2),
      ),
      paint..color = shade(third, 4),
    );
    canvas.drawRect(
      Rect.fromLTRB(0, barEnd + lcarsLine, s, h),
      paint..color = shade(second, 8),
    );
    canvas.restore();

    final label = this.label;
    if (label == null) return;
    // At the end of the first length, as a console letters its bars.
    final left = (sweep > s + bend ? sweep : s + bend) + 4;
    final room = firstEnd - left - 8;
    if (room < 24) return;
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: lcarsInk,
          fontFamily: fontFamily,
          fontSize: rail * 0.68,
          fontWeight: FontWeight.w700,
          letterSpacing: rail * 0.04,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: room);
    final y = down ? h - rail : 0.0;
    text.paint(
      canvas,
      Offset(firstEnd - 8 - text.width, y + (rail - text.height) / 2),
    );
    text.dispose();
  }

  @override
  bool shouldRepaint(_PanelPainter old) =>
      old.lit != lit ||
      old.first != first ||
      old.second != second ||
      old.third != third ||
      old.rail != rail ||
      old.outer != outer ||
      old.inner != inner ||
      old.down != down ||
      old.label != label ||
      old.fontFamily != fontFamily;
}

/// Where a block sits in a strip of them, which decides which of its ends
/// are rounded: the strip is round only at its two ends.
enum LcarsEnds { both, start, end, none }

/// A button: a flat block of [colour] with its [child] in black.
class LcarsBlock extends StatelessWidget {
  const LcarsBlock({
    super.key,
    required this.colour,
    required this.child,
    this.onTap,
    this.ends = LcarsEnds.both,
    this.radius,
    this.width,
    this.height = 56,
    this.padding = EdgeInsets.zero,
    this.alignment = Alignment.center,
  });

  final Color colour;
  final Widget child;
  final VoidCallback? onTap;
  final LcarsEnds ends;

  /// Its corners, where [ends] cannot say it: the keys of a direction pad,
  /// each rounded on its outer side.
  final BorderRadius? radius;

  /// Null for as wide as the child and its [padding].
  final double? width;
  final double height;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final round = Radius.circular(height / 2);
    final start = ends == LcarsEnds.both || ends == LcarsEnds.start;
    final end = ends == LcarsEnds.both || ends == LcarsEnds.end;
    return Material(
      // A button with nothing to do is the same block, unlit.
      color: onTap == null
          ? colour.withValues(alpha: colour.a * _unlit)
          : colour,
      shape: RoundedRectangleBorder(
        borderRadius:
            radius ??
            BorderRadius.horizontal(
              left: start ? round : Radius.zero,
              right: end ? round : Radius.zero,
            ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // Lit flat under the finger: a console's blocks do not ripple.
        splashFactory: NoSplash.splashFactory,
        highlightColor: lcarsLit.withValues(alpha: 0.7),
        child: SizedBox(
          width: width,
          height: height,
          child: Padding(
            padding: padding,
            // As wide as what is in it, unless told how wide to be.
            child: Align(
              alignment: alignment,
              widthFactor: width == null ? 1 : null,
              child: IconTheme.merge(
                data: const IconThemeData(color: lcarsInk),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(
                    color: lcarsInk,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The colour a block takes from the colour its icon was asked for in.
///
/// The kiosk's buttons are told what colour to draw their icons — the
/// theme's text colour for most, something else to mean something: the
/// accent for play, red for delete. On a console the icon is black and the
/// colour is the block's, so an icon asked for in the text colour gets one of
/// the theme's colours, by [seed], and any other colour is kept as the block.
Color lcarsBlockColour(DashboardTheme look, Color? asked, int seed) {
  final plain = look.textPrimary.toARGB32() & 0xFFFFFF;
  if (asked == null || (asked.toARGB32() & 0xFFFFFF) == plain) {
    return look.block(seed).withValues(alpha: asked?.a ?? 1);
  }
  return asked;
}

/// One figure with its name: a block capped on the left, the [name] quiet
/// at its start and the [value] bold at its end, both in black. It flashes
/// near-white as the value changes.
class LcarsReadout extends StatefulWidget {
  const LcarsReadout({
    super.key,
    required this.colour,
    required this.value,
    this.name,
    this.width,
    this.height = 30,
  });

  final Color colour;
  final String value;
  final String? name;

  /// Null to fill the width it is given.
  final double? width;
  final double height;

  @override
  State<LcarsReadout> createState() => _LcarsReadoutState();
}

class _LcarsReadoutState extends State<LcarsReadout>
    with PauseWhenHidden<LcarsReadout> {
  static const _flash = Duration(milliseconds: 220);

  Timer? _timer;

  @override
  void didUpdateWidget(LcarsReadout old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value || !shown) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _timer?.cancel();
    _timer = Timer(_flash, () => setState(() => _timer = null));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LcarsReadout(:name, :value, :width, :height) = widget;
    final size = height * 0.62;
    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.only(left: height * 0.55, right: height * 0.3),
      decoration: BoxDecoration(
        color: _timer == null ? widget.colour : lcarsLit,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(height / 2),
        ),
      ),
      child: Row(
        children: [
          if (name != null)
            Text(
              lcarsCaps(name),
              maxLines: 1,
              // Fitted to the bar, which a tile's font size does not grow.
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: lcarsInk.withValues(alpha: 0.65),
                fontSize: size,
                height: 1,
                letterSpacing: size * 0.05,
              ),
            ),
          Expanded(
            child: Text(
              lcarsCaps(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: lcarsInk,
                fontSize: size,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: size * 0.05,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How far through something is, as a row of segments: those passed in the
/// theme's colours, four at a time, and the rest unlit. A value that moves a
/// long way is counted to, a few segments at a time; one that creeps, as a
/// song's place does, is simply drawn.
class LcarsSegments extends StatefulWidget {
  const LcarsSegments({
    super.key,
    required this.theme,
    required this.value,
    this.height = 10,
    this.colour,
  });

  final DashboardTheme theme;

  /// 0 to 1.
  final double value;
  final double height;

  /// One colour for every lit segment, where the colour means something;
  /// the theme's own, in turn, without.
  final Color? colour;

  @override
  State<LcarsSegments> createState() => LcarsSegmentsState();
}

class LcarsSegmentsState extends State<LcarsSegments>
    with PauseWhenHidden<LcarsSegments> {
  /// How far it moves at a time, and how often: the whole row in under
  /// half a second.
  static const _stride = 1 / 12;
  static const _beat = Duration(milliseconds: 40);

  double _drawn = 0;
  Timer? _timer;

  /// The value as it is drawn now, on its way to the widget's.
  @visibleForTesting
  double get drawn => _drawn;

  double get _target => widget.value.clamp(0.0, 1.0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chase();
  }

  @override
  void didUpdateWidget(LcarsSegments old) {
    super.didUpdateWidget(old);
    _chase();
  }

  /// Called while building is still to come, so what it sets is drawn.
  void _chase() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still || !shown || (_target - _drawn).abs() <= _stride) {
      _timer?.cancel();
      _timer = null;
      _drawn = _target;
      return;
    }
    _timer ??= Timer.periodic(_beat, (_) {
      final gap = _target - _drawn;
      setState(() {
        if (gap.abs() <= _stride) {
          _drawn = _target;
          _timer?.cancel();
          _timer = null;
        } else {
          _drawn += gap.sign * _stride;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(double.infinity, widget.height),
    painter: _SegmentsPainter(widget.theme, _drawn, widget.colour),
  );
}

class _SegmentsPainter extends CustomPainter {
  _SegmentsPainter(this.theme, this.value, this.colour);

  final DashboardTheme theme;
  final double value;
  final Color? colour;

  @override
  void paint(Canvas canvas, Size size) {
    final count = (size.width / (size.height * 1.8)).floor().clamp(8, 64);
    final each = size.width / count;
    final paint = Paint();
    final unlit = theme.wash(0.18);
    for (var i = 0; i < count; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i * each, 0, each - 2, size.height),
        paint
          ..color = (i + 0.5) / count <= value
              ? (colour ?? theme.block(i ~/ 4))
              : unlit,
      );
    }
  }

  @override
  bool shouldRepaint(_SegmentsPainter old) =>
      old.value != value || old.theme != theme || old.colour != colour;
}

/// The head of a screen: an end cap, the [title] in the accent, then a bar
/// that runs on to the right carrying the [note] in black.
class LcarsTextBar extends StatelessWidget {
  const LcarsTextBar({super.key, required this.title, this.note});

  final String title;
  final String? note;

  static const _bar = 36.0;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    return LayoutBuilder(
      builder: (context, c) => Row(
        children: [
          Container(
            width: 44,
            height: _bar,
            decoration: BoxDecoration(
              color: look.block(0),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(_bar / 2),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // The title takes what it needs, up to most of the row; the bar
          // has the rest.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: c.hasBoundedWidth ? c.maxWidth * 0.62 : 900,
            ),
            child: Text(
              lcarsCaps(title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 46,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                height: 1.1,
                color: look.accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: _bar,
              color: look.block(2),
              alignment: Alignment.bottomRight,
              padding: const EdgeInsets.only(left: 10, right: 10, bottom: 3),
              child: note == null || note!.isEmpty
                  ? null
                  : Text(
                      lcarsCaps(note!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: lcarsInk,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        height: 1.1,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One of a rail's places: a square block, named in its bottom corner, with
/// its number above where it is tall enough. Near-white while it is the
/// place you are in.
class LcarsRailBlock extends StatelessWidget {
  const LcarsRailBlock({
    super.key,
    required this.index,
    required this.label,
    required this.selected,
    required this.onTap,
    this.first = false,
    this.last = false,
  });

  final int index;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The ends of the rail, which are swept: the top of the first block and
  /// the bottom of the last.
  final bool first;
  final bool last;

  /// Uneven, as a console's are, and none shorter than a finger.
  static const _heights = [68.0, 92.0, 68.0, 104.0, 76.0];

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final height = _heights[index % _heights.length];
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? lcarsLit : look.block(index),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: first ? const Radius.circular(40) : Radius.zero,
            bottomLeft: last ? const Radius.circular(40) : Radius.zero,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: lcarsLit.withValues(alpha: 0.7),
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                if (height >= 90)
                  Positioned(
                    top: 6,
                    right: 12,
                    child: Text(
                      '${index + 1}'.padLeft(2, '0'),
                      style: TextStyle(
                        color: lcarsInk.withValues(alpha: 0.55),
                        fontSize: 17,
                        height: 1,
                      ),
                    ),
                  ),
                Positioned(
                  left: 8,
                  right: 12,
                  bottom: 6,
                  child: Text(
                    lcarsCaps(label),
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: lcarsInk,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      height: 1,
                    ),
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

/// Which page of several: a strip of bar segments, the current one the long
/// one and lit.
class LcarsPageStrip extends StatelessWidget {
  const LcarsPageStrip({
    super.key,
    required this.count,
    required this.current,
    required this.onTap,
    this.fill,
  });

  final int count;
  final int current;
  final void Function(int) onTap;

  /// Drawn inside the current segment, in place of its plain lit bar — the
  /// dashboard's page timer.
  final Widget? fill;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Container(
              // The box is the touch target; the segment stays slim.
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: i == current ? 76 : 44,
                height: 18,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: i == current
                      ? (fill == null
                            ? lcarsLit
                            : lcarsLit.withValues(alpha: 0.3))
                      : look.block(i),
                  borderRadius: BorderRadius.horizontal(
                    left: i == 0 ? const Radius.circular(9) : Radius.zero,
                    right: i == count - 1
                        ? const Radius.circular(9)
                        : Radius.zero,
                  ),
                ),
                child: i == current ? fill : null,
              ),
            ),
          ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../time_format.dart';
import '../widgets/lcars.dart';
import 'dashboard_model.dart';
import 'dashboard_theme.dart';
import 'widget_registry.dart';

/// A picture of a dashboard page as it was when last looked at, for
/// [PageOverview].
class PageShot {
  PageShot(this.image, this.at, this.layout);

  final ui.Image image;
  final DateTime at;

  /// The page's [pageLayout] when it was taken. A picture of a page laid
  /// out since is not shown: it would be a picture of somewhere else.
  final int layout;

  void dispose() => image.dispose();
}

/// How [page] is laid out — which tiles, where, how big, in which theme —
/// as one number, to tell whether a [PageShot] is still of it.
int pageLayout(DashboardSettings settings, int page) => Object.hash(
  settings.themeId,
  Object.hashAll([
    for (final w in settings.widgetsOn(page))
      Object.hash(w.id, w.type, w.x, w.y, w.width, w.height),
  ]),
);

/// What [page] is called: its own name, or, for a page never given one,
/// what is on it — the two biggest tiles' names, and how many more there
/// are. "Servers · Notes +5" says which page that is; "Page 3" does not.
String pageTitle(DashboardSettings settings, int page) {
  final own = page < settings.pages.length ? settings.pages[page].name : '';
  if (own.trim().isNotEmpty) return own.trim();
  final tiles = settings.widgetsOn(page)
    ..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
  final names = <String>[];
  for (final t in tiles) {
    final name = WidgetRegistry.find(t.type)?.localName ?? t.type;
    if (!names.contains(name)) names.add(name);
  }
  if (names.isEmpty) return tr('dashboard.emptyPage', 'Nothing on it yet');
  final first = names.take(2).join(' · ');
  return names.length > 2 ? '$first +${names.length - 2}' : first;
}

/// Where [count] cards go in [area]: as many columns as make them biggest,
/// each a picture of [aspect] — the page's own, so nothing of it is cut
/// off — in a [frame], with a [label] under it. The last row, if short, is
/// centred. The card is the picture and its frame; the label is apart.
List<({Rect card, Rect picture, Rect label})> arrangeCards(
  int count,
  Size area, {
  required double aspect,
  double gap = 28,
  double label = 44,
  EdgeInsets frame = EdgeInsets.zero,
}) {
  if (count <= 0 || area.isEmpty) return const [];
  var columns = 1;
  var width = 0.0;
  for (var c = 1; c <= count; c++) {
    final r = (count / c).ceil();
    final byWidth = (area.width - gap * (c + 1)) / c - frame.horizontal;
    final byHeight =
        ((area.height - gap * (r + 1)) / r - label - frame.vertical) * aspect;
    final w = math.min(byWidth, byHeight);
    if (w > width) {
      width = w;
      columns = c;
    }
  }
  if (width <= 0) return const [];
  final rows = (count / columns).ceil();
  final cellWidth = width + frame.horizontal;
  final cellHeight = frame.vertical + width / aspect + label;
  final usedHeight = rows * cellHeight + (rows - 1) * gap;
  final top = (area.height - usedHeight) / 2;
  return [
    for (var i = 0; i < count; i++)
      () {
        final row = i ~/ columns;
        final inRow = row == rows - 1 ? count - row * columns : columns;
        final rowWidth = inRow * cellWidth + (inRow - 1) * gap;
        final left =
            (area.width - rowWidth) / 2 +
            (i - row * columns) * (cellWidth + gap);
        final y = top + row * (cellHeight + gap);
        final picture = Rect.fromLTWH(
          left + frame.left,
          y + frame.top,
          width,
          width / aspect,
        );
        return (
          card: Rect.fromLTRB(
            left,
            y,
            picture.right + frame.right,
            picture.bottom + frame.bottom,
          ),
          picture: picture,
          label: Rect.fromLTWH(
            left,
            picture.bottom + frame.bottom,
            cellWidth,
            label,
          ),
        );
      }(),
  ];
}

/// Every page of the dashboard at once, to choose one from: the dashboard
/// seen from further away.
///
/// Each page is a card: the page as it looked when last on screen, or —
/// for a page not looked at since the panel started, or laid out again
/// since — a map of its tiles, each where it sits on the grid and named.
/// Under it, the page's name, or what is on it. A picture older than a few
/// minutes says when it was taken, so a clock in it is not read as the time.
///
/// It comes out of the page being looked at, which shrinks into its card
/// as the others arrive round it; a card touched grows back out into its
/// page. A touch anywhere else, back, or two fingers spread apart, goes
/// back to the page it came from. On a console nothing glides: the cards
/// come up one at a time, and the one chosen is lit, then shown.
class PageOverview extends StatefulWidget {
  const PageOverview({
    super.key,
    required this.settings,
    required this.theme,
    required this.pages,
    required this.current,
    required this.shots,
    required this.onChosen,
    required this.onClosed,
    this.margin = EdgeInsets.zero,
  });

  final DashboardSettings settings;
  final DashboardTheme theme;

  /// The pages showing now, by number as saved, in order.
  final List<int> pages;

  /// Which of [pages] was being looked at.
  final int current;

  /// What each page looked like, by number as saved.
  final Map<int, PageShot> shots;

  /// A page chosen, by its place in [pages] — called as soon as it is, so
  /// the dashboard is on it by the time the overview has gone.
  final void Function(int) onChosen;

  /// Gone, and the page showing.
  final VoidCallback onClosed;

  /// Kept clear of cards: where something floats over the pages. The page
  /// itself still grows out of, and back into, the whole of it.
  final EdgeInsets margin;

  @override
  State<PageOverview> createState() => PageOverviewState();
}

class PageOverviewState extends State<PageOverview>
    with TickerProviderStateMixin {
  /// Out of the page and into the cards.
  late final AnimationController _out = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  /// Back from a card into its page.
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// The page being gone to, once one is.
  int? _target;

  /// On a console: how many cards are up so far, and the beat they come
  /// up on.
  int _up = 0;
  Timer? _beat;

  final Map<int, Offset> _fingers = {};
  double? _spreadFrom;

  bool get _lcars => widget.theme.isLcars;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_lcars || _still) {
        _out.value = 1;
        if (_still) {
          _up = widget.pages.length;
        } else {
          _beat = Timer.periodic(const Duration(milliseconds: 32), (t) {
            if (!mounted) return t.cancel();
            setState(() => _up++);
            if (_up >= widget.pages.length) t.cancel();
          });
        }
      } else {
        _up = widget.pages.length;
        _out.forward();
      }
    });
  }

  @override
  void dispose() {
    _beat?.cancel();
    _out.dispose();
    _in.dispose();
    super.dispose();
  }

  /// Back to the page it came from — back, a touch between the cards, or
  /// two fingers spread.
  Future<void> close() => choose(widget.current);

  /// The page at [i] in [PageOverview.pages], chosen: as a touch on its
  /// card does — or a page dot, or back, which chooses the page it came from.
  Future<void> choose(int i) async {
    if (_target != null) return;
    setState(() => _target = i);
    widget.onChosen(i);
    if (_lcars || _still) {
      // The card lit, for a moment, as a console's button is.
      _beat?.cancel();
      _up = widget.pages.length;
      if (!_still) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    } else {
      await _in.forward();
    }
    if (mounted) widget.onClosed();
  }

  double _spread() {
    final p = _fingers.values.toList();
    return (p[0] - p[1]).distance;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Listener(
      onPointerDown: (e) {
        _fingers[e.pointer] = e.position;
        _spreadFrom = _fingers.length == 2 ? _spread() : null;
      },
      onPointerMove: (e) {
        if (!_fingers.containsKey(e.pointer)) return;
        _fingers[e.pointer] = e.position;
        final from = _spreadFrom;
        if (from != null && _fingers.length == 2 && _spread() > from * 1.4) {
          _spreadFrom = null;
          unawaited(close());
        }
      },
      onPointerUp: (e) => _lift(e.pointer),
      onPointerCancel: (e) => _lift(e.pointer),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: close,
        child: LayoutBuilder(
          builder: (context, c) {
            final area = Rect.fromLTWH(0, 0, c.maxWidth, c.maxHeight);
            final room = widget.margin.deflateRect(area);
            final cards = [
              for (final c in arrangeCards(
                widget.pages.length,
                room.size,
                aspect: area.width / area.height,
                gap: _lcars ? 22 : 28,
                label: _lcars ? 0 : 44,
                frame: _lcars ? _DeckCard.frame : EdgeInsets.zero,
              ))
                (
                  card: c.card.shift(room.topLeft),
                  picture: c.picture.shift(room.topLeft),
                  label: c.label.shift(room.topLeft),
                ),
            ];
            return AnimatedBuilder(
              animation: Listenable.merge([_out, _in]),
              builder: (context, _) {
                final out = Curves.easeOutCubic.transform(_out.value);
                final back = Curves.easeInOutCubic.transform(_in.value);
                return Stack(
                  children: [
                    // The page behind shows through at first, and again
                    // at the end, so the picture of it is seen to move.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: theme.background.first.withValues(
                            alpha: (out * (1 - back)).clamp(0.0, 1.0),
                          ),
                        ),
                      ),
                    ),
                    for (var i = 0; i < cards.length; i++)
                      if (_lcars ? i < _up : true)
                        ..._card(i, cards[i], area, out, back),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _lift(int pointer) {
    _fingers.remove(pointer);
    if (_fingers.length != 2) _spreadFrom = null;
  }

  List<Widget> _card(
    int i,
    ({Rect card, Rect picture, Rect label}) at,
    Rect area,
    double out,
    double back,
  ) {
    final page = widget.pages[i];
    final current = i == widget.current;
    final target = i == _target;
    final shot = widget.shots[page];
    final fresh =
        shot != null && shot.layout == pageLayout(widget.settings, page);
    final title = pageTitle(widget.settings, page);
    final asAt = fresh && DateTime.now().difference(shot.at).inMinutes >= 10
        ? tr('dashboard.seenAt', 'As at {time}', {'time': hhmm(shot.at)})
        : null;
    final picture = fresh
        ? RawImage(
            image: shot.image,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          )
        : PageMap(settings: widget.settings, theme: widget.theme, page: page);

    if (_lcars) {
      return [
        Positioned.fromRect(
          rect: at.card,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => choose(i),
            child: _DeckCard(
              theme: widget.theme,
              number: page + 1,
              title: title,
              note: asAt,
              lit: target || (_target == null && current),
              colour: widget.theme.block(i + 1),
              child: picture,
            ),
          ),
        ),
      ];
    }

    // Where its picture is: the page itself at first for the one being
    // looked at, and again at the end for the one chosen.
    var rect = at.picture;
    if (current && _target == null) rect = Rect.lerp(area, at.picture, out)!;
    if (target) rect = Rect.lerp(at.picture, area, back)!;
    final radius = widget.theme.cornerRadius.clamp(6.0, 18.0);
    // The others come in round it, nearest first, and go as one is chosen.
    final order = (i - widget.current).abs() / widget.pages.length;
    final arrive = current
        ? 1.0
        : Interval(
            0.15 + 0.35 * order,
            (0.65 + 0.35 * order).clamp(0.0, 1.0),
          ).transform(out);
    final fade = target
        // The chosen picture gives way to the page itself at the very end,
        // so whatever changed on it since is not a jump.
        ? 1 - const Interval(0.75, 1).transform(back)
        : arrive * (1 - back);
    final lit = target || (_target == null && current);
    // How much a card it is yet, rather than the page: square-cornered and
    // unlabelled while it fills the screen, on the way out and on the way
    // back.
    final card = current && _target == null
        ? out
        : target
        ? 1 - back
        : 1.0;
    final named = current && _target == null
        ? const Interval(0.55, 1).transform(out)
        : arrive * (1 - back * 2);
    return [
      Positioned.fromRect(
        rect: rect,
        child: Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: current || target ? 1 : 0.86 + 0.14 * arrive,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => choose(i),
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius * card),
                  border: Border.all(
                    color: lit
                        ? widget.theme.accent.withValues(alpha: card)
                        : widget.theme.border,
                    width: lit ? 3 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius * card),
                  child: DecoratedBox(
                    decoration: widget.theme.backgroundDecoration,
                    child: picture,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      // Its name is as much the card as its picture is.
      Positioned.fromRect(
        rect: at.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => choose(i),
          child: Opacity(
            opacity: named.clamp(0.0, 1.0),
            child: _Label(
              theme: widget.theme,
              number: page + 1,
              title: title,
              note: asAt,
              lit: lit,
            ),
          ),
        ),
      ),
    ];
  }
}

/// A card's name off a console: the page's number in the accent, its
/// name, and when its picture was taken if that was a while ago.
class _Label extends StatelessWidget {
  const _Label({
    required this.theme,
    required this.number,
    required this.title,
    required this.lit,
    this.note,
  });

  final DashboardTheme theme;
  final int number;
  final String title;
  final String? note;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
      child: Row(
        children: [
          Text(
            '$number',
            style: TextStyle(
              color: theme.accent,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: lit ? theme.textPrimary : theme.textSecondary,
                fontSize: 20,
                fontWeight: lit ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          if (note != null)
            Text(
              note!,
              style: TextStyle(
                color: theme.textSecondary.withValues(alpha: 0.7),
                fontSize: 15,
              ),
            ),
        ],
      ),
    );
  }
}

/// A card on a console: a panel's elbow and bar in [colour] — near-white
/// for the page being looked at, or chosen — lettered in black with the
/// page's name and number, and the page inside.
class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.theme,
    required this.number,
    required this.title,
    required this.colour,
    required this.lit,
    required this.child,
    this.note,
  });

  final DashboardTheme theme;
  final int number;
  final String title;
  final String? note;
  final Color colour;
  final bool lit;
  final Widget child;

  static const _bar = 30.0;
  static const _side = 14.0;

  /// Where the page sits in the card: right of the bar down the side and
  /// under the one across the top.
  static const frame = EdgeInsets.only(
    left: _side + lcarsLine * 2,
    top: _bar + lcarsLine * 2,
  );

  @override
  Widget build(BuildContext context) {
    final ink = TextStyle(
      color: lcarsInk,
      fontSize: 19,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _ElbowPainter(
            colour: lit ? lcarsLit : colour,
            bar: _bar,
            side: _side,
          ),
        ),
        Positioned(
          left: _side + 30,
          right: 14,
          top: 0,
          height: _bar,
          child: Row(
            children: [
              if (note != null) ...[
                Text(lcarsCaps(note!), style: ink.copyWith(fontSize: 15)),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  lcarsCaps(title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  textScaler: TextScaler.noScaling,
                  style: ink,
                ),
              ),
              const SizedBox(width: 10),
              Text(two(number), textScaler: TextScaler.noScaling, style: ink),
            ],
          ),
        ),
        Positioned(
          left: frame.left,
          top: frame.top,
          right: 0,
          bottom: 0,
          child: ClipRect(child: child),
        ),
      ],
    );
  }
}

/// A panel's bar down the left sweeping round into a bar across the top.
class _ElbowPainter extends CustomPainter {
  _ElbowPainter({required this.colour, required this.bar, required this.side});

  final Color colour;
  final double bar;
  final double side;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = bar + side * 0.6;
    final inner = bar * 0.4;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, outer)
      ..arcToPoint(Offset(outer, 0), radius: Radius.circular(outer))
      ..lineTo(size.width - bar / 2, 0)
      ..arcToPoint(
        Offset(size.width - bar / 2, bar),
        radius: Radius.circular(bar / 2),
      )
      ..lineTo(side + inner, bar)
      ..arcToPoint(
        Offset(side, bar + inner),
        radius: Radius.circular(inner),
        clockwise: false,
      )
      ..lineTo(side, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_ElbowPainter old) =>
      old.colour != colour || old.bar != bar || old.side != side;
}

/// A page drawn as a map of its tiles: each where it sits on the grid,
/// named — for a page with no picture yet.
class PageMap extends StatelessWidget {
  const PageMap({
    super.key,
    required this.settings,
    required this.theme,
    required this.page,
  });

  final DashboardSettings settings;
  final DashboardTheme theme;
  final int page;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final tiles = [
      for (final w in settings.widgetsOn(page))
        if (w.schedule.isAlways || w.schedule.activeAt(now)) w,
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cell = Size(
          c.maxWidth / DashboardGrid.columns,
          c.maxHeight / DashboardGrid.rows,
        );
        final gap = theme.isLcars ? lcarsLine : 4.0;
        return Stack(
          children: [
            for (final w in tiles)
              Positioned(
                left: w.x * cell.width + gap / 2,
                top: w.y * cell.height + gap / 2,
                width: math.max(0, w.width * cell.width - gap),
                height: math.max(0, w.height * cell.height - gap),
                child: _MapTile(theme: theme, type: w.type),
              ),
          ],
        );
      },
    );
  }
}

class _MapTile extends StatelessWidget {
  const _MapTile({required this.theme, required this.type});

  final DashboardTheme theme;
  final String type;

  @override
  Widget build(BuildContext context) {
    final kind = WidgetRegistry.find(type);
    final name = kind?.localName ?? type;
    return LayoutBuilder(
      builder: (context, c) {
        final size = (math.min(
          c.maxHeight * 0.3,
          c.maxWidth * 0.14,
        )).clamp(8.0, 16.0);
        if (theme.isLcars) {
          // A block in one of the console's colours, named in its corner.
          return Container(
            color: theme.block(lcarsIndex(type)),
            padding: const EdgeInsets.fromLTRB(4, 2, 5, 3),
            alignment: Alignment.bottomRight,
            child: Text(
              lcarsCaps(name),
              maxLines: 2,
              overflow: TextOverflow.clip,
              textAlign: TextAlign.right,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: lcarsInk,
                fontSize: size,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          );
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.solidSurface,
            borderRadius: BorderRadius.circular(
              theme.cornerRadius.clamp(2.0, 8.0),
            ),
            border: Border.all(color: theme.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (kind != null && c.maxHeight > 34)
                      Text(
                        kind.glyph,
                        style: TextStyle(fontSize: size * 1.6, height: 1.1),
                      ),
                    Text(
                      name,
                      maxLines: 1,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: size,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

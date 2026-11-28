import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../screens/dashboard_screen.dart' show DashboardTile;
import '../widgets/glass.dart';
import 'dashboard_model.dart';
import 'dashboard_theme.dart';
import 'widget_registry.dart';

/// A tile brought close: held on the dashboard, it lifts out of the grid and
/// grows to fill the screen, the rest of the dashboard blurred behind it and
/// a gap left where it was until it goes back.
///
/// A wall panel is read from across a room, and a tile sized to share a page
/// with ten others is often too small to read from there — the news in a
/// corner, the calendar at 3x3. Rather than a page of its own for each, any
/// tile can be brought close for a moment.
///
/// Brought close it is both bigger and roomier: laid out on more cells than
/// it has on the grid, so the news has more stories and the forecast more
/// days, then drawn up to [maxZoom] times larger, so it reads from further
/// away. Its own taps and scrolling work as they do on the grid.
///
/// It goes back with the back button in its header, a tap on the blurred
/// dashboard around it, "back" by voice, or by itself after [autoClose]
/// untouched — the dashboard is the thing the panel is for.
class TileSpotlight extends StatefulWidget {
  const TileSpotlight({
    super.key,
    required this.config,
    required this.from,
    required this.pitch,
    required this.theme,
    required this.settings,
    required this.onClosed,
    this.autoClose = const Duration(minutes: 2),
  });

  /// The tile as it is on the grid.
  final DashboardWidgetConfig config;

  /// Where it sits on the grid, in this widget's own coordinates: it grows
  /// out of there, and shrinks back into it.
  final Rect from;

  /// One cell of the grid and the gap after it, so the room it is given here
  /// can be counted in cells, which is what the widgets size themselves by.
  final Size pitch;

  final DashboardTheme theme;
  final DashboardSettings settings;

  /// Once it is back in its place: the dashboard draws it there again.
  final VoidCallback onClosed;

  final Duration autoClose;

  /// The most it is drawn up. Larger, and a tile laid out for a third of the
  /// screen would have little more room than it had on the grid.
  static const double maxZoom = 1.6;

  /// The height of the header above it: the same as [ScreenHeader] with its
  /// back button, so the tile starts where the dashboard's grid does.
  static const double headerHeight = 92;

  /// How far it stays in from the screen's edges, so the blurred dashboard
  /// shows round it — what it was lifted out of, and where to tap to put it
  /// back.
  static const double margin = 24;

  /// The room it is given, on a screen of [size].
  static Rect stageIn(Size size) => Rect.fromLTRB(
    margin,
    headerHeight,
    math.max(margin, size.width - margin),
    math.max(headerHeight, size.height - margin),
  );

  /// How much larger a tile lifted from [from] is drawn on [stage]: by the
  /// square root of how much it grew, so a small tile gains both size and
  /// room, and a large one mostly room. Never smaller than it was.
  static double zoomFor(Rect from, Rect stage) {
    if (from.isEmpty) return 1;
    final grew = math.min(stage.width / from.width, stage.height / from.height);
    return math.sqrt(math.max(1.0, grew)).clamp(1.0, maxZoom);
  }

  /// The tile as it is laid out brought close: the same widget on as many
  /// cells as fit in [room], counted by [pitch], at the top of a page so a
  /// console's frame runs along its top.
  static DashboardWidgetConfig cellsFor(
    DashboardWidgetConfig config,
    Size room,
    Size pitch,
  ) {
    int count(double length, double step, int most) =>
        step <= 0 ? most : (length / step).round().clamp(1, most);
    return DashboardWidgetConfig(
      id: config.id,
      type: config.type,
      x: 0,
      y: 0,
      width: count(room.width, pitch.width, DashboardGrid.columns),
      height: count(room.height, pitch.height, DashboardGrid.rows),
      page: config.page,
      fontFamily: config.fontFamily,
      fontScale: config.fontScale,
      schedule: config.schedule,
      options: config.options,
    );
  }

  @override
  State<TileSpotlight> createState() => TileSpotlightState();
}

class TileSpotlightState extends State<TileSpotlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 300),
  );

  /// Out quickly and settling, back the same way: a lift, then a drop.
  late final Animation<double> _flight = CurvedAnimation(
    parent: _lift,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// The dashboard recedes behind it as it rises, and the header comes in.
  late final Animation<double> _around = CurvedAnimation(
    parent: _lift,
    curve: const Interval(0, 0.8, curve: Curves.easeOut),
  );

  /// The tile itself fades only at the very start and end, where its shape
  /// on the grid and its shape brought close are furthest apart — and only
  /// briefly, or the dashboard shows through it on the way.
  late final Animation<double> _shown = CurvedAnimation(
    parent: _lift,
    curve: const Interval(0, 0.1, curve: Curves.easeOut),
  );

  Timer? _idle;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_lift.forward());
    _touched();
  }

  @override
  void dispose() {
    _idle?.cancel();
    _lift.dispose();
    super.dispose();
  }

  /// Whether it is going back already.
  bool get closing => _closing;

  /// Sends it back into its place on the grid.
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _idle?.cancel();
    await _lift.reverse();
    if (mounted) widget.onClosed();
  }

  void _touched() {
    _idle?.cancel();
    _idle = Timer(widget.autoClose, close);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final type = WidgetRegistry.find(widget.config.type);
    return LayoutBuilder(
      builder: (context, c) {
        final stage = TileSpotlight.stageIn(c.biggest);
        final zoom = TileSpotlight.zoomFor(widget.from, stage);
        // Laid out once, at the size it ends up, and only drawn larger or
        // smaller on the way: a widget laid out afresh at every frame of
        // the flight would stutter on a Pi.
        final room = stage.size / zoom;
        final cells = TileSpotlight.cellsFor(widget.config, room, widget.pitch);
        Widget tile = DashboardTile(
          config: cells,
          theme: theme,
          settings: widget.settings,
        );
        // A console's tile is the page's black inside its bars, not a box
        // of its own, so over the blurred dashboard it is given that black
        // back — tucked under the bars, clear of the elbow's outer sweep.
        if (theme.isLcars) {
          tile = Stack(
            children: [
              Positioned.fill(
                left: 8,
                top: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.background.first,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(56),
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: tile),
            ],
          );
        }
        tile = RepaintBoundary(
          child: SizedBox.fromSize(size: room, child: tile),
        );

        return Listener(
          // Any touch at all keeps it up for its full time again.
          onPointerDown: (_) => _touched(),
          child: Stack(
            children: [
              // The dashboard behind, blurred and dimmed; a tap on it puts
              // the tile back.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: close,
                  child: AnimatedBuilder(
                    animation: _around,
                    builder: (context, _) => BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: 14 * _around.value,
                        sigmaY: 14 * _around.value,
                      ),
                      child: ColoredBox(
                        color: theme.background.first.withValues(
                          alpha: 0.55 * _around.value,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: TileSpotlight.headerHeight,
                child: FadeTransition(
                  opacity: _around,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, -0.3),
                      end: Offset.zero,
                    ).animate(_around),
                    child: ScreenHeader(
                      title: type?.localName ?? widget.config.type,
                      onBack: close,
                      backTooltip: tr('dashboard.putBack', 'Put it back'),
                      iconColour: theme.textPrimary,
                      padding: const EdgeInsets.fromLTRB(
                        TileSpotlight.margin,
                        16,
                        TileSpotlight.margin,
                        12,
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _flight,
                builder: (context, child) {
                  final rect = Rect.lerp(widget.from, stage, _flight.value)!;
                  return Positioned.fromRect(
                    rect: rect,
                    child: FadeTransition(
                      opacity: _shown,
                      child: FittedBox(child: child),
                    ),
                  );
                },
                child: tile,
              ),
            ],
          ),
        );
      },
    );
  }
}

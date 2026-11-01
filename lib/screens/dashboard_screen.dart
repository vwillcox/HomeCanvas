import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:provider/provider.dart';

import '../dashboard/dashboard_model.dart';
import '../dashboard/page_overview.dart';
import '../dashboard/photo_backdrop.dart';
import '../dashboard/schedule.dart';
import '../dashboard/tile_spotlight.dart';
import '../dashboard/dashboard_theme.dart';
import '../dashboard/widgets/tv_inputs_sheet.dart';
import '../dashboard/widgets/weather_forecast_sheet.dart';
import '../dashboard/widget_registry.dart';
import '../services/config_service.dart';
import '../services/dashboard_service.dart';
import '../services/screen_idle_service.dart';
import '../services/playback_source.dart';
import '../look.dart';
import '../theme.dart' show fontFallback;
import '../widgets/glass.dart';
import '../widgets/lcars.dart';
import '../widgets/module_bar.dart';
import '../widgets/now_playing_overlay.dart';
import 'home_screen.dart' show showablePlayback;
import '../widgets/pause_when_hidden.dart';
import '../widgets/shown_timers.dart';
import '../widgets/stepped_timeline.dart';
import '../l10n/l10n.dart';

/// The dashboard: widgets laid out on a grid, drawn in the chosen theme.
///
/// Placement comes entirely from the saved configuration, which is edited in
/// a browser rather than here — this screen only draws it. Editing on a
/// wall-mounted touchscreen with no keyboard is miserable, and a phone is
/// already in your hand.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.initialPage = 0});

  /// Which page to open on. Only used by the debug launch hook — the panel
  /// itself always opens on the first page.
  final int initialPage;

  /// A page to show — its number as saved, not its place among the pages
  /// showing now — asked for from outside: a reminder falling due brings
  /// up the page its widget is on. Taken up by an open dashboard at once,
  /// or by the next one to open.
  static final ValueNotifier<int?> requestedPage = ValueNotifier(null);

  /// A page turn asked for from outside — by voice: 1 for the next page,
  /// -1 for the one before. Taken up by an open dashboard, and nothing else.
  static final ValueNotifier<int?> requestedTurn = ValueNotifier(null);

  /// The automatic page turn held or let go from outside, as the page dots
  /// do it. Taken up by an open dashboard.
  static final ValueNotifier<bool?> requestedPause = ValueNotifier(null);

  /// A tile to bring close (see [TileSpotlight]), by its widget's id or
  /// type, asked for from outside — by a test, or the control API. Taken up
  /// by the first such tile on the page showing, and by nothing otherwise.
  static final ValueNotifier<String?> requestedLift = ValueNotifier(null);

  /// Every page at once — see [PageOverview] — asked for from outside: by
  /// voice, true to open it. Taken up by an open dashboard, or the next one
  /// to open.
  static final ValueNotifier<bool?> requestedOverview = ValueNotifier(null);

  /// The dashboard's route, by name, so whatever is on top of it can be
  /// cleared away to show it — see [route].
  static const String routeName = 'dashboard';

  /// The way to the dashboard from anywhere in the kiosk.
  static Route<void> route() => MaterialPageRoute(
    settings: const RouteSettings(name: routeName),
    builder: (_) => const DashboardScreen(),
  );

  /// Whether a dashboard is on screen to take a [requestedPage] up.
  static bool get isOpen => _open > 0;
  static int _open = 0;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with PauseWhenHidden, ShownTimers {
  ScreenIdleService? _screenIdle;

  late final PageController _pages = PageController(
    initialPage: widget.initialPage,
  );
  late int _page = widget.initialPage;

  /// The automatic page turn: it runs from 0 to 1 over the page's time and
  /// turns the page when it gets there. That same value fills the current
  /// page's dot, so a turn is never a surprise, and pausing is simply
  /// stopping it. In steps, not frames — see [SteppedTimeline] — and held
  /// while the dashboard cannot be seen, as an animation would be.
  late final SteppedTimeline _turn = SteppedTimeline(
    onDone: () => _goTo(_page + 1, _pageCount),
  );

  /// Paused from the page dots. Holds until they are tapped again — through
  /// leaving the dashboard and through a restart, since it is saved.
  late bool _paused = context
      .read<ConfigService>()
      .config
      .dashboard
      .pagesPaused;
  bool _turning = false;
  int _pageCount = 1;

  /// The pages showing now, by page number — those whose hours are on. The
  /// page view runs over these, so a page out of its hours is simply not
  /// there to swipe to.
  List<int> _visible = const [];

  /// Looks again every half minute at which pages and widgets are due.
  Timer? _clock;

  /// The full now-playing player, opened from a Now playing tile or the
  /// top bar's controls — the home screen's player, growing out of whatever
  /// was tapped.
  final NowPlayingOverlayController _player = NowPlayingOverlayController();

  /// The tile brought close, if one is — see [TileSpotlight]. Its place on
  /// the grid is left empty meanwhile, and the page does not turn.
  _Lifted? _lifted;
  final _spotlight = GlobalKey<TileSpotlightState>();

  /// The stack everything is drawn in, which the spotlight covers: a tile's
  /// place on screen is turned into a place in this.
  final _body = GlobalKey();

  /// Every page at once, while it is up — see [PageOverview]. The pages do
  /// not turn under it.
  bool _overview = false;
  final _overviewState = GlobalKey<PageOverviewState>();

  /// What each page looked like when last on screen, by page number, for
  /// the overview; and the boundary each page is drawn in, to take that
  /// from. A page is pictured a moment after it arrives, once anything it
  /// fetched on the way is in, and every few minutes while it stays. Kept
  /// for as long as the kiosk runs, through a visit to the photos and back:
  /// one picture a page, so never more than the pages there are.
  static final Map<int, PageShot> _shots = {};
  final Map<int, GlobalKey> _shotKeys = {};
  Timer? _shotSoon;
  Timer? _shotEvery;

  /// Fingers down on the pages, for a pinch: two drawn together are the
  /// dashboard seen from further away.
  final Map<int, Offset> _fingers = {};
  double? _pinchFrom;

  /// The page is not turned out from under the full player: it would take
  /// the tile the player shrinks back into with it.
  void _playerOpened() {
    if (!_turning) return;
    if (_player.isOpen.value) {
      _turn.stop();
    } else {
      _restartTurn();
    }
  }

  @override
  void initState() {
    super.initState();
    DashboardScreen._open++;
    DashboardScreen.requestedPage.addListener(_pageRequested);
    DashboardScreen.requestedTurn.addListener(_turnRequested);
    DashboardScreen.requestedPause.addListener(_pauseRequested);
    DashboardScreen.requestedLift.addListener(_liftRequested);
    DashboardScreen.requestedOverview.addListener(_overviewRequested);
    // Opened for a page: gone to once the page view is laid out.
    if (DashboardScreen.requestedPage.value != null) _pageRequested();
    // And for a tile, once that page is.
    if (DashboardScreen.requestedLift.value != null) _liftRequested();
    _player.isOpen.addListener(_playerOpened);
    // Scheduled pages and tiles come and go by the clock — only looked at
    // while the dashboard can be seen.
    _clock = everyWhileShown(
      const Duration(seconds: 30),
      () => setState(() {}),
    );
    // A page left showing — held, or the only one — is pictured again now
    // and then, so the overview does not show it as it was this morning.
    _shotEvery = everyWhileShown(
      const Duration(minutes: 3),
      () => unawaited(_picture()),
    );
    // A dashboard is a thing you glance at from across the room without
    // touching it, so the idle timer would switch the panel off precisely
    // when it is doing its job. Held awake for as long as it is on screen;
    // switching it off is left to the user, or to Alexa.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _screenIdle = context.read<ScreenIdleService>()..dashboardShowing = true;
      _pictureSoon();
      if (DashboardScreen.requestedOverview.value != null) {
        _overviewRequested();
      }
      _debugPopup();
    });
  }

  /// Dev aid: HOMECANVAS_TEST_POPUP=forecast|inputs opens that pop-up once
  /// the dashboard is up. Both open only on a tap otherwise, and the panel is
  /// not something to send synthetic taps to. HOMECANVAS_TEST_LIFT=<widget
  /// id or type> brings that tile close, as a hold on it would, a few
  /// seconds later — once its widget has something to show.
  /// HOMECANVAS_TEST_OVERVIEW=1 opens every page at once a few seconds in;
  /// =tour first visits each page for long enough to picture it, as a
  /// panel left turning its pages would have done by then.
  void _debugPopup() {
    final overview = Platform.environment['HOMECANVAS_TEST_OVERVIEW'];
    if (overview == 'tour') unawaited(_tour());
    if (overview == '1') {
      Timer(const Duration(seconds: 5), () {
        if (mounted) unawaited(_openOverview());
      });
    }
    final lift = Platform.environment['HOMECANVAS_TEST_LIFT'];
    if (lift != null && lift.isNotEmpty) {
      Timer(const Duration(seconds: 4), () {
        if (mounted) DashboardScreen.requestedLift.value = lift;
      });
    }
    final which = Platform.environment['HOMECANVAS_TEST_POPUP'];
    if (which == null || which.isEmpty) return;
    final theme = context.read<DashboardService>().themes.byId(
      context.read<ConfigService>().config.dashboard.themeId,
    );
    if (which == 'forecast') unawaited(showWeatherForecast(context, theme));
    if (which == 'inputs') unawaited(showTvInputs(context, theme));
  }

  Future<void> _tour() async {
    await Future<void>.delayed(const Duration(seconds: 4));
    for (var i = 0; i < _visible.length; i++) {
      if (!mounted) return;
      _pages.jumpToPage(i);
      setState(() => _page = i);
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      await _picture();
    }
    if (!mounted) return;
    _pages.jumpToPage(0);
    setState(() => _page = 0);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) await _openOverview();
  }

  @override
  void onShownChanged(bool shown) {
    super.onShownChanged(shown);
    _turn.hold(!shown);
  }

  /// The page showing is pictured once it has settled.
  void _pictureSoon() {
    _shotSoon?.cancel();
    _shotSoon = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) unawaited(_picture());
    });
  }

  /// Pictures the page showing for the overview, unless it is not all
  /// there to picture: half turned, a tile lifted off it, or out of sight.
  Future<void> _picture({double ratio = 0.3}) async {
    if (!mounted || !shown || _overview || _lifted != null) return;
    if (_page >= _visible.length || !_pages.hasClients) return;
    if (((_pages.page ?? 0) - _page).abs() > 0.01) return;
    final page = _visible[_page];
    final boundary = _shotKeys[page]?.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return;
    final layout = pageLayout(
      context.read<ConfigService>().config.dashboard,
      page,
    );
    try {
      final image = await boundary.toImage(pixelRatio: ratio);
      // The overview may have opened meanwhile, showing the picture this
      // replaces, which cannot be let go until it closes.
      if (!mounted || _overview) {
        image.dispose();
        return;
      }
      _shots.remove(page)?.dispose();
      _shots[page] = PageShot(image, DateTime.now(), layout);
    } catch (e) {
      debugPrint('Dashboard: could not picture page ${page + 1}: $e');
    }
  }

  void _overviewRequested() {
    final open = DashboardScreen.requestedOverview.value;
    if (open == null || !mounted) return;
    // A dashboard with another opened over it to take this up leaves it to
    // that one: it would open under it, out of sight.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    DashboardScreen.requestedOverview.value = null;
    if (open) {
      unawaited(_openOverview());
    } else {
      unawaited(_overviewState.currentState?.close());
    }
  }

  /// Every page at once. The page showing is pictured afresh first, sharp
  /// enough to fill the screen, so that what shrinks into its card is the
  /// page exactly as it was.
  Future<void> _openOverview() async {
    if (_overview || _visible.length < 2 || !_pages.hasClients) return;
    _dropLifted();
    // A finger half way through a swipe lets go of it.
    _pages.jumpToPage(_page);
    _fingers.clear();
    _pinchFrom = null;
    _turn.stop();
    await WidgetsBinding.instance.endOfFrame;
    // Not waited for long: an old picture, or the page's map, does if
    // this one is slow.
    await _picture(
      ratio: 0.6,
    ).timeout(const Duration(milliseconds: 400), onTimeout: () {});
    if (!mounted || _overview) return;
    setState(() => _overview = true);
    _restartTurn();
  }

  /// A page chosen in the overview: gone to at once, under it, so it is
  /// there as the overview goes.
  void _overviewChose(int i) {
    if (!_pages.hasClients) return;
    if (i != _page) {
      _pages.jumpToPage(i);
      setState(() => _page = i);
    }
  }

  void _overviewClosed() {
    if (!mounted) return;
    setState(() => _overview = false);
    _restartTurn();
    _pictureSoon();
  }

  /// Gone at once: the page is being changed from outside.
  void _dropOverview() {
    if (!_overview) return;
    setState(() => _overview = false);
  }

  void _toggleOverview() {
    if (_overview) {
      unawaited(_overviewState.currentState?.close());
    } else {
      unawaited(_openOverview());
    }
  }

  /// Two fingers drawn together on the pages open the overview.
  void _fingerDown(PointerDownEvent e) {
    _restartTurn();
    _fingers[e.pointer] = e.position;
    _pinchFrom = _fingers.length == 2 ? _spread() : null;
  }

  void _fingerMoved(PointerMoveEvent e) {
    if (!_fingers.containsKey(e.pointer)) return;
    _fingers[e.pointer] = e.position;
    final from = _pinchFrom;
    if (from != null && _fingers.length == 2 && _spread() < from * 0.65) {
      _pinchFrom = null;
      unawaited(_openOverview());
    }
  }

  void _fingerUp(PointerEvent e) {
    _fingers.remove(e.pointer);
    if (_fingers.length != 2) _pinchFrom = null;
  }

  double _spread() {
    final p = _fingers.values.toList();
    return (p[0] - p[1]).distance;
  }

  /// Goes to [DashboardScreen.requestedPage], if it is one of the pages
  /// showing now; otherwise stays where it is.
  void _pageRequested() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final want = DashboardScreen.requestedPage.value;
      if (want == null || !mounted || !_pages.hasClients) return;
      DashboardScreen.requestedPage.value = null;
      final settings = context.read<ConfigService>().config.dashboard;
      final visible = visiblePages(
        settings.pageCount,
        settings.pages,
        DateTime.now(),
      );
      final target = visible.indexOf(want);
      if (target < 0) return;
      _dropLifted();
      _dropOverview();
      _pages.jumpToPage(target);
      setState(() => _page = target);
      // A full page's time from now, if the pages are turning.
      _restartTurn();
    });
  }

  void _turnRequested() {
    final by = DashboardScreen.requestedTurn.value;
    if (by == null || !mounted || !_pages.hasClients) return;
    DashboardScreen.requestedTurn.value = null;
    _goTo(_page + by, _pageCount);
  }

  /// Brings [DashboardScreen.requestedLift]'s tile close, if it is on the
  /// page showing; otherwise lets the asking go. After the frame, and for a
  /// few frames more if need be: a page gone to in the same breath — "the
  /// news closer" from another page — has its tiles built a frame later.
  void _liftRequested([int tries = 4]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final want = DashboardScreen.requestedLift.value;
      if (want == null || !mounted) return;
      final tile = _page < _visible.length
          ? _LiftableState.find(want, _visible[_page])
          : null;
      if (tile == null && tries > 1) return _liftRequested(tries - 1);
      DashboardScreen.requestedLift.value = null;
      tile?.lift();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _pauseRequested() {
    final paused = DashboardScreen.requestedPause.value;
    if (paused == null || !mounted) return;
    DashboardScreen.requestedPause.value = null;
    if (paused != _paused) _togglePause();
  }

  @override
  void dispose() {
    DashboardScreen._open--;
    DashboardScreen.requestedPage.removeListener(_pageRequested);
    DashboardScreen.requestedTurn.removeListener(_turnRequested);
    DashboardScreen.requestedPause.removeListener(_pauseRequested);
    DashboardScreen.requestedLift.removeListener(_liftRequested);
    DashboardScreen.requestedOverview.removeListener(_overviewRequested);
    // Releasing it here rather than on the way in to the next screen means
    // the timer restarts from now, not from whenever the dashboard opened.
    _screenIdle?.dashboardShowing = false;
    _clock?.cancel();
    _shotSoon?.cancel();
    _shotEvery?.cancel();
    _player.isOpen.removeListener(_playerOpened);
    _player.dispose();
    _turn.dispose();
    _pages.dispose();
    super.dispose();
  }

  /// Starts, retimes or stops the automatic page turn to match the settings
  /// and how many pages there actually are. Called from build, so the change
  /// itself waits for the frame to finish: starting an animation mid-build
  /// would redraw the dots in the middle of drawing them.
  void _syncTurn(DashboardSettings settings, int pageCount) {
    _pageCount = pageCount;
    final wanted = settings.pageSeconds > 0 && pageCount > 1;
    final length = Duration(seconds: settings.pageSeconds);
    if (wanted == _turning && (!wanted || _turn.duration == length)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final changed = _turn.duration != length;
      if (wanted) _turn.duration = length;
      setState(() => _turning = wanted);
      if (!wanted) {
        _turn
          ..stop()
          ..value = 0;
      } else if (!_paused &&
          !_player.isOpen.value &&
          _lifted == null &&
          !_overview &&
          (changed || !_turn.isAnimating)) {
        _turn.forward(from: changed ? 0 : _turn.value);
      }
    });
  }

  /// Keeps the page view in step as pages come and go with their hours.
  ///
  /// A page whose hours have just begun is gone to straight away — the
  /// morning page arriving at six is the point of giving it hours. Otherwise
  /// the page being looked at stays, wherever it now sits in the list.
  void _followVisible(List<int> visible) {
    final was = _visible;
    if (listEquals(was, visible)) return;
    _visible = visible;
    if (was.isEmpty) return; // first build: the page view starts where it is
    final arrived = visible.where((p) => !was.contains(p)).toList();
    final current = _page < was.length ? was[_page] : 0;
    final target = arrived.isNotEmpty
        ? visible.indexOf(arrived.first)
        : math.max(0, visible.indexOf(current));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pages.hasClients) return;
      _pages.jumpToPage(target);
      setState(() => _page = target);
      _restartTurn();
    });
  }

  /// The page's time starts again — on arriving at a page, and whenever it
  /// is touched, so a page being read or scrolled is not taken away from
  /// under the finger.
  void _restartTurn() {
    if (!_turning) return;
    if (_paused || _player.isOpen.value || _lifted != null || _overview) {
      // Stopped too, should it have been running: a tile is lifted while
      // its page's time runs.
      _turn
        ..stop()
        ..value = 0;
    } else {
      _turn.forward(from: 0);
    }
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    final config = context.read<ConfigService>();
    config.config.dashboard.pagesPaused = _paused;
    unawaited(config.save());
    if (_paused) {
      _turn.stop();
    } else if (_turning &&
        !_player.isOpen.value &&
        _lifted == null &&
        !_overview) {
      _turn.forward();
    }
  }

  /// Brings [config]'s tile close, out of [global] — where it is on screen.
  void _lift(DashboardWidgetConfig config, Rect global, Size pitch) {
    final body = _body.currentContext?.findRenderObject() as RenderBox?;
    if (_lifted != null || body == null || !body.hasSize) return;
    final from = Rect.fromPoints(
      body.globalToLocal(global.topLeft),
      body.globalToLocal(global.bottomRight),
    );
    setState(() => _lifted = (config: config, from: from, pitch: pitch));
    // Held for as long as it is up, and a full page's time once it is back.
    _restartTurn();
  }

  /// Back in its place, at the end of the way back.
  void _landed() {
    if (!mounted) return;
    setState(() => _lifted = null);
    _restartTurn();
  }

  /// Gone at once, without the way back: the page is about to change under
  /// it, and it would shrink into a place that is no longer there.
  void _dropLifted() {
    if (_lifted == null) return;
    setState(() => _lifted = null);
  }

  void _goTo(int index, int pageCount) {
    if (pageCount <= 1) return;
    _dropLifted();
    final next = index % pageCount;
    // A page dot touched with every page showing: that card, chosen.
    if (_overviewState.currentState case final overview?) {
      unawaited(overview.choose(next));
      return;
    }
    _pages.animateToPage(
      next,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
    );
  }

  /// A tap anywhere that a widget did not claim.
  ///
  /// Only reached when the widget under the finger ignored it, so tapping the
  /// TV remote or the speed test still does what those do rather than turning
  /// the page underneath them.
  void _tapped(DashboardSettings settings) {
    if (!settings.tapToFlip) return;
    // Arriving at the page restarts its time (see onPageChanged), so a page
    // you just chose is not whipped away half a second later.
    _goTo(_page + 1, settings.pageCount);
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardService>();
    final settings = context.watch<ConfigService>().config.dashboard;
    // The kiosk's theme, which the dashboard's choice sets — including the
    // HOMECANVAS_TEST_THEME override, applied where it is chosen.
    final theme = context.look;

    final visible = visiblePages(
      settings.pageCount,
      settings.pages,
      DateTime.now(),
    );
    _followVisible(visible);
    final pageCount = visible.length;
    // Kept in step with the config on every build, so editing the interval in
    // the browser takes effect without leaving and re-entering the dashboard.
    _syncTurn(settings, pageCount);
    final dotsTurn = _turning ? _turn : null;
    final onPause = _turning ? _togglePause : null;

    final grid = Stack(
      children: [
        if (settings.widgets.isEmpty)
          _Empty(
            theme: theme,
            address: dashboard.editorAddress,
            fallback: dashboard.editorIpAddress,
          )
        else
          // Behind the widgets, not over them: a translucent layer on
          // top would swallow every tap meant for a widget. This only
          // sees taps that fell on empty grid.
          // Any touch on a page gives it its full time again. A Listener
          // sees the touch without taking it, so the widget underneath
          // still gets its tap or its scroll.
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _fingerDown,
            onPointerMove: _fingerMoved,
            onPointerUp: _fingerUp,
            onPointerCancel: _fingerUp,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _tapped(settings),
              child: PageView.builder(
                controller: _pages,
                itemCount: pageCount,
                // Swiping works whatever the settings say — it is
                // unambiguous in a way that tapping is not.
                onPageChanged: (i) {
                  setState(() => _page = i);
                  _restartTurn();
                  _pictureSoon();
                },
                // Each page in a boundary of its own, which is what the
                // overview's picture of it is taken from.
                itemBuilder: (context, i) => RepaintBoundary(
                  key: _shotKeys.putIfAbsent(visible[i], GlobalKey.new),
                  child: _Grid(
                    settings: settings,
                    theme: theme,
                    page: visible[i],
                    lifted: _lifted?.config.id,
                    onLift: _lift,
                  ),
                ),
              ),
            ),
          ),
        // Over the pages, under the top bar — or the dots and back button
        // floating in its place — whose page dots still go to a page, and
        // whose All pages button puts it away again.
        if (_overview)
          Positioned.fill(
            child: PageOverview(
              key: _overviewState,
              settings: settings,
              theme: theme,
              pages: visible,
              current: _page.clamp(0, math.max(0, pageCount - 1)),
              shots: _shots,
              onChosen: _overviewChose,
              onClosed: _overviewClosed,
              // The cards kept clear of the floating dots.
              margin: EdgeInsets.only(bottom: settings.topBar ? 0 : 84),
            ),
          ),
        // With the top bar off: the panel has no keyboard and no
        // window chrome, so without this there is no way off the
        // dashboard at all.
        if (!settings.topBar) ...[
          Positioned(left: 12, bottom: 12, child: _BackButton(theme: theme)),
          if (pageCount > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: _PageDots(
                  count: pageCount,
                  current: _page,
                  theme: theme,
                  onTap: (i) => _goTo(i, pageCount),
                  turn: dotsTurn,
                  paused: _paused,
                  onTogglePause: onPause,
                  overview: _overview,
                  onOverview: _toggleOverview,
                ),
              ),
            ),
        ],
      ],
    );

    // The tiles find the player through this: a Now playing tile opens it.
    return NowPlayingOpener(
      controller: _player,
      // Back — the button, or by voice — puts a tile brought close back
      // before it leaves the dashboard.
      child: PopScope(
        canPop: _lifted == null && !_overview,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          // Back puts away whatever is over the page first.
          if (_overview) {
            unawaited(_overviewState.currentState?.close());
          } else {
            unawaited(_spotlight.currentState?.close());
          }
        },
        child: _scaffold(settings, theme, grid, pageCount, dotsTurn, onPause),
      ),
    );
  }

  Widget _scaffold(
    DashboardSettings settings,
    DashboardTheme theme,
    Widget grid,
    int pageCount,
    ValueListenable<double>? dotsTurn,
    VoidCallback? onPause,
  ) {
    return Scaffold(
      body: Container(
        decoration: theme.backgroundDecoration,
        child: Stack(
          key: _body,
          fit: StackFit.expand,
          children: [
            if (theme.glowEndDecoration != null)
              DecoratedBox(decoration: theme.glowEndDecoration!),
            if (settings.photoBackground)
              PhotoBackdrop(
                albumId: settings.photoAlbum,
                dim: settings.photoDim,
                every: Duration(seconds: settings.photoSeconds),
                base: theme.background.first,
              ),
            SafeArea(
              child: !settings.topBar
                  ? grid
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The same bar as every other screen, in the theme's
                        // colours: back on the left, the greeting and date, and
                        // the pages on the right where the dots used to float
                        // over the widgets.
                        _TopBar(
                          theme: theme,
                          pageCount: pageCount,
                          page: _page,
                          onPage: (i) => _goTo(i, pageCount),
                          turn: dotsTurn,
                          paused: _paused,
                          onTogglePause: onPause,
                          player: _player,
                          onOverview: _toggleOverview,
                        ),
                        Expanded(child: grid),
                      ],
                    ),
            ),
            // Over the top bar as well as the grid, but under the player,
            // which a Now playing tile brought close can still open.
            if (_lifted case final lifted?)
              TileSpotlight(
                key: _spotlight,
                config: lifted.config,
                from: lifted.from,
                pitch: lifted.pitch,
                theme: theme,
                settings: settings,
                onClosed: _landed,
              ),
            // Over everything, top bar included, as it is on the home
            // screen. Draws nothing until something opens it.
            NowPlayingOverlay(fullScreen: true, controller: _player),
          ],
        ),
      ),
    );
  }
}

/// The kiosk's top bar, drawn for the dashboard.
///
/// [ScreenHeader] in the dashboard theme's colours rather than the app's, so
/// it belongs to whichever theme is chosen — under Glass it is the home
/// screen's bar exactly; under Nightstand it is amber on black.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.theme,
    required this.pageCount,
    required this.page,
    required this.onPage,
    this.turn,
    this.paused = false,
    this.onTogglePause,
    this.player,
    this.onOverview,
  });

  final DashboardTheme theme;
  final int pageCount;
  final int page;
  final void Function(int) onPage;
  final ValueListenable<double>? turn;
  final bool paused;
  final VoidCallback? onTogglePause;
  final NowPlayingOverlayController? player;
  final VoidCallback? onOverview;

  @override
  Widget build(BuildContext context) {
    final playing = showablePlayback(context);
    return DefaultTextStyle.merge(
      style: TextStyle(color: theme.textPrimary),
      child: ScreenHeader(
        titleWidget: GreetingTitle(
          colour: theme.textPrimary,
          secondary: theme.textSecondary,
        ),
        padding: const EdgeInsets.fromLTRB(28, 14, 20, 4),
        // The home screen's own bar, rather than a back button: Photos takes
        // you home, and everything else is where it is there.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (playing != null) ...[
              _MediaControls(source: playing, theme: theme, player: player),
              const SizedBox(width: 12),
            ],
            if (pageCount > 1) ...[
              _PageDots(
                count: pageCount,
                current: page,
                theme: theme,
                onTap: onPage,
                turn: turn,
                paused: paused,
                onTogglePause: onTogglePause,
              ),
              const SizedBox(width: 12),
            ],
            // Dashboard, touched again on the dashboard, is every page at
            // once: the dashboard as a whole. A button of its own would
            // crowd the greeting out of a bar with a dozen pages in it.
            ModuleBar(
              current: KioskModule.dashboard,
              colour: theme.textPrimary,
              accent: theme.accent,
              onAgain: pageCount > 1 ? onOverview : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Back to whatever the kiosk was showing before the dashboard.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.theme});

  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    // Glass like every other screen's back button, but never fully clear: a
    // control you cannot see is a control you cannot find.
    return GlassIconButton(
      icon: Icons.arrow_back_rounded,
      tooltip: tr('dashboard.back', 'Back'),
      size: 72,
      colour: theme.textPrimary,
      onPressed: () => Navigator.of(context).maybePop(),
    );
  }
}

/// A tile brought close: which, where it was on screen, and the grid's
/// cell and gap, to count the room it is given in cells.
typedef _Lifted = ({DashboardWidgetConfig config, Rect from, Size pitch});

class _Grid extends StatelessWidget {
  const _Grid({
    required this.settings,
    required this.theme,
    this.page = 0,
    this.lifted,
    this.onLift,
  });

  final DashboardSettings settings;
  final DashboardTheme theme;
  final int page;

  /// The id of the tile brought close, whose place is left empty.
  final String? lifted;

  /// A tile held: bring it close.
  final void Function(DashboardWidgetConfig, Rect, Size)? onLift;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final gap = theme.gap;
        final now = DateTime.now();
        // Cells are whatever is left once the gaps are taken out, so the
        // outermost widgets sit the same distance from the edge as they do
        // from each other.
        final cellWidth =
            (c.maxWidth - gap * (DashboardGrid.columns + 1)) /
            DashboardGrid.columns;
        final cellHeight =
            (c.maxHeight - gap * (DashboardGrid.rows + 1)) / DashboardGrid.rows;
        final pitch = Size(cellWidth + gap, cellHeight + gap);

        return Stack(
          children: [
            for (final w in settings.widgetsOn(page))
              if (w.schedule.isAlways || w.schedule.activeAt(now))
                Positioned(
                  left: gap + w.x * (cellWidth + gap),
                  top: gap + w.y * (cellHeight + gap),
                  width: w.width * cellWidth + (w.width - 1) * gap,
                  height: w.height * cellHeight + (w.height - 1) * gap,
                  child: _Liftable(
                    config: w,
                    lifted: w.id == lifted,
                    onLift: onLift == null
                        ? null
                        : (rect) => onLift!(w, rect, pitch),
                    child: DashboardTile(
                      config: w,
                      theme: theme,
                      settings: settings,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

/// A tile on the grid that can be held to bring it close, and the empty
/// place it leaves while it is.
///
/// A hold, because a tap is the widget's own: the TV remote's keys, a news
/// story, the weather's forecast. Holding is free on every tile but the
/// timers', whose own hold — clearing a timer — still comes first, being the
/// nearer to the finger.
class _Liftable extends StatefulWidget {
  const _Liftable({
    required this.config,
    required this.lifted,
    required this.onLift,
    required this.child,
  });

  final DashboardWidgetConfig config;
  final bool lifted;

  /// With where the tile is on screen.
  final void Function(Rect)? onLift;
  final Widget child;

  @override
  State<_Liftable> createState() => _LiftableState();
}

class _LiftableState extends State<_Liftable> {
  /// Every tile built, for [DashboardScreen.requestedLift] to be found in.
  static final Set<_LiftableState> _built = {};

  /// The first tile built that answers to [want], by id or type, on
  /// [page] of a dashboard that can be seen — not one under another screen.
  static _LiftableState? find(String want, int page) {
    for (final tile in _built) {
      final c = tile.widget.config;
      if (c.page != page || tile.widget.lifted) continue;
      if (c.id != want && c.type != want) continue;
      if (TickerMode.valuesOf(tile.context).enabled) return tile;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _built.add(this);
  }

  @override
  void dispose() {
    _built.remove(this);
    super.dispose();
  }

  void lift() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    widget.onLift?.call(
      MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Nothing at all while it is lifted, rather than the same widget hidden:
    // a camera or a video would otherwise run twice, once out of sight.
    if (widget.lifted) return const SizedBox.expand();
    return GestureDetector(
      // The whole tile answers, its empty corners included. A tap still
      // goes to the widget, or to the page behind when the widget ignores it.
      behavior: HitTestBehavior.opaque,
      onLongPress: widget.onLift == null ? null : lift,
      child: widget.child,
    );
  }
}

/// One widget in its tile: the theme's frame, the chosen font and size, and
/// the shrink for a small tile.
///
/// Public because the web editor's previews are drawn by this too — see
/// `TileRenderHost` — so a preview is the panel's own drawing, not a copy.
class DashboardTile extends StatelessWidget {
  const DashboardTile({
    super.key,
    required this.config,
    required this.theme,
    required this.settings,
    this.framed = true,
  });

  final DashboardWidgetConfig config;
  final DashboardTheme theme;
  final DashboardSettings settings;

  /// Whether to draw the tile's own background, border and shadow. Off for
  /// the editor, which draws the frame itself — a shadow falls outside the
  /// tile and would be cut off in a picture of it — and lays the picture of
  /// the contents over it.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final type = WidgetRegistry.find(config.type);

    final child = type == null
        // A type this build doesn't know — a config from a newer version, or
        // a widget mid-development. Say so rather than drawing nothing, and
        // leave the configuration alone so it comes back when the widget does.
        ? Center(
            child: Text(
              tr('dashboard.unknownWidget', 'Unknown widget "{type}"', {
                'type': config.type,
              }),
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.textSecondary, fontSize: 14),
            ),
          )
        : Builder(
            builder: (context) => type.build(
              context,
              DashboardWidgetContext(config: config, theme: theme),
            ),
          );

    // Font and size are applied here, for every widget, rather than in each
    // one. The family rides on the default text style, which Text merges into
    // its own; the scale goes through the text scaler, which is the only
    // thing that also reaches the explicit font sizes widgets set on
    // themselves.
    // How much the tile has been shrunk below the size this widget's fixed
    // font sizes and paddings were written for. Every widget can now be
    // placed at 1x1, where a 17-point heading and 16 pixels of padding on
    // each side simply do not fit.
    final fit = type?.contentScale(config.width, config.height) ?? 1.0;
    // A widget that fits its own text to the tile gets the user's font size
    // untouched; shrinking it here as well would undo the fitting.
    final textFit = (type?.fitsItself ?? false) ? 1.0 : fit;

    final decoration = theme.tileDecorationWith(
      radius: settings.radiusOver(theme.cornerRadius),
      withShadow: settings.shadowOver(theme.shadow),
    );
    final media = MediaQuery.of(context);
    // A console's tile is black inside drawn bars, not a filled box, with
    // what it is lettered on the bar — its name, and a number to tell two
    // of a kind apart. The lower half of the grid sweeps down and across
    // the bottom, so a page is framed along both edges.
    final Widget tile;
    if (theme.isLcars) {
      tile = LcarsPanel(
        theme: theme,
        label:
            '${type?.localName ?? config.type} '
            '${lcarsIndex(config.id) % 90 + 10}',
        down: config.y * 2 + config.height > DashboardGrid.rows,
        scale: fit,
        square: settings.radiusOver(theme.cornerRadius) == 0,
        framed: framed,
        child: child,
      );
    } else {
      tile = framed
          ? Container(
              decoration: decoration,
              // Padding shrinks with the text. At 1x1 the old fixed 16 took
              // a fifth of the tile before anything was drawn in it.
              padding: EdgeInsets.all(16 * fit),
              clipBehavior: Clip.antiAlias,
              child: child,
            )
          // Where the framed tile's contents would be: a Container adds its
          // border's width to the padding, so the same inset is kept here.
          : Padding(
              padding: EdgeInsets.all(16 * fit).add(decoration.padding),
              child: child,
            );
    }
    return MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(
          media.textScaler.scale(1) * config.fontScale * textFit,
        ),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: theme.textPrimary,
          fontFamily: config.fontFamily.isEmpty
              ? theme.fontFamily
              : config.fontFamily,
          // A fresh style, not a merge, so the app's fallback is named again.
          fontFamilyFallback: fontFallback,
        ),
        child: tile,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.theme, required this.address, this.fallback});

  final DashboardTheme theme;
  final String address;

  /// The same address by IP, for a browser that can't resolve .local names.
  final String? fallback;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dashboard_customize_outlined,
            size: 64,
            color: theme.textSecondary,
          ),
          const SizedBox(height: 20),
          Text(
            tr('dashboard.noWidgetsYet', 'No widgets yet'),
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tr(
              'dashboard.openThisInABrowser',
              'Open this in a browser to arrange the dashboard:',
            ),
            style: TextStyle(color: theme.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 10),
          SelectableText(
            address,
            style: TextStyle(
              color: theme.accent,
              fontSize: 24,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (fallback != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              'or $fallback',
              style: TextStyle(color: theme.textSecondary, fontSize: 16),
            ),
          ],
        ],
      ),
    );
  }
}

/// Play and pause from any page, whenever something is playing: the
/// artwork, which opens the full player out of itself, and back, play and
/// next — in a glass pill the size of the module bar's, beside it.
class _MediaControls extends StatefulWidget {
  const _MediaControls({
    required this.source,
    required this.theme,
    this.player,
  });

  final PlaybackSource source;
  final DashboardTheme theme;
  final NowPlayingOverlayController? player;

  @override
  State<_MediaControls> createState() => _MediaControlsState();
}

class _MediaControlsState extends State<_MediaControls> {
  final _art = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final t = widget.theme;
    final playing = source.now.isPlaying;
    final art = source.artUrl;
    return Glass(
      strip: true,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: tr(
              'dashboard.nowPlayingOpenThePlayer',
              'Now playing: {title}. Open the player.',
              {'title': source.now.title},
            ),
            child: GestureDetector(
              onTap: () => widget.player?.expand(from: _art),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 60,
                height: 60,
                child: Center(
                  child: ClipRRect(
                    key: _art,
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: art == null
                          ? ColoredBox(
                              color: t.textSecondary.withValues(alpha: 0.15),
                              child: Icon(
                                Icons.music_note_rounded,
                                size: 24,
                                color: t.textSecondary,
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: art,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => const SizedBox(),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          PillIconButton(
            icon: Icons.skip_previous_rounded,
            tooltip: tr('dashboard.previous', 'Previous'),
            colour: t.textPrimary,
            onPressed: source.previous,
          ),
          PillIconButton(
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: playing
                ? tr('dashboard.pause', 'Pause')
                : tr('dashboard.play', 'Play'),
            colour: t.accent,
            onPressed: source.playPause,
          ),
          PillIconButton(
            icon: Icons.skip_next_rounded,
            tooltip: tr('dashboard.next', 'Next'),
            colour: t.textPrimary,
            onPressed: source.next,
          ),
        ],
      ),
    );
  }
}

/// Which page you are on, and a way to jump straight to another — and,
/// with the pages turning themselves, how long until the next turn and a
/// way to hold it.
///
/// Sized for a finger rather than as decoration: on a wall panel these are
/// the only visible sign that there is more than one page at all.
class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.current,
    required this.theme,
    required this.onTap,
    this.turn,
    this.paused = false,
    this.onTogglePause,
    this.overview = false,
    this.onOverview,
  });

  final int count;
  final int current;
  final DashboardTheme theme;
  final void Function(int) onTap;

  /// Every page at once: whether it is up, and the button that puts it up
  /// or away.
  final bool overview;
  final VoidCallback? onOverview;

  /// How far through its time the current page is, when pages turn
  /// themselves. Fills the current dot.
  final ValueListenable<double>? turn;
  final bool paused;
  final VoidCallback? onTogglePause;

  @override
  Widget build(BuildContext context) {
    final dim = theme.textSecondary.withValues(alpha: 0.4);
    if (theme.isLcars) {
      // A console's strip of segments, the page you are on the long one,
      // filling as its time runs, with hold and carry on as a block.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onOverview != null) ...[
            Semantics(
              button: true,
              label: tr('dashboard.allPages', 'All pages'),
              child: LcarsBlock(
                colour: overview ? lcarsLit : theme.block(3),
                onTap: onOverview,
                width: 72,
                height: 44,
                child: const Icon(Icons.grid_view_rounded, size: 26),
              ),
            ),
            const SizedBox(width: 6),
          ],
          LcarsPageStrip(
            count: count,
            current: current,
            onTap: (i) => i == current && onTogglePause != null
                ? onTogglePause!()
                : onTap(i),
            fill: turn == null
                ? null
                : _Fill(turn: turn!, paused: paused, colour: lcarsLit),
          ),
          if (onTogglePause != null) ...[
            const SizedBox(width: 6),
            Semantics(
              button: true,
              label: paused
                  ? tr(
                      'dashboard.carryOnTurningPages',
                      'Carry on turning pages',
                    )
                  : tr('dashboard.holdThisPage', 'Hold this page'),
              child: LcarsBlock(
                colour: paused ? lcarsLit : theme.block(1),
                onTap: onTogglePause,
                width: 72,
                height: 44,
                child: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 28,
                ),
              ),
            ),
          ],
        ],
      );
    }
    // In a glass pill, like every other control on the kiosk's screens, and
    // the same height as the module bar beside it: 60-point targets, as the
    // bar's buttons are, so the two pills line up and read as one toolbar.
    return Glass(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Every page at once, first: the way to the pages as a whole,
          // before the way to each.
          if (onOverview != null) ...[
            Semantics(
              button: true,
              label: tr('dashboard.allPages', 'All pages'),
              child: GestureDetector(
                onTap: onOverview,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: Center(
                    child: Icon(
                      Icons.grid_view_rounded,
                      size: 28,
                      color: overview ? theme.accent : theme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: 1,
              height: 34,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: dim,
            ),
          ],
          for (var i = 0; i < count; i++)
            GestureDetector(
              // The current dot is the clock: tapping it holds or carries on,
              // the same as the button beside it. The others go to their page.
              onTap: () => i == current && onTogglePause != null
                  ? onTogglePause!()
                  : onTap(i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                // The box is the touch target; the dot itself stays smaller
                // so it does not compete with the widgets for attention.
                constraints: const BoxConstraints(minWidth: 52, minHeight: 60),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: i == current ? 44 : 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: i == current
                        ? (turn == null
                              ? theme.accent
                              : theme.accent.withValues(alpha: 0.3))
                        : dim,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: i == current && turn != null
                      ? _Fill(turn: turn!, paused: paused, colour: theme.accent)
                      : null,
                ),
              ),
            ),
          if (onTogglePause != null) ...[
            Container(
              width: 1,
              height: 34,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: dim,
            ),
            Semantics(
              button: true,
              label: paused
                  ? tr(
                      'dashboard.carryOnTurningPages',
                      'Carry on turning pages',
                    )
                  : tr('dashboard.holdThisPage', 'Hold this page'),
              child: GestureDetector(
                onTap: onTogglePause,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, a) => ScaleTransition(
                        scale: a,
                        child: FadeTransition(opacity: a, child: child),
                      ),
                      child: Icon(
                        paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        key: ValueKey(paused),
                        size: 30,
                        color: paused ? theme.accent : theme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The current dot filling up as its page's time runs out. Paused, the fill
/// stays where it stopped, dimmed, beside the play button that says it is
/// held. It used to breathe, which kept the whole screen redrawing sixty
/// times a second for as long as the pages were held — and being held is
/// saved, so that was often for good.
class _Fill extends StatelessWidget {
  const _Fill({required this.turn, required this.paused, required this.colour});

  final ValueListenable<double> turn;
  final bool paused;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: turn,
      builder: (context, value, _) => Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colour.withValues(alpha: paused ? 0.55 : 1),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

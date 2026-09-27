import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../screens/link_viewer_screen.dart';
import '../screens/video_player_screen.dart'
    show VideoBottomControls, VideoVolumeColumn;
import '../services/youtube_service.dart';

/// The YouTube video sent to the panel: full screen, or floating as a
/// picture-in-picture window over whatever else the kiosk is showing.
///
/// Placed once in `main.dart`'s `MaterialApp.builder`, beside the share
/// overlay, so the picture-in-picture window stays up while the dashboard,
/// the photos or Settings are used underneath it. That puts it outside the
/// Navigator — and so outside the Navigator's Overlay, which sliders and
/// tooltips need — so it brings an Overlay of its own.
class YouTubeOverlay extends StatefulWidget {
  const YouTubeOverlay({super.key, required this.navigatorKey});

  /// For opening the browser when a video will not play here — see
  /// [IncomingShareOverlay.navigatorKey] for why a key rather than a context.
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<YouTubeOverlay> createState() => _YouTubeOverlayState();
}

class _YouTubeOverlayState extends State<YouTubeOverlay> {
  late final OverlayEntry _entry = OverlayEntry(
    builder: (_) => _Body(navigatorKey: widget.navigatorKey),
  );

  @override
  Widget build(BuildContext context) {
    final closed = context.select<YouTubeService, bool>(
        (y) => y.view == YouTubeView.closed);
    if (closed) return const SizedBox.shrink();
    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: Overlay(initialEntries: [_entry]),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.navigatorKey});
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _subs = <StreamSubscription>[];
  Player? _watching;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _seeking = false;
  double _rate = 1;

  bool _controls = true;
  Timer? _hideTimer;
  String? _hud;
  Timer? _hudTimer;

  // The picture-in-picture window's size while a pinch is under way.
  double _pinchStartWidth = 0;

  YouTubeView? _shown;

  static const double _aspect = 16 / 9;
  static const double _margin = 24;
  static const double _minPipWidth = 280;

  @override
  void dispose() {
    _unwatch();
    _hideTimer?.cancel();
    _hudTimer?.cancel();
    super.dispose();
  }

  void _unwatch() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _watching = null;
  }

  /// Follows the service's player, which exists only once the first video
  /// has been resolved and is then kept for the next.
  void _watch(Player? player) {
    if (player == _watching) return;
    _unwatch();
    if (player == null) return;
    _watching = player;
    _position = player.state.position;
    _duration = player.state.duration;
    _playing = player.state.playing;
    _rate = player.state.rate;
    _subs.add(player.stream.position.listen((p) {
      if (!_seeking && mounted) setState(() => _position = p);
    }));
    _subs.add(player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    }));
    _subs.add(player.stream.playing.listen((p) {
      if (!mounted) return;
      setState(() => _playing = p);
      _scheduleHide();
    }));
    _scheduleHide();
  }

  /// Controls fade after a few seconds of playing, and stay while paused.
  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_playing) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _showHud(String text) {
    _hudTimer?.cancel();
    setState(() => _hud = text);
    _hudTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _hud = null);
    });
  }

  void _skip(Player player, int seconds) {
    var to = _position + Duration(seconds: seconds);
    if (to < Duration.zero) to = Duration.zero;
    if (_duration > Duration.zero && to > _duration) to = _duration;
    player.seek(to);
    _showHud('${seconds > 0 ? '+' : ''}${seconds}s');
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  /// Hands the video to the browser, signed in if the kiosk is, for the
  /// videos yt-dlp cannot get at.
  void _openInBrowser(YouTubeService yt) {
    final link = yt.link;
    if (link == null) return;
    final title = yt.stream?.title;
    unawaited(yt.close());
    widget.navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => LinkViewerScreen(
        url: link.watchUrl,
        title: title ?? 'YouTube',
        profile: YouTubeService.loginProfile,
        keepProfile: true,
        timeout: const Duration(hours: 1),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final yt = context.watch<YouTubeService>();
    _watch(yt.player);
    // Each change of view starts with the controls up, then fades them.
    if (yt.view != _shown) {
      _shown = yt.view;
      _controls = true;
      _scheduleHide();
    }
    return LayoutBuilder(builder: (context, c) {
      final screen = c.biggest;
      return switch (yt.view) {
        YouTubeView.closed => const SizedBox.shrink(),
        YouTubeView.full => _full(yt),
        YouTubeView.pip => Stack(children: [_pip(yt, screen)]),
      };
    });
  }

  // --- Full screen ----------------------------------------------------------

  Widget _full(YouTubeService yt) {
    final player = yt.player;
    final ready = !yt.loading && yt.error == null && player != null;
    final total = _duration.inMilliseconds.toDouble();
    final pos =
        _position.inMilliseconds.clamp(0, total <= 0 ? 0 : total).toDouble();

    return ColoredBox(
      color: Colors.black,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: !ready
            ? null
            : (d) {
                final w = MediaQuery.sizeOf(context).width;
                final x = d.globalPosition.dx;
                if (x < w / 3) {
                  _skip(player, -10);
                } else if (x > w * 2 / 3) {
                  _skip(player, 10);
                } else {
                  player.playOrPause();
                }
              },
        onDoubleTap: ready ? () {} : null,
        child: Stack(
          children: [
            if (yt.controller != null && ready)
              Positioned.fill(
                child: Video(
                  controller: yt.controller!,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                ),
              ),
            if (yt.loading) _loadingView(yt),
            if (yt.error != null) _errorView(yt),
            _fade(
              visible: _controls || !ready,
              child: Align(
                alignment: Alignment.topCenter,
                child: _topBar(yt, ready),
              ),
            ),
            if (ready) ...[
              _fade(
                visible: _controls,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: VideoBottomControls(
                    playing: _playing,
                    position: _position,
                    duration: _duration,
                    posValue: pos,
                    totalValue: total,
                    rate: _rate,
                    fmt: _fmt,
                    onPlayPause: () {
                      player.playOrPause();
                      _scheduleHide();
                    },
                    onSeekStart: () {
                      _hideTimer?.cancel();
                      setState(() => _seeking = true);
                    },
                    onSeekChanged: (v) => setState(
                        () => _position = Duration(milliseconds: v.toInt())),
                    onSeekEnd: (v) async {
                      await player.seek(Duration(milliseconds: v.toInt()));
                      if (mounted) setState(() => _seeking = false);
                      _scheduleHide();
                    },
                    onRate: (r) {
                      player.setRate(r);
                      setState(() => _rate = r);
                    },
                  ),
                ),
              ),
              Positioned(
                right: 20,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _fade(
                    visible: _controls,
                    child: VideoVolumeColumn(
                      volume: yt.settings.volume,
                      muted: yt.settings.muted,
                      onChanged: (v) {
                        _scheduleHide();
                        unawaited(yt.setVolume(v));
                      },
                      onToggleMute: yt.toggleMute,
                    ),
                  ),
                ),
              ),
            ],
            if (_hud != null)
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.66),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(_hud!,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fade({required bool visible, required Widget child}) =>
      AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(ignoring: !visible, child: child),
      );

  Widget _topBar(YouTubeService yt, bool ready) {
    final stream = yt.stream;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: yt.close,
            icon: const Icon(Icons.close, size: 30),
            label: const Text('Close', style: TextStyle(fontSize: 22)),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3261E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stream?.title ?? 'YouTube',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600),
                ),
                if ((stream?.channel ?? '').isNotEmpty)
                  Text(stream!.channel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 17)),
              ],
            ),
          ),
          const SizedBox(width: 20),
          if (ready)
            FilledButton.tonalIcon(
              onPressed: yt.showPip,
              icon: const Icon(Icons.picture_in_picture_alt, size: 30),
              label: const Text('Picture in picture',
                  style: TextStyle(fontSize: 20)),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _loadingView(YouTubeService yt) {
    final link = yt.link;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (link != null)
          Opacity(
            opacity: 0.35,
            child: Image.network(link.thumbnailUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
        const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(strokeWidth: 5)),
              SizedBox(height: 24),
              Text('Fetching the video from YouTube…',
                  style: TextStyle(color: Colors.white70, fontSize: 22)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _errorView(YouTubeService yt) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 64),
            const SizedBox(height: 18),
            Text(
              yt.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 22),
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 20,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => _openInBrowser(yt),
                  icon: const Icon(Icons.open_in_browser, size: 28),
                  label: const Text('Open in the browser',
                      style: TextStyle(fontSize: 20)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 20),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => yt.play(yt.link!),
                  icon: const Icon(Icons.refresh, size: 28),
                  label:
                      const Text('Try again', style: TextStyle(fontSize: 20)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- Picture in picture ---------------------------------------------------

  /// Where the window goes the first time: bottom right, a third of the
  /// screen wide.
  Rect _defaultPip(Size screen) {
    final w = math.min(640.0, screen.width / 3);
    final h = w / _aspect;
    return Rect.fromLTWH(screen.width - w - _margin,
        screen.height - h - _margin, w, h);
  }

  /// [r] kept on screen and within a sensible size, at 16:9.
  Rect _fit(Rect r, Size screen) {
    final maxW = math.min(screen.width - _margin * 2,
        (screen.height - _margin * 2) * _aspect);
    final w = r.width.clamp(math.min(_minPipWidth, maxW), maxW).toDouble();
    final h = w / _aspect;
    final left = r.left.clamp(0.0, math.max(0.0, screen.width - w)).toDouble();
    final top = r.top.clamp(0.0, math.max(0.0, screen.height - h)).toDouble();
    return Rect.fromLTWH(left, top, w, h);
  }

  void _setPip(YouTubeService yt, Rect r, Size screen) =>
      setState(() => yt.pipRect = _fit(r, screen));

  Widget _pip(YouTubeService yt, Size screen) {
    final rect = _fit(yt.pipRect ?? _defaultPip(screen), screen);
    final player = yt.player;

    // The handle sits on the corner facing the middle of the screen, which is
    // the direction there is room to grow in; the opposite corner stays put.
    final growLeft = rect.center.dx > screen.width / 2;
    final growUp = rect.center.dy > screen.height / 2;

    return Positioned.fromRect(
      rect: rect,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTap: yt.showFull,
        // One finger moves it; two pinch it bigger or smaller about the
        // point between them.
        onScaleStart: (_) => _pinchStartWidth = rect.width,
        onScaleUpdate: (d) {
          final current = yt.pipRect ?? rect;
          if (d.pointerCount < 2) {
            _setPip(yt, current.shift(d.focalPointDelta), screen);
            return;
          }
          final w = _pinchStartWidth * d.scale;
          final h = w / _aspect;
          final c = current.center + d.focalPointDelta;
          _setPip(yt, Rect.fromCenter(center: c, width: w, height: h), screen);
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 24, spreadRadius: 2),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (yt.controller != null)
                  Video(
                    controller: yt.controller!,
                    controls: NoVideoControls,
                    fit: BoxFit.contain,
                  ),
                _fade(
                  visible: _controls,
                  child: ColoredBox(
                    color: Colors.black38,
                    child: Center(
                      child: FittedBox(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _pipButton(Icons.close, yt.close),
                            _pipButton(
                              _playing
                                  ? Icons.pause_circle
                                  : Icons.play_circle,
                              () {
                                player?.playOrPause();
                                _scheduleHide();
                              },
                              big: true,
                            ),
                            _pipButton(Icons.fullscreen, yt.showFull),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: growLeft ? 0 : null,
                  right: growLeft ? null : 0,
                  top: growUp ? 0 : null,
                  bottom: growUp ? null : 0,
                  child: _ResizeHandle(
                    growLeft: growLeft,
                    growUp: growUp,
                    onDrag: (delta) {
                      final current = yt.pipRect ?? rect;
                      // Wider by however far the corner was pulled outwards.
                      final dw = growLeft ? -delta.dx : delta.dx;
                      final w = current.width + dw;
                      final h = w / _aspect;
                      final left = growLeft ? current.right - w : current.left;
                      final top = growUp ? current.bottom - h : current.top;
                      _setPip(yt, Rect.fromLTWH(left, top, w, h), screen);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pipButton(IconData icon, VoidCallback onTap, {bool big = false}) =>
      IconButton(
        onPressed: onTap,
        iconSize: big ? 72 : 52,
        color: Colors.white,
        icon: Icon(icon),
      );
}

/// A corner grip for resizing the picture-in-picture window with one finger,
/// for anyone who does not think to pinch it.
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    required this.growLeft,
    required this.growUp,
    required this.onDrag,
  });

  final bool growLeft;
  final bool growUp;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Claimed before the window's own move gesture can see it.
      onPanStart: (_) {},
      onPanUpdate: (d) => onDrag(d.delta),
      child: SizedBox(
        width: 64,
        height: 64,
        child: Align(
          alignment: Alignment(growLeft ? -0.6 : 0.6, growUp ? -0.6 : 0.6),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white38),
            ),
            child: Transform.rotate(
              // open_in_full points up-right; turned to point out of whichever
              // corner the handle is on.
              angle: growLeft == growUp ? -math.pi / 2 : 0,
              child: const Icon(Icons.open_in_full,
                  color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/now_playing_service.dart';
import '../../services/playback_source.dart';
import '../../services/spotify_service.dart';
import '../../widgets/now_playing_overlay.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'scrolling_text.dart';

/// What's playing, with transport controls.
///
/// Watches both sources the app knows about and shows whichever has
/// something, exactly as the corner overlay does: Spotify when it is active,
/// the phone over Bluetooth otherwise.
///
/// A tap anywhere but its buttons opens the full player — the home screen's,
/// growing out of the tile and shrinking back into it.
class DashboardSpotifyWidget extends StatefulWidget {
  const DashboardSpotifyWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<DashboardSpotifyWidget> createState() => _DashboardSpotifyWidgetState();
}

class _DashboardSpotifyWidgetState extends State<DashboardSpotifyWidget> {
  final _tile = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final content = _content(context);
    // Only on the dashboard itself: the editor's preview of this tile is
    // drawn off-screen, with no player to open.
    final player = NowPlayingOpener.maybeOf(context);
    if (player == null) return content;
    return GestureDetector(
      key: _tile,
      behavior: HitTestBehavior.opaque,
      onTap: () => player.expand(from: _tile),
      child: content,
    );
  }

  Widget _content(BuildContext context) {
    final w = widget.w;
    final t = w.theme;
    final spotify = context.watch<SpotifyService>();
    final avrcp = context.watch<NowPlayingService>();
    final PlaybackSource source = spotify.available ? spotify : avrcp;

    if (!source.available || !source.now.hasTrack) {
      return Center(
        child: Text(
          'Nothing playing',
          style: TextStyle(color: t.textSecondary, fontSize: 16),
        ),
      );
    }

    final art = source.artUrl;
    final showArt = w.option('showArtwork', true);
    final showControls = w.option('showControls', true);
    final showLike = w.option('showLike', true) && source.canLike;
    final backdrop = w.option('artworkBackdrop', true);

    return LayoutBuilder(
      builder: (context, c) {
        // The artwork goes wherever there is room for it: beside the text on
        // a wide tile, above it on a square or tall one. Judged from the
        // tile's proportions rather than its cell count, so it still holds on
        // a panel of a different shape.
        final ratio = c.maxWidth / c.maxHeight;

        // Sized from the tile so a big panel gets big controls, with a floor
        // that keeps them thumb-sized on the smallest tile this widget allows.
        final controlSize = (c.maxHeight * 0.30).clamp(80.0, 160.0);

        // Beside the text only if the text and its controls still fit next
        // to it: on a squarish tile a big cover beside them crowded the
        // controls off the edge.
        final needed = showControls
            ? controlSize * ((showLike ? 3 : 2) + 1.3)
            : 220.0;
        final room = c.maxWidth - 16 - needed;
        final wantSide = c.maxHeight * (ratio > 2.0 ? 0.78 : 0.9);
        final side = math.min(wantSide, room);
        final layout = !showArt || art == null
            ? _Layout.textOnly
            : ratio > 1.15 && side >= c.maxHeight * 0.5
            ? _Layout.beside
            : _Layout.above;

        final content = switch (layout) {
          _Layout.textOnly => _Details(
            w: w,
            source: source,
            showControls: showControls,
            showLike: showLike,
            controlSize: controlSize,
            centred: true,
          ),
          _Layout.beside => Row(
            children: [
              _Art(url: art!, side: side, radius: t.cornerRadius * 0.5),
              const SizedBox(width: 16),
              Expanded(
                child: _Details(
                  w: w,
                  source: source,
                  showControls: showControls,
                  showLike: showLike,
                  controlSize: controlSize,
                ),
              ),
            ],
          ),
          _Layout.above => Column(
            children: [
              Expanded(
                child: Center(
                  child: _Art(
                    url: art!,
                    side: c.maxWidth * 0.66,
                    radius: t.cornerRadius * 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _Details(
                w: w,
                source: source,
                showControls: showControls,
                showLike: showLike,
                controlSize: controlSize,
                centred: true,
              ),
            ],
          ),
        };

        if (!backdrop || art == null) return content;

        // The same treatment as the kiosk's own now-playing panel: the cover
        // blurred behind, veiled towards the bottom so the text stays legible
        // over whatever the artwork happens to be.
        return Stack(
          fit: StackFit.expand,
          children: [
            _Backdrop(url: art, theme: t),
            content,
          ],
        );
      },
    );
  }
}

enum _Layout { beside, above, textOnly }

class _Art extends StatelessWidget {
  const _Art({required this.url, required this.side, required this.radius});

  final String url;
  final double side;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: url,
        width: side,
        height: side,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => SizedBox(width: side, height: side),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.url, required this.theme});

  final String url;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    // Darkened on dark themes, lightened on light ones, so the same effect
    // keeps the text readable either way rather than only against black.
    final darkText = theme.textPrimary.computeLuminance() < 0.5;
    final veil = darkText ? Colors.white : Colors.black;
    // Faded out towards every edge, so the colour melts into the tile's own
    // glass rather than sitting in it as a sharp-cornered rectangle — and
    // the blur's dark rim at the edges goes with it.
    return _EdgeFade(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Clipped: a blur spreads past its own box, and that spill is what
          // drew a hard-edged rectangle with a glow round it.
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 16,
                sigmaY: 16,
                tileMode: TileMode.clamp,
              ),
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  veil.withValues(alpha: 0.35),
                  veil.withValues(alpha: 0.92),
                ],
                stops: const [0.0, 0.9],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades its child to nothing at every edge.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.child});

  final Widget child;

  static Shader _fade(Rect r, Alignment from, Alignment to) => LinearGradient(
    begin: from,
    end: to,
    colors: const [
      Colors.transparent,
      Colors.white,
      Colors.white,
      Colors.transparent,
    ],
    stops: const [0, 0.18, 0.82, 1],
  ).createShader(r);

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) =>
          _fade(r, Alignment.centerLeft, Alignment.centerRight),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) =>
            _fade(r, Alignment.topCenter, Alignment.bottomCenter),
        child: child,
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.w,
    required this.source,
    required this.showControls,
    required this.controlSize,
    this.showLike = false,
    this.centred = false,
  });

  final DashboardWidgetContext w;
  final PlaybackSource source;
  final bool showControls;

  /// The heart, as on the home screen's mini player and the full player.
  final bool showLike;

  /// Tap-target size for the skip buttons, from the tile.
  final double controlSize;
  final bool centred;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final now = source.now;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: centred ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: centred
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        // Track names are frequently longer than the tile — anything with a
        // "- From ... Soundtrack Version" on the end — and truncating them
        // hides the part that says which version it is. Scrolls only when it
        // has to; a title that fits sits still.
        ScrollingText(
          now.title,
          align: centred ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          now.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: centred ? TextAlign.center : TextAlign.start,
          style: TextStyle(color: t.textSecondary, fontSize: 15),
        ),
        if (now.duration > Duration.zero) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (now.position.inMilliseconds / now.duration.inMilliseconds)
                  .clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: t.textSecondary.withValues(alpha: 0.25),
              valueColor: AlwaysStoppedAnimation(t.accent),
            ),
          ),
        ],
        if (showControls) ...[
          const SizedBox(height: 8),
          // Shrinks rather than runs off the edge on a tile too small for
          // the buttons at full size.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: centred ? Alignment.center : Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: centred
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (showLike)
                  _Like(
                    liked: source.isLiked,
                    colour: t.textPrimary,
                    target: controlSize,
                    onPressed: source.toggleLike,
                  ),
                _Button(
                  icon: Icons.skip_previous,
                  colour: t.textPrimary,
                  target: controlSize,
                  onPressed: source.previous,
                ),
                _Button(
                  icon: now.status == 'playing'
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  colour: t.accent,
                  target: controlSize * 1.3,
                  onPressed: source.playPause,
                ),
                _Button(
                  icon: Icons.skip_next,
                  colour: t.textPrimary,
                  target: controlSize,
                  onPressed: source.next,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A control sized for a finger rather than a cursor.
///
/// Grows with the tile and never drops below 80 (104 for play/pause), which
/// is well past the 48 Material asks for. This is a panel on a wall, usually
/// reached for in passing, and a skip button that needs aiming at is one that
/// gets pressed twice.
class _Button extends StatelessWidget {
  const _Button({
    required this.icon,
    required this.colour,
    required this.onPressed,
    required this.target,
  });

  final IconData icon;
  final Color colour;
  final VoidCallback onPressed;
  final double target;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: target,
          height: target,
          child: Icon(icon, color: colour, size: target * 0.62),
        ),
      ),
    );
  }
}

/// Pink and filled when the track is in your Liked Songs, with a pop when
/// that changes so a tap visibly took — the home screen's heart, in the
/// tile's colours.
class _Like extends StatelessWidget {
  const _Like({
    required this.liked,
    required this.colour,
    required this.onPressed,
    required this.target,
  });

  final bool liked;
  final Color colour;
  final VoidCallback onPressed;
  final double target;

  static const _pink = Color(0xFFFF6B81);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: liked,
      label: liked ? 'Remove from Liked Songs' : 'Add to Liked Songs',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: target,
            height: target,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutBack,
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                key: ValueKey(liked),
                size: target * 0.48,
                color: liked ? _pink : colour,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final spotifyWidgetType = DashboardWidgetType(
  type: 'spotify',
  category: WidgetCategory.photosAndMedia,
  name: 'Now playing',
  description:
      'The current track with transport controls. Shows Spotify when it is '
      'active, otherwise the phone over Bluetooth. The artwork moves to suit '
      'the tile’s shape.',
  glyph: '🎵',
  defaultWidth: 5,
  defaultHeight: 2,
  minWidth: 1,
  minHeight: 1,
  options: const [
    WidgetOption(
      key: 'showArtwork',
      label: 'Show artwork',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'artworkBackdrop',
      label: 'Blur the artwork behind the tile',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'The same look as the kiosk’s own now-playing panel.',
    ),
    WidgetOption(
      key: 'showControls',
      label: 'Show transport controls',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'Turn off for a display-only panel nobody can skip tracks on.',
    ),
    WidgetOption(
      key: 'showLike',
      label: 'Show the like button',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'With the controls, for Spotify. Bluetooth audio has no likes.',
    ),
  ],
  preview: const [
    PreviewLine('Fake Plastic Trees', scale: 0.16, px: 20),
    PreviewLine('Radiohead', scale: 0.11, muted: true, px: 15),
    PreviewLine('▬▬▬▬▬▭▭▭▭', scale: 0.08, accent: true),
    PreviewLine('⏮   ⏯   ⏭', scale: 0.15, accent: true),
  ],
  live: (config, data) {
    final source = data.playback;
    if (source == null || !source.available || !source.now.hasTrack) {
      return const [
        PreviewLine('Nothing playing', scale: 0.13, muted: true, centre: true),
      ];
    }
    final now = source.now;
    return [
      PreviewLine(now.title, scale: 0.16, px: 20),
      PreviewLine(now.artist, scale: 0.11, muted: true, px: 15),
      if (config.options['showControls'] != false)
        const PreviewLine('⏮   ⏯   ⏭', scale: 0.16, accent: true),
    ];
  },
  build: (context, w) => DashboardSpotifyWidget(w: w),
);

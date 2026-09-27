import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../services/mpv_tuning.dart';
import '../../services/video_link.dart';
import '../../services/video_player_service.dart';
import '../../services/youtube_site.dart';
import '../../widgets/pause_when_hidden.dart';
import '../tile_renderer.dart';
import '../widget_registry.dart';
import 'feed_tile.dart';
import 'tile_bits.dart';
import 'video_grid.dart';

/// The latest from the account's subscriptions, to pick one and watch it on
/// the panel — or, if chosen, one video playing in the tile. Touching either
/// sends it to the panel, full screen.
class YouTubeWidget extends StatelessWidget {
  const YouTubeWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(w.theme.cornerRadius * 0.6),
      child: w.option('source', 'subscriptions') == 'video'
          ? _VideoTile(w: w)
          : SiteFeedTile<YouTubeSite>(w: w),
    );
  }
}

/// Tiles are small: 720 lines is plenty, and half the decoding of 1080.
const int _tileHeight = 720;

class _VideoTile extends StatefulWidget {
  const _VideoTile({required this.w});
  final DashboardWidgetContext w;

  @override
  State<_VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<_VideoTile> with PauseWhenHidden {
  Player? _player;
  VideoController? _controller;
  String? _error;
  String? _title;
  VideoPlayerService? _video;
  bool _pausedByUs = false;

  VideoLink? get _link => VideoLink.parse(widget.w.option('url', ''));
  bool get _muted => widget.w.option('muted', true);

  /// The editor's preview draws each tile off screen for a moment. A still is
  /// what that wants — not a stream opened and dropped a second later.
  bool get _inPreview =>
      context.findAncestorWidgetOfExactType<TileRenderHost>() != null;

  @override
  void initState() {
    super.initState();
    _video = context.read<VideoPlayerService>()..addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_inPreview) unawaited(_start());
    });
  }

  @override
  void didUpdateWidget(_VideoTile old) {
    super.didUpdateWidget(old);
    final was = old.w.config.options;
    final now = widget.w.config.options;
    if (was['url'] != now['url']) {
      unawaited(_stop().then((_) => _start()));
    } else if (was['muted'] != now['muted'] && _player != null) {
      unawaited(VideoPlayerService.applyAudio(_player!, _video!.settings,
          muted: _muted ? true : null));
    }
  }

  @override
  void dispose() {
    _video?.removeListener(_sync);
    _player?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final link = _link;
    final video = _video;
    if (link == null || video == null) return;
    try {
      final stream = await video.resolve(link,
          maxHeight: math.min(_tileHeight, video.settings.maxHeight));
      if (!mounted || _link != link) return;
      final player = Player();
      await MpvTuning.apply(player);
      if (!mounted || _link != link || _player != null) {
        await player.dispose();
        return;
      }
      final controller =
          VideoController(player, configuration: VideoPlayerService.videoConfig);
      setState(() {
        _player = player;
        _controller = controller;
        _title = stream.title;
        _error = null;
      });
      await player.setPlaylistMode(PlaylistMode.single);
      await VideoPlayerService.applyAudio(player, video.settings,
          muted: _muted ? true : null);
      await stream.prepare(player);
      await player.open(
        Media(
          stream.uri,
          httpHeaders: stream.headers,
          start: !stream.isLive && link.start > Duration.zero
              ? link.start
              : null,
        ),
        play: _shouldPlay,
      );
      _pausedByUs = !_shouldPlay;
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _stop() async {
    final player = _player;
    setState(() {
      _player = null;
      _controller = null;
      _title = null;
      _error = null;
    });
    await player?.dispose();
  }

  /// Plays only when it can be seen and nothing is on the panel. Two videos
  /// decoding at once is more than the Pi wants to do and two soundtracks is
  /// more than anyone wants to hear; and a tile on a dashboard hidden behind
  /// Settings is decoding frames for nobody.
  bool get _shouldPlay => shown && _video!.view == VideoView.closed;

  @override
  void onShownChanged(bool shown) => _sync();

  void _sync() {
    final player = _player;
    if (player == null) return;
    if (_shouldPlay) {
      if (_pausedByUs) {
        _pausedByUs = false;
        unawaited(player.play());
      }
    } else if (player.state.playing) {
      _pausedByUs = true;
      unawaited(player.pause());
    }
  }

  void _openFull() {
    final link = _link;
    if (link == null) return;
    unawaited(_video!.play(link, at: _player?.state.position));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final link = _link;
    if (link == null) {
      return TileMessage(
        'Paste a YouTube, Floatplane or Nebula link into this widget’s '
        'settings in the editor.',
        theme: t,
      );
    }
    final controller = _controller;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openFull,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          // Underneath until the first frame arrives, and whenever the
          // stream cannot be had.
          if (link.thumbnailUrl != null)
            Image.network(link.thumbnailUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink()),
          if (controller != null)
            Video(
              controller: controller,
              controls: NoVideoControls,
              fit: BoxFit.cover,
              fill: Colors.transparent,
            ),
          if (_error != null)
            ColoredBox(
              color: Colors.black54,
              child: TileMessage(_error!, theme: t),
            ),
          if (widget.w.option('showTitle', true) && _title != null)
            Align(
              alignment: Alignment.bottomLeft,
              child: VideoCaption(title: _title!),
            ),
          if (_muted && controller != null)
            const Positioned(
              right: 10,
              top: 10,
              child: Icon(Icons.volume_off, color: Colors.white70, size: 22),
            ),
          if (controller == null && _error == null)
            const Center(
              child: Icon(Icons.play_circle_fill,
                  color: Colors.white70, size: 56),
            ),
        ],
      ),
    );
  }
}

final youtubeWidgetType = DashboardWidgetType(
  type: 'youtube',
  category: WidgetCategory.photosAndMedia,
  name: 'YouTube',
  description:
      'The latest videos from your YouTube subscriptions: touch one to watch '
      'it on the panel. Can instead play one video in the tile, muted or '
      'with sound.',
  glyph: '▶️',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 2,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'source',
      label: 'Show',
      kind: OptionKind.choice,
      defaultValue: 'subscriptions',
      choices: {
        'subscriptions': 'Latest from my subscriptions',
        'video': 'One video, playing in the tile',
      },
      help: 'Subscriptions need the panel signed in to YouTube — in Settings '
          '→ Music → Videos, by tapping the tile, or from a computer at the '
          'editor’s address followed by /youtube.',
    ),
    WidgetOption(
      key: 'url',
      label: 'Video link',
      help: 'For “One video”: paste the link from YouTube’s Share button. A '
          't= in it starts the video from there.',
    ),
    WidgetOption(
      key: 'muted',
      label: 'Play muted (one video)',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'Full screen has sound either way, at the YouTube volume.',
    ),
    WidgetOption(
      key: 'showTitle',
      label: 'Show the title',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'count',
      label: 'Subscription videos',
      kind: OptionKind.number,
      defaultValue: 6,
      help: 'How many of the latest to show.',
    ),
  ],
  preview: const [
    PreviewLine('▶  YouTube', scale: 0.2, centre: true),
  ],
  build: (context, w) => YouTubeWidget(w: w),
);

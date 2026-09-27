import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../screens/youtube_sign_in.dart';
import '../../services/dashboard_service.dart';
import '../../services/mpv_tuning.dart';
import '../../services/youtube_link.dart';
import '../../services/youtube_service.dart';
import '../../widgets/pause_when_hidden.dart';
import '../tile_renderer.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

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
          : _Subscriptions(w: w),
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
  YouTubeService? _yt;
  bool _pausedByUs = false;

  YouTubeLink? get _link => YouTubeLink.parse(widget.w.option('url', ''));
  bool get _muted => widget.w.option('muted', true);

  /// The editor's preview draws each tile off screen for a moment. A still is
  /// what that wants — not a stream opened and dropped a second later.
  bool get _inPreview =>
      context.findAncestorWidgetOfExactType<TileRenderHost>() != null;

  @override
  void initState() {
    super.initState();
    _yt = context.read<YouTubeService>()..addListener(_sync);
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
      unawaited(YouTubeService.applyAudio(_player!, _yt!.settings,
          muted: _muted ? true : null));
    }
  }

  @override
  void dispose() {
    _yt?.removeListener(_sync);
    _player?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final link = _link;
    final yt = _yt;
    if (link == null || yt == null) return;
    try {
      final stream = await yt.resolve(link,
          maxHeight: math.min(_tileHeight, yt.settings.maxHeight));
      if (!mounted || _link != link) return;
      final player = Player();
      await MpvTuning.apply(player);
      final controller =
          VideoController(player, configuration: YouTubeService.videoConfig);
      setState(() {
        _player = player;
        _controller = controller;
        _title = stream.title;
        _error = null;
      });
      await player.setPlaylistMode(PlaylistMode.single);
      await YouTubeService.applyAudio(player, yt.settings,
          muted: _muted ? true : null);
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
  bool get _shouldPlay => shown && _yt!.view == YouTubeView.closed;

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
    unawaited(_yt!.play(link, at: _player?.state.position));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final link = _link;
    if (link == null) {
      return TileMessage(
        'Paste a YouTube link into this widget’s settings in the editor.',
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
          Image.network(link.thumbnailUrl,
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
              child: _Caption(title: _title!),
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

class _Caption extends StatelessWidget {
  const _Caption({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 22, 12, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.2)),
          if ((subtitle ?? '').isNotEmpty)
            Text(subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

class _Subscriptions extends StatelessWidget {
  const _Subscriptions({required this.w});
  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final t = w.theme;
    final yt = context.watch<YouTubeService>();
    if (!yt.settings.signedIn) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => signInToYouTube(context),
        child: TileMessage(
          'Tap to sign in to YouTube and show your subscriptions here — or '
          'sign in from a computer at '
          '${context.read<DashboardService>().editorAddress}/youtube',
          theme: t,
        ),
      );
    }
    final items = yt.subscriptions();
    if (items == null) {
      return TileMessage(
        yt.subscriptionsError ?? 'Fetching your subscriptions…',
        theme: t,
      );
    }
    if (items.isEmpty) {
      return TileMessage('Nothing new from your subscriptions.', theme: t);
    }
    final count = math.min(items.length, w.option('count', 6).clamp(1, 30).toInt());
    return LayoutBuilder(builder: (context, c) {
      final grid = bestGrid(count, c.biggest, cellAspect: 16 / 9);
      final gap = math.min(c.maxWidth, c.maxHeight) * 0.03;
      final cellW = (c.maxWidth - gap * (grid.columns - 1)) / grid.columns;
      final cellH = (c.maxHeight - gap * (grid.rows - 1)) / grid.rows;
      return Stack(
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: (i % grid.columns) * (cellW + gap),
              top: (i ~/ grid.columns) * (cellH + gap),
              width: cellW,
              height: cellH,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => yt.play(items[i].link),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(t.cornerRadius * 0.4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: t.wash(0.08)),
                      Image.network(items[i].link.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: _Caption(
                          title: items[i].title,
                          subtitle: items[i].channel,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    });
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
          '→ Music → YouTube, or by tapping the tile.',
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

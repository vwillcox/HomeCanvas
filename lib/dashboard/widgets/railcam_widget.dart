import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/config_service.dart';
import '../../services/mpv_tuning.dart';
import '../../services/railcam_service.dart';
import '../../services/video_link.dart';
import '../../services/video_player_service.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/shown_timers.dart';
import '../tile_renderer.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';
import '../../look.dart';

/// How a camera is shown in the tile.
enum RailcamLive {
  /// The site's own picture of the view.
  still,

  /// Its stream, but only the frames that stand alone — one every couple of
  /// seconds — which costs a twentieth of decoding them all.
  frames,

  /// Its stream, every frame, drawn small.
  video,
}

/// What each of [count] cameras gets when the tile is set to [option].
///
/// The Pi decodes in software, and a tile is on screen all day. Measured on
/// the panel, a 1080p camera as video takes a fifth of a core to decode and
/// a tenth of the thread the whole UI runs on to draw; as frames, a
/// twentieth of a core and next to none of that thread. So a tile with a
/// page to itself ([alone]) plays six as video, which leaves the UI's thread
/// a third free; one that shares its page plays two, and leaves the rest to
/// its neighbours. Then frames, up to twelve streams or eight in all, and
/// any cameras past that keep their picture.
@visibleForTesting
List<RailcamLive> railcamLive(String option, int count, {required bool alone}) {
  final videos = option == 'video' ? (alone ? 6 : 2) : 0;
  final streams = option == 'video' || option == 'frames'
      ? (alone ? 12 : 8)
      : 0;
  return [
    for (var i = 0; i < count; i++)
      i < videos
          ? RailcamLive.video
          : i < streams
          ? RailcamLive.frames
          : RailcamLive.still,
  ];
}

/// Railcam's lineside cameras: the ones picked in the settings, as a grid
/// of the site's pictures of them — or, if chosen, of the cameras live.
/// Touching one plays it on the panel, full screen, as the account in the
/// settings.
class RailcamWidget extends StatefulWidget {
  const RailcamWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  @override
  State<RailcamWidget> createState() => _RailcamWidgetState();
}

class _RailcamWidgetState extends State<RailcamWidget>
    with PauseWhenHidden, ShownTimers {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    // The service fetches its list once a day; this only gives it the chance.
    everyWhileShown(const Duration(hours: 1), _sync);
  }

  @override
  void didUpdateWidget(covariant RailcamWidget old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final service = context.read<RailcamService>()
      ..useAccount(
        widget.w.option('username', ''),
        widget.w.option('password', ''),
      );
    unawaited(service.ensure());
  }

  /// Whether this is the only widget on its page.
  bool _alone(BuildContext context) {
    try {
      return context
              .watch<ConfigService>()
              .config
              .dashboard
              .widgetsOn(widget.w.config.page)
              .length ==
          1;
    } on ProviderNotFoundException {
      return false;
    }
  }

  /// The cameras picked in the settings: each one's id, and what to call it.
  List<({String id, String name})> _cameras(RailcamService service) => [
    for (final r in widget.w.rows('cameras'))
      if ('${r['camera'] ?? ''}'.trim().isNotEmpty)
        (
          id: '${r['camera']}'.trim(),
          name: '${r['name'] ?? ''}'.trim().isNotEmpty
              ? '${r['name']}'.trim()
              : service.cam('${r['camera']}'.trim())?.name ??
                    '${r['camera']}'.trim(),
        ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final service = context.watch<RailcamService>();
    final cams = _cameras(service);
    if (cams.isEmpty) {
      return TileMessage(
        tr(
          'widget.railcam.pick',
          'Pick cameras in this widget’s settings in the editor.',
        ),
        theme: t,
      );
    }
    final captions = widget.w.option('captions', true);
    final live = railcamLive(
      widget.w.option('live', 'off'),
      cams.length,
      alone: _alone(context),
    );
    final error = service.error;
    return Column(
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              error,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary, fontSize: 12),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final grid = bestGrid(
                cams.length,
                box.biggest,
                cellAspect: 16 / 9,
              );
              const gap = 6.0;
              return Column(
                children: [
                  for (var row = 0; row < grid.rows; row++) ...[
                    if (row > 0) const SizedBox(height: gap),
                    Expanded(
                      child: Row(
                        children: [
                          for (var col = 0; col < grid.columns; col++) ...[
                            if (col > 0) const SizedBox(width: gap),
                            Expanded(
                              child: row * grid.columns + col < cams.length
                                  ? _CamView(
                                      cam: cams[row * grid.columns + col],
                                      caption: captions,
                                      live: live[row * grid.columns + col],
                                    )
                                  : const SizedBox(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CamView extends StatelessWidget {
  const _CamView({
    required this.cam,
    required this.caption,
    required this.live,
  });

  final ({String id, String name}) cam;
  final bool caption;
  final RailcamLive live;

  @override
  Widget build(BuildContext context) {
    final link = RailcamLink(cam.id);
    return GestureDetector(
      onTap: () => unawaited(context.read<VideoPlayerService>().play(link)),
      child: ClipRRect(
        // Square on a console, as its blocks are.
        borderRadius: BorderRadius.circular(context.look.isLcars ? 0 : 8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: Image.network(
                link.thumbnailUrl,
                fit: BoxFit.cover,
                // The site's pictures are small; smoothed, not blocky.
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, _, _) => const Center(
                  child: Icon(
                    Icons.videocam_outlined,
                    color: Colors.white38,
                    size: 28,
                  ),
                ),
              ),
            ),
            // Over the picture, which shows until the first frame arrives and
            // whenever the stream cannot be had.
            if (live != RailcamLive.still)
              _LiveCam(
                key: ValueKey(cam.id),
                id: cam.id,
                video: live == RailcamLive.video,
              ),
            if (caption)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 5),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xB0000000)],
                    ),
                  ),
                  child: Text(
                    cam.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A camera's stream playing in its cell, silent and small.
///
/// Only while it can be seen: a stream left running behind Settings,
/// another page or a dark screen is the Pi's work and railcam's bandwidth
/// spent on nobody. It is closed, not paused — a live stream paused is no
/// longer live when it carries on.
///
/// Behind a video sent to the panel — one of these cameras, touched — it
/// rests instead: kept open, decoding only the frames that stand alone.
/// media_kit works on one player at a time, and closing six of these held
/// the full-screen one up for five seconds; opening them again afterwards
/// took eight. Rested, both are as quick as the stream allows.
class _LiveCam extends StatefulWidget {
  const _LiveCam({super.key, required this.id, required this.video});

  final String id;

  /// Every frame, rather than the one in fifty that stands alone.
  final bool video;

  @override
  State<_LiveCam> createState() => _LiveCamState();
}

class _LiveCamState extends State<_LiveCam> with PauseWhenHidden, ShownTimers {
  /// Railcam's cameras come in one size, mostly 1080p; other sites' and
  /// YouTube's are asked for at about this.
  static const _height = 360;

  /// As wide as it is drawn, whatever the stream's own size: turning a 1080p
  /// frame into pixels for Flutter costs three times what decoding it does,
  /// and at a ninth of the size next to nothing.
  static const _width = 640;

  static const _config = VideoControllerConfiguration(
    enableHardwareAcceleration: false,
    hwdec: 'no',
    width: _width,
    height: _height,
  );

  /// Measured on the panel with a 1080p25 camera, as a share of one core:
  /// 41% drawn small, 31% with these — the loop filter is polish nobody
  /// sees at this size — and 4% decoding the stand-alone frames only. One
  /// decoding thread a camera keeps up with room to spare, and spreads six
  /// cameras over the Pi's four cores rather than setting two dozen threads
  /// on them. No sound is decoded at all.
  static const _light = {
    'aid': 'no',
    'ao': 'null',
    'vd-lavc-skiploopfilter': 'all',
    'vd-lavc-fast': 'yes',
    'vd-lavc-threads': '1',
    // Shrunk by mpv's own thread before it is drawn. Left to the drawing,
    // which media_kit does on the thread the whole UI runs on, four cameras
    // kept that thread 90% busy turning 1080p frames into small ones.
    'vf': 'scale=$_width:-2:flags=fast_bilinear',
    'demuxer-max-bytes': '16MiB',
    // Enough to go back to the last frame that stands alone, which is where
    // decoding picks up after a rest.
    'demuxer-max-back-bytes': '4MiB',
  };

  /// How long a rest lasts before the stream is closed after all: a film
  /// on the panel is not a reason to keep six cameras coming all evening.
  static const _restFor = Duration(minutes: 5);

  VideoPlayerService? _service;
  Player? _player;
  VideoController? _controller;
  Timer? _retry;
  Timer? _rest;
  Timer? _slow;
  bool _resting = false;

  /// Resting, and by now decoding only the frames that stand alone.
  bool _slowed = false;
  Duration? _lastAt;
  int _failures = 0;
  bool _starting = false;

  /// Counts the starts and stops, so one overtaken by the next gives up.
  int _run = 0;

  /// The editor's preview draws each tile off screen for a moment; the
  /// picture is what that wants.
  bool get _inPreview =>
      context.findAncestorWidgetOfExactType<TileRenderHost>() != null;

  /// A video sent to the panel has the screen, or a corner of it.
  bool get _covered => _service?.view != VideoView.closed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _inPreview) return;
      _service = context.read<VideoPlayerService>()..addListener(_sync);
      _sync();
    });
    everyWhileShown(const Duration(seconds: 45), _checkMoving);
  }

  @override
  void didUpdateWidget(covariant _LiveCam old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id || old.video != widget.video) {
      _stop();
      _failures = 0;
      _sync();
    }
  }

  @override
  void dispose() {
    _service?.removeListener(_sync);
    _run++;
    _retry?.cancel();
    _rest?.cancel();
    _slow?.cancel();
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  void onShownChanged(bool shown) {
    super.onShownChanged(shown);
    // Told in the middle of a build further up; acted on once it is done.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!mounted || _service == null) return;
    final player = _player;
    if (_covered) {
      if (player != null && !_resting) {
        _resting = true;
        _rest = Timer(_restFor, _stop);
        // Not at once: telling six players takes most of a second, and
        // that second is the one the video touched is opening in.
        _slow = Timer(const Duration(seconds: 2), () {
          if (!widget.video || !identical(_player, player)) return;
          _slowed = true;
          unawaited(_decode(player, standAloneOnly: true));
        });
      }
    } else if (_resting && player != null) {
      _resting = false;
      _rest?.cancel();
      _slow?.cancel();
      if (_slowed) unawaited(_decode(player, standAloneOnly: false));
      _slowed = false;
      // The video's closing is heard of a frame before the dashboard is
      // uncovered. Looked at again then, in case it is not — the video was
      // closed from some other screen.
      WidgetsBinding.instance
        ..addPostFrameCallback((_) => _sync())
        ..ensureVisualUpdate();
    } else if (!shown) {
      _stop();
    } else if (player == null && !_starting && _retry == null) {
      unawaited(_start());
    }
  }

  /// Which frames [player] decodes. The decoder reads this as it starts, so
  /// the picture is switched off and on again to start it afresh — from
  /// the last frame that stands alone, so there is nothing to see of it.
  Future<void> _decode(Player player, {required bool standAloneOnly}) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty(
        'vd-lavc-skipframe',
        standAloneOnly ? 'nonkey' : 'default',
      );
      await platform.setProperty('vid', 'no');
      await platform.setProperty('vid', 'auto');
    } catch (e) {
      debugPrint('Railcam: ${widget.id}: $e');
    }
  }

  Future<void> _start() async {
    final run = ++_run;
    _starting = true;
    Player? player;
    try {
      final service = _service!;
      final stream = await service.resolve(
        RailcamLink(widget.id),
        maxHeight: _height,
      );
      if (!mounted || run != _run) return;
      player = Player();
      await MpvTuning.apply(player);
      final platform = player.platform;
      if (platform is NativePlayer) {
        for (final e in {
          ..._light,
          'vd-lavc-skipframe': widget.video ? 'default' : 'nonkey',
        }.entries) {
          await platform.setProperty(e.key, e.value);
        }
      }
      final controller = VideoController(player, configuration: _config);
      await VideoPlayerService.applyAudio(
        player,
        service.settings,
        muted: true,
      );
      await stream.prepare(player);
      if (!mounted || run != _run) return;
      final mine = player;
      player = null;
      // media_kit sizes its picture to the video's, and to the size the
      // video had before `vf` shrank it — so each small frame was blown
      // back up to 1080p, on the UI's own thread, before Flutter shrank it
      // again: half a core for every camera. Told the size it is really
      // given, once media_kit has had its say.
      mine.stream.videoParams.listen((params) async {
        final w = params.dw ?? 0, h = params.dh ?? 0;
        if (w <= 0 || h <= 0) return;
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!identical(_player, mine)) return;
        await controller.setSize();
        await controller.setSize(
          width: _width,
          height: (_width * h / w / 2).round() * 2,
        );
      });
      // A live stream has no end; one that reaches it has been cut off.
      mine.stream.completed.listen((done) {
        if (done && identical(_player, mine)) _failed();
      });
      setState(() {
        _player = mine;
        _controller = controller;
        _lastAt = null;
      });
      await mine.open(Media(stream.uri, httpHeaders: stream.headers));
      // Something may have covered it while it was opening.
      _sync();
      // Touched, it goes full screen: the player for that is made ready
      // now, once these have had the few seconds they take to start.
      unawaited(Future<void>.delayed(const Duration(seconds: 4), service.warm));
    } catch (e) {
      debugPrint('Railcam: ${widget.id} would not play in the tile: $e');
      if (mounted && run == _run) {
        _starting = false;
        _failed();
      }
    } finally {
      await player?.dispose();
      if (run == _run) _starting = false;
    }
  }

  void _stop() {
    _run++;
    _starting = false;
    _retry?.cancel();
    _retry = null;
    _rest?.cancel();
    _slow?.cancel();
    _resting = false;
    _slowed = false;
    final player = _player;
    if (player == null) return;
    setState(() {
      _player = null;
      _controller = null;
    });
    unawaited(player.dispose());
  }

  /// Tried again in a while — longer each time, up to five minutes — so a
  /// camera that is off line, or an account not signed in, is not asked
  /// about every few seconds all day.
  void _failed() {
    _stop();
    final wait = Duration(seconds: math.min(300, 20 << math.min(_failures, 4)));
    _failures++;
    _retry = Timer(wait, () {
      _retry = null;
      _sync();
    });
  }

  /// A stream that has stopped arriving says nothing; its clock just stops.
  void _checkMoving() {
    final player = _player;
    if (player == null) return;
    final at = player.state.position;
    if (at == _lastAt) {
      _failed();
    } else {
      _lastAt = at;
      _failures = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return Video(
      controller: controller,
      controls: NoVideoControls,
      fit: BoxFit.cover,
      fill: Colors.transparent,
    );
  }
}

final railcamWidgetType = DashboardWidgetType(
  type: 'railcam',
  category: WidgetCategory.photosAndMedia,
  name: 'Railcam',
  description:
      'Lineside cameras from railcam.uk: pick any of its 300 and touch one '
      'to watch it live on the panel — or have them playing in the tile, '
      'small and silent. Needs your own railcam.uk account — supporters’ '
      'cameras, a supporter’s.',
  glyph: '🚂',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 2,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'username',
      label: 'Railcam username',
      defaultValue: '',
      help: 'The one you sign in to railcam.uk with — not your email address.',
    ),
    WidgetOption(
      key: 'password',
      label: 'Railcam password',
      kind: OptionKind.secret,
      defaultValue: '',
      help: 'Kept on the panel and sent only to railcam.uk, to sign in.',
    ),
    WidgetOption(
      key: 'cameras',
      label: 'Cameras',
      kind: OptionKind.list,
      addLabel: 'Add a camera',
      help:
          'Every camera is listed once the panel has signed in — save the '
          'username and password, then open the editor again. Before that, '
          'only those on railcam’s public map.',
      fields: [
        WidgetOption(
          key: 'camera',
          label: 'Camera',
          kind: OptionKind.choice,
          choicesFrom: 'railcams',
          defaultValue: '',
        ),
        WidgetOption(
          key: 'name',
          label: 'Caption',
          defaultValue: '',
          help: 'Optional — the camera’s own name otherwise.',
        ),
      ],
    ),
    WidgetOption(
      key: 'live',
      label: 'Show',
      kind: OptionKind.choice,
      defaultValue: 'off',
      choices: {
        'off': 'Pictures — touch one to watch',
        'frames': 'Live, a new picture every couple of seconds',
        'video': 'Live video, low quality',
      },
      help:
          'Live leaves each camera’s stream running while its page shows, '
          'silent and small — work for the panel, and bandwidth for you and '
          'railcam. A picture every couple of seconds is light. Video is '
          'for the first six cameras when the tile has a page to itself, '
          'and the first two when it shares one; the rest get a picture '
          'every couple of seconds.',
    ),
    WidgetOption(
      key: 'captions',
      label: 'Show names',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
  ],
  preview: const [
    PreviewLine('🚂 Crewe 1    🚂 Ribblehead Viaduct', scale: .11, px: 14),
  ],
  build: (context, w) => RailcamWidget(w: w),
);

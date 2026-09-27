import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../config/app_config.dart' show YouTubeSettings;
import 'config_service.dart';
import 'hls_edl.dart';
import 'mpv_tuning.dart';
import 'video_link.dart';
import 'video_site.dart';
import 'video_stream.dart';
import 'yt_dlp.dart';

/// How a video sent to the panel is being shown.
enum VideoView { closed, full, pip }

/// YouTube, Floatplane and Nebula videos, played by the kiosk itself.
///
/// A browser window cannot sit inside a dashboard tile or float as a
/// resizable picture-in-picture over the kiosk — labwc gives no client a way
/// to place another's window — so videos are played by the same mpv the
/// photo videos use, and drawn by Flutter wherever they are wanted. yt-dlp
/// turns each site's page into a stream, signed in as the site's account.
///
/// One video at a time is "sent to the panel": the full-screen player and the
/// picture-in-picture window are two views of that one session. Dashboard
/// tiles play their own, and only [resolve] is shared with them.
class VideoPlayerService extends ChangeNotifier {
  VideoPlayerService(this._config, this.ytDlp, List<VideoSite> sites)
      : _sites = {for (final s in sites) s.id: s} {
    for (final site in sites) {
      // Streams worked out for an old account are not reused for a new one.
      site.onAccountChanged = () => _streams.removeWhere(
          (key, _) => key.startsWith('${site.id}:'));
    }
  }

  final ConfigService _config;
  final YtDlp ytDlp;
  final Map<String, VideoSite> _sites;

  /// Picture quality and the sound level. Kept under YouTube's settings,
  /// where they were first saved, but they apply to every site.
  YouTubeSettings get settings => _config.config.youtube;

  /// Decoded and drawn by the CPU, bar HEVC — see [VideoStream.prepare].
  ///
  /// media_kit's OpenGL output would take the drawing off the CPU, and was
  /// tried: on this Pi it shows a solid blue picture even with decoding in
  /// software, and dropped a third of a 60fps video's frames besides,
  /// because it draws on the GTK thread the whole UI shares. The software
  /// output draws each frame into memory for Flutter to upload instead; see
  /// [MpvTuning] for what keeps that at 60fps.
  static const videoConfig = VideoControllerConfiguration(
    enableHardwareAcceleration: false,
    hwdec: 'no',
  );

  /// Paused or finished for this long, a video sent to the panel closes —
  /// a kiosk left on a paused video is a kiosk showing it tomorrow morning.
  static const Duration idleClose = Duration(minutes: 30);

  /// Stream addresses stay good for about six hours. Reused well within that.
  static const Duration _streamLife = Duration(minutes: 30);

  Timer? _idleTimer;

  /// Called as a video starts, so music playing already can be paused.
  void Function()? onStart;

  void start() {
    _idleTimer ??=
        Timer.periodic(const Duration(minutes: 1), (_) => _idleCheck());
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _player?.dispose();
    super.dispose();
  }

  // --- Resolving ------------------------------------------------------------

  final Map<String, (DateTime, Future<VideoStream>)> _streams = {};

  /// What mpv should open for [link], no taller than [maxHeight] (or the
  /// setting), as the site's account. Shared between the panel's player and
  /// the dashboard's tiles, so a tile tapped to go full screen does not ask
  /// the site twice.
  Future<VideoStream> resolve(VideoLink link, {int? maxHeight}) {
    final height = maxHeight ?? settings.maxHeight;
    final key = '${link.site}:${link.id}@$height';
    final now = DateTime.now();
    // Nothing older is any use, and without this the cache only grows.
    _streams.removeWhere((_, v) => now.difference(v.$1) >= _streamLife);
    final cached = _streams[key];
    if (cached != null) return cached.$2;

    final future = () async {
      final account = await _sites[link.site]?.ytDlpAccount() ?? const [];
      final info = await ytDlp.run(
          [...YtDlp.streamArgs(height, hevc: YtDlp.hevcDecoder), link.url],
          account: account);
      final stream = VideoStream.fromInfo(info);
      if (stream == null) {
        throw const VideoException('The site sent back nothing playable.');
      }
      // mpv is given the same cookies, for sites that want them for the
      // stream as well — Floatplane's decryption key.
      final i = account.indexOf('--cookies');
      final cookies = i >= 0 ? account[i + 1] : null;
      if (!stream.hls || stream.isLive) {
        return stream.copyWith(cookiesFile: cookies);
      }
      // Fragmented HLS is played through mpv's own fragment list rather
      // than ffmpeg's HLS reader, which cannot seek some of it — see HlsEdl.
      final audio = stream.audioUri;
      final edl = await Future.wait([
        HlsEdl.resolve(stream.uri, headers: stream.headers),
        if (audio != null) HlsEdl.resolve(audio, headers: stream.headers),
      ]);
      return stream.copyWith(
        uri: edl.first,
        audioUri: audio == null ? null : edl.last,
        cookiesFile: cookies,
      );
    }();
    _streams[key] = (now, future);
    // A failure is not worth remembering; the next attempt might work.
    unawaited(future.then<void>((_) {}, onError: (Object _) {
      if (_streams[key]?.$2 == future) _streams.remove(key);
    }));
    return future;
  }

  Future<void> setMaxHeight(int height) async {
    settings.maxHeight = height;
    // Addresses already worked out are for the old size.
    _streams.clear();
    notifyListeners();
    await _config.save();
  }

  // --- The video sent to the panel -----------------------------------------

  Player? _player;
  VideoController? _controller;
  VideoView _view = VideoView.closed;
  VideoLink? _link;
  VideoStream? _stream;
  String? _error;
  bool _loading = false;
  int _session = 0;
  DateTime _lastPlaying = DateTime.now();

  Player? get player => _player;
  VideoController? get controller => _controller;
  VideoView get view => _view;
  VideoLink? get link => _link;
  VideoStream? get stream => _stream;
  String? get error => _error;
  bool get loading => _loading;

  /// Whether a video sent to the panel is actually playing — which keeps the
  /// screen from switching itself off under it.
  bool get playing =>
      _view != VideoView.closed && (_player?.state.playing ?? false);

  /// Where the picture-in-picture window was left, in logical pixels. Kept
  /// here rather than in the window so it comes back where it was.
  Rect? pipRect;

  /// Sends [link] to the panel, full screen, from [at] or the link's own
  /// start time.
  Future<void> play(VideoLink link, {Duration? at}) async {
    final session = ++_session;
    _link = link;
    _stream = null;
    _error = null;
    _loading = true;
    _view = VideoView.full;
    _lastPlaying = DateTime.now();
    await _player?.stop();
    notifyListeners();
    onStart?.call();

    final VideoStream stream;
    try {
      stream = await resolve(link);
    } catch (e) {
      if (session != _session) return;
      _error = '$e';
      _loading = false;
      notifyListeners();
      return;
    }
    if (session != _session) return;

    final player = _player ??= await _newPlayer();
    _controller ??= VideoController(player, configuration: videoConfig);
    final from = at ?? link.start;
    // The level first, so a loud video does not begin at mpv's 100%.
    await applyAudio(player, settings);
    await stream.prepare(player);
    await player.open(Media(
      stream.uri,
      httpHeaders: stream.headers,
      start: !stream.isLive && from > Duration.zero ? from : null,
    ));
    if (session != _session) return;
    _stream = stream;
    _loading = false;
    notifyListeners();
  }

  Future<Player> _newPlayer() async {
    final player = Player();
    await MpvTuning.apply(player);
    // A stream mpv cannot open says so here and nowhere else — without this
    // the player sat black, with no way back but Close. Only while nothing
    // has loaded: once a video is playing, mpv's complaints are about a
    // dropped packet, not the video.
    player.stream.error.listen((e) {
      if (_view == VideoView.closed || _error != null) return;
      if (player.state.duration != Duration.zero) return;
      debugPrint('Video: mpv could not play it: $e');
      _error = 'The video would not play here.';
      _loading = false;
      notifyListeners();
    });
    return player;
  }

  void showFull() => _setView(VideoView.full);
  void showPip() => _setView(VideoView.pip);

  void _setView(VideoView v) {
    if (_view == VideoView.closed || _view == v) return;
    _view = v;
    notifyListeners();
  }

  Future<void> close() async {
    _session++;
    _view = VideoView.closed;
    _loading = false;
    _error = null;
    _stream = null;
    _link = null;
    notifyListeners();
    await _player?.stop();
  }

  // --- Sound ------------------------------------------------------------------

  Future<void> setVolume(double v) async {
    settings.volume = v.clamp(0, 100).toDouble();
    settings.muted = settings.volume <= 0;
    await _audioChanged();
  }

  Future<void> toggleMute() async {
    settings.muted = !settings.muted;
    if (!settings.muted && settings.volume <= 0) settings.volume = 40;
    await _audioChanged();
  }

  Future<void> _audioChanged() async {
    final player = _player;
    if (player != null) await applyAudio(player, settings);
    notifyListeners();
    await _config.save();
  }

  /// Sets [player] to the level in [s]. mpv's `mute` as well as its volume:
  /// the photo player found volume 0 alone still audible on this hardware.
  static Future<void> applyAudio(Player player, YouTubeSettings s,
      {bool? muted}) async {
    final mute = muted ?? s.muted;
    await player.setVolume(mute ? 0 : s.volume);
    final platform = player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('mute', mute ? 'yes' : 'no');
      } catch (_) {}
    }
  }

  // --- Once a minute ------------------------------------------------------------

  void _idleCheck() {
    if (_view == VideoView.closed || _loading || _error != null) return;
    if (_player?.state.playing ?? false) {
      _lastPlaying = DateTime.now();
      unawaited(_logSmoothness());
    } else if (DateTime.now().difference(_lastPlaying) > idleClose) {
      unawaited(close());
    }
  }

  /// Frames dropped since the video started, once a minute, so whether it
  /// plays smoothly can be read off the log rather than guessed at.
  Future<void> _logSmoothness() async {
    final platform = _player?.platform;
    if (platform is! NativePlayer) return;
    Future<String> get(String p) async {
      try {
        return await platform.getProperty(p);
      } catch (_) {
        return '?';
      }
    }

    final [w, h, at, fps, drawn, dropped, decoderDropped, hwdec] =
        await Future.wait([
      for (final p in const [
        'video-params/w',
        'video-params/h',
        'time-pos',
        'container-fps',
        'estimated-vf-fps',
        'frame-drop-count',
        'decoder-frame-drop-count',
        'hwdec-current',
      ])
        get(p),
    ]);
    if (w.isEmpty) {
      debugPrint('Video: nothing is showing yet');
      return;
    }
    debugPrint('Video: at ${at}s, ${w}x$h at $fps fps, drawing $drawn; '
        'dropped $dropped (decoder $decoderDropped), decoded by $hwdec');
  }
}

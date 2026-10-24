import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../l10n/l10n.dart';
import 'http_client.dart';
import 'itunes_art.dart';
import 'radio_stations.dart';
import 'seven_fm.dart';

/// A song the radio played, for the tile's list of recent ones.
class RadioSong {
  const RadioSong(this.title, this.station, this.at);

  /// As the station sent it: usually "Artist - Title".
  final String title;
  final String station;
  final DateTime at;

  /// [title] split at its first " - ", when it has one.
  ({String? artist, String song}) get parts => splitRadioTitle(title);
}

/// "Artist - Title" as its two halves; the whole of it as the song when
/// there is no dash to split at.
({String? artist, String song}) splitRadioTitle(String title) {
  final at = title.indexOf(' - ');
  if (at <= 0 || at >= title.length - 3) return (artist: null, song: title);
  return (
    artist: title.substring(0, at).trim(),
    song: title.substring(at + 3).trim(),
  );
}

/// Internet radio, played on the panel's own speakers.
///
/// One player for the whole app rather than one per tile, so the station
/// carries on while the dashboard turns to another page, and two radio tiles
/// cannot talk over each other. Made on first use: most panels never play
/// the radio.
class RadioService extends ChangeNotifier {
  RadioService({this.onStart, this.file, Dio? dio})
    : _dio = dio ?? httpClient();

  final Dio _dio;

  /// Where the volume last set is kept, so the radio starts at it again
  /// after a restart. Null keeps nothing — for tests.
  final String? file;

  /// Called as a station starts, to pause whatever else is playing.
  void Function()? onStart;

  Player? _player;
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _titlePoll;

  /// Watches a station starting, for one that never does.
  Timer? _startWatch;

  /// How long a station has to start before it is asked for again, and
  /// then given up on.
  static const startWait = Duration(seconds: 12);

  RadioStation? _station;
  bool _loading = false;
  String? _error;
  String? _title;
  double _volume = 60;

  /// Whether somebody has set [volume] themselves, with a tile's buttons or
  /// by voice. From then on that is the level every station starts at, and
  /// a tile's own starting level no longer applies.
  bool _volumeSet = false;

  final List<RadioSong> _history = [];
  final Map<String, String?> _artCache = {};
  String? _artUrl;

  Timer? _sleep;
  DateTime? _sleepAt;

  /// Which of [sleepSteps] [cycleSleep] set last.
  int _sleepStep = 0;

  /// The lengths the sleep timer steps through, in minutes. 0 is off.
  static const sleepSteps = [0, 15, 30, 60, 90];

  /// How many recent songs are kept.
  static const historyLength = 20;

  /// What is on, or was last: kept after [stop] so the tile still names it.
  RadioStation? get station => _station;
  bool get playing =>
      _station != null && (_pretend || (_player?.state.playing ?? false));

  /// Set by [debugPlaying] alone.
  bool _pretend = false;

  /// As if [station] were playing [title], with [history] before it — for
  /// drawing the tile in a test, where there is no mpv to play anything.
  @visibleForTesting
  void debugPlaying(
    RadioStation station, {
    String? title,
    List<RadioSong> history = const [],
  }) {
    _pretend = true;
    _station = station;
    _title = title;
    _history
      ..clear()
      ..addAll(history);
    notifyListeners();
  }

  bool get loading => _loading || (_player?.state.buffering ?? false);
  String? get error => _error;

  /// The song or programme, from the stream's own ICY title where it sends
  /// one. BBC and other HLS streams do not.
  String? get title => _title;
  double get volume => _volume;

  /// Songs played since the panel started, the latest first.
  List<RadioSong> get history => List.unmodifiable(_history);

  /// Cover art for [title], from the iTunes Search API. Null until found,
  /// and for anything it does not know — speech, jingles, adverts.
  String? get artUrl => _artUrl;

  /// When the sleep timer will stop the radio, or null when it is off.
  DateTime? get sleepAt => _sleepAt;

  /// The next of [sleepSteps] after the one set now: off, 15 minutes, half
  /// an hour… and round to off again.
  void cycleSleep() {
    final next = (_sleepStep + 1) % sleepSteps.length;
    final minutes = sleepSteps[next];
    setSleep(minutes == 0 ? null : Duration(minutes: minutes));
    _sleepStep = next;
  }

  /// Stops the radio after [after], or never when it is null.
  void setSleep(Duration? after) {
    _sleepStep = 0;
    _sleep?.cancel();
    _sleep = null;
    _sleepAt = after == null ? null : DateTime.now().add(after);
    if (after != null) {
      _sleep = Timer(after, () {
        _sleepAt = null;
        _sleepStep = 0;
        unawaited(stop());
      });
    }
    notifyListeners();
  }

  /// The station [by] along from the one on now in [stations], round from
  /// the end to the start; the first when none of them is on.
  RadioStation? stepFrom(List<RadioStation> stations, int by) {
    if (stations.isEmpty) return null;
    final at = stations.indexWhere((s) => s.url == _station?.url);
    if (at < 0) return stations.first;
    return stations[(at + by) % stations.length];
  }

  /// Reads the volume kept by [setVolume] last time.
  Future<void> load() async {
    final path = file;
    if (path == null) return;
    try {
      final f = File(path);
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString());
      final v = data is Map ? data['volume'] : null;
      if (v is num) {
        _volume = v.clamp(0, 100).toDouble();
        _volumeSet = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Radio: could not read $path: $e');
    }
  }

  /// Plays [station], or carries on with it if it is already on. [volume]
  /// is a tile's level to start at, out of 100 — used only until somebody
  /// sets one themselves, which is then kept.
  Future<void> play(RadioStation station, {double? volume}) async {
    if (volume != null && !_volumeSet) {
      _volume = volume.clamp(0, 100).toDouble();
    }
    if (_station?.url == station.url && (playing || _loading)) return;
    final uri = Uri.tryParse(station.url);
    // Handed straight to mpv, so nothing but a stream on the web.
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      _station = station;
      _error = tr('widget.radio.badAddress', 'That address is not a stream.');
      notifyListeners();
      return;
    }
    _station = station;
    _title = null;
    _artUrl = null;
    _error = null;
    _loading = true;
    notifyListeners();
    _watchStart(station);
    try {
      onStart?.call();
      await _open(station);
    } catch (e) {
      debugPrint('Radio: could not play ${station.url}: $e');
      _failed();
    }
  }

  Future<void> _open(RadioStation station) async {
    final player = _ensurePlayer();
    await player.setVolume(_volume);
    await player.open(Media(station.url));
  }

  /// The first station after a restart sometimes never starts: mpv is
  /// handed it, says nothing, and the tile says "Tuning in…" for ever.
  /// Asking for it again starts it, so that is done once, unasked; a
  /// second silence is the station's, and says so.
  void _watchStart(RadioStation station, {bool again = false}) {
    _startWatch?.cancel();
    _startWatch = Timer(startWait, () {
      if (!_loading || _station?.url != station.url) return;
      if (again) {
        debugPrint('Radio: ${station.url} never started');
        _failed();
        return;
      }
      debugPrint('Radio: ${station.url} has not started, asking again');
      _watchStart(station, again: true);
      unawaited(
        _player?.stop().then((_) => _open(station)).catchError((Object e) {
          debugPrint('Radio: could not play ${station.url}: $e');
          _failed();
        }),
      );
    });
  }

  void _failed() {
    _startWatch?.cancel();
    _loading = false;
    _error = tr('widget.radio.wouldNotPlay', 'The station would not play.');
    notifyListeners();
  }

  Future<void> stop() async {
    _loading = false;
    _startWatch?.cancel();
    _title = null;
    _artUrl = null;
    _titlePoll?.cancel();
    _sleep?.cancel();
    _sleep = null;
    _sleepAt = null;
    _sleepStep = 0;
    await _player?.stop();
    notifyListeners();
  }

  Future<void> toggle(RadioStation station, {double? volume}) =>
      playing && _station?.url == station.url
      ? stop()
      : play(station, volume: volume);

  /// Sets the level, and keeps it for every station after, restarts too.
  Future<void> setVolume(double v) async {
    _volume = v.clamp(0, 100).toDouble();
    _volumeSet = true;
    notifyListeners();
    await _player?.setVolume(_volume);
    await _keepVolume();
  }

  Future<void> _keepVolume() async {
    final path = file;
    if (path == null) return;
    try {
      final f = File(path);
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({'volume': _volume}), flush: true);
    } catch (e) {
      debugPrint('Radio: could not keep the volume in $path: $e');
    }
  }

  Player _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = _player = Player();
    final platform = player.platform;
    if (platform is NativePlayer) {
      // Sound only: a stream with a picture in it still draws nothing.
      unawaited(platform.setProperty('vid', 'no').catchError((_) {}));
    }
    _subs
      ..add(
        player.stream.playing.listen((on) {
          if (on) {
            _loading = false;
            _startWatch?.cancel();
            _error = null;
            _pollTitle();
          } else {
            _titlePoll?.cancel();
          }
          notifyListeners();
        }),
      )
      ..add(player.stream.buffering.listen((_) => notifyListeners()))
      ..add(
        player.stream.error.listen((e) {
          // Only while it is starting: once playing, mpv's complaints are
          // about a dropped packet, not the station.
          if (!_loading) return;
          debugPrint('Radio: mpv could not play ${_station?.url}: $e');
          _failed();
        }),
      )
      ..add(
        player.stream.completed.listen((done) {
          // A live stream only ends when the station drops it.
          if (done && _station != null) {
            _error = tr('widget.radio.ended', 'The station stopped sending.');
            notifyListeners();
          }
        }),
      );
    return player;
  }

  /// The ICY title, now and every ten seconds while it plays. Asked for
  /// rather than watched: it changes once a song, and a song's first few
  /// seconds under the old name do no harm.
  void _pollTitle() {
    _titlePoll?.cancel();
    unawaited(_readTitle());
    _titlePoll = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _readTitle(),
    );
  }

  Future<void> _readTitle() async {
    final platform = _player?.platform;
    if (platform is! NativePlayer) return;
    String? title;
    try {
      title = (await platform.getProperty('metadata/by-key/icy-title')).trim();
    } catch (_) {
      // No such key: the stream sends no titles.
    }
    if (title != null && title.isEmpty) title = null;
    if (title == _title) return;
    _title = title;
    _artUrl = null;
    final station = _station;
    if (title != null && station != null) {
      if (_history.isEmpty || _history.first.title != title) {
        _history.insert(0, RadioSong(title, station.name, DateTime.now()));
        if (_history.length > historyLength) _history.removeLast();
      }
      unawaited(_lookupArt(title, station));
    }
    notifyListeners();
  }

  /// Cover art for the song [title] names, as the Now playing tile finds it
  /// for a phone's music. Only for "Artist - Title": a title without a
  /// dash is a programme's name, and iTunes would find a song called that.
  ///
  /// A station that says which album it is playing is asked first: a film
  /// score's cues share their names with half of iTunes, and the composer
  /// alone picks out none of them.
  Future<void> _lookupArt(String title, RadioStation station) async {
    final parts = splitRadioTitle(title);
    final artist = parts.artist;
    if (artist == null) return;
    if (_artCache.containsKey(title)) {
      _artUrl = _artCache[title];
      notifyListeners();
      return;
    }
    String? art;
    final seven = sevenStationAt(Uri.tryParse(station.url)?.host ?? '');
    if (seven != null) art = await _stationArt(seven, parts.song);
    art ??= await itunesSongArt(_dio, artist: artist, song: parts.song);
    _artCache[title] = art;
    if (_title == title) {
      _artUrl = art;
      notifyListeners();
    }
  }

  /// The cover from a 24seven.FM station's own now-playing. Asked a few
  /// times, as the station's feed can be a few seconds ahead of or behind
  /// the stream's title.
  Future<String?> _stationArt(SevenStation station, String song) async {
    for (var i = 0; i < 3; i++) {
      if (i > 0) await Future<void>.delayed(const Duration(seconds: 5));
      try {
        final r = await _dio.get(
          '${station.site}/now-playing.php',
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 8),
          ),
        );
        final now = parseSevenNowPlaying(r.data as String).track;
        if (now != null && sameName(now.title, song)) return now.art;
      } catch (e) {
        debugPrint('Radio: ${station.name} now playing failed: $e');
        return null;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _titlePoll?.cancel();
    _startWatch?.cancel();
    _sleep?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_player?.dispose());
    super.dispose();
  }
}

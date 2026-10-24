import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'radio_stations.dart';

/// One of the five stations of 24seven.FM, the network StreamingSoundtracks
/// belongs to. All five say what they are playing, what is coming up and
/// what played before, with the album's cover, at the same addresses on
/// their own sites: https://24seven.fm/developers.php.
class SevenStation {
  const SevenStation(this.id, this.name, this.site, this.badge, this.about);

  final String id;
  final String name;

  /// Its website, with no slash at the end.
  final String site;
  final String badge;

  /// What it plays, in its own words.
  final String about;

  /// 192 kbps AAC+, the best each of them sends.
  String get stream => '$site/live';

  /// For the radio player, which plays every station on the panel.
  RadioStation get radio =>
      RadioStation('seven_$id', name, 'Internet', stream, badge: badge);
}

const sevenStations = [
  SevenStation(
    'sst',
    'StreamingSoundtracks.com',
    'https://streamingsoundtracks.com',
    'SST',
    'Film, game and TV scores',
  ),
  SevenStation(
    '80s',
    '1980s.FM',
    'https://1980s.fm',
    '80s',
    'Vintage nostalgia and 80s hits',
  ),
  SevenStation(
    'afm',
    'Adagio.FM',
    'https://adagio.fm',
    'AFM',
    'Classical music and compositions',
  ),
  SevenStation(
    'dfm',
    'Death.FM',
    'https://death.fm',
    'DFM',
    'Death metal, grind and black metal',
  ),
  SevenStation(
    'efm',
    'Entranced.FM',
    'https://entranced.fm',
    'EFM',
    'Trance and electronica',
  ),
];

SevenStation sevenStation(String? id) =>
    sevenStations.firstWhere((s) => s.id == id, orElse: () => sevenStations[0]);

/// The station of these whose site [host] is, if any.
SevenStation? sevenStationAt(String host) {
  for (final s in sevenStations) {
    if (Uri.parse(s.site).host == host) return s;
  }
  return null;
}

/// A track, on now, coming up or played.
class SevenTrack {
  const SevenTrack({
    required this.title,
    this.artist,
    this.album,
    this.art,
    this.started,
    this.length,
    this.requestedBy,
    this.play,
  });

  final String title;
  final String? artist;
  final String? album;

  /// The album's cover, or for the track on now the station's logo when it
  /// has none.
  final String? art;

  /// Known only for the track on now.
  final DateTime? started;
  final Duration? length;

  /// A listener who asked for it; null for the station's own choice.
  final String? requestedBy;

  /// This play of it, for the track on now: the same song played again
  /// is a different play.
  final String? play;
}

/// The track on now, from a station's now-playing.php; null when there is
/// none, or the station has not said for over a minute — a song left up
/// long after it ended is worse than none.
({SevenTrack? track, int refresh}) parseSevenNowPlaying(
  String body, {
  DateTime? now,
}) {
  const none = (track: null, refresh: 10);
  final data = jsonDecode(body);
  if (data is! Map || data['schema_version'] != 1) return none;
  final refresh = switch (data['refresh_after_seconds']) {
    final num n when n >= 10 => n.round(),
    _ => 10,
  };
  final track = data['track'];
  if (data['status'] != 'playing' || track is! Map) {
    return (track: null, refresh: refresh);
  }
  final at = DateTime.tryParse('${data['generated_at']}');
  if (at != null && (now ?? DateTime.now()).difference(at).inSeconds > 60) {
    return (track: null, refresh: refresh);
  }
  String? text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
  final title = text(track['title']);
  if (title == null) return (track: null, refresh: refresh);
  final seconds = track['duration_seconds'];
  return (
    track: SevenTrack(
      title: title,
      artist: text(track['artist']),
      album: text(track['album']),
      art: text(data['artwork_url']),
      started: DateTime.tryParse('${track['started_at']}')?.toLocal(),
      length: seconds is num && seconds > 0
          ? Duration(milliseconds: (seconds * 1000).round())
          : null,
      play: text(track['play_id']),
    ),
    refresh: refresh,
  );
}

/// The tracks of a station's GetQueue or GetHistory, in its order: the
/// next first, or the latest.
List<SevenTrack> parseSevenTracks(String body) {
  final data = jsonDecode(body);
  if (data is! List) return const [];
  String? text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
  return [
    for (final item in data)
      if (item is Map && text(item['Track']) != null)
        SevenTrack(
          title: text(item['Track'])!,
          artist: text(item['Artist']),
          album: text(item['Album']),
          art: text(item['CoverLink']),
          requestedBy: switch (text(item['RequestedBy'])) {
            // The station's own pick.
            'System/Admin' => null,
            final who => who,
          },
        ),
  ];
}

/// What one station is playing, kept up to date while a tile shows it.
class SevenFeed extends ChangeNotifier {
  SevenFeed(this.station, this._dio);

  final SevenStation station;
  final Dio _dio;

  SevenTrack? now;
  List<SevenTrack> next = const [];
  List<SevenTrack> before = const [];

  /// Whether the station could not be reached last time it was asked.
  bool offline = false;

  Timer? _timer;
  int _failures = 0;
  int _polls = 0;
  bool _stopped = true;

  void _start() {
    if (!_stopped) return;
    _stopped = false;
    unawaited(_poll());
  }

  void _stop() {
    _stopped = true;
    _timer?.cancel();
  }

  Future<String> _get(String path, [Map<String, String>? query]) async {
    final r = await _dio.get(
      '${station.site}/$path',
      queryParameters: query,
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
      ),
    );
    return r.data as String;
  }

  Future<void> _poll() async {
    // The next asked for only once this one is answered, as the station
    // asks, and never sooner than it says.
    var wait = 10;
    try {
      final read = parseSevenNowPlaying(await _get('now-playing.php'));
      wait = read.refresh;
      final changed = read.track?.play != now?.play || read.track == null;
      now = read.track;
      offline = false;
      _failures = 0;
      // The lists on a new track, and once a minute between for requests
      // added to the queue.
      if (changed || _polls++ % 6 == 0) await _lists();
    } catch (e) {
      debugPrint('24seven: ${station.name} not reached: $e');
      now = null;
      offline = true;
      // 20 s, 40 s, then a minute at most between tries.
      _failures++;
      wait = (10 << _failures.clamp(1, 3)).clamp(10, 60);
    }
    if (_stopped) return;
    notifyListeners();
    _timer = Timer(Duration(seconds: wait), _poll);
  }

  Future<void> _lists() async {
    try {
      final (q, h) = await (
        _get('soap/FM24sevenJSON.php', {'action': 'GetQueue'}),
        _get('soap/FM24sevenJSON.php', {'action': 'GetHistory'}),
      ).wait;
      next = parseSevenTracks(q);
      // The history starts with the track on now.
      before = parseSevenTracks(h).where((t) => t.title != now?.title).toList();
    } catch (e) {
      debugPrint('24seven: ${station.name} lists not read: $e');
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}

/// The feeds the panel's StreamingSoundtracks tiles show, each asked only
/// while some tile shows it.
class SevenFmService {
  SevenFmService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  final _feeds = <String, SevenFeed>{};
  final _watchers = <String, int>{};

  /// The feed for [station], kept up to date until as many [unwatch]es.
  SevenFeed watch(SevenStation station) {
    final feed = _feeds.putIfAbsent(station.id, () => SevenFeed(station, _dio));
    _watchers.update(station.id, (n) => n + 1, ifAbsent: () => 1);
    feed._start();
    return feed;
  }

  void unwatch(SevenStation station) {
    final left = (_watchers[station.id] ?? 1) - 1;
    _watchers[station.id] = left;
    if (left <= 0) _feeds[station.id]?._stop();
  }
}

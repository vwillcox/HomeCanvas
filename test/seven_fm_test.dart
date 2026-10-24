import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/seven_fm.dart';

void main() {
  // As https://streamingsoundtracks.com/now-playing.php sent it.
  const nowPlaying = '''
{"schema_version":1,"station":{"name":"StreamingSoundtracks.com"},
 "status":"playing","generated_at":"2026-10-24T13:05:41+00:00",
 "refresh_after_seconds":10,
 "track":{"id":"349521","play_id":"2928072","title":"The Spirit Of Man",
  "artist":"Jeff Wayne",
  "album":"Jeff Wayne's Musical Version Of The War Of The Worlds",
  "started_at":"2026-10-24T13:02:38+00:00","duration_seconds":697.932},
 "artwork_url":"https://streamingsoundtracks.com/images/cover/500/B002896Q54.jpg?v=1"}
''';
  final at = DateTime.utc(2026, 10, 24, 13, 6);

  group('what is on now', () {
    test('the track, its cover and how long it runs', () {
      final read = parseSevenNowPlaying(nowPlaying, now: at);
      final t = read.track!;
      expect(t.title, 'The Spirit Of Man');
      expect(t.artist, 'Jeff Wayne');
      expect(t.album, contains('War Of The Worlds'));
      // The query string kept, as the station asks.
      expect(t.art, endsWith('B002896Q54.jpg?v=1'));
      expect(t.started, DateTime.utc(2026, 10, 24, 13, 2, 38).toLocal());
      expect(t.length, const Duration(milliseconds: 697932));
      expect(t.play, '2928072');
      expect(read.refresh, 10);
    });

    test('nothing once the station has gone quiet for a minute', () {
      final late = at.add(const Duration(minutes: 2));
      expect(parseSevenNowPlaying(nowPlaying, now: late).track, isNull);
    });

    test('nothing when the station says so, or sends what is not known', () {
      expect(
        parseSevenNowPlaying(
          '{"schema_version":1,"status":"unavailable","track":null}',
        ).track,
        isNull,
      );
      expect(
        parseSevenNowPlaying('{"schema_version":2,"status":"playing"}').track,
        isNull,
      );
      expect(parseSevenNowPlaying('{"error":"unavailable"}').track, isNull);
    });
  });

  test('the queue, with who asked for what', () {
    const queue = '''
[{"Artist":"Kenji Kawai","Album":"Fate/Stay Night","Track":"Holy Grail",
  "Length":"97111","CoverLink":"https://streamingsoundtracks.com/images/cover/B000JVSUKW.jpg",
  "RequestedBy":"System/Admin","Message":null},
 {"Artist":null,"Album":"TRON: Legacy","Track":"End Of Line",
  "Length":"155249","CoverLink":"https://streamingsoundtracks.com/images/cover/B0037KMHRY.jpg",
  "RequestedBy":"GusGus1388","Message":null},
 {"Artist":"Nobody","Track":""}]
''';
    final tracks = parseSevenTracks(queue);
    expect(tracks.map((t) => t.title), ['Holy Grail', 'End Of Line']);
    expect(tracks[0].requestedBy, isNull);
    expect(tracks[1].requestedBy, 'GusGus1388');
    expect(tracks[1].artist, isNull);
    expect(tracks[1].album, 'TRON: Legacy');
    expect(parseSevenTracks('{"error":"x"}'), isEmpty);
  });

  test('the five stations, and which a stream is', () {
    expect(sevenStations.map((s) => s.id).toSet(), hasLength(5));
    expect(sevenStation('sst').radio.letters, 'SST');
    expect(sevenStation('nope').id, 'sst');
    expect(sevenStationAt('streamingsoundtracks.com')?.id, 'sst');
    expect(sevenStationAt('death.fm')?.name, 'Death.FM');
    expect(sevenStationAt('example.org'), isNull);
  });
}

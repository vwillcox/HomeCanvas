import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/services/itunes_art.dart';
import 'package:home_canvas/services/radio_service.dart';
import 'package:home_canvas/services/radio_stations.dart';
import 'package:home_canvas/services/voice_commands.dart';

/// A panel with one Radio tile, on page 2, tuned to these.
VoiceCommands _panel() => VoiceCommands(
  pageCount: 3,
  pages: const [],
  widgets: [
    DashboardWidgetConfig(
      id: 'radio',
      type: 'radio',
      x: 0,
      y: 0,
      width: 4,
      height: 3,
      page: 1,
      options: {
        'stations': [
          {'station': 'bbc_radio_4', 'name': '', 'url': ''},
          {'station': 'bbc_6music', 'name': '', 'url': ''},
          {'station': '', 'name': 'Kitchen FM', 'url': 'https://example.org/k'},
        ],
      },
    ),
    DashboardWidgetConfig(
      id: 'news',
      type: 'news',
      x: 0,
      y: 0,
      width: 3,
      height: 2,
      page: 2,
    ),
  ],
  nameOf: (type) => {'radio': 'Radio', 'news': 'News feed'}[type],
);

void main() {
  group('the catalogue', () {
    test('every station has its own id and a web address', () {
      final ids = <String>{};
      for (final s in radioStations) {
        expect(ids.add(s.id), isTrue, reason: '${s.id} twice');
        final uri = Uri.parse(s.url);
        expect(uri.isScheme('http') || uri.isScheme('https'), isTrue);
      }
    });

    test('a tile\'s rows become its stations, in order', () {
      final stations = radioStationsFrom([
        {'station': 'fip', 'name': '', 'url': ''},
        {'station': 'bbc_radio_4', 'name': 'The Four', 'url': ''},
        {'station': '', 'name': '', 'url': 'https://example.org/live'},
        {'station': 'gone', 'name': '', 'url': ''},
        {'station': '', 'name': '', 'url': ''},
      ]);
      expect(stations.map((s) => s.name), ['FIP', 'The Four', 'example.org']);
      expect(stations[1].url, radioStation('bbc_radio_4')!.url);
      expect(radioStationsFrom(null), isEmpty);
    });
  });

  test('badges', () {
    expect(radioBadge('BBC Radio 4'), 'R4');
    expect(radioBadge('BBC Radio 6 Music'), 'R6');
    expect(radioBadge('NRK P1'), 'P1');
    expect(radioBadge('FM4'), 'FM4');
    expect(radioBadge('KEXP Seattle'), 'KEXP');
    expect(radioBadge('Classic FM'), 'CFM');
    expect(radioBadge('Smooth Radio'), 'SR');
    expect(radioBadge('SomaFM Groove Salad'), 'SG');
    expect(radioBadge('talkSPORT'), 'T');
    expect(radioBadge(''), '?');
  });

  group('a station by what was said', () {
    test('figures as words, BBC and "radio" not needed', () {
      expect(matchRadioStation('radio four', radioStations)?.id, 'bbc_radio_4');
      expect(matchRadioStation('six music', radioStations)?.id, 'bbc_6music');
      expect(
        matchRadioStation('radio four extra', radioStations)?.id,
        'bbc_radio_4_extra',
      );
      expect(matchRadioStation('fip', radioStations)?.id, 'fip');
    });

    test('in full, when asked to be', () {
      expect(matchRadioStation('news', radioStations)?.id, 'npr');
      expect(matchRadioStation('news', radioStations, whole: true), isNull);
      expect(
        matchRadioStation('npr news', radioStations, whole: true)?.id,
        'npr',
      );
    });

    test('nothing for a name no station has', () {
      expect(matchRadioStation('the weather', radioStations), isNull);
      expect(matchRadioStation('radio', radioStations), isNull);
    });
  });

  test('ICY titles split into artist and song', () {
    expect(splitRadioTitle('Daft Punk - One More Time'), (
      artist: 'Daft Punk',
      song: 'One More Time',
    ));
    expect(splitRadioTitle('The Archers'), (artist: null, song: 'The Archers'));
  });

  group('cover art', () {
    test('names alike, or one with a subtitle after it', () {
      expect(sameName('X-MT', 'x mt'), isTrue);
      expect(
        sameName(
          'Xperiments from Dark Phoenix (Original Score)',
          'Xperiments From Dark Phoenix',
        ),
        isTrue,
      );
      expect(sameName('Jai Jai Ram (Orchestral)', 'X-MT'), isFalse);
      expect(sameName('Time', 'Timeless'), isFalse);
      expect(sameName('', 'X'), isFalse);
      // Any alphabet, not only A to Z.
      expect(sameName('残酷な天使のテーゼ', '残酷な天使のテーゼ (TV Size)'), isTrue);
    });
  });

  group('said to the panel', () {
    VoiceRadio? radio(String heard) => _panel().resolve(heard) as VoiceRadio?;

    test('the radio on and off', () {
      expect(radio('play the radio')?.ask, VoiceRadioAsk.play);
      expect(radio('turn the radio on')?.ask, VoiceRadioAsk.play);
      expect(radio('stop the radio')?.ask, VoiceRadioAsk.stop);
      expect(radio('turn the radio off')?.ask, VoiceRadioAsk.stop);
      expect(radio('next station')?.ask, VoiceRadioAsk.next);
    });

    test('a station by its name', () {
      final a = radio('hey canvas play radio four')!;
      expect(a.ask, VoiceRadioAsk.play);
      expect(_panel().stationFor(a.station!)?.id, 'bbc_radio_4');
      expect(_panel().stationFor('kitchen')?.name, 'Kitchen FM');
      // Not one of the tile's, but in the catalogue.
      expect(_panel().stationFor(radio('listen to fip')!.station!)?.id, 'fip');
    });

    test('"play" and something that is not a station is not the radio', () {
      expect(_panel().resolve('play the news'), isA<VoiceShowPage>());
      expect(_panel().resolve('play'), isA<VoiceMusic>());
      expect(_panel().resolve('show the radio'), isA<VoiceShowPage>());
    });
  });

  group('the volume', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('radio'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a tile\'s starting level only until one is set, then kept', () async {
      final file = '${dir.path}/radio.json';
      final r = RadioService(file: file);
      addTearDown(r.dispose);
      // Nothing set yet: the tile's level is taken. (play() goes no further
      // than the address check for one that is not a stream.)
      await r.play(const RadioStation('x', 'X', '', 'file:///x'), volume: 35);
      expect(r.volume, 35);
      await r.setVolume(20);
      await r.play(const RadioStation('y', 'Y', '', 'file:///y'), volume: 80);
      expect(r.volume, 20);

      // And after a restart.
      final again = RadioService(file: file);
      addTearDown(again.dispose);
      await again.load();
      await again.play(
        const RadioStation('z', 'Z', '', 'file:///z'),
        volume: 80,
      );
      expect(again.volume, 20);
    });
  });

  group('a station that stops sending', () {
    const minutes = Duration(minutes: 5);
    const seconds = Duration(seconds: 5);

    test('after playing a while, is always tuned in again', () {
      // StreamingSoundtracks closes its stream every few minutes, mid-song.
      expect(RadioService.dropsAfter(0, minutes), 1);
      expect(RadioService.dropsAfter(RadioService.maxDrops, minutes), 1);
    });

    test('as soon as it starts, is given up on after a few goes', () {
      final runs = <int?>[];
      var drops = 0;
      for (var i = 0; i <= RadioService.maxDrops; i++) {
        final next = RadioService.dropsAfter(drops, seconds);
        runs.add(next);
        drops = next ?? 0;
      }
      expect(runs, [1, 2, 3, null]);
    });
  });

  group('the sleep timer', () {
    test('steps through its lengths and round to off', () {
      final r = RadioService();
      addTearDown(r.dispose);
      expect(r.sleepAt, isNull);
      final seen = <int?>[];
      for (var i = 0; i < RadioService.sleepSteps.length; i++) {
        r.cycleSleep();
        seen.add(r.sleepAt?.difference(DateTime.now()).inMinutes);
      }
      // Each just under its length, by the time it is read.
      expect(seen, [14, 29, 59, 89, null]);
    });
  });
}

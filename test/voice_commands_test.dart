import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/schedule.dart';
import 'package:home_canvas/services/voice_commands.dart';

DashboardWidgetConfig _tile(String type, int page) => DashboardWidgetConfig(
  id: '$type-$page',
  type: type,
  x: 0,
  y: 0,
  width: 3,
  height: 2,
  page: page,
);

const _names = {
  'clock': 'Clock',
  'weather': 'Weather',
  'spotify': 'Now playing',
  'news': 'News feed',
  'tv': 'TV remote',
  'youtube': 'YouTube',
  'floatplane': 'Floatplane',
  'nebula': 'Nebula',
  'servers': 'Servers',
  'sun_moon': 'Sun & moon',
  'stocks': 'Stocks',
  'crypto': 'Crypto',
  'fuel': 'Fuel prices',
  'history': 'On this day in history',
  'unifi_health': 'Network health',
  'unifi_clients': 'Network clients',
  'homey_room': 'Homey room',
};

/// A dashboard laid out like the one on the wall.
VoiceCommands _panel({DateTime? now, List<DashboardPage>? pages}) =>
    VoiceCommands(
      pageCount: 6,
      pages:
          pages ??
          const [DashboardPage(name: 'Main'), DashboardPage(name: 'Media')],
      widgets: [
        for (final t in ['clock', 'weather', 'spotify', 'news', 'tv'])
          _tile(t, 0),
        for (final t in ['youtube', 'floatplane', 'nebula']) _tile(t, 1),
        for (final t in ['servers', 'sun_moon']) _tile(t, 2),
        for (final t in ['unifi_health', 'unifi_clients']) _tile(t, 3),
        for (final t in ['stocks', 'crypto']) _tile(t, 4),
        for (final t in ['fuel', 'history', 'homey_room']) _tile(t, 5),
      ],
      nameOf: (type) => _names[type],
      now: now,
    );

int? _page(String heard, {VoiceCommands? on}) {
  final action = (on ?? _panel()).resolve(heard);
  return action is VoiceShowPage ? action.page : null;
}

void main() {
  group('a widget, by name', () {
    test('goes to the page it is on', () {
      expect(_page('show stocks'), 4);
      expect(_page('show crypto'), 4);
      expect(_page('show servers'), 2);
    });

    test('however it is asked for', () {
      for (final said in [
        'Show Stocks',
        'hey canvas show stocks',
        'Hey Canvas, show me the stocks, please.',
        'open the stocks page',
        'go to stocks',
        'switch to the stocks widget',
        'stocks',
        'show stock',
      ]) {
        expect(_page(said), 4, reason: said);
      }
    });

    test('by part of a longer name', () {
      expect(_page('show fuel'), 5);
      expect(_page('show fuel prices'), 5);
      expect(_page('show history'), 5);
      expect(_page('show the moon'), 2);
      expect(_page('show sun and moon'), 2);
    });

    test('by another word for it', () {
      expect(_page('show videos'), 1);
      expect(_page('show youtube'), 1);
      expect(_page('show music'), 0);
      expect(_page('show the network'), 3);
      expect(_page('show bitcoin'), 4);
      expect(_page('show petrol'), 5);
    });

    test('by its type, when the name says something else', () {
      expect(_page('show spotify'), 0);
      expect(_page('show unifi clients'), 3);
    });

    test('with a letter wrong, as typed or as misheard', () {
      expect(_page('showe vidoes'), 1);
      expect(_page('show vidoes'), 1);
      expect(_page('show crypt'), 4);
      expect(_page('show noos'), isNull, reason: 'too short to guess at');
      expect(_page('show servres'), 2);
      expect(_page('show flotplane'), 1);
    });

    test('said exactly beats said in part', () {
      final panel = VoiceCommands(
        pageCount: 2,
        pages: const [],
        widgets: [_tile('news', 0), _tile('newsroom', 1)],
        nameOf: (t) => t == 'news' ? 'News feed' : 'Feed',
      );
      expect(_page('show feed', on: panel), 1);
      expect(_page('show news', on: panel), 0);
    });

    test('the earliest page, when two answer equally', () {
      final panel = VoiceCommands(
        pageCount: 3,
        pages: const [],
        widgets: [_tile('weather', 2), _tile('weather', 1)],
        nameOf: (_) => 'Weather',
      );
      expect(_page('show weather', on: panel), 1);
    });

    test('whatever the wake words were heard as', () {
      expect(_page('s hacambus show stocks'), 4);
      expect(_page('a canvas show me the videos'), 1);
      final action = _panel().resolve('hay campus next page');
      expect(action, isA<VoiceTurnPage>());
      // The whole of it first: "back a page" is not "page".
      expect((_panel().resolve('hey canvas go back a page') as VoiceTurnPage).by, -1);
    });

    test('nothing, for something that is not there', () {
      expect(_panel().resolve('show the tides'), isNull);
      expect(_panel().resolve('what is the time'), isNull);
      expect(_panel().resolve(''), isNull);
      expect(_panel().resolve('hey canvas'), isNull);
      expect(_panel().resolve('show me the'), isNull);
    });
  });

  group('a page', () {
    test('by its name', () {
      expect(_page('show media'), 1);
      expect(_page('go to the main page'), 0);
    });

    test('by its number, counted from one', () {
      expect(_page('page three'), 2);
      expect(_page('go to page 5'), 4);
      expect(_page('show the second page'), 1);
      expect(_page('show page number six'), 5);
      expect(_page('page for'), 3, reason: 'what "four" is heard as');
    });

    test('but not a number there is no page for', () {
      expect(_panel().resolve('page seven'), isNull);
      expect(_panel().resolve('page zero'), isNull);
    });

    test('not one that is out of its hours', () {
      final evening = const DashboardPage(
        name: 'Evening',
        schedule: Schedule(from: '18:00', to: '23:00'),
      );
      final pages = [const DashboardPage(name: 'Main'), evening];
      expect(
        _page('show evening',
            on: _panel(now: DateTime(2026, 10, 13, 20), pages: pages)),
        1,
      );
      final morning = _panel(now: DateTime(2026, 10, 13, 9), pages: pages);
      expect(morning.resolve('show evening'), isNull);
      expect(morning.resolve('show videos'), isNull,
          reason: 'its widgets go with it');
    });
  });

  group('the fixed commands', () {
    T heard<T extends VoiceAction>(String said) {
      final action = _panel().resolve(said);
      expect(action, isA<T>(), reason: said);
      return action as T;
    }

    test('turn the page', () {
      for (final said in ['next page', 'next', 'hey canvas go forward']) {
        expect(heard<VoiceTurnPage>(said).by, 1);
      }
      for (final said in ['previous page', 'go back a page', 'page back']) {
        expect(heard<VoiceTurnPage>(said).by, -1);
      }
    });

    test('go back, which is not a page back', () {
      for (final said in ['go back', 'back', 'close that', 'close']) {
        expect(heard<VoiceGo>(said).place, VoicePlace.back);
      }
    });

    test('the places', () {
      expect(heard<VoiceGo>('show photos').place, VoicePlace.photos);
      expect(heard<VoiceGo>('go home').place, VoicePlace.photos);
      expect(heard<VoiceGo>('open the dashboard').place, VoicePlace.dashboard);
      expect(heard<VoiceGo>('show the forecast').place, VoicePlace.forecast);
    });

    test('the TV remote is the remote itself, not the page its tile is on', () {
      for (final said in [
        'open the remote',
        'show the remote panel',
        'open the tv remote',
        'remote control',
      ]) {
        expect(heard<VoiceGo>(said).place, VoicePlace.remote);
      }
      // The TV itself is still a widget to go to.
      expect(_page('show the telly'), 0);
    });

    test('the music: play, pause, skip, and how loud', () {
      VoiceMusicAsk ask(String said) => heard<VoiceMusic>(said).ask;
      for (final said in ['play', 'play music', 'play spotify', 'resume the music']) {
        expect(ask(said), VoiceMusicAsk.play, reason: said);
      }
      for (final said in ['pause', 'pause the music', 'stop', 'stop the music']) {
        expect(ask(said), VoiceMusicAsk.pause, reason: said);
      }
      for (final said in ['skip', 'skip this song', 'next track', 'next song']) {
        expect(ask(said), VoiceMusicAsk.next, reason: said);
      }
      for (final said in ['previous track', 'go to the last song', 'skip back']) {
        expect(ask(said), VoiceMusicAsk.previous, reason: said);
      }
      expect(ask('volume up'), VoiceMusicAsk.louder);
      expect(ask('turn it up'), VoiceMusicAsk.louder);
      expect(ask('louder'), VoiceMusicAsk.louder);
      expect(ask('turn the volume down'), VoiceMusicAsk.quieter);
      expect(ask('mute'), VoiceMusicAsk.mute);
      expect(ask('unmute the music'), VoiceMusicAsk.unmute);
    });

    test('next and previous alone are still the pages', () {
      expect(heard<VoiceTurnPage>('next').by, 1);
      expect(heard<VoiceTurnPage>('previous').by, -1);
      // And the music is still somewhere to go, as well as something to stop.
      expect(_page('show music'), 0);
      expect(_page('bring up the stocks'), 4);
    });

    test('hold the pages and let them go', () {
      for (final said in ['pause pages', 'stay on this page', 'hold this page']) {
        expect(heard<VoicePausePages>(said).paused, isTrue);
      }
      for (final said in ['resume', 'carry on', 'continue']) {
        expect(heard<VoicePausePages>(said).paused, isFalse);
      }
    });

    test('the camera, shown and put away', () {
      expect(heard<VoiceCamera>('show the camera').open, isTrue);
      expect(heard<VoiceCamera>('hide the camera').open, isFalse);
      expect(heard<VoiceCamera>('close the camera').open, isFalse);
    });

    test('never the Locked Folder, and never Settings', () {
      for (final said in [
        'open the locked folder',
        'show locked folder',
        'open settings',
        'show the settings',
      ]) {
        expect(_panel().resolve(said), isNull, reason: said);
      }
    });
  });

  test('the Konami code, however the B and the A come out', () {
    for (final said in [
      'hey canvas up up down down left right left right b a',
      'Hey, Douglas. Up, up, down, down, left, right, left, right, be a.',
      'up up down down left right left right',
      'up up down down left right left right b a start',
    ]) {
      expect(_panel().resolve(said), isA<VoiceKonami>(), reason: said);
    }
    expect(_panel().resolve('up down left right'), isNull);
  });

  test('says what it answers to, for a listener to be told', () {
    final phrases = _panel().phrases;
    expect(phrases, containsAll(['stocks', 'videos', 'media', 'next page']));
    expect(phrases.toSet().length, phrases.length);
  });

  test('the wake words taken off, for Home Assistant', () {
    expect(
      VoiceCommands.afterWake('Hey Canvas, turn on the lamp.'),
      'turn on the lamp.',
    );
    expect(VoiceCommands.afterWake('hey congress what time is it'), 'what time is it');
    expect(VoiceCommands.afterWake('hay canvass turn off the fan'), 'turn off the fan');
    expect(VoiceCommands.afterWake('a canvas turn off the fan'), 'turn off the fan');
    expect(VoiceCommands.afterWake('hey convas lights off'), 'lights off');
    // Said after a pause, without them: all of it is the request.
    expect(VoiceCommands.afterWake("what's the temperature"), "what's the temperature");
    expect(VoiceCommands.afterWake('hi there'), 'hi there');
    expect(VoiceCommands.afterWake('Hey, Canvas, what’s on?'), 'what’s on?');
  });
}

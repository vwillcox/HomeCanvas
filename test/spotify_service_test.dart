import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/spotify_service.dart';

void main() {
  group('PKCE code challenge', () {
    test('matches RFC 7636\'s own worked example', () {
      // https://www.rfc-editor.org/rfc/rfc7636#appendix-B — the standard's
      // own verifier/challenge pair, so this is checked against a fixed
      // external answer rather than just against its own algorithm.
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const expected = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';
      expect(SpotifyService.codeChallengeFor(verifier), expected);
    });

    test('never contains base64 padding', () {
      // Spotify's /authorize rejects a code_challenge containing "=".
      final challenge = SpotifyService.codeChallengeFor('x' * 43);
      expect(challenge.contains('='), isFalse);
    });
  });

  group('repeat state', () {
    test('cycles off -> repeat all -> repeat one -> off', () {
      expect(SpotifyService.nextRepeatState('off'), 'context');
      expect(SpotifyService.nextRepeatState('alltracks'), 'track');
      expect(SpotifyService.nextRepeatState('singletrack'), 'off');
    });

    test('an unrecognised state is treated as off', () {
      expect(SpotifyService.nextRepeatState('bogus'), 'context');
    });

    test('repeatStateFrom is the inverse mapping', () {
      expect(SpotifyService.repeatStateFrom('off'), 'off');
      expect(SpotifyService.repeatStateFrom('context'), 'alltracks');
      expect(SpotifyService.repeatStateFrom('track'), 'singletrack');
    });

    test('round-trips through a full cycle', () {
      var state = 'off';
      final seen = <String>[];
      for (var i = 0; i < 3; i++) {
        state = SpotifyService.nextRepeatState(
          SpotifyService.repeatStateFrom(state),
        );
        seen.add(state);
      }
      expect(seen, ['context', 'track', 'off']);
    });
  });

  group("what Spotify's player reply means", () {
    test('a track is a track', () {
      final r = SpotifyService.readPlayer(_reply(item: _track));
      expect(r.kind, PlayerReplyKind.track);
      expect(r.now.title, 'Centuries');
      expect(r.now.artist, 'Fall Out Boy');
      expect(r.now.trackId, 'track123');
      expect(r.now.isPlaying, isTrue);
      expect(r.artUrl, 'https://i.scdn.co/image/abc');
    });

    test('the DJ talking keeps the player up, and says it is the DJ', () {
      // The reply Spotify gives while X is speaking: playing, no item, the DJ
      // playlist as context.
      final r = SpotifyService.readPlayer(
        _reply(
          item: null,
          context: 'spotify:playlist:${SpotifyService.djPlaylistId}',
        ),
      );
      expect(r.kind, PlayerReplyKind.dj);
      expect(r.now.hasTrack, isTrue, reason: 'hasTrack is what keeps it up');
      expect(r.now.isPlaying, isTrue);
      expect(r.now.title, 'DJ X');
      expect(r.now.trackId, isEmpty, reason: 'nothing to like');
      expect(r.now.duration, Duration.zero);
      expect(r.artUrl, isNull, reason: 'keeps the last track’s artwork');
    });

    test('playing with nothing named is still playing', () {
      final r = SpotifyService.readPlayer(
        _reply(item: null, context: 'spotify:playlist:somethingelse'),
      );
      expect(r.kind, PlayerReplyKind.unlabelled);
      expect(r.now.hasTrack, isTrue);
      expect(r.now.isPlaying, isTrue);
    });

    test('paused with nothing named is nothing', () {
      final r = SpotifyService.readPlayer(_reply(item: null, playing: false));
      expect(r.kind, PlayerReplyKind.nothing);
      expect(r.now.hasTrack, isFalse);
    });

    test(
      'a podcast episode names the show, and cannot be liked as a track',
      () {
        final r = SpotifyService.readPlayer(
          _reply(
            item: {
              'type': 'episode',
              'id': 'ep1',
              'name': 'The one about DJs',
              'duration_ms': 3600000,
              'images': [
                {'url': 'https://i.scdn.co/image/ep'},
              ],
              'show': {'name': 'Some Podcast', 'publisher': 'Some Network'},
            },
          ),
        );
        expect(r.kind, PlayerReplyKind.episode);
        expect(r.now.title, 'The one about DJs');
        expect(r.now.artist, 'Some Podcast');
        expect(r.now.trackId, isEmpty);
        expect(r.artUrl, 'https://i.scdn.co/image/ep');
      },
    );

    test("an episode without its own artwork uses the show's", () {
      final r = SpotifyService.readPlayer(
        _reply(
          item: {
            'type': 'episode',
            'name': 'Ep',
            'duration_ms': 1000,
            'show': {
              'name': 'Show',
              'images': [
                {'url': 'https://i.scdn.co/image/show'},
              ],
            },
          },
        ),
      );
      expect(r.artUrl, 'https://i.scdn.co/image/show');
    });
  });

  group('hiding the player', () {
    final t0 = DateTime(2026, 9, 24, 10);

    test('not on the first empty reply', () {
      expect(SpotifyService.emptyLongEnough(t0, t0), isFalse);
    });

    test('not for a gap of a few seconds between tracks', () {
      expect(
        SpotifyService.emptyLongEnough(t0, t0.add(const Duration(seconds: 6))),
        isFalse,
      );
    });

    test('once nothing has played for a while', () {
      expect(
        SpotifyService.emptyLongEnough(t0, t0.add(SpotifyService.emptyGrace)),
        isTrue,
      );
    });

    test('never when nothing has been empty', () {
      expect(SpotifyService.emptyLongEnough(null, t0), isFalse);
    });
  });

  group('a 429 on the player', () {
    test('is not asked again until Retry-After has passed', () async {
      final spotify = _Spotify([429], retryAfter: '3600');
      await spotify.service.pollOnce();
      await spotify.service.pollOnce();
      await spotify.service.pollOnce();
      expect(spotify.playerAsks, 1);
      spotify.service.dispose();
    });

    test('a short block is asked again once it is over', () async {
      final spotify = _Spotify([429, 429]);
      await spotify.service.pollOnce();
      await spotify.service.pollOnce();
      expect(spotify.playerAsks, 2);
      spotify.service.dispose();
    });

    test('slows every poll after it, up to four times', () async {
      final spotify = _Spotify([204, 429, 429, 429]);
      final every = <Duration?>[];
      for (var i = 0; i < 4; i++) {
        await spotify.service.pollOnce();
        every.add(spotify.service.pollEvery);
      }
      expect(every, const [
        Duration(seconds: 15),
        Duration(seconds: 30),
        Duration(seconds: 60),
        Duration(seconds: 60),
      ]);
      spotify.service.dispose();
    });

    test('hides what was playing, for Bluetooth to show instead', () async {
      final spotify = _Spotify([200, 429]);
      await spotify.service.pollOnce();
      expect(spotify.service.available, isTrue);
      expect(spotify.service.now.title, 'Centuries');
      await spotify.service.pollOnce();
      expect(spotify.service.available, isFalse);
      spotify.service.dispose();
    });
  });

  group('how often the player is asked', () {
    test('every five seconds while music plays on a lit screen', () async {
      final spotify = _Spotify([200]);
      await spotify.service.pollOnce();
      expect(spotify.service.pollEvery, const Duration(seconds: 5));
      spotify.service.dispose();
    });

    test('every fifteen while nothing plays', () async {
      final spotify = _Spotify([204]);
      await spotify.service.pollOnce();
      expect(spotify.service.pollEvery, const Duration(seconds: 15));
      spotify.service.dispose();
    });

    test('a tap while an ask is on its way is asked about after it', () async {
      final spotify = _Spotify([200, 200], hold: true);
      final first = spotify.service.pollOnce();
      await spotify.service.next();
      expect(spotify.playerAsks, 1);
      spotify.gate.complete();
      await first;
      await pumpEventQueue();
      expect(spotify.playerAsks, 2);
      spotify.service.dispose();
    });

    test('music starting over Bluetooth asks at once, but not twice', () async {
      final spotify = _Spotify([204, 204]);
      spotify.service.nudge();
      spotify.service.nudge();
      await pumpEventQueue();
      expect(spotify.playerAsks, 1);
      spotify.service.dispose();
    });
  });
}

/// A connected [SpotifyService] whose player polls are answered, in turn,
/// with [statuses]: 200 is a track playing, 204 nothing, 429 a block of
/// [retryAfter] seconds.
class _Spotify implements HttpClientAdapter {
  _Spotify(this.statuses, {this.retryAfter = '0', this.hold = false}) {
    final config = ConfigService();
    config.config.spotify
      ..clientId = 'client'
      ..refreshToken = 'refresh';
    service = SpotifyService(config, dio: Dio()..httpClientAdapter = this);
  }

  final List<int> statuses;
  final String retryAfter;
  late final SpotifyService service;
  int playerAsks = 0;

  /// With [hold], the first player ask is not answered until [gate] is.
  final bool hold;
  final gate = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    const json = {
      Headers.contentTypeHeader: ['application/json'],
    };
    if (options.uri.path.endsWith('/api/token')) {
      return ResponseBody.fromString(
        jsonEncode({'access_token': 'token', 'expires_in': 3600}),
        200,
        headers: json,
      );
    }
    // The liked-status check, and anything else that is not the player.
    if (!options.uri.path.endsWith('/me/player')) {
      return ResponseBody.fromString('[false]', 200, headers: json);
    }
    final ask = playerAsks++;
    if (hold && ask == 0) await gate.future;
    final status = statuses[ask];
    return switch (status) {
      200 => ResponseBody.fromString(
        jsonEncode(_reply(item: _track)),
        200,
        headers: json,
      ),
      204 => ResponseBody.fromString('', 204),
      _ => ResponseBody.fromString(
        '{}',
        status,
        headers: {
          ...json,
          'retry-after': [retryAfter],
        },
      ),
    };
  }

  @override
  void close({bool force = false}) {}
}

// --- Spotify's DJ, podcasts and gaps ---------------------------------------

Map<String, dynamic> _reply({
  Map<String, dynamic>? item,
  bool playing = true,
  String? context,
  int progress = 30000,
}) => {
  'is_playing': playing,
  'progress_ms': progress,
  'repeat_state': 'off',
  'shuffle_state': false,
  'currently_playing_type': 'track',
  'device': {'name': 'Kiosk Connect', 'supports_volume': true},
  'context': context == null ? null : {'uri': context},
  'item': item,
};

final _track = {
  'type': 'track',
  'id': 'track123',
  'name': 'Centuries',
  'duration_ms': 228000,
  'artists': [
    {'name': 'Fall Out Boy'},
  ],
  'album': {
    'name': 'American Beauty/American Psycho',
    'images': [
      {'url': 'https://i.scdn.co/image/abc'},
    ],
  },
};

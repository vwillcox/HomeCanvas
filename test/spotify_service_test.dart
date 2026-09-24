import 'package:flutter_test/flutter_test.dart';
import 'package:immich_kiosk_pi/services/spotify_service.dart';

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
            SpotifyService.repeatStateFrom(state));
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
      final r = SpotifyService.readPlayer(_reply(
          item: null,
          context: 'spotify:playlist:${SpotifyService.djPlaylistId}'));
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
          _reply(item: null, context: 'spotify:playlist:somethingelse'));
      expect(r.kind, PlayerReplyKind.unlabelled);
      expect(r.now.hasTrack, isTrue);
      expect(r.now.isPlaying, isTrue);
    });

    test('paused with nothing named is nothing', () {
      final r = SpotifyService.readPlayer(_reply(item: null, playing: false));
      expect(r.kind, PlayerReplyKind.nothing);
      expect(r.now.hasTrack, isFalse);
    });

    test('a podcast episode names the show, and cannot be liked as a track',
        () {
      final r = SpotifyService.readPlayer(_reply(item: {
        'type': 'episode',
        'id': 'ep1',
        'name': 'The one about DJs',
        'duration_ms': 3600000,
        'images': [
          {'url': 'https://i.scdn.co/image/ep'}
        ],
        'show': {'name': 'Some Podcast', 'publisher': 'Some Network'},
      }));
      expect(r.kind, PlayerReplyKind.episode);
      expect(r.now.title, 'The one about DJs');
      expect(r.now.artist, 'Some Podcast');
      expect(r.now.trackId, isEmpty);
      expect(r.artUrl, 'https://i.scdn.co/image/ep');
    });

    test("an episode without its own artwork uses the show's", () {
      final r = SpotifyService.readPlayer(_reply(item: {
        'type': 'episode',
        'name': 'Ep',
        'duration_ms': 1000,
        'show': {
          'name': 'Show',
          'images': [
            {'url': 'https://i.scdn.co/image/show'}
          ],
        },
      }));
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
          SpotifyService.emptyLongEnough(
              t0, t0.add(const Duration(seconds: 6))),
          isFalse);
    });

    test('once nothing has played for a while', () {
      expect(
          SpotifyService.emptyLongEnough(
              t0, t0.add(SpotifyService.emptyGrace)),
          isTrue);
    });

    test('never when nothing has been empty', () {
      expect(SpotifyService.emptyLongEnough(null, t0), isFalse);
    });
  });
}


// --- Spotify's DJ, podcasts and gaps ---------------------------------------

Map<String, dynamic> _reply({
  Map<String, dynamic>? item,
  bool playing = true,
  String? context,
  int progress = 30000,
}) =>
    {
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
    {'name': 'Fall Out Boy'}
  ],
  'album': {
    'name': 'American Beauty/American Psycho',
    'images': [
      {'url': 'https://i.scdn.co/image/abc'}
    ],
  },
};


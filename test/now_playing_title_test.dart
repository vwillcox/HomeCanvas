import 'package:flutter_test/flutter_test.dart';
import 'package:home_canvas/services/now_playing_service.dart';

/// A Mac playing Spotify over Bluetooth says it is playing and never what:
/// the panel said nothing was playing while music came out of it.
void main() {
  String shown(String title, String status, [String device = 'Mac mini']) =>
      NowPlayingService.shownTitle(title, status, device);

  test('a named track is shown by its name', () {
    expect(shown('Centuries', 'playing'), 'Centuries');
    expect(shown('Centuries', 'paused'), 'Centuries');
  });

  test('playing with nothing named is shown as playing from the device', () {
    expect(shown('', 'playing'), 'Playing from Mac mini');
    expect(shown('Not Provided', 'playing'), 'Playing from Mac mini');
    expect(shown('', 'playing', ''), 'Playing from Bluetooth');
  });

  test('paused or stopped with nothing named is nothing', () {
    expect(shown('', 'paused'), '');
    expect(shown('Not Provided', 'stopped'), 'Not Provided');
    expect(
      const NowPlaying(title: 'Not Provided', status: 'stopped').hasTrack,
      isFalse,
    );
  });

  test('what is shown counts as something to show', () {
    final n = NowPlaying(
      title: shown('', 'playing'),
      status: 'playing',
      deviceName: 'Mac mini',
    );
    expect(n.hasTrack, isTrue);
  });
}

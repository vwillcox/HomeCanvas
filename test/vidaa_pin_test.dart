import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/vidaa_client.dart';

void main() {
  group('a PIN submitted to the television', () {
    VidaaClient client() =>
        VidaaClient(host: '192.0.2.1', uuid: '02:10:ac:92:12:52');

    test('an empty box is no PIN, and does not throw', () async {
      // It used to: int.parse threw out of the tap handler and left the
      // widget's Pair button greyed out until the panel restarted.
      expect(await client().submitPin(''), isNull);
    });

    test('nor is a stray letter', () async {
      expect(await client().submitPin('12a4'), isNull);
    });

    test('with no session it gives up at once, not after twelve seconds', () {
      final sw = Stopwatch()..start();
      return client().submitPin('1234').then((tok) {
        expect(tok, isNull);
        expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
      });
    });

    test('a client that never connected says so', () {
      expect(client().isConnected, isFalse);
      expect(client().refused, isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/http_client.dart';
import 'package:home_canvas/time_format.dart';

void main() {
  test('times as the panel writes them', () {
    final at = DateTime(2026, 3, 4, 7, 5, 9);
    expect(hhmm(at), '07:05');
    expect(isoDay(at), '2026-03-04');
    expect(playTime(const Duration(minutes: 4, seconds: 9)), '04:09');
    expect(
      playTime(const Duration(hours: 1, minutes: 2, seconds: 9)),
      '1:02:09',
    );
  });

  test('an address with nothing round it or after it', () {
    expect(
      trimAddress(' http://homey.local:4859// '),
      'http://homey.local:4859',
    );
    expect(trimAddress('http://10.0.0.5'), 'http://10.0.0.5');
    expect(trimAddress(''), '');
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/tv_service.dart';

/// The power key toggles. Pressed not knowing whether the set was on, at
/// bedtime, it could switch on a set in standby.
void main() {
  PowerStep step(bool on, bool? isOn, {bool canWake = true}) =>
      TvService.powerStep(on, isOn: isOn, canWake: canWake);

  test('already as asked: nothing', () {
    expect(step(true, true), PowerStep.already);
    expect(step(false, false), PowerStep.already);
  });

  test('known otherwise: the key', () {
    expect(step(true, false), PowerStep.key);
    expect(step(false, true), PowerStep.key);
    // With the power known, never the packet as well: it could wake the
    // set as the key went, and the key switch it back.
    expect(step(true, false, canWake: true), PowerStep.key);
  });

  test('not known: never the key for off', () {
    expect(step(false, null), PowerStep.leave);
    expect(step(false, null, canWake: false), PowerStep.leave);
  });

  test('not known: the packet for on, the key only without one', () {
    expect(step(true, null), PowerStep.wake);
    expect(step(true, null, canWake: false), PowerStep.key);
  });
}

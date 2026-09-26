import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/config/app_config.dart';
import 'package:home_canvas/services/brightness_service.dart';
import 'package:home_canvas/services/config_service.dart';

/// The backlight is a sysfs file, so a temporary folder stands in for it,
/// and screen_control.py is pointed at a port nothing listens on — the
/// service then writes the file itself, as it does when that isn't running.
/// Saving is counted rather than done: the real save writes the kiosk's own
/// config, which tests run on the Pi must not touch.
void main() {
  late Directory dir;
  late ConfigService config;
  late int saves;

  BrightnessService make() => BrightnessService(
        config,
        backlightDir: dir.path,
        base: 'http://127.0.0.1:1',
        save: () async => saves++,
      );

  Future<String> panel() async =>
      (await File('${dir.path}/brightness').readAsString()).trim();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('backlight');
    await File('${dir.path}/max_brightness').writeAsString('31\n');
    await File('${dir.path}/brightness').writeAsString('1\n');
    config = ConfigService();
    saves = 0;
  });

  tearDown(() => dir.delete(recursive: true));

  group('the setting', () {
    test('is full brightness until set', () {
      expect(ScreenSettings().brightness, 100);
      expect(ScreenSettings.fromJson({}).brightness, 100);
    });

    test('survives a save and load', () {
      final s = ScreenSettings(brightness: 40);
      expect(ScreenSettings.fromJson(s.toJson()).brightness, 40);
    });

    test('is never loaded too dim to see', () {
      expect(ScreenSettings.fromJson({'brightness': 0}).brightness, 5);
      expect(ScreenSettings.fromJson({'brightness': 250}).brightness, 100);
    });
  });

  group('the panel', () {
    test('is put back to the saved level on start', () async {
      // As systemd leaves it after a shutdown while the screen was asleep.
      config.config.screen.brightness = 60;
      await make().start();
      expect(await panel(), '19'); // 60% of 31
    });

    test('is left dark on start when the screen was switched off', () async {
      await File('${dir.path}/brightness').writeAsString('0\n');
      await make().start();
      expect(await panel(), '0');
    });

    test('follows the slider, and saves once it settles', () async {
      final light = make();
      light.set(20);
      light.set(35);
      light.set(50);
      expect(light.level, 50);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await panel(), '16'); // 50% of 31
      expect(saves, 0);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(saves, 1);
      expect(config.config.screen.brightness, 50);
    });

    test('never goes below the minimum from a slider', () async {
      final light = make();
      light.set(0);
      expect(light.level, BrightnessService.minimum);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await panel(), '2'); // 5% of 31, rounded
    });
  });
}

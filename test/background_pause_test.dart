import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/background_pause.dart';

void main() {
  late List<(int, ProcessSignal)> sent;
  late BackgroundPause pause;

  setUp(() {
    sent = [];
    pause = BackgroundPause(
      names: const ['wf-panel-pi', 'vidaa_remote'],
      find: (name) async => switch (name) {
        'wf-panel-pi' => [101],
        'vidaa_remote' => [202, 203],
        _ => <int>[],
      },
      signal: (pid, signal) {
        sent.add((pid, signal));
        return true;
      },
    );
  });

  test('stops every process of each name, then carries on the same ones',
      () async {
    await pause.pause();
    expect(sent, [
      (101, ProcessSignal.sigstop),
      (202, ProcessSignal.sigstop),
      (203, ProcessSignal.sigstop),
    ]);
    expect(pause.paused, isTrue);

    sent.clear();
    await pause.resume();
    expect(sent.map((s) => s.$1), unorderedEquals([101, 202, 203]));
    expect(sent.every((s) => s.$2 == ProcessSignal.sigcont), isTrue);
    expect(pause.paused, isFalse);
  });

  test('resuming with nothing paused does nothing', () async {
    await pause.resume();
    expect(sent, isEmpty);
  });

  test('at start-up, carries on anything left stopped', () async {
    await pause.resume(all: true);
    expect(sent.map((s) => s.$1), unorderedEquals([101, 202, 203]));
    expect(sent.every((s) => s.$2 == ProcessSignal.sigcont), isTrue);
  });

  test('a process that has gone is not remembered as paused', () async {
    final gone = BackgroundPause(
      names: const ['x'],
      find: (_) async => [7],
      signal: (_, _) => false,
    );
    await gone.pause();
    expect(gone.paused, isFalse);
  });
}

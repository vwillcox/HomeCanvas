import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/voice_service.dart';

void main() {
  late StreamController<String> lines;
  late int opened;
  late int stopped;
  late bool on;
  late int wakes;
  late List<String> acted;
  late VoiceService voice;

  Future<VoiceListener> open() async {
    opened++;
    lines = StreamController<String>();
    return VoiceListener(
    lines: lines.stream,
    stop: () async => stopped++,
    );
  }

  setUp(() {
    opened = 0;
    stopped = 0;
    on = false;
    wakes = 0;
    acted = [];
    voice = VoiceService(
    enabled: () => on,
    act: (heard) {
      acted.add(heard);
      return heard.contains('stocks') ? 'page 7' : null;
    },
    onWake: () => wakes++,
    open: open,
    );
  });

  testWidgets('nothing runs, and no microphone is open, until it is switched on', (tester) async {
    voice.sync();
    await tester.pump();
    expect(opened, 0);
    expect(voice.status, VoiceStatus.off);

    on = true;
    voice.sync();
    await tester.pump();
    expect(opened, 1);
    expect(voice.status, VoiceStatus.starting);
    lines.add('{"event": "ready"}');
    await tester.pump();
    expect(voice.status, VoiceStatus.listening);
  });

  testWidgets('switching it off stops the listener', (tester) async {
    on = true;
    voice.sync();
    await tester.pump();
    on = false;
    voice.sync();
    await tester.pump();
    expect(stopped, 1);
    expect(voice.status, VoiceStatus.off);
    // And it stays stopped.
    await tester.pump(const Duration(minutes: 5));
    expect(opened, 1);
  });

  testWidgets('the wake words, then what was said, done and shown a while', (tester) async {
    on = true;
    voice.sync();
    await tester.pump();
    lines.add('{"event": "ready"}');
    lines.add('{"event": "wake"}');
    await tester.pump();
    expect(voice.status, VoiceStatus.awake);
    expect(wakes, 1);
    expect(acted, isEmpty);

    lines.add('{"event": "heard", "text": "hey canvas show stocks"}');
    await tester.pump();
    expect(acted, ['hey canvas show stocks']);
    expect(voice.status, VoiceStatus.done);
    expect(voice.heard, 'hey canvas show stocks');

    await tester.pump(const Duration(seconds: 5));
    expect(voice.status, VoiceStatus.listening);
  });

  testWidgets('says so when what was said meant nothing, or was nothing', (tester) async {
    on = true;
    voice.sync();
    await tester.pump();
    lines.add('{"event": "wake"}');
    lines.add('{"event": "heard", "text": "make the tea"}');
    await tester.pump();
    expect(voice.status, VoiceStatus.missed);

    lines.add('{"event": "wake"}');
    lines.add('{"event": "heard", "text": ""}');
    await tester.pump();
    expect(voice.status, VoiceStatus.missed);
    expect(acted, ['make the tea'], reason: 'nothing is not acted on');
    // What was heard is still on show; put away with the service.
    voice.dispose();
  });

  testWidgets('tries the second hearing when the first means nothing', (tester) async {
    on = true;
    voice.sync();
    await tester.pump();
    lines.add('{"event": "wake"}');
    lines.add('{"event": "heard", "text": "hey canvas show socks", "other": "hey canvas show stocks"}');
    await tester.pump();
    expect(acted, ['hey canvas show socks', 'hey canvas show stocks']);
    expect(voice.status, VoiceStatus.done);
    expect(voice.heard, 'hey canvas show stocks');
    voice.dispose();
  });

  testWidgets('what it makes nothing of is asked elsewhere, and the answer shown', (tester) async {
    final asked = <String>[];
    final ha = VoiceService(
      enabled: () => true,
      act: (_) => null,
      ask: (heard) async {
        asked.add(heard);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return heard.contains('lamp') ? 'Turned on the lamp' : null;
      },
      open: open,
    );
    ha.sync();
    await tester.pump();
    lines.add('{"event": "wake"}');
    lines.add('{"event": "heard", "text": "hey canvas turn on the lump", "other": "hey canvas turn on the lamp"}');
    await tester.pump();
    expect(ha.status, VoiceStatus.asking);
    await tester.pump(const Duration(milliseconds: 250));
    expect(asked, ['hey canvas turn on the lump', 'hey canvas turn on the lamp']);
    expect(ha.status, VoiceStatus.done);
    expect(ha.heard, 'hey canvas turn on the lamp');
    expect(ha.answer, 'Turned on the lamp');
    // An answer is up longer than words alone, to be read.
    await tester.pump(const Duration(seconds: 5));
    expect(ha.status, VoiceStatus.done);
    await tester.pump(const Duration(seconds: 4));
    expect(ha.status, VoiceStatus.listening);

    lines.add('{"event": "heard", "text": "make the tea"}');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(ha.status, VoiceStatus.missed);
    expect(ha.answer, isEmpty);
    ha.dispose();
  });

  testWidgets('an answer that comes back after something newer is dropped', (tester) async {
    final ha = VoiceService(
      enabled: () => true,
      act: (heard) => heard == 'next page' ? 'next page' : null,
      ask: (heard) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return 'Turned on the lamp';
      },
      open: open,
    );
    ha.sync();
    await tester.pump();
    lines.add('{"event": "heard", "text": "turn on the lamp"}');
    await tester.pump();
    lines.add('{"event": "heard", "text": "next page"}');
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(ha.heard, 'next page');
    expect(ha.answer, isEmpty);
    ha.dispose();
  });

  testWidgets('a listener that dies is started again, while it is wanted', (tester) async {
    on = true;
    voice.sync();
    await tester.pump();
    lines.add('{"event": "ready"}');
    lines.add('{"event": "error", "message": "the microphone stopped"}');
    await tester.pump();
    unawaited(lines.close());
    await tester.pump();
    expect(voice.status, VoiceStatus.starting);
    expect(voice.error, isNotNull);

    await tester.pump(const Duration(seconds: 10));
    expect(opened, 2);
  });

  testWidgets('nothing installed to listen with is said once, not retried', (tester) async {
    final none = VoiceService(
      enabled: () => true,
      act: (_) => null,
      open: () async {
        opened++;
        throw const ProcessException('python', [], 'not installed');
      },
    );
    none.sync();
    await tester.pump();
    expect(none.status, VoiceStatus.unavailable);
    await tester.pump(const Duration(minutes: 10));
    expect(opened, 1);
  });

  testWidgets('what a library prints is not mistaken for something heard', (tester) async {
    on = true;
    voice.sync();
    await tester.pump();
    lines.add('onnxruntime: some warning');
    lines.add('[1, 2, 3]');
    lines.add('{"event": "ready"}');
    await tester.pump();
    expect(voice.status, VoiceStatus.listening);
    expect(acted, isEmpty);
  });
}

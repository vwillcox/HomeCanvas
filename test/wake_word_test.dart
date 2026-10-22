import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/voice_commands.dart';
import 'package:home_canvas/services/wake_word.dart';

void main() {
  // The same cases deploy/test_wake_word.py checks the listener against.
  final fixture =
      jsonDecode(File('test/fixtures/wake_words.json').readAsStringSync())
          as Map<String, dynamic>;
  final wakes = fixture['wakes'] as Map<String, dynamic>;

  group('agrees with the listener', () {
    for (final c in fixture['cases'] as List) {
      final [name as String, text as String, want as int] = c as List;
      test('$name: "$text"', () {
        expect(WakeWord.fromJson(wakes[name]).ends(text), want);
      });
    }
  });

  test('the default is hey canvas, with its lookalikes', () {
    final wake = WakeWord();
    expect(wake.phrase, 'hey canvas');
    expect(wake.lookalikes, contains('campus'));
    expect(WakeWord.fromJson(null).phrase, 'hey canvas');
    expect(WakeWord.fromJson({'phrase': '!!'}).phrase, 'hey canvas');
  });

  test('another phrase starts with nothing learned, and round-trips', () {
    final wake = WakeWord(phrase: 'Hey, Jarvis!');
    expect(wake.toJson(), {
      'phrase': 'hey jarvis',
      'lookalikes': <String>[],
      'variants': <String>[],
    });
    final learned = WakeWord(
      phrase: 'hey jarvis',
      lookalikes: ['service'],
      variants: ['hijarvis'],
    );
    expect(WakeWord.fromJson(learned.toJson()).toJson(), learned.toJson());
  });

  test('a chosen wake word is taken off before Home Assistant is asked', () {
    final jarvis = WakeWord.fromJson(wakes['jarvis']);
    expect(
      VoiceCommands.forAssist('Hey Jarvis, turn off the lamp.', wake: jarvis),
      'turn off the lamp.',
    );
    expect(
      VoiceCommands.forAssist('hey service term the fan off', wake: jarvis),
      'turn the fan off',
    );
    // "Hey canvas" is just words, to a panel woken by something else.
    expect(
      VoiceCommands.forAssist('hey canvas lights off', wake: jarvis),
      'hey canvas lights off',
    );
  });

  test('and passed over before a command is looked for', () {
    final panel = VoiceCommands(
      pageCount: 1,
      pages: const [],
      widgets: const [],
      wake: WakeWord(phrase: 'computer'),
    );
    expect(panel.resolve('computer next page'), isA<VoiceTurnPage>());
    expect(panel.resolve('computer, pause'), isA<VoiceMusic>());
  });
}

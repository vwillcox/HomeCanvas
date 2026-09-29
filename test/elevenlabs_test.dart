import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/elevenlabs_tts.dart';

/// Answers every request with [status], and remembers what was asked.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status);
  int status;
  final asked = <RequestOptions>[];
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options);
    bodies.add(Map<String, dynamic>.from(options.data as Map));
    return ResponseBody.fromBytes(
      status == 200 ? utf8.encode('ID3 fake mp3') : utf8.encode('{}'),
      status,
      headers: {
        Headers.contentTypeHeader: [
          status == 200 ? 'audio/mpeg' : 'application/json',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('asks for the voice with the key, and hands back an MP3', () async {
    final adapter = _Adapter(200);
    final tts = ElevenLabsTts(
      dio: Dio(BaseOptions(responseType: ResponseType.bytes))
        ..httpClientAdapter = adapter,
    );
    final f = await tts.synthesise(
      'Hello there.',
      const ElevenLabsVoice(apiKey: ' key ', voiceId: 'abcDEF123456'),
      speed: 1.5,
    );
    expect(f, isNotNull);
    expect(f!.path, endsWith('.mp3'));
    await f.delete();
    final asked = adapter.asked.single;
    expect(asked.uri.path, '/v1/text-to-speech/abcDEF123456');
    expect(asked.headers['xi-api-key'], 'key');
    expect(adapter.bodies.single['text'], 'Hello there.');
    expect(adapter.bodies.single['model_id'], kElevenLabsDefaultModel);
    // Held to what ElevenLabs allows.
    expect(adapter.bodies.single['voice_settings']['speed'], 1.2);
  });

  test('a voice id that is not one falls back to the default', () async {
    final adapter = _Adapter(200);
    final tts = ElevenLabsTts(dio: Dio()..httpClientAdapter = adapter);
    final f = await tts.synthesise(
      'Hi.',
      const ElevenLabsVoice(apiKey: 'k', voiceId: '../../user'),
    );
    await f?.delete();
    expect(
      adapter.asked.single.uri.path,
      '/v1/text-to-speech/$kElevenLabsDefaultVoice',
    );
  });

  test(
    'a refused key is left alone rather than asked every paragraph',
    () async {
      final adapter = _Adapter(401);
      final tts = ElevenLabsTts(dio: Dio()..httpClientAdapter = adapter);
      const voice = ElevenLabsVoice(apiKey: 'bad');
      expect(await tts.synthesise('One.', voice), isNull);
      expect(await tts.synthesise('Two.', voice), isNull);
      expect(adapter.asked, hasLength(1));
    },
  );

  test('no key, no request', () async {
    final adapter = _Adapter(200);
    final tts = ElevenLabsTts(dio: Dio()..httpClientAdapter = adapter);
    expect(
      await tts.synthesise('Hi.', const ElevenLabsVoice(apiKey: '')),
      isNull,
    );
    expect(adapter.asked, isEmpty);
  });
}

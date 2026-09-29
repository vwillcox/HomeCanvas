import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Which ElevenLabs voice to read in, from the news widget's settings.
@immutable
class ElevenLabsVoice {
  const ElevenLabsVoice({
    required this.apiKey,
    this.voiceId = kElevenLabsDefaultVoice,
    this.model = kElevenLabsDefaultModel,
  });

  final String apiKey;
  final String voiceId;
  final String model;

  @override
  bool operator ==(Object other) =>
      other is ElevenLabsVoice &&
      other.apiKey == apiKey &&
      other.voiceId == voiceId &&
      other.model == model;

  @override
  int get hashCode => Object.hash(apiKey, voiceId, model);
}

/// George: a warm British narrator, one of the voices every account has.
const kElevenLabsDefaultVoice = 'JBFqnCBsd6RMkjVDRZzb';

/// Flash: quick to start, and half the credits of the others.
const kElevenLabsDefaultModel = 'eleven_flash_v2_5';

/// Speech from ElevenLabs, for anyone who would rather hear a studio voice
/// than piper's and has an account. Piper stays the default: it is free,
/// works without the internet, and sends nothing anywhere.
///
/// Each piece of text goes to ElevenLabs and comes back as an MP3. A key
/// that is turned away, or an account out of credits, is left alone for a
/// while rather than asked again for every paragraph; the reader falls back
/// to piper meanwhile.
class ElevenLabsTts {
  ElevenLabsTts({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              responseType: ResponseType.bytes,
            ),
          );

  final Dio _dio;
  static const _base = 'https://api.elevenlabs.io/v1';

  /// Until when a key is being left alone, after it was refused.
  final Map<String, DateTime> _restingUntil = {};

  /// A voice id as ElevenLabs writes them: letters and digits, nothing that
  /// could climb out of the URL's path.
  static bool validVoiceId(String id) =>
      RegExp(r'^[A-Za-z0-9]{8,40}$').hasMatch(id);

  /// [text] as an MP3 in a temporary file the caller deletes, or null if it
  /// could not be made. [speed] is held to the 0.7–1.2 ElevenLabs allows.
  Future<File?> synthesise(
    String text,
    ElevenLabsVoice voice, {
    double speed = 1,
  }) async {
    final key = voice.apiKey.trim();
    if (text.trim().isEmpty || key.isEmpty) return null;
    final resting = _restingUntil[key];
    if (resting != null && DateTime.now().isBefore(resting)) return null;
    final id = validVoiceId(voice.voiceId.trim())
        ? voice.voiceId.trim()
        : kElevenLabsDefaultVoice;
    try {
      final r = await _dio.post<List<int>>(
        '$_base/text-to-speech/$id',
        queryParameters: {'output_format': 'mp3_44100_128'},
        options: Options(
          headers: {'xi-api-key': key, 'Accept': 'audio/mpeg'},
          contentType: Headers.jsonContentType,
        ),
        data: {
          'text': text,
          'model_id': voice.model,
          'voice_settings': {
            'stability': 0.5,
            'similarity_boost': 0.75,
            'speed': speed.clamp(0.7, 1.2),
          },
        },
      );
      final bytes = r.data;
      if (bytes == null || bytes.isEmpty) return null;
      final mp3 = File(
        '${Directory.systemTemp.path}/kiosk-11labs-${DateTime.now().microsecondsSinceEpoch}.mp3',
      );
      await mp3.writeAsBytes(bytes, flush: true);
      return mp3;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final why = switch (code) {
        401 => 'the API key was turned away',
        402 || 429 => 'out of credits, or too many requests',
        404 => 'no voice with that id',
        _ => '${code ?? e.type}',
      };
      debugPrint('ElevenLabs: $why — piper instead');
      // A refused key or an empty account won't mend itself in a minute;
      // a busy moment might.
      if (code == 401 || code == 402) {
        _restingUntil[key] = DateTime.now().add(const Duration(minutes: 30));
      } else if (code == 429) {
        _restingUntil[key] = DateTime.now().add(const Duration(minutes: 2));
      }
      return null;
    } catch (e) {
      debugPrint('ElevenLabs: $e — piper instead');
      return null;
    }
  }
}

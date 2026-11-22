import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/config/app_config.dart';
import 'package:home_canvas/services/art_matrix_service.dart';

/// The Art Matrix's HTTP side, as its firmware has it: `/display`, on and
/// off and a brightness 1 to 100, answered with the display as it now is.
/// Nothing here goes near a real one.
class _Display implements HttpClientAdapter {
  final List<String> asked = [];
  var on = true;
  var brightness = 100;

  /// Nothing answering at all.
  var gone = false;

  /// Something else at the address, answering in its own way.
  String? other;

  /// Answered without a JSON content type.
  var asText = false;

  /// Every request turned away, as a bad value is.
  var refuse = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri;
    asked.add('${options.method} ${uri.authority}${uri.path}?${uri.query}');
    if (gone) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'No route to host',
      );
    }
    if (other != null) return ResponseBody.fromString(other!, 200);
    if (refuse) return _text('Bad request', 400);
    if (uri.path != '/display') return _text('Not found', 404);
    final q = uri.queryParameters;
    if (q['brightness'] case final b?) {
      final n = int.tryParse(b);
      if (n == null || n < 1 || n > 100) return _text('Bad brightness', 400);
      brightness = n;
      on = true;
    }
    if (q['on'] case final o?) {
      final want = switch (o) {
        '1' || 'true' || 'on' => true,
        '0' || 'false' || 'off' => false,
        _ => null,
      };
      if (want == null) return _text('Bad on', 400);
      on = want;
    }
    final body = jsonEncode({'on': on, 'brightness': brightness});
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [
          asText ? 'text/plain' : Headers.jsonContentType,
        ],
      },
    );
  }

  static ResponseBody _text(String body, int status) => ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: ['text/plain'],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Display display;
  late ArtMatrixSettings settings;
  late List<String> looked;
  late List<InternetAddress> found;

  ArtMatrixService service() => ArtMatrixService(
    () => settings,
    dio: Dio()..httpClientAdapter = display,
    lookup: (host) async {
      looked.add(host);
      return found;
    },
  );

  setUp(() {
    display = _Display();
    settings = ArtMatrixSettings(enabled: true, host: 'arty.local');
    looked = [];
    found = [InternetAddress('192.168.1.60')];
  });

  test('off and on, at the address its name stands for', () async {
    final art = service();
    expect(await art.setPower(false), ArtMatrixResult.done);
    expect(display.on, isFalse);
    expect(await art.setPower(true), ArtMatrixResult.done);
    expect(display.on, isTrue);
    expect(looked, ['arty.local', 'arty.local']);
    expect(display.asked, [
      'POST 192.168.1.60/display?on=0',
      'POST 192.168.1.60/display?on=1',
    ]);
  });

  test('a brightness is kept, puts it on, and is kept to 1 to 100', () async {
    final art = service();
    display.on = false;
    expect(await art.setBrightness(40), ArtMatrixResult.done);
    expect((display.on, display.brightness), (true, 40));
    expect(await art.setBrightness(0), ArtMatrixResult.done);
    expect(display.brightness, 1);
    expect(await art.setBrightness(250), ArtMatrixResult.done);
    expect(display.brightness, 100);
    expect(display.asked, [
      'POST 192.168.1.60/display?brightness=40&on=1',
      'POST 192.168.1.60/display?brightness=1&on=1',
      'POST 192.168.1.60/display?brightness=100&on=1',
    ]);
  });

  test('an address given as one is not looked up; a port is kept', () async {
    settings.host = '192.168.1.61:8080';
    expect(await service().setPower(true), ArtMatrixResult.done);
    expect(looked, isEmpty);
    expect(display.asked, ['POST 192.168.1.61:8080/display?on=1']);
  });

  test('not set up: nothing asked', () async {
    settings.enabled = false;
    expect(await service().setPower(true), ArtMatrixResult.notSetUp);
    settings
      ..enabled = true
      ..host = '';
    expect(await service().setBrightness(40), ArtMatrixResult.notSetUp);
    expect(looked, isEmpty);
    expect(display.asked, isEmpty);
  });

  test('not on the home network: nothing sent', () async {
    found = [InternetAddress('203.0.113.7')];
    expect(await service().setPower(false), ArtMatrixResult.notLocal);
    found = [InternetAddress('192.168.1.60'), InternetAddress('203.0.113.7')];
    expect(await service().setPower(false), ArtMatrixResult.notLocal);
    settings.host = '203.0.113.7';
    expect(await service().setPower(false), ArtMatrixResult.notLocal);
    expect(display.asked, isEmpty);
  });

  test('nothing answering, or no such name', () async {
    display.gone = true;
    expect(await service().setPower(true), ArtMatrixResult.unreachable);
    found = [];
    expect(await service().setPower(true), ArtMatrixResult.unreachable);
    final art = ArtMatrixService(
      () => settings,
      dio: Dio()..httpClientAdapter = display,
      lookup: (host) async =>
          throw const SocketException('Failed host lookup: arty.local'),
    );
    expect(await art.setBrightness(40), ArtMatrixResult.unreachable);
    expect(display.asked, hasLength(1));
  });

  test('a refusal, or something else at the address', () async {
    display.refuse = true;
    expect(await service().setBrightness(40), ArtMatrixResult.refused);
    display
      ..refuse = false
      ..other = '<html>Router login</html>';
    expect(await service().setPower(true), ArtMatrixResult.refused);
    // An answer, but not off as asked.
    display.other = jsonEncode({'on': true});
    expect(await service().setPower(false), ArtMatrixResult.refused);
  });

  test('its answer read as JSON whatever it is labelled', () async {
    display.asText = true;
    expect(await service().setPower(false), ArtMatrixResult.done);
  });
}

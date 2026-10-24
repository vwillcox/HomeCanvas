import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/audio_levels_service.dart';
import 'package:home_canvas/services/radio_service.dart';
import 'package:home_canvas/services/seven_fm.dart';

import 'new_widgets_fit_test.dart' show tile;

/// A station that cannot be reached.
class _Gone extends Interceptor {
  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler handler) =>
      handler.reject(DioException(requestOptions: o, message: 'offline'));
}

/// Answers as the station would, without the network.
class _Station extends Interceptor {
  _Station(this.now);

  final DateTime now;

  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler handler) {
    final started = now.subtract(const Duration(minutes: 2)).toUtc();
    final body = o.path.endsWith('now-playing.php')
        ? '{"schema_version":1,"status":"playing",'
              '"generated_at":"${now.toUtc().toIso8601String()}",'
              '"refresh_after_seconds":10,"track":{"play_id":"1",'
              '"title":"The Spirit Of Man And Everything After It, Extended",'
              '"artist":"Jeff Wayne","album":"Jeff Wayne\'s Musical Version '
              'Of The War Of The Worlds","started_at":"'
              '${started.toIso8601String()}","duration_seconds":697.9}}'
        : '[${List.filled(10, '{"Artist":"Kenji Kawai","Album":"Fate/Stay '
          'Night","Track":"Holy Grail Of A Very Long Name","RequestedBy":'
          '"GusGus1388"}').join(',')}]';
    handler.resolve(Response(requestOptions: o, data: body, statusCode: 200));
  }
}

/// The StreamingSoundtracks tile, before and after the station answers, in
/// every theme and size — without overflowing or throwing.
void main() {
  setUpAll(registerBuiltInWidgets);

  const sizes = [(12, 8), (6, 4), (4, 3), (4, 2), (2, 1), (12, 1), (2, 8)];

  final levels = AudioLevelsService(
    open: () async => PcmStream(bytes: const Stream.empty(), stop: () async {}),
  );

  for (final answered in [false, true]) {
    testWidgets('fits, ${answered ? 'with a track' : 'before one'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final radio = RadioService();
      final dio = Dio()..interceptors.add(_Station(DateTime.now()));
      final seven = SevenFmService(
        dio: answered ? dio : (Dio()..interceptors.add(_Gone())),
      );
      if (answered) radio.debugPlaying(sevenStation('sst').radio);

      for (final theme in kBuiltInThemes) {
        for (final (cw, ch) in sizes) {
          final w = DashboardWidgetContext(
            theme: theme,
            config: DashboardWidgetConfig(
              id: 'w',
              type: 'sevenFm',
              x: 0,
              y: 0,
              width: 4,
              height: 2,
            ),
          );
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: radio),
                ChangeNotifierProvider.value(value: levels),
                Provider.value(value: seven),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox.fromSize(
                      size: tile(cw, ch),
                      child: Builder(
                        builder: (context) =>
                            WidgetRegistry.find('sevenFm')!.build(context, w),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(() => Future.delayed(Duration.zero));
          await tester.pump(const Duration(milliseconds: 50));
          final e = tester.takeException();
          expect(e, isNull, reason: '${theme.id}, $cw × $ch: $e');
        }
      }
      await tester.pumpWidget(const SizedBox());
      radio.dispose();
    });
  }
}

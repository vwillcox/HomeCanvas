import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/custom_widget_spec.dart';
import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/code_widgets.dart';
import 'package:home_canvas/services/custom_widgets.dart';

import 'new_widgets_fit_test.dart' show shapes, tile;

/// The example the editor hands out, as it is on disk.
final _example = File(
  'assets/dashboard/example-widget.json',
).readAsStringSync();

/// What the example's source answers with.
const _sea = {
  'current': {
    'time': '2026-10-04T12:45',
    'sea_level_height_msl': -1.17,
    'wave_height': 0.04,
    'sea_surface_temperature': 18.9,
  },
};

String _spec(Map<String, dynamic> changes) =>
    jsonEncode({...jsonDecode(_example) as Map<String, dynamic>, ...changes});

/// A source: answers every address with [body], and remembers what was
/// asked for.
class _Source implements HttpClientAdapter {
  Object body = _sea;
  int status = 200;
  final List<Uri> asked = [];
  final List<Map<String, dynamic>> headers = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options.uri);
    headers.add(options.headers);
    return ResponseBody.fromString(
      body is String ? body as String : jsonEncode(body),
      status,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('a custom widget\'s file', () {
    test(
      'the example is read: what it is, its settings, source and layout',
      () {
        final spec = CustomWidgetSpec.parse(_example);
        expect(spec.id, 'sea_state');
        expect(spec.type, 'custom_sea_state');
        expect(spec.name, 'Sea state');
        expect(spec.options.map((o) => o.key), [
          'place',
          'latitude',
          'longitude',
        ]);
        expect(spec.options[1].kind, OptionKind.number);
        expect(spec.options[1].defaultValue, 51.95);
        expect(spec.every, const Duration(minutes: 15));
        expect(spec.show.layout, CustomLayout.cards);
        expect(spec.show.cards.length, 4);
        expect(spec.source, _example);
      },
    );

    test('what is wrong with a file is said in words', () {
      String wrong(String source) {
        try {
          CustomWidgetSpec.parse(source);
        } on FormatException catch (e) {
          return e.message;
        }
        return 'accepted';
      }

      expect(wrong('{not json'), startsWith('Not valid JSON'));
      expect(wrong('[]'), 'The file must be a JSON object.');
      expect(wrong(_spec({'type': 'Sea State'})), contains('lower-case'));
      expect(wrong(_spec({'name': ''})), '"name" is needed, as text.');
      expect(wrong(_spec({'defaultWidth': 40})), contains('1 to 12'));
      expect(
        wrong(
          _spec({
            'source': {'url': 'file:///etc/passwd'},
          }),
        ),
        contains('http://'),
      );
      expect(
        wrong(
          _spec({
            'show': {'kind': 'chart'},
          }),
        ),
        '"show.kind" must be value, cards or list.',
      );
      expect(
        wrong(
          _spec({
            'options': [
              {'key': 'rows', 'kind': 'list'},
            ],
          }),
        ),
        contains('"kind" must be one of'),
      );
      expect(wrong('{"type":"${'a' * 70000}"}'), 'The file is over 64 KB.');
    });

    test(
      'a type already prefixed is not prefixed twice; the least is kept',
      () {
        final spec = CustomWidgetSpec.parse(
          _spec({
            'type': 'custom_sea_state',
            'source': {'url': 'http://tides.local/now', 'every': 1},
          }),
        );
        expect(spec.type, 'custom_sea_state');
        expect(spec.every, const Duration(seconds: 30));
      },
    );
  });

  group('templates', () {
    const data = {
      'current': {'level': -1.168, 'cloud': 0.42, 'at': '2026-10-04T07:05:00'},
      'rows': [
        {'name': 'High', 'height': 3.0},
        {'name': 'Low'},
      ],
    };

    test('reach into the answer, the settings and the row', () {
      expect(customFill('{{current.level}} m', data: data), '-1.168 m');
      expect(
        customFill('{{rows[1].name}}/{{rows.0.name}}', data: data),
        'Low/High',
      );
      expect(
        customFill('{{option.place}}', options: {'place': 'Harwich'}),
        'Harwich',
      );
      expect(customFill('{{item.name}}', item: {'name': 'High'}), 'High');
      expect(customFill('{{item}}', item: 'plain'), 'plain');
      expect(customFill('no braces'), 'no braces');
    });

    test('are shaped by what follows the bar', () {
      expect(customFill('{{current.level | number:2}}', data: data), '-1.17');
      expect(customFill('{{current.level | round}}', data: data), '-1');
      expect(customFill('{{current.cloud | percent}}', data: data), '42%');
      expect(
        customFill('{{current.cloud | times:100 | number:0}}', data: data),
        '42',
      );
      expect(customFill('{{rows[0].height}}', data: data), '3');
      expect(customFill('{{current.at | time}}', data: data), '07:05');
      expect(customFill('{{current.at | date}}', data: data), '4 Oct');
      expect(customFill('{{rows[0].name | upper}}', data: data), 'HIGH');
    });

    test('what is missing is a dash, or what the file says instead', () {
      expect(customFill('{{current.nothing}}', data: data), '—');
      expect(customFill('{{rows[9].name | number:1}}', data: data), '—');
      expect(
        customFill('{{rows[1].height | or:unknown}}', data: data),
        'unknown',
      );
      expect(customFill('{{current.level.deeper}}', data: data), '—');
    });

    test('in an address, are made safe for one', () {
      expect(
        customFill(
          'https://x.example/?q={{option.place}}&n={{option.none}}',
          options: {'place': 'Lyme Regis & Charmouth'},
          encode: true,
        ),
        'https://x.example/?q=Lyme+Regis+%26+Charmouth&n=',
      );
    });
  });

  group('installing', () {
    late Directory dir;
    late _Source source;
    late CustomWidgets custom;
    var redrawn = 0;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('custom');
      source = _Source();
      redrawn = 0;
      custom = CustomWidgets(
        dir: dir.path,
        dio: Dio()..httpClientAdapter = source,
        onChanged: () => redrawn++,
      );
    });
    tearDown(() {
      for (final s in custom.all) {
        WidgetRegistry.unregister(s.type);
      }
      custom.dispose();
      dir.deleteSync(recursive: true);
    });

    test(
      'a file is kept, and is a widget at once — and after a restart',
      () async {
        expect(WidgetRegistry.find('custom_sea_state'), isNull);
        await custom.install(_example);
        expect(redrawn, 1);
        final type = WidgetRegistry.find('custom_sea_state')!;
        expect(type.name, 'Sea state');
        expect(type.category, WidgetCategory.custom);
        expect(
          WidgetRegistry.defaultsFor('custom_sea_state')['place'],
          'Harwich',
        );
        expect(File('${dir.path}/sea_state.json').readAsStringSync(), _example);

        // Uploaded again, changed: the one widget, as it now is.
        await custom.install(_spec({'name': 'The sea'}));
        expect(custom.all.single.name, 'The sea');
        expect(WidgetRegistry.find('custom_sea_state')!.name, 'The sea');

        // The panel starting again finds it in the folder.
        WidgetRegistry.unregister('custom_sea_state');
        File('${dir.path}/broken.json').writeAsStringSync('{');
        final again = CustomWidgets(dir: dir.path);
        await again.load();
        expect(again.all.single.name, 'The sea');
        expect(WidgetRegistry.find('custom_sea_state'), isNotNull);
        again.dispose();
      },
    );

    test('a file that is wrong is refused, and nothing is kept', () async {
      await expectLater(
        custom.install(_spec({'show': {}})),
        throwsA(isA<FormatException>()),
      );
      expect(custom.all, isEmpty);
      expect(dir.listSync(), isEmpty);
      expect(redrawn, 0);
    });

    test('removing one takes it out of the registry and the folder', () async {
      await custom.install(_example);
      expect(await custom.remove('sea_state'), isTrue);
      expect(WidgetRegistry.find('custom_sea_state'), isNull);
      expect(dir.listSync(), isEmpty);
      expect(await custom.remove('sea_state'), isFalse);
      expect(redrawn, 2);
    });

    test('a built-in widget cannot be replaced by an upload', () async {
      registerBuiltInWidgets();
      final clock = WidgetRegistry.find('clock');
      await custom.install(_spec({'type': 'clock'}));
      expect(WidgetRegistry.find('clock'), same(clock));
      expect(WidgetRegistry.find('custom_clock'), isNotNull);
    });

    test('its source is fetched once, kept, and its failures said', () async {
      const url = 'https://sea.example/now';
      await custom.ensure(url, headers: {'X-Key': 'k'});
      expect(
        customLookup(custom.answer(url)!.data, 'current.wave_height'),
        0.04,
      );
      expect(source.headers.single['X-Key'], 'k');
      await custom.ensure(url);
      expect(source.asked.length, 1);

      // Gone wrong later: the last answer stays, with why.
      source.status = 503;
      await custom.ensure(url, every: Duration.zero);
      expect(custom.answer(url)!.error, 'Its source answered 503.');
      expect(custom.answer(url)!.data, isNotNull);

      source
        ..status = 200
        ..body = '<html>not json</html>';
      await custom.ensure('https://sea.example/page');
      expect(
        custom.answer('https://sea.example/page')!.error,
        'Its source did not send JSON.',
      );

      await custom.ensure('ftp://sea.example/now');
      expect(source.asked.length, 3);
      expect(
        custom.answer('ftp://sea.example/now')!.error,
        'Its address is not one to fetch.',
      );
    });
  });

  group('the tile', () {
    late Directory dir;
    late CustomWidgets custom;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('custom');
      custom = CustomWidgets(dir: dir.path);
    });
    tearDown(() {
      for (final s in custom.all) {
        WidgetRegistry.unregister(s.type);
      }
      custom.dispose();
      dir.deleteSync(recursive: true);
    });

    Future<void> draw(
      WidgetTester tester,
      String type,
      Size size, [
      Map<String, dynamic>? options,
    ]) {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final w = DashboardWidgetContext(
        theme: kBuiltInThemes.first,
        config: DashboardWidgetConfig(
          id: 'w',
          type: type,
          x: 0,
          y: 0,
          width: 3,
          height: 2,
          options: options,
        ),
      );
      return tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: custom,
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                  size: size,
                  child: Builder(
                    builder: (context) =>
                        WidgetRegistry.find(type)!.build(context, w),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> sweep(WidgetTester tester, String type) async {
      for (final (cols, rows) in shapes) {
        await draw(tester, type, tile(cols, rows));
        await tester.pump(const Duration(milliseconds: 50));
        final e = tester.takeException();
        expect(e, isNull, reason: '$type at $cols × $rows: $e');
      }
      await draw(tester, type, tile(3, 2));
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('the example: cards from its source, at every size', (
      tester,
    ) async {
      await tester.runAsync(() => custom.install(_example));
      custom.debugAnswer(
        'https://marine-api.open-meteo.com/v1/marine?latitude=51.95'
        '&longitude=1.29&current=sea_level_height_msl,wave_height,'
        'sea_surface_temperature&timezone=auto',
        _sea,
      );
      await sweep(tester, 'custom_sea_state');
      expect(find.text('Harwich'), findsOneWidget);
      expect(find.text('-1.17 m'), findsOneWidget);
      expect(find.text('0.0 m'), findsOneWidget);
      expect(find.text('Read at'), findsOneWidget);
      expect(find.text('12:45'), findsOneWidget);
      expect(find.text('18.9 °C'), findsOneWidget);

      // Another place is another address: its own answer, not yet in.
      await draw(tester, 'custom_sea_state', tile(3, 2), {
        'place': 'Hythe',
        'latitude': 51.07,
        'longitude': 1.08,
      });
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('-1.17 m'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a figure, a list, and one with no source at all', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await custom.install(
          _spec({
            'type': 'one_figure',
            'source': {'url': 'http://tides.local/now'},
            'show': {
              'kind': 'value',
              'title': '{{option.place}}',
              'value': '{{current.wave_height | number:2}} m',
              'detail': 'at {{current.time | time}}',
            },
          }),
        );
        await custom.install(
          _spec({
            'type': 'tide_list',
            'source': {'url': 'http://tides.local/list'},
            'show': {
              'kind': 'list',
              'items': 'tides',
              'title': '{{item.kind}} water',
              'trailing': '{{item.at | time}} · {{item.height | number:1}} m',
              'limit': 3,
            },
          }),
        );
        await custom.install(
          _spec({
            'type': 'door_sign',
            'source': null,
            'show': {'kind': 'value', 'value': '{{option.place}}'},
          }),
        );
      });
      custom
        ..debugAnswer('http://tides.local/now', _sea)
        ..debugAnswer('http://tides.local/list', {
          'tides': [
            for (final (kind, at, height) in [
              ('High', '2026-10-04T03:10:00', 3.94),
              ('Low', '2026-10-04T09:25:00', 0.52),
              ('High', '2026-10-04T15:40:00', 4.1),
              ('Low', '2026-10-04T21:55:00', 0.4),
            ])
              {'kind': kind, 'at': at, 'height': height},
          ],
        });

      await sweep(tester, 'custom_one_figure');
      expect(find.text('Harwich'), findsOneWidget);
      expect(find.text('0.04 m'), findsOneWidget);
      expect(find.text('at 12:45'), findsOneWidget);

      await sweep(tester, 'custom_tide_list');
      await draw(tester, 'custom_tide_list', tile(4, 3));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('High water'), findsNWidgets(2));
      expect(find.text('09:25 · 0.5 m'), findsOneWidget);
      // The fourth is past the limit.
      expect(find.text('21:55 · 0.4 m'), findsNothing);

      await sweep(tester, 'custom_door_sign');
      expect(find.text('Harwich'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('widgets written in Dart', () {
    late Directory dir;
    late List<List<String>> ran;
    late CodeWidgets code;
    final example = File(
      'assets/dashboard/example_widget.dart',
    ).readAsStringSync();

    File status() => File('${dir.path}/state/status.json');

    setUp(() {
      dir = Directory.systemTemp.createTempSync('code');
      ran = [];
      code = CodeWidgets(
        root: '/home/pi/homecanvas',
        sources: '${dir.path}/src',
        state: '${dir.path}/state',
        run: (command) async {
          ran.add(command);
          return true;
        },
      );
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('the example declares what the registry takes', () {
      expect(CodeWidgets.declares(example), isTrue);
      expect(
        CodeWidgets.declares('final DashboardWidgetType widgetType =\n x;'),
        isTrue,
      );
      expect(
        CodeWidgets.declares('// final widgetType = nothing\nvoid main() {}'),
        isFalse,
      );
      expect(CodeWidgets.declares('final tideWidgetType = x;'), isFalse);
    });

    test('a file is named for a Dart file, or refused', () {
      expect(CodeWidgets.nameOf('tide_curve.dart'), 'tide_curve');
      expect(CodeWidgets.nameOf('Tide Curve.dart'), 'tide_curve');
      expect(CodeWidgets.nameOf('tide.json'), isNull);
      expect(CodeWidgets.nameOf('../../main.dart'), 'main');
      expect(CodeWidgets.nameOf('9lives.dart'), isNull);
      expect(CodeWidgets.nameOf('custom_registry.dart'), isNull);
    });

    test('an upload is set aside and the builder started on it', () async {
      expect(await code.install('Tide Curve.dart', example), isNull);
      expect(
        File('${dir.path}/state/incoming/tide_curve.dart').readAsStringSync(),
        example,
      );
      // Not installed until it has built: that is the builder's to do.
      expect(code.installed, isEmpty);
      expect(ran.single, [
        'bash',
        '/home/pi/homecanvas/scripts/widget-build.sh',
        'install',
        'tide_curve',
      ]);
      expect(code.status()['state'], 'building');
      expect(
        await code.install('other.dart', example),
        'A build is already running.',
      );
      expect(ran.length, 1);
    });

    test(
      'what cannot be a widget is refused before anything is built',
      () async {
        expect(
          await code.install('tide.txt', example),
          contains('ending .dart'),
        );
        expect(
          await code.install('tide.dart', 'void main() {}'),
          contains('final widgetType'),
        );
        expect(
          await code.install('tide.dart', '$example${'/' * 300000}'),
          'The file is over 256 KB.',
        );
        expect(await code.remove('tide'), 'There is no widget of that name.');
        expect(ran, isEmpty);

        final elsewhere = CodeWidgets(
          root: null,
          sources: '${dir.path}/src',
          state: '${dir.path}/state',
          run: (_) async => true,
        );
        expect(elsewhere.available, isFalse);
        // A root is looked for when none is given; a test has none either.
        expect(await elsewhere.install('tide.dart', example), isNotNull);
      },
    );

    test(
      'what is installed is listed, handed back, and removed by a build',
      () async {
        Directory('${dir.path}/src').createSync();
        File('${dir.path}/src/tide_curve.dart').writeAsStringSync(example);
        File('${dir.path}/src/notes.txt').writeAsStringSync('not one');
        expect(code.installed, ['tide_curve']);
        expect(code.source('tide_curve'), example);
        expect(code.source('../state/status'), isNull);
        expect(await code.remove('tide_curve'), isNull);
        expect(ran.single.sublist(2), ['remove', 'tide_curve']);
      },
    );

    test('a build is read as the builder left it — or as cut off', () async {
      expect(code.status(), {'state': 'idle'});
      status()
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'state': 'failed',
            'step': 'checking',
            'name': 'tide_curve',
            'error': "error • Undefined name 'x' • tide_curve.dart:12:3",
          }),
        );
      expect(code.status()['error'], contains('tide_curve.dart:12:3'));
      expect(code.building, isFalse);

      status().writeAsStringSync(
        jsonEncode({
          'state': 'building',
          'step': 'building',
          'started': DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 2))
              .toIso8601String(),
        }),
      );
      expect(code.status()['state'], 'failed');
      expect(code.status()['error'], contains('cut off'));
      // And so the next upload is not turned away.
      expect(await code.install('tide.dart', example), isNull);
    });

    test(
      'a builder that will not start is said, and does not block the next',
      () async {
        final stuck = CodeWidgets(
          root: '/home/pi/homecanvas',
          sources: '${dir.path}/src',
          state: '${dir.path}/state',
          run: (_) async => false,
        );
        expect(
          await stuck.install('tide.dart', example),
          'The build could not be started.',
        );
        expect(stuck.building, isFalse);
      },
    );

    test('the switch is the panel\'s: off unless the config says on', () {
      expect(DashboardSettings().codeWidgets, isFalse);
      expect(DashboardSettings.fromJson({}).codeWidgets, isFalse);
      final on = DashboardSettings(codeWidgets: true);
      expect(DashboardSettings.fromJson(on.toJson()).codeWidgets, isTrue);
    });
  });
}

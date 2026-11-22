import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/app_version.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/services/addons.dart';
import 'package:home_canvas/services/code_widgets.dart';
import 'package:home_canvas/services/custom_widgets.dart';

/// The catalogue of add-ons: what the Add-ons page is told, and what is
/// taken from it.
void main() {
  const commit = '0123456789abcdef0123456789abcdef01234567';
  const raw = 'https://raw.githubusercontent.com/someone/widgets';
  final described = jsonEncode({
    'type': 'sea_state',
    'name': 'Sea state',
    'description': 'The sea at a place you choose.',
    'glyph': '🌊',
    'show': {'kind': 'value', 'title': 'Sea', 'value': 'calm'},
  });

  Map<String, dynamic> entry(
    String id, {
    String kind = 'dart',
    String version = '1.0.0',
    String minApp = '1.0.0',
    List<String>? types,
    String? source,
  }) => {
    'id': id,
    'name': id.toUpperCase(),
    'description': 'What $id does.',
    'author': 'Somebody',
    'authorUrl': 'https://example.org/somebody',
    'category': 'Time & day',
    'glyph': '🧩',
    'version': version,
    'kind': kind,
    'types': types ?? [id],
    'permissions': const <String>[],
    'minApp': minApp,
    'screenshot': 'screenshot.png',
    'files': [
      {
        'path': kind == 'dart' ? '${id}_widget.dart' : '$id.json',
        'sha256': '${sha256.convert(utf8.encode(source ?? id))}',
        'size': 1,
      },
    ],
  };

  late Directory dir;
  late List<List<String>> ran;
  late List<String> asked;
  late Map<String, String> served;
  late CustomWidgets custom;

  Addons addons({String? root = '/home/pi/homecanvas', String? version}) =>
      Addons(
        repo: 'someone/widgets',
        dir: '${dir.path}/addons',
        appVersion: version ?? '1.1.0',
        custom: custom,
        code: CodeWidgets(
          root: root,
          sources: '${dir.path}/src',
          state: '${dir.path}/state',
          run: (command) async {
            ran.add(command);
            return true;
          },
        ),
        fetch: (url, most) async {
          asked.add(url);
          final body = served[url];
          if (body == null) throw const SocketException('unreachable');
          return utf8.encode(body);
        },
      );

  void serve(List<Map<String, dynamic>> listed) =>
      served['$raw/catalogue/index.json'] = jsonEncode({
        'schema': 1,
        'commit': commit,
        'addons': listed,
      });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('addons');
    ran = [];
    asked = [];
    served = {};
    custom = CustomWidgets(dir: '${dir.path}/widgets');
  });
  tearDown(() {
    custom.dispose();
    WidgetRegistry.unregister('custom_sea_state');
    dir.deleteSync(recursive: true);
  });

  test('the version an add-on is held to is the one in the pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      contains(RegExp('^version: $kAppVersion\\+', multiLine: true)),
    );
  });

  test('versions are compared by their numbers, not their letters', () {
    expect(Addons.older('1.9.0', '1.10.0'), isTrue);
    expect(Addons.older('1.10.0', '1.9.0'), isFalse);
    expect(Addons.older('1.1.0', '1.1.0'), isFalse);
    expect(Addons.older('1.1.0+7', '1.1.0'), isFalse);
    expect(Addons.older('1.0', '1.0.1'), isTrue);
  });

  test('a repository that is no owner/name falls back to the app\'s own', () {
    Addons make(String? repo) => Addons(
      repo: repo,
      dir: dir.path,
      custom: custom,
      code: CodeWidgets(root: null, sources: dir.path, state: dir.path),
    );
    expect(make(null).repo, Addons.defaultRepo);
    expect(make('https://evil.example/x').repo, Addons.defaultRepo);
    expect(make('../../etc').repo, Addons.defaultRepo);
    expect(make('someone/widgets').repo, 'someone/widgets');
  });

  test(
    'the listing says what is installed, wanted, newer and too new',
    () async {
      serve([
        entry('clock', version: '1.2.0'),
        entry('weather'),
        entry('future', minApp: '9.0.0'),
        entry('unifi', types: ['unifi_health', 'unifi_isp']),
      ]);
      Directory('${dir.path}/addons/clock').createSync(recursive: true);
      File(
        '${dir.path}/addons/clock/addon.json',
      ).writeAsStringSync(jsonEncode({...entry('clock'), 'commit': commit}));
      Directory('${dir.path}/addons/gone').createSync(recursive: true);
      File(
        '${dir.path}/addons/gone/addon.json',
      ).writeAsStringSync(jsonEncode(entry('gone')));

      final l = await addons().listing({'clock', 'unifi_isp', 'calendar'});
      expect(l['repo'], 'someone/widgets');
      expect(l['canBuild'], isTrue);
      expect(l.containsKey('error'), isFalse);
      final by = {for (final a in l['addons'] as List) a['id']: a as Map};
      expect(by.keys, ['clock', 'weather', 'future', 'unifi', 'gone']);
      expect(by['clock']!['installed'], '1.0.0');
      expect(by['clock']!['update'], isTrue);
      expect(by['clock']!['wanted'], isFalse);
      expect(
        by['clock']!['screenshot'],
        '$raw/$commit/widgets/clock/screenshot.png',
      );
      expect(by['weather']!['installed'], isNull);
      expect(by['weather']!['wanted'], isFalse);
      expect(by['unifi']!['wanted'], isTrue);
      expect(by['future']!['compatible'], isFalse);
      expect(by['weather']!['compatible'], isTrue);
      // Installed here and no longer listed: still this panel's to remove.
      expect(by['gone']!['listed'], isFalse);
      expect(by['gone']!['installed'], '1.0.0');
      // The files and their sums are the panel's business, not the page's.
      expect(by['clock']!.containsKey('files'), isFalse);
    },
  );

  test('an entry that is not one to install is left out of the list', () async {
    serve([
      entry('clock'),
      {...entry('up'), 'id': '../up'},
      {...entry('exe'), 'kind': 'binary'},
      {
        ...entry('sly'),
        'files': [
          {'path': '../../.bashrc', 'sha256': 'a' * 64},
        ],
      },
      {
        ...entry('unsummed'),
        'files': [
          {'path': 'unsummed_widget.dart', 'sha256': 'nope'},
        ],
      },
    ]);
    final l = await addons().listing(const {});
    expect([for (final a in l['addons'] as List) a['id']], ['clock']);
  });

  test(
    'a catalogue that cannot be reached is said, with what is installed',
    () async {
      Directory('${dir.path}/addons/clock').createSync(recursive: true);
      File(
        '${dir.path}/addons/clock/addon.json',
      ).writeAsStringSync(jsonEncode(entry('clock')));
      final l = await addons().listing(const {});
      expect(l['error'], 'The catalogue could not be reached.');
      expect([for (final a in l['addons'] as List) a['id']], ['clock']);

      served['$raw/catalogue/index.json'] = '{"commit": "main", "addons": []}';
      expect(
        (await addons().listing(const {}))['error'],
        'The catalogue could not be read.',
      );
    },
  );

  test('add-ons in Dart are handed to the builder, together', () async {
    serve([entry('clock'), entry('weather')]);
    expect(await addons().install(['clock', 'weather']), isNull);
    expect(ran.single.sublist(2), ['addons', 'clock,weather']);
    expect(ran.single[1], '/home/pi/homecanvas/scripts/widget-build.sh');
  });

  test('nothing is built for a name that is not in the catalogue', () async {
    serve([entry('clock'), entry('future', minApp: '9.0.0')]);
    final a = addons();
    expect(await a.install(['nope']), contains('no add-on called nope'));
    expect(await a.install(['clock; rm -rf ~']), isNotNull);
    expect(await a.install(const []), isNotNull);
    expect(
      await a.install(['future']),
      'FUTURE needs HomeCanvas 9.0.0 or newer; this panel has 1.1.0.',
    );
    expect(ran, isEmpty);
  });

  test('a panel that cannot build takes none in Dart, and says why', () async {
    serve([entry('clock')]);
    final a = addons(root: null);
    expect((await a.listing(const {}))['canBuild'], isFalse);
    expect(await a.install(['clock']), contains('was not built where it runs'));
    expect(ran, isEmpty);
  });

  test(
    'one described in JSON is on the panel at once, and out again',
    () async {
      serve([
        entry(
          'sea_state',
          kind: 'json',
          types: ['custom_sea_state'],
          source: described,
        ),
      ]);
      served['$raw/$commit/widgets/sea_state/sea_state.json'] = described;
      final a = addons();
      expect(await a.install(['sea_state']), isNull);
      expect(ran, isEmpty);
      expect(WidgetRegistry.find('custom_sea_state')?.name, 'Sea state');
      expect(a.installed()['sea_state']!['commit'], commit);
      expect(
        (await a.listing({'custom_sea_state'}))['addons'].single['installed'],
        '1.0.0',
      );

      expect(await a.remove('sea_state'), isNull);
      expect(WidgetRegistry.find('custom_sea_state'), isNull);
      expect(a.installed(), isEmpty);
      expect(custom.all, isEmpty);
    },
  );

  test(
    'a file that is not the one the catalogue checked is not installed',
    () async {
      serve([
        entry(
          'sea_state',
          kind: 'json',
          types: ['custom_sea_state'],
          source: described,
        ),
      ]);
      served['$raw/$commit/widgets/sea_state/sea_state.json'] = described
          .replaceFirst('calm', 'rough');
      final a = addons();
      expect(
        await a.install(['sea_state']),
        contains('is not the file the catalogue checked'),
      );
      expect(WidgetRegistry.find('custom_sea_state'), isNull);
      expect(a.installed(), isEmpty);
    },
  );

  test('removing one in Dart is a build without it', () async {
    Directory('${dir.path}/addons/clock').createSync(recursive: true);
    File(
      '${dir.path}/addons/clock/addon.json',
    ).writeAsStringSync(jsonEncode(entry('clock')));
    final a = addons();
    expect(await a.remove('weather'), 'That add-on is not installed.');
    expect(await a.remove('../clock'), 'That add-on is not installed.');
    expect(await a.remove('clock'), isNull);
    expect(ran.single.sublist(2), ['addon-remove', 'clock']);
  });
}

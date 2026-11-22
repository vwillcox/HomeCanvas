import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../app_version.dart';
import '../dashboard/custom_widget_spec.dart';
import '../dashboard/widget_registry.dart';
import 'code_widgets.dart';
import 'custom_widgets.dart';
import 'http_client.dart';

/// Widget add-ons: the catalogue the editor's Add-ons page lists, and what
/// of it this panel has.
///
/// The widgets are kept in a repository of their own. Its checks — run on
/// every widget anybody sends it — write an `index.json` to its `catalogue`
/// branch: each add-on that passed, the commit it was read at, and the
/// SHA-256 of each of its files. That index is all this reads; a file that
/// does not match its sum is never installed.
///
/// An add-on written in Dart is built into the app, by the panel, with the
/// builder [CodeWidgets] starts. One described in JSON is on the panel at
/// once, through [CustomWidgets].
///
/// Which repository is read is the panel's own choice — `addonsRepo` in
/// config.json — and nothing the editor can set: what comes from it is run.
class Addons {
  Addons({
    required this.custom,
    required this.code,
    String? repo,
    String? dir,
    this.appVersion = kAppVersion,
    Future<List<int>> Function(String url, int most)? fetch,
  }) : repo = _repo.hasMatch(repo ?? '') ? repo! : defaultRepo,
       dir = dir ?? p.join(AppPaths.config, 'addons'),
       _fetch = fetch ?? _get;

  static const defaultRepo = 'vwillcox/HomeCanvas-Widgets';
  static const branch = 'catalogue';
  static const _raw = 'https://raw.githubusercontent.com';

  final CustomWidgets custom;
  final CodeWidgets code;
  final String repo;
  final String appVersion;

  /// What is installed: a folder each, with the `addon.json` it came with.
  final String dir;
  final Future<List<int>> Function(String url, int most) _fetch;

  static final _repo = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9_][A-Za-z0-9_.-]*$',
  );
  static final _id = RegExp(r'^[a-z][a-z0-9_]{1,39}$');
  static final _commit = RegExp(r'^[0-9a-f]{40}$');
  static final _sum = RegExp(r'^[0-9a-f]{64}$');
  static final _part = RegExp(r'^[a-z][a-z0-9_]*\.(dart|json)$');
  static const _maxIndex = 4 * 1024 * 1024;

  /// The widgets still in the app itself.
  static const coreTypes = {'calendar', 'parcels'};

  Map<String, dynamic>? _index;
  DateTime? _read;

  static Future<List<int>> _get(String url, int most) async {
    final dio = httpClient(
      connect: const Duration(seconds: 8),
      headers: const {'User-Agent': homeCanvasAgent},
    );
    try {
      final r = await dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in r.data?.stream ?? const Stream.empty()) {
        bytes.add(chunk);
        if (bytes.length > most) throw const FormatException('too big');
      }
      return bytes.takeBytes();
    } finally {
      dio.close();
    }
  }

  /// The catalogue's index, read again after five minutes or when [fresh].
  /// Throws a [FormatException] in words when it cannot be had.
  Future<Map<String, dynamic>> index({bool fresh = false}) async {
    final had = _index;
    final read = _read;
    if (!fresh &&
        had != null &&
        read != null &&
        DateTime.now().difference(read) < const Duration(minutes: 5)) {
      return had;
    }
    final Object? j;
    try {
      j = jsonDecode(
        utf8.decode(await _fetch('$_raw/$repo/$branch/index.json', _maxIndex)),
      );
    } on FormatException {
      throw const FormatException('The catalogue could not be read.');
    } catch (_) {
      // The last one read will do for looking through.
      if (had != null) return had;
      throw const FormatException('The catalogue could not be reached.');
    }
    final commit = j is Map ? j['commit'] : null;
    final listed = j is Map ? j['addons'] : null;
    if (commit is! String || !_commit.hasMatch(commit) || listed is! List) {
      throw const FormatException('The catalogue could not be read.');
    }
    _read = DateTime.now();
    return _index = {
      'commit': commit,
      'addons': [
        for (final a in listed)
          if (_good(a)) Map<String, dynamic>.from(a as Map),
      ],
    };
  }

  /// Whether an entry is one this panel could install: named, of a kind it
  /// knows, with files it would take.
  static bool _good(Object? a) {
    if (a is! Map) return false;
    final id = a['id'];
    final files = a['files'];
    final types = a['types'];
    return id is String &&
        _id.hasMatch(id) &&
        (a['kind'] == 'dart' || a['kind'] == 'json') &&
        types is List &&
        types.every((t) => t is String) &&
        files is List &&
        files.isNotEmpty &&
        files.every(
          (f) =>
              f is Map &&
              f['path'] is String &&
              _part.hasMatch(f['path'] as String) &&
              f['sha256'] is String &&
              _sum.hasMatch(f['sha256'] as String),
        );
  }

  /// What is installed, by name: each one's `addon.json`.
  Map<String, Map<String, dynamic>> installed() {
    final out = <String, Map<String, dynamic>>{};
    final folder = Directory(dir);
    if (!folder.existsSync()) return out;
    for (final d in folder.listSync().whereType<Directory>()) {
      final id = p.basename(d.path);
      if (!_id.hasMatch(id)) continue;
      try {
        final j = jsonDecode(
          File(p.join(d.path, 'addon.json')).readAsStringSync(),
        );
        if (j is Map<String, dynamic>) out[id] = j;
      } catch (_) {}
    }
    return out;
  }

  /// Whether version [a] is older than [b]: `1.9.0` before `1.10.0`.
  static bool older(String a, String b) {
    List<int> parts(String v) => [
      for (final s in v.split('+').first.split('.')) int.tryParse(s) ?? 0,
    ];
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final m = i < x.length ? x[i] : 0, n = i < y.length ? y[i] : 0;
      if (m != n) return m < n;
    }
    return false;
  }

  /// The catalogue for the page: every add-on, with whether this panel has
  /// it, could have it, and has a tile waiting for it. [used] is the widget
  /// types on the dashboard.
  Future<Map<String, dynamic>> listing(
    Set<String> used, {
    bool fresh = false,
  }) async {
    final have = installed();
    Map<String, dynamic>? index;
    String? error;
    try {
      index = await this.index(fresh: fresh);
    } on FormatException catch (e) {
      error = e.message;
    }
    final commit = index?['commit'];
    final listed = [
      for (final a in (index?['addons'] as List?) ?? const [])
        a as Map<String, dynamic>,
    ];
    final ids = {for (final a in listed) a['id']};
    // What the catalogue no longer lists is still this panel's to remove.
    for (final e in have.entries) {
      if (!ids.contains(e.key)) listed.add({...e.value, 'id': e.key});
    }
    return {
      'repo': repo,
      'url': 'https://github.com/$repo',
      'appVersion': appVersion,
      'canBuild': code.available,
      'error': ?error,
      'addons': [
        for (final a in listed)
          {
            for (final k in const [
              'id', 'name', 'description', 'author', 'authorUrl', //
              'category', 'glyph', 'version', 'kind', 'types', 'permissions',
              'minApp',
            ])
              k: a[k],
            'categoryName': WidgetCategory.localName('${a['category']}'),
            'listed': ids.contains(a['id']),
            if (commit != null && a['screenshot'] is String)
              'screenshot':
                  '$_raw/$repo/$commit/widgets/${a['id']}/screenshot.png',
            'installed': have[a['id']]?['version'],
            'update':
                have[a['id']] != null &&
                ids.contains(a['id']) &&
                older('${have[a['id']]!['version']}', '${a['version']}'),
            'compatible': !older(appVersion, '${a['minApp'] ?? '0'}'),
            'wanted':
                have[a['id']] == null &&
                (a['types'] as List? ?? const []).any(used.contains),
          },
      ],
    };
  }

  /// Installs [ids] from the catalogue. Null when it is done — or, for
  /// anything in Dart, when the build has started; otherwise why not.
  Future<String?> install(List<String> ids) async {
    if (ids.isEmpty || ids.length > 60 || !ids.every(_id.hasMatch)) {
      return 'That is no name for an add-on.';
    }
    final Map<String, dynamic> index;
    try {
      index = await this.index(fresh: true);
    } on FormatException catch (e) {
      return e.message;
    }
    final byId = {
      for (final a in index['addons'] as List)
        (a as Map<String, dynamic>)['id'] as String: a,
    };
    final dart = <String>[];
    final json = <Map<String, dynamic>>[];
    for (final id in ids) {
      final a = byId[id];
      if (a == null) return 'The catalogue has no add-on called $id.';
      if (older(appVersion, '${a['minApp'] ?? '0'}')) {
        return '${a['name']} needs HomeCanvas ${a['minApp']} or newer; '
            'this panel has $appVersion.';
      }
      a['kind'] == 'dart' ? dart.add(id) : json.add(a);
    }
    if (dart.isNotEmpty) {
      if (!code.available) {
        return 'This panel was not built where it runs, so it cannot build '
            'widgets in.';
      }
      if (code.building) return 'A build is already running.';
    }
    for (final a in json) {
      final refused = await _installDescribed(a, '${index['commit']}');
      if (refused != null) return refused;
    }
    return dart.isEmpty ? null : code.installAddons(dart);
  }

  /// One described in JSON: fetched, checked against its sum, and handed
  /// to the widgets installed from files — which check it again, as they
  /// would an upload.
  Future<String?> _installDescribed(
    Map<String, dynamic> a,
    String commit,
  ) async {
    final id = a['id'] as String;
    final files = a['files'] as List;
    final file = files.first as Map;
    if (files.length != 1 || !'${file['path']}'.endsWith('.json')) {
      return '${a['name']} is not one file of JSON.';
    }
    final String source;
    try {
      final bytes = await _fetch(
        '$_raw/$repo/$commit/widgets/$id/${file['path']}',
        CustomWidgetSpec.maxBytes,
      );
      if ('${sha256.convert(bytes)}' != file['sha256']) {
        return '${a['name']} is not the file the catalogue checked. '
            'It was not installed.';
      }
      source = utf8.decode(bytes);
    } catch (_) {
      return '${a['name']} could not be fetched.';
    }
    final CustomWidgetSpec spec;
    try {
      spec = await custom.install(source);
    } on FormatException catch (e) {
      return '${a['name']}: ${e.message}';
    }
    final folder = Directory(p.join(dir, id));
    await folder.create(recursive: true);
    await File(p.join(folder.path, 'addon.json')).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
        for (final e in a.entries)
          if (e.key != 'files') e.key: e.value,
        'commit': commit,
        'files': [file['path']],
        'types': [spec.type],
      })}\n',
      flush: true,
    );
    return null;
  }

  /// Takes one out. Null when it is gone — or, for one in Dart, when the
  /// build without it has started; otherwise why not.
  Future<String?> remove(String id) async {
    final had = _id.hasMatch(id) ? installed()[id] : null;
    if (had == null) return 'That add-on is not installed.';
    if (had['kind'] == 'dart') {
      if (!code.available) {
        return 'This panel was not built where it runs, so it cannot '
            'rebuild without it.';
      }
      return code.removeAddon(id);
    }
    for (final t in had['types'] as List? ?? const []) {
      final type = '$t';
      await custom.remove(
        type.startsWith(CustomWidgetSpec.typePrefix)
            ? type.substring(CustomWidgetSpec.typePrefix.length)
            : type,
      );
    }
    try {
      await Directory(p.join(dir, id)).delete(recursive: true);
    } catch (e) {
      debugPrint('Add-on $id: $e');
    }
    return null;
  }
}

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
import '../dashboard/dashboard_theme.dart';
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
/// once, through [CustomWidgets]. A theme is on it at once too: a file in
/// the themes folder ([themesDir]), which the dashboard reads again.
///
/// Which repository is the catalogue is the panel's own choice —
/// `addonsRepo` in config.json — and nothing the editor can set.
///
/// Beside it, the page can be given **third-party libraries**: any
/// repository laid out as the catalogue is, publishing an index the same
/// way. Their files are checked against their own index's sums and no
/// more — nobody has reviewed them — so the page says so on each, and one
/// written in Dart is installed only while the panel's own "Widgets
/// written in Dart" switch is on ([allowsCode]). The catalogue comes
/// first: a library cannot replace an add-on or a widget type it has.
class Addons {
  Addons({
    required this.custom,
    required this.code,
    String? repo,
    String? dir,
    this.appVersion = kAppVersion,
    String? themesDir,
    List<String> Function()? libraries,
    bool Function()? allowsCode,
    this.onThemes,
    Future<List<int>> Function(String url, int most)? fetch,
  }) : repo = _repo.hasMatch(repo ?? '') ? repo! : defaultRepo,
       dir = dir ?? p.join(AppPaths.config, 'addons'),
       themesDir = themesDir ?? p.join(AppPaths.config, 'themes'),
       _libraries = libraries ?? (() => const []),
       _allowsCode = allowsCode ?? (() => false),
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

  /// Where themes are read from: a theme add-on's theme.json is put here,
  /// as `<theme id>.json`, beside any theme made by hand.
  final String themesDir;

  /// Run once a theme has come or gone, for the dashboard to read them again.
  final Future<void> Function()? onThemes;
  final Future<List<int>> Function(String url, int most) _fetch;
  final List<String> Function() _libraries;
  final bool Function() _allowsCode;

  /// How many libraries a panel reads beside the catalogue.
  static const maxLibraries = 8;

  /// The libraries read beside the catalogue, as the panel has them.
  List<String> get libraries {
    final seen = {repo.toLowerCase()};
    return [
      for (final r in _libraries())
        if (_repo.hasMatch(r) && seen.add(r.toLowerCase())) r,
    ].take(maxLibraries).toList();
  }

  /// Why [named] cannot be added as a library; null when it can. It is
  /// read once here, so that what is added is a library and not a typo.
  Future<String?> checkLibrary(String named) async {
    if (!_repo.hasMatch(named)) {
      return 'A library is named owner/name, as it is on GitHub.';
    }
    if (named.toLowerCase() == repo.toLowerCase()) {
      return 'That is the catalogue this panel already reads.';
    }
    if (libraries.any((r) => r.toLowerCase() == named.toLowerCase())) {
      return 'This panel already reads that library.';
    }
    if (libraries.length >= maxLibraries) {
      return 'This panel reads $maxLibraries libraries already; take one '
          'away first.';
    }
    try {
      await index(from: named, fresh: true);
    } on FormatException {
      return '$named has no index this panel can read. A library publishes '
          'index.json on a branch called $branch.';
    }
    return null;
  }

  static final _repo = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9_][A-Za-z0-9_.-]*$',
  );
  static final _id = RegExp(r'^[a-z][a-z0-9_]{1,39}$');
  static final _themeId = RegExp(r'^[a-z][a-z0-9-]{1,39}$');
  static final _commit = RegExp(r'^[0-9a-f]{40}$');
  static final _sum = RegExp(r'^[0-9a-f]{64}$');
  static final _part = RegExp(r'^[a-z][a-z0-9_]*\.(dart|json)$');
  static const _maxIndex = 4 * 1024 * 1024;

  final _indexes = <String, Map<String, dynamic>>{};
  final _read = <String, DateTime>{};

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

  /// The index of the catalogue — or of the library [from] — read again
  /// after five minutes or when [fresh]. Throws a [FormatException] in
  /// words when it cannot be had.
  Future<Map<String, dynamic>> index({String? from, bool fresh = false}) async {
    final repo = from ?? this.repo;
    final had = _indexes[repo];
    final read = _read[repo];
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
    _read[repo] = DateTime.now();
    return _indexes[repo] = {
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
    final themes = a['themes'];
    // A theme brings one theme, and never the app's own.
    if (a['kind'] == 'theme' &&
        !(themes is List &&
            themes.length == 1 &&
            themes.first is String &&
            _themeId.hasMatch(themes.first as String) &&
            !kBuiltInThemes.any((t) => t.id == themes.first))) {
      return false;
    }
    return id is String &&
        _id.hasMatch(id) &&
        const {'dart', 'json', 'theme'}.contains(a['kind']) &&
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

  /// Everything on offer: the catalogue's add-ons, then each library's
  /// that the catalogue — or a library before it — does not already have
  /// by name, by widget type or by theme. Each carries where it is from (`source`,
  /// `commit`) and whether that is the catalogue (`official`).
  Future<_Offer> _offer({bool fresh = false}) async {
    final out = _Offer();
    final ids = <String>{};
    final types = <String>{};
    for (final from in [repo, ...libraries]) {
      final official = from == repo;
      final Map<String, dynamic> index;
      try {
        index = await this.index(from: from, fresh: fresh);
      } on FormatException catch (e) {
        if (official) {
          out.error = e.message;
        } else {
          out.libraries.add({
            'repo': from,
            'url': 'https://github.com/$from',
            'error': 'This library could not be read.',
          });
        }
        continue;
      }
      var listed = 0, hidden = 0;
      final taken = <String>{};
      for (final a in index['addons'] as List) {
        final entry = a as Map<String, dynamic>;
        final brings = [
          for (final t in entry['types'] as List) '$t',
          for (final t in entry['themes'] as List? ?? const []) 'theme:$t',
        ];
        if (ids.contains(entry['id']) || brings.any(types.contains)) {
          hidden++;
          continue;
        }
        ids.add(entry['id'] as String);
        taken.addAll(brings);
        listed++;
        out.addons.add({
          ...entry,
          'source': from,
          'commit': index['commit'],
          'official': official,
        });
      }
      types.addAll(taken);
      if (!official) {
        out.libraries.add({
          'repo': from,
          'url': 'https://github.com/$from',
          'count': listed,
          'hidden': hidden,
        });
      }
    }
    return out;
  }

  /// The page: every add-on, with whether this panel has it, could have
  /// it, and has a tile waiting for it. [used] is the widget types on the
  /// dashboard, and [theme] the theme it is dressed in.
  Future<Map<String, dynamic>> listing(
    Set<String> used, {
    String? theme,
    bool fresh = false,
  }) async {
    final have = installed();
    final offer = await _offer(fresh: fresh);
    final listed = offer.addons;
    final ids = {for (final a in listed) a['id']};
    // What is no longer listed is still this panel's to remove.
    for (final e in have.entries) {
      if (ids.contains(e.key)) continue;
      final from = e.value['repo'];
      listed.add({
        ...e.value,
        'id': e.key,
        'source': from is String ? from : repo,
        'commit': null,
        'official': from is! String || from == repo,
      });
    }
    return {
      'repo': repo,
      'url': 'https://github.com/$repo',
      'appVersion': appVersion,
      'canBuild': code.available,
      'codeAllowed': _allowsCode(),
      'libraries': offer.libraries,
      'maxLibraries': maxLibraries,
      'error': ?offer.error,
      'addons': [
        for (final a in listed)
          {
            for (final k in const [
              'id', 'name', 'description', 'author', 'authorUrl', //
              'category', 'glyph', 'version', 'kind', 'types', 'themes',
              'permissions', 'minApp', 'source', 'official',
            ])
              k: a[k],
            'categoryName': WidgetCategory.localName('${a['category']}'),
            'listed': ids.contains(a['id']),
            if (a['commit'] != null && a['screenshot'] is String)
              'screenshot':
                  '$_raw/${a['source']}/${a['commit']}/widgets/${a['id']}/'
                  'screenshot.png',
            'installed': have[a['id']]?['version'],
            'update':
                have[a['id']] != null &&
                ids.contains(a['id']) &&
                older('${have[a['id']]!['version']}', '${a['version']}'),
            'compatible': !older(appVersion, '${a['minApp'] ?? '0'}'),
            'wanted':
                have[a['id']] == null &&
                ((a['types'] as List? ?? const []).any(used.contains) ||
                    (a['themes'] as List? ?? const []).contains(theme)),
            if (a['kind'] == 'theme')
              'inUse': (a['themes'] as List? ?? const []).contains(theme),
          },
      ],
    };
  }

  /// Installs [ids] from the catalogue or a library. Null when it is done
  /// — or, for anything in Dart, when the build has started; otherwise why
  /// not.
  Future<String?> install(List<String> ids) async {
    if (ids.isEmpty || ids.length > 60 || !ids.every(_id.hasMatch)) {
      return 'That is no name for an add-on.';
    }
    final offer = await _offer(fresh: true);
    final byId = {for (final a in offer.addons) a['id'] as String: a};
    final dart = <String>[];
    final json = <Map<String, dynamic>>[];
    final themes = <Map<String, dynamic>>[];
    for (final id in ids) {
      final a = byId[id];
      if (a == null) {
        return offer.error ?? 'There is no add-on called $id to download.';
      }
      if (older(appVersion, '${a['minApp'] ?? '0'}')) {
        return '${a['name']} needs HomeCanvas ${a['minApp']} or newer; '
            'this panel has $appVersion.';
      }
      if (a['kind'] == 'theme') {
        // Colours and measures, from anywhere: there is no code in one.
        themes.add(a);
      } else if (a['kind'] != 'dart') {
        json.add(a);
      } else if (a['official'] == true) {
        dart.add(id);
      } else if (!_allowsCode()) {
        return '${a['name']} is from ${a['source']}, which nobody has '
            'checked, and it is code that would run on the panel. To allow '
            'it, switch on "Widgets written in Dart" in Settings → '
            'Dashboard, on the panel itself.';
      } else {
        dart.add('$id@${a['source']}');
      }
    }
    if (dart.isNotEmpty) {
      if (!code.available) {
        return 'This panel was not built where it runs, so it cannot build '
            'widgets in.';
      }
      if (code.building) return 'A build is already running.';
    }
    for (final a in json) {
      final refused = await _installDescribed(a);
      if (refused != null) return refused;
      _noteRemoved(drop: [a['id'] as String]);
    }
    for (final a in themes) {
      final refused = await _installTheme(a);
      if (refused != null) return refused;
      _noteRemoved(drop: [a['id'] as String]);
    }
    if (themes.isNotEmpty) await onThemes?.call();
    return dart.isEmpty ? null : code.installAddons(dart);
  }

  /// One described in JSON: fetched, checked against its sum, and handed
  /// to the widgets installed from files — which check it again, as they
  /// would an upload.
  Future<String?> _installDescribed(Map<String, dynamic> a) async {
    final id = a['id'] as String;
    final commit = '${a['commit']}';
    final source = '${a['source']}';
    final files = a['files'] as List;
    final file = files.first as Map;
    if (files.length != 1 || !'${file['path']}'.endsWith('.json')) {
      return '${a['name']} is not one file of JSON.';
    }
    final String text;
    try {
      final bytes = await _fetch(
        '$_raw/$source/$commit/widgets/$id/${file['path']}',
        CustomWidgetSpec.maxBytes,
      );
      if ('${sha256.convert(bytes)}' != file['sha256']) {
        return '${a['name']} is not the file the catalogue checked. '
            'It was not installed.';
      }
      text = utf8.decode(bytes);
    } catch (_) {
      return '${a['name']} could not be fetched.';
    }
    final CustomWidgetSpec spec;
    try {
      spec = await custom.install(text);
    } on FormatException catch (e) {
      return '${a['name']}: ${e.message}';
    }
    final folder = Directory(p.join(dir, id));
    await folder.create(recursive: true);
    await File(p.join(folder.path, 'addon.json')).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
        for (final e in a.entries)
          if (!const {'files', 'source', 'official'}.contains(e.key)) e.key: e.value,
        'repo': source,
        'files': [file['path']],
        'types': [spec.type],
      })}\n',
      flush: true,
    );
    return null;
  }

  /// A theme: its theme.json fetched, checked against its sum, read as the
  /// dashboard would read it, and put in the themes folder.
  Future<String?> _installTheme(Map<String, dynamic> a) async {
    final id = a['id'] as String;
    final named = '${(a['themes'] as List).first}';
    final files = a['files'] as List;
    final file = files.first as Map;
    if (files.length != 1 || file['path'] != 'theme.json') {
      return '${a['name']} is not one theme.json.';
    }
    final List<int> bytes;
    try {
      bytes = await _fetch(
        '$_raw/${a['source']}/${a['commit']}/widgets/$id/theme.json',
        _maxTheme,
      );
    } catch (_) {
      return '${a['name']} could not be fetched.';
    }
    if ('${sha256.convert(bytes)}' != file['sha256']) {
      return '${a['name']} is not the file the catalogue checked. '
          'It was not installed.';
    }
    try {
      final j = jsonDecode(utf8.decode(bytes));
      if (j is! Map<String, dynamic> || j['id'] != named) {
        throw const FormatException();
      }
      DashboardTheme.fromJson(j);
    } catch (_) {
      return '${a['name']} is not a theme this panel can read.';
    }
    await Directory(themesDir).create(recursive: true);
    final part = File(p.join(themesDir, '.$named.json.part'));
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(p.join(themesDir, '$named.json'));
    final folder = Directory(p.join(dir, id));
    await folder.create(recursive: true);
    await File(p.join(folder.path, 'addon.json')).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
        for (final e in a.entries)
          if (!const {'files', 'source', 'official'}.contains(e.key)) e.key: e.value,
        'repo': a['source'],
        'files': ['theme.json'],
      })}\n',
      flush: true,
    );
    return null;
  }

  static const _maxTheme = 64 * 1024;

  /// Add-ons taken off by hand, which an update — `scripts/addons.py
  /// ensure` — leaves off even when the dashboard still names them. The
  /// builder notes those in Dart itself; these are the rest.
  String get _removedFile => p.join(p.dirname(dir), 'addons-removed.json');

  void _noteRemoved({
    List<String> add = const [],
    List<String> drop = const [],
  }) {
    try {
      final file = File(_removedFile);
      final had = <String>{};
      if (file.existsSync()) {
        final j = jsonDecode(file.readAsStringSync());
        if (j is List) had.addAll(j.whereType<String>());
      }
      final now = {...had, ...add}..removeAll(drop);
      if (setEquals(had, now)) return;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(now.toList()..sort())}\n',
      );
    } catch (e) {
      debugPrint('Add-ons: $_removedFile: $e');
    }
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
    if (had['kind'] == 'theme') {
      for (final t in had['themes'] as List? ?? const []) {
        final named = '$t';
        if (!_themeId.hasMatch(named)) continue;
        try {
          await File(p.join(themesDir, '$named.json')).delete();
        } catch (_) {}
      }
      try {
        await Directory(p.join(dir, id)).delete(recursive: true);
      } catch (e) {
        debugPrint('Add-on $id: $e');
      }
      _noteRemoved(add: [id]);
      await onThemes?.call();
      return null;
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
    _noteRemoved(add: [id]);
    return null;
  }
}

/// What can be downloaded, and what was read to find out.
class _Offer {
  final addons = <Map<String, dynamic>>[];
  final libraries = <Map<String, dynamic>>[];
  String? error;
}

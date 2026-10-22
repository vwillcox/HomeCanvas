import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';

/// Widgets uploaded as Dart: real ones, as full as any the app comes with.
///
/// The app is compiled, so a new one means building the app again — which
/// the panel does itself, with `scripts/widget-build.sh`, in a unit of its
/// own so that it outlives the restart at the end. That script keeps the
/// last good build, and puts it back if the new source does not check,
/// build or start; this class hands it the file, and reads back how it
/// went for the editor to show.
///
/// Dart that is uploaded is Dart that is run, as the panel's own user. So
/// it is off until switched on in Settings on the panel itself, which the
/// editor cannot do.
class CodeWidgets {
  CodeWidgets({
    String? root,
    String? sources,
    String? state,
    Future<bool> Function(List<String> command)? run,
  }) : root = root ?? _findRoot(),
       sources = sources ?? p.join(AppPaths.config, 'widgets-src'),
       state =
           state ??
           p.join(
             Platform.environment['HOME'] ?? '.',
             '.local',
             'share',
             AppPaths.name,
             'widget-build',
           ),
       _run = run ?? _systemdRun;

  /// The source the app was built from, or null when this copy was not
  /// built where it runs.
  final String? root;

  /// The uploaded widgets, as installed.
  final String sources;

  /// Where the builder keeps its status, its log and the build before.
  final String state;
  final Future<bool> Function(List<String> command) _run;

  static const maxBytes = 256 * 1024;
  static final _name = RegExp(r'^[a-z][a-z0-9_]{1,39}$');

  /// What every upload must declare: the description the registry takes.
  static final _declares = RegExp(
    r'^\s*(final|var|const|DashboardWidgetType|late)\b[^;=]*\bwidgetType\s*=',
    multiLine: true,
  );

  /// Up from the running binary — build/linux/arm64/release/bundle — to the
  /// folder with the pubspec in it.
  static String? _findRoot() {
    var dir = File(Platform.resolvedExecutable).parent;
    for (var up = 0; up < 8; up++) {
      if (File(p.join(dir.path, 'pubspec.yaml')).existsSync() &&
          File(p.join(dir.path, 'scripts', 'widget-build.sh')).existsSync()) {
        return dir.path;
      }
      dir = dir.parent;
    }
    return null;
  }

  static Future<bool> _systemdRun(List<String> command) async {
    try {
      // A unit of its own: restarting the kiosk stops everything in the
      // kiosk's, and the builder has to see the restart through.
      final r = await Process.run('systemd-run', [
        '--user',
        '--collect',
        '--quiet',
        '--unit=homecanvas-widget-build',
        ...command,
      ]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Whether this panel can build at all.
  bool get available => root != null;

  /// "sea_chart" from "Sea Chart.dart", or null if it is no name for one.
  static String? nameOf(String file) {
    final base = p
        .basenameWithoutExtension(file)
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-]+'), '_');
    return file.toLowerCase().endsWith('.dart') &&
            _name.hasMatch(base) &&
            base != 'custom_registry'
        ? base
        : null;
  }

  /// The names installed.
  List<String> get installed {
    final dir = Directory(sources);
    if (!dir.existsSync()) return const [];
    return [
      for (final f in dir.listSync().whereType<File>())
        if (nameOf(p.basename(f.path)) case final String name) name,
    ]..sort();
  }

  /// One's source, to be changed and uploaded again.
  String? source(String name) {
    final f = File(p.join(sources, '$name.dart'));
    return _name.hasMatch(name) && f.existsSync() ? f.readAsStringSync() : null;
  }

  /// How the last build went, or is going.
  Map<String, dynamic> status() {
    Map<String, dynamic> last = const {'state': 'idle'};
    try {
      final j = jsonDecode(
        File(p.join(state, 'status.json')).readAsStringSync(),
      );
      if (j is Map<String, dynamic>) last = j;
    } catch (_) {}
    // A builder that was cut off mid-build — the power, say — left
    // "building" behind it; nothing takes half an hour.
    if (last['state'] == 'building') {
      final started = DateTime.tryParse('${last['started']}');
      if (started == null ||
          DateTime.now().toUtc().difference(started).inMinutes >= 30) {
        last = {
          ...last,
          'state': 'failed',
          'error': 'The build was cut off before it finished.',
        };
      }
    }
    return last;
  }

  bool get building => status()['state'] == 'building';

  /// Takes an upload and starts the build. Null when it has started;
  /// otherwise why not, in words for whoever uploaded it.
  Future<String?> install(String file, String source) async {
    final name = nameOf(file);
    if (name == null) {
      return 'The file must be named in lower-case letters, digits and '
          'underscores, starting with a letter and ending .dart: '
          'tide_times.dart.';
    }
    if (utf8.encode(source).length > maxBytes) {
      return 'The file is over 256 KB.';
    }
    if (!_declares.hasMatch(source)) {
      return 'The file must declare its widget for the registry: '
          'final widgetType = DashboardWidgetType(…);';
    }
    // Before the file is written: the build that is running may not have
    // taken its own of this name yet.
    if (building) return 'A build is already running.';
    final incoming = Directory(p.join(state, 'incoming'));
    await incoming.create(recursive: true);
    await File(
      p.join(incoming.path, '$name.dart'),
    ).writeAsString(source, flush: true);
    return _start('install', name);
  }

  /// Takes one out, and builds without it.
  Future<String?> remove(String name) async {
    if (source(name) == null) return 'There is no widget of that name.';
    return _start('remove', name);
  }

  Future<String?> _start(String action, String name) async {
    final root = this.root;
    if (root == null) {
      return 'This panel was not built where it runs, so it cannot build '
          'widgets.';
    }
    if (building) return 'A build is already running.';
    // Said here as well as by the builder, so the editor's first look
    // finds it building rather than whatever the last build left.
    await Directory(state).create(recursive: true);
    await File(p.join(state, 'status.json')).writeAsString(
      jsonEncode({
        'state': 'building',
        'step': 'checking',
        'action': action,
        'name': name,
        'error': '',
        'started': DateTime.now().toUtc().toIso8601String(),
        'finished': null,
      }),
    );
    final started = await _run([
      'bash',
      p.join(root, 'scripts', 'widget-build.sh'),
      action,
      name,
    ]);
    if (!started) {
      await File(p.join(state, 'status.json')).writeAsString(
        jsonEncode({
          'state': 'failed',
          'step': 'checking',
          'action': action,
          'name': name,
          'error': 'The build could not be started.',
        }),
      );
      return 'The build could not be started.';
    }
    return null;
  }

  @visibleForTesting
  static bool declares(String source) => _declares.hasMatch(source);
}

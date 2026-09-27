import 'dart:io';

/// Where [name] is on the PATH, or null when it is not installed.
///
/// What `which` answers, found by looking rather than by starting a process
/// to ask: a Pi playing video has better things to do with a fork.
Future<String?> findOnPath(String name) async {
  for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
    if (dir.isEmpty) continue;
    final file = File('$dir/$name');
    try {
      if (!await file.exists()) continue;
      // Owner, group or anyone may run it: rwxr-xr-x has an x somewhere.
      if ((await file.stat()).modeString().contains('x')) return file.path;
    } catch (_) {}
  }
  return null;
}

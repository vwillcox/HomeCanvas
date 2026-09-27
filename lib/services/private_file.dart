import 'dart:io';

/// Writes [contents] to [path] readable by this user only, and moves it into
/// place whole.
///
/// For files that hold secrets — the config with its passwords and tokens,
/// the share keys, a site's cookies. Made private before anything is in it,
/// rather than written and then locked down, which leaves a moment when
/// anyone on the machine could read it. Written beside the real file and
/// renamed over it, so a power cut part-way through leaves the old file
/// rather than half of the new one. The part file's name is unique, so two
/// saves at once cannot write into the same one.
Future<void> writePrivateFile(String path, String contents) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final part = File('$path.${pid}_${DateTime.now().microsecondsSinceEpoch}.part');
  try {
    await part.writeAsString('');
    await Process.run('chmod', ['600', part.path]);
    await part.writeAsString(contents, flush: true);
    await part.rename(path);
  } catch (_) {
    try {
      await part.delete();
    } catch (_) {}
    rethrow;
  }
}

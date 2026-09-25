import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/app_paths.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('paths'));
  tearDown(() => root.deleteSync(recursive: true));

  test('an old folder moves to the new name, leaving a link behind', () async {
    final old = Directory('${root.path}/immich_kiosk_pi')..createSync();
    File('${old.path}/config.json').writeAsStringSync('{"a":1}');
    final to = Directory('${root.path}/homecanvas');

    await AppPaths.moveFolder(old, to);

    expect(File('${to.path}/config.json').readAsStringSync(), '{"a":1}');
    expect(FileSystemEntity.isLinkSync(old.path), isTrue);
    // Through the link, the old path still finds the same file.
    expect(File('${old.path}/config.json').existsSync(), isTrue);
  });

  test('when the new folder is already there, what it lacks moves across',
      () async {
    // The screen controller can write its log under the new name a moment
    // before the kiosk moves the old folder.
    final old = Directory('${root.path}/immich_kiosk_pi')..createSync();
    File('${old.path}/media.json').writeAsStringSync('cached');
    Directory('${old.path}/media').createSync();
    File('${old.path}/screen_control.log').writeAsStringSync('old log');
    final to = Directory('${root.path}/homecanvas')..createSync();
    File('${to.path}/screen_control.log').writeAsStringSync('new log');

    await AppPaths.moveFolder(old, to);

    expect(File('${to.path}/media.json').readAsStringSync(), 'cached');
    expect(Directory('${to.path}/media').existsSync(), isTrue);
    // Nothing already in the new folder is overwritten.
    expect(File('${to.path}/screen_control.log').readAsStringSync(), 'new log');
  });

  test('an old file that clashes is left where it was, not lost', () async {
    final old = Directory('${root.path}/immich_kiosk_pi')..createSync();
    File('${old.path}/config.json').writeAsStringSync('old');
    final to = Directory('${root.path}/homecanvas')..createSync();
    File('${to.path}/config.json').writeAsStringSync('new');

    await AppPaths.moveFolder(old, to);

    expect(File('${to.path}/config.json').readAsStringSync(), 'new');
    expect(File('${old.path}/config.json').readAsStringSync(), 'old');
    expect(FileSystemEntity.isLinkSync(old.path), isFalse);
  });

  test('a second start does nothing', () async {
    final old = Directory('${root.path}/immich_kiosk_pi')..createSync();
    final to = Directory('${root.path}/homecanvas');
    await AppPaths.moveFolder(old, to);
    await AppPaths.moveFolder(old, to);
    expect(to.existsSync(), isTrue);
  });
}

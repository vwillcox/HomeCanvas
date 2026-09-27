import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/share_inbox_service.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shared');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<File> photo(String name) async =>
      File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);

  test('a photo is deleted once it has been seen', () async {
    final file = await photo('1.jpg');
    final inbox = ShareInboxService(ConfigService());
    await inbox.discard(
        SharedItem(type: ShareType.image, sender: 'Sam', localPath: file.path));
    expect(file.existsSync(), isFalse);
  });

  test('a text share has nothing to delete', () async {
    final inbox = ShareInboxService(ConfigService());
    await inbox.discard(
        SharedItem(type: ShareType.text, sender: 'Sam', content: 'Milk'));
  });

  test('a file already gone is not an error', () async {
    final inbox = ShareInboxService(ConfigService());
    await inbox.discard(SharedItem(
        type: ShareType.video,
        sender: 'Sam',
        localPath: '${dir.path}/missing.mp4'));
  });

  test('what a restart left behind is cleared, the folder kept', () async {
    await photo('1.jpg');
    await photo('2.mp4');
    await ShareInboxService.clearFolder(dir);
    expect(dir.existsSync(), isTrue);
    expect(dir.listSync(), isEmpty);
    // And no folder at all is not an error.
    await ShareInboxService.clearFolder(Directory('${dir.path}/none'));
  });
}

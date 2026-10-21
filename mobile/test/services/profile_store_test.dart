import 'dart:io';
import 'dart:typed_data';

import 'package:civiclens_mobile/services/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('civiclens_profile_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('a profile with no picture resolves to the default avatar', () async {
    final store = ProfileStore(directory: tempDir);

    expect(await store.readAvatarFileName(), isNull);
    expect(await store.resolveAvatar(), isNull);
  });

  test('save and resolve round trip', () async {
    final store = ProfileStore(directory: tempDir);
    final bytes = Uint8List.fromList([10, 20, 30, 40]);

    final fileName = await store.saveAvatar(bytes, extension: 'png');
    expect(fileName, 'avatar.png');

    final resolved = await store.resolveAvatar();
    expect(resolved, isNotNull);
    expect(resolved!.existsSync(), isTrue);
    expect(resolved.lengthSync(), 4);
    expect(resolved.parent.path, contains('profile_images'));
  });

  test('the reference is a file name, not the picture bytes', () async {
    final store = ProfileStore(directory: tempDir);
    await store.saveAvatar(Uint8List.fromList(List<int>.filled(4096, 7)));

    final payload = await File('${tempDir.path}/profile.json').readAsString();

    // Only a small reference is persisted: the image itself lives in its own
    // file and is never embedded as a blob in a preferences-style document.
    expect(payload.length, lessThan(200));
    expect(payload, contains('avatar'));
    expect(payload.contains('AAAA'), isFalse);
  });

  test('the picture survives a fresh store instance', () async {
    await ProfileStore(directory: tempDir)
        .saveAvatar(Uint8List.fromList([1, 2, 3]));

    final reopened = ProfileStore(directory: tempDir);
    final resolved = await reopened.resolveAvatar();

    expect(resolved, isNotNull);
    expect(resolved!.readAsBytesSync(), [1, 2, 3]);
  });

  test('replacing the picture leaves no orphaned file behind', () async {
    final store = ProfileStore(directory: tempDir);
    await store.saveAvatar(Uint8List.fromList([1]), extension: 'png');
    await store.saveAvatar(Uint8List.fromList([2, 2]), extension: 'jpg');

    final images = Directory('${tempDir.path}/profile_images')
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .toList();

    expect(images, hasLength(1));
    expect(images.single, endsWith('avatar.jpg'));

    final resolved = await store.resolveAvatar();
    expect(resolved!.lengthSync(), 2);
  });

  test(
    'a picture removed from disk falls back to the default avatar',
    () async {
      final store = ProfileStore(directory: tempDir);
      await store.saveAvatar(Uint8List.fromList([1, 2, 3]));

      // The reference survives but the file itself is gone (app storage
      // cleanup, a restored backup, ...): the screen must not crash on it.
      Directory('${tempDir.path}/profile_images')
          .listSync()
          .whereType<File>()
          .forEach((file) => file.deleteSync());

      expect(await store.resolveAvatar(), isNull);
    },
  );

  test('clearAvatar removes the picture and its reference', () async {
    final store = ProfileStore(directory: tempDir);
    await store.saveAvatar(Uint8List.fromList([1, 2, 3]));
    await store.clearAvatar();

    expect(await store.readAvatarFileName(), isNull);
    expect(await store.resolveAvatar(), isNull);
    expect(Directory('${tempDir.path}/profile_images').listSync(), isEmpty);
  });

  test('an unreadable reference is treated as no picture', () async {
    final store = ProfileStore(directory: tempDir);
    await File('${tempDir.path}/profile.json').writeAsString('{ not json');

    expect(await store.readAvatarFileName(), isNull);
    expect(await store.resolveAvatar(), isNull);
  });

  test('a malformed reference is ignored instead of throwing', () async {
    final store = ProfileStore(directory: tempDir);
    await File('${tempDir.path}/profile.json')
        .writeAsString('{"version":1,"avatarFileName":1234}');

    expect(await store.readAvatarFileName(), isNull);
    expect(await store.resolveAvatar(), isNull);
  });

  test('extensions are sanitised', () async {
    final store = ProfileStore(directory: tempDir);

    expect(
      await store.saveAvatar(Uint8List.fromList([1]), extension: 'Png'),
      'avatar.png',
    );
    expect(
      await store.saveAvatar(Uint8List.fromList([1]), extension: 'e.f/g'),
      'avatar.efg',
    );
    expect(
      await store.saveAvatar(Uint8List.fromList([1]), extension: ''),
      'avatar.jpg',
    );
  });
}

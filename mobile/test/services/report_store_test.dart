import 'dart:io';
import 'dart:typed_data';

import 'package:civiclens_mobile/services/report_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('civiclens_store_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('image save, resolve, delete', () async {
    final store = ReportStore(directory: tempDir);
    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    final fileName = await store.saveReportImage(
      'CL-R1',
      bytes,
      extension: 'png',
    );

    expect(fileName, isNotNull);
    expect(fileName!.endsWith('.png'), isTrue);

    final resolved = await store.resolveImage(fileName);
    expect(resolved, isNotNull);
    expect(resolved!.existsSync(), isTrue);
    expect(resolved.lengthSync(), 4);

    await store.deleteImage(fileName);
    final missing = await store.resolveImage(fileName);
    expect(missing, isNull);
  });

  test('resolveImage returns null for missing or empty', () async {
    final store = ReportStore(directory: tempDir);
    expect(await store.resolveImage(null), isNull);
    expect(await store.resolveImage(''), isNull);
    expect(await store.resolveImage('nope.jpg'), isNull);
  });

  test('lazily resolves a cache directory from the provider', () async {
    final store = ReportStore(directoryProvider: () async => tempDir);

    final fileName = await store.saveReportImage(
      'r1',
      Uint8List.fromList(const [1, 2]),
    );

    expect(fileName, isNotNull);
    expect(await store.resolveImage(fileName), isNotNull);
  });

  test(
    'never throws and caches nothing when no directory is available',
    () async {
      final store = ReportStore(
        directoryProvider: () async => throw StateError('no cache directory'),
      );

      expect(
        await store.saveReportImage('r1', Uint8List.fromList(const [1, 2])),
        isNull,
      );
      expect(await store.resolveImage('r1.jpg'), isNull);
      await store.deleteImage('r1.jpg');
    },
  );
}

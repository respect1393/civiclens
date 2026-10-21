import 'dart:io';
import 'dart:typed_data';

import 'package:civiclens_mobile/services/report_store.dart';

/// In-memory [ReportStore] used by widget tests.
///
/// Widget tests run inside `AutomatedTestWidgetsFlutterBinding`'s FakeAsync
/// zone. dart:io operations started in that zone never deliver their
/// completion (the test body's microtask chain starves the real event loop),
/// so any repository call that awaits disk I/O would stall forever and
/// `notifyListeners()` would never run.
///
/// This double keeps the photo cache in memory and resolves with plain
/// futures, which the test binding flushes while pumping. Real on-disk
/// behaviour is covered separately by `test/services/report_store_test.dart`.
class FakeReportStore extends ReportStore {
  FakeReportStore();

  /// In-memory image payloads keyed by stored file name.
  final Map<String, Uint8List> savedImages = <String, Uint8List>{};

  @override
  Future<String?> saveReportImage(
    String reportId,
    Uint8List bytes, {
    String extension = 'jpg',
  }) async {
    final fileName = '$reportId.${_sanitizeExtension(extension)}';
    savedImages[fileName] = bytes;
    return fileName;
  }

  @override
  Future<File?> resolveImage(String? fileName) async {
    if (fileName == null || fileName.trim().isEmpty) return null;
    // No real file is created in widget tests, so callers fall back to their
    // placeholder rendering instead of decoding bytes.
    return null;
  }

  @override
  Future<void> deleteImage(String? fileName) async {
    if (fileName == null || fileName.trim().isEmpty) return;
    savedImages.remove(fileName);
  }

  String _sanitizeExtension(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
    return cleaned.isEmpty ? 'jpg' : cleaned;
  }
}

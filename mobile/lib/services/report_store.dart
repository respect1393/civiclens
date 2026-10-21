import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A short-lived, best-effort cache of report photo bytes on the device.
///
/// This is **not** a report database: the backend is the only durable home for
/// reports and their images. The cache exists solely so a photo the citizen just
/// attached renders instantly (and keeps working if the network is slow). Every
/// method therefore degrades gracefully: when no writable directory is available
/// the store silently does nothing instead of throwing. A failure to cache must
/// never be treated as a failure to submit a report.
class ReportStore {
  ReportStore({
    Directory? directory,
    this.folderName = 'civiclens',
    Future<Directory> Function()? directoryProvider,
  }) : _baseDirectory = directory,
       _directoryProvider = directoryProvider ?? getTemporaryDirectory;

  final String folderName;

  /// An explicitly injected cache root, or null to resolve one lazily.
  final Directory? _baseDirectory;

  /// Resolves the cache root lazily when no [Directory] was injected.
  ///
  /// Defaults to the OS temporary/cache directory, which the system may purge
  /// at any time — exactly the right lifetime for a cache. Tests inject
  /// [directory] (or a [directoryProvider]) to avoid touching platform plugins.
  final Future<Directory> Function() _directoryProvider;

  static const String _imagesFolderName = 'report_images';

  /// Resolves (and creates) the image cache directory, or null when unavailable.
  ///
  /// Returns null — never throws — when neither an injected directory nor a
  /// platform-provided one can be obtained, so callers can treat caching as
  /// optional.
  Future<Directory?> _imagesDirectory() async {
    try {
      final base = _baseDirectory ?? await _directoryProvider();
      final images = Directory(p.join(base.path, _imagesFolderName));
      if (!await images.exists()) {
        await images.create(recursive: true);
      }
      return images;
    } catch (_) {
      return null;
    }
  }

  /// Copies raw image bytes into the cache and returns the file name that should
  /// be referenced from the in-memory report.
  ///
  /// Returns null when no cache directory is available or the write fails; the
  /// caller must continue without a cached copy.
  Future<String?> saveReportImage(
    String reportId,
    Uint8List bytes, {
    String extension = 'jpg',
  }) async {
    final images = await _imagesDirectory();
    if (images == null) return null;
    try {
      final safeId = _sanitizeFileName(reportId);
      final safeExtension = _sanitizeExtension(extension);
      final fileName = '$safeId.$safeExtension';
      final file = File(p.join(images.path, fileName));
      await file.writeAsBytes(bytes, flush: true);
      return fileName;
    } catch (_) {
      return null;
    }
  }

  /// Resolves a stored file name to an existing file, or null when missing.
  Future<File?> resolveImage(String? fileName) async {
    if (fileName == null || fileName.trim().isEmpty) return null;
    final images = await _imagesDirectory();
    if (images == null) return null;
    final file = File(p.join(images.path, fileName));
    return await file.exists() ? file : null;
  }

  /// Deletes a stored image if it exists.
  Future<void> deleteImage(String? fileName) async {
    if (fileName == null || fileName.trim().isEmpty) return;
    try {
      final images = await _imagesDirectory();
      if (images == null) return;
      final file = File(p.join(images.path, fileName));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Deleting a missing image is not an error for callers.
    }
  }

  String _sanitizeFileName(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? 'photo' : safe;
  }

  String _sanitizeExtension(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return safe.isEmpty ? 'jpg' : safe;
  }
}

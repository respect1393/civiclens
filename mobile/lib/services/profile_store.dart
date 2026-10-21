import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Device-local storage for the citizen's own profile picture.
///
/// Design mirrors [ReportStore] on purpose:
/// * the picture bytes live in their own file inside the app documents
///   directory (`profile_images/`), and
/// * `profile.json` stores only the small file *name* reference.
///
/// This keeps a large base64 blob out of preferences and means a missing or
/// corrupted picture degrades to the default avatar instead of breaking the
/// screen. The picture stays on the device and never leaves it. This
/// store never deletes data it cannot understand: an unreadable reference is
/// treated as "no picture".
class ProfileStore {
  ProfileStore({Directory? directory, this.folderName = 'civiclens'})
    : _baseDirectory = directory;

  static const String _profileFileName = 'profile.json';
  static const String _imagesFolderName = 'profile_images';

  final String folderName;
  Directory? _baseDirectory;

  /// Resolves (and lazily creates) the directory that holds app data.
  Future<Directory> _resolveBaseDirectory() async {
    final existing = _baseDirectory;
    if (existing != null) {
      if (!await existing.exists()) {
        await existing.create(recursive: true);
      }
      return existing;
    }

    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, folderName));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _baseDirectory = directory;
    return directory;
  }

  Future<File> _profileFile() async {
    final directory = await _resolveBaseDirectory();
    return File(p.join(directory.path, _profileFileName));
  }

  Future<Directory> _imagesDirectory() async {
    final directory = await _resolveBaseDirectory();
    final images = Directory(p.join(directory.path, _imagesFolderName));
    if (!await images.exists()) {
      await images.create(recursive: true);
    }
    return images;
  }

  /// The saved picture's file name, or null when none was ever saved.
  ///
  /// Any unreadable or malformed document is reported as "no picture" rather
  /// than throwing, so a bad file can never break the profile screen.
  Future<String?> readAvatarFileName() async {
    final file = await _profileFile();
    if (!await file.exists()) return null;

    String raw;
    try {
      raw = await file.readAsString();
    } catch (_) {
      return null;
    }
    if (raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final name = decoded['avatarFileName'];
      if (name is! String) return null;
      final trimmed = name.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  /// Resolves the saved picture to an existing file, or null when it is
  /// missing from disk (for example after the user cleared app storage).
  Future<File?> resolveAvatar() async {
    final name = await readAvatarFileName();
    if (name == null) return null;

    final images = await _imagesDirectory();
    final file = File(p.join(images.path, name));
    return await file.exists() ? file : null;
  }

  /// Writes new picture bytes and returns the stored file name.
  ///
  /// A previously saved picture is removed when its name changes so replacing
  /// the avatar does not leave orphaned files behind.
  Future<String> saveAvatar(Uint8List bytes, {String extension = 'jpg'}) async {
    final images = await _imagesDirectory();
    final previousName = await readAvatarFileName();
    final fileName = 'avatar.${_sanitizeExtension(extension)}';

    final file = File(p.join(images.path, fileName));
    await file.writeAsBytes(bytes, flush: true);

    if (previousName != null && previousName != fileName) {
      final previous = File(p.join(images.path, previousName));
      try {
        if (await previous.exists()) await previous.delete();
      } catch (_) {
        // An orphaned file is harmless; never fail the save because of it.
      }
    }

    await _writeProfileFile(fileName);
    return fileName;
  }

  /// Removes the saved picture, returning the profile to its default avatar.
  Future<void> clearAvatar() async {
    final name = await readAvatarFileName();
    if (name != null) {
      final images = await _imagesDirectory();
      final file = File(p.join(images.path, name));
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Deleting a missing picture is not an error for callers.
      }
    }
    await _writeProfileFile(null);
  }

  Future<void> _writeProfileFile(String? avatarFileName) async {
    final file = await _profileFile();
    final payload = jsonEncode({
      'version': 1,
      'avatarFileName': avatarFileName,
    });

    final temp = File('${file.path}.tmp');
    await temp.writeAsString(payload, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
  }

  String _sanitizeExtension(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
    return cleaned.isEmpty ? 'jpg' : cleaned;
  }
}

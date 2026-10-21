import 'dart:io';
import 'dart:typed_data';

import 'package:civiclens_mobile/services/profile_store.dart';

/// In-memory [ProfileStore] used by widget tests.
///
/// Widget tests run inside `AutomatedTestWidgetsFlutterBinding`'s FakeAsync
/// zone. dart:io operations started in that zone never deliver their
/// completion, so any call that awaited real disk I/O (or the
/// `path_provider` platform channel) would stall forever. This double keeps
/// the picture in a plain variable and still exercises the same
/// save/resolve/clear contract as production.
///
/// Real on-disk persistence is covered separately by
/// `test/services/profile_store_test.dart`.
class FakeProfileStore extends ProfileStore {
  FakeProfileStore({File? initialAvatar}) : avatar = initialAvatar;

  /// The current picture, or null when the default avatar is used.
  File? avatar;

  /// Bytes handed to the last [saveAvatar].
  Uint8List? savedBytes;

  int saveCount = 0;
  int clearCount = 0;

  /// When true every read throws, so an unreadable reference (a deleted or
  /// corrupted file) can be exercised as the "fall back to default" path.
  bool failReads = false;

  /// When true every write throws, so a failed save can be observed.
  bool failWrites = false;

  @override
  Future<String?> readAvatarFileName() async {
    if (failReads) throw StateError('Simulated unreadable profile reference');
    return avatar == null ? null : _nameOf(avatar!);
  }

  @override
  Future<File?> resolveAvatar() async {
    if (failReads) throw StateError('Simulated unreadable profile reference');
    return avatar;
  }

  @override
  Future<String> saveAvatar(Uint8List bytes, {String extension = 'jpg'}) async {
    if (failWrites) throw StateError('Simulated write failure');
    saveCount++;
    savedBytes = bytes;
    final name = 'avatar.$extension';
    avatar = File('/fake/civiclens/profile_images/$name');
    return name;
  }

  @override
  Future<void> clearAvatar() async {
    if (failWrites) throw StateError('Simulated write failure');
    clearCount++;
    avatar = null;
  }

  String _nameOf(File file) {
    final path = file.path;
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}

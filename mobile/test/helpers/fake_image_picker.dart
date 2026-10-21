import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// In-memory [ImagePicker] double.
///
/// Widget tests run in a FakeAsync zone and have no camera, gallery or
/// platform channel, so the report form is given one of these to attach photo
/// evidence without touching the device.
class FakeImagePicker extends ImagePicker {
  FakeImagePicker({this.file});

  /// File returned by [pickImage]; null simulates the citizen backing out.
  final XFile? file;

  /// Number of [pickImage] calls, so tests can prove which source was used.
  int pickCalls = 0;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    pickCalls++;
    return file;
  }
}

/// Builds an in-memory photo whose file name decides the stored photo format.
///
/// The bytes never hit disk: [XFile.fromData] serves them from memory, which
/// the FakeAsync test zone can always complete.
XFile fakePhoto({String name = 'evidence.png', int length = 64}) {
  return XFile.fromData(
    Uint8List.fromList(List<int>.filled(length, 1)),
    path: name,
    mimeType: 'image/png',
  );
}

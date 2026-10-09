import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

enum ReceiptSource { camera, gallery }

/// Takes or chooses the photo of a receipt (Beleg). Behind an interface so tests do not need a camera.
abstract class ReceiptPicker {
  /// The path of a private copy of the photo (it stays until it is sent or thrown away), or null if
  /// the user cancelled.
  Future<String?> pick(ReceiptSource source);
}

class ImagePickerReceiptPicker implements ReceiptPicker {
  ImagePickerReceiptPicker(this._directory);

  final Future<String> Function() _directory;

  @override
  Future<String?> pick(ReceiptSource source) async {
    // Scaled down and compressed: still sharp enough to read small print, but about 0.5 MB.
    final picked = await ImagePicker().pickImage(
      source: source == ReceiptSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2800,
      imageQuality: 85,
    );
    if (picked == null) return null;
    // Copy into the app's private storage: the picker's cache can be cleared by the system.
    final target = p.join(await _directory(), 'receipt_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await File(picked.path).copy(target);
    return target;
  }
}

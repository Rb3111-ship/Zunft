import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Makes the small picture (about 400 pixels) that is stored next to a job photo, so a job with
/// many photos does not have to download every full picture just to show the overview.
abstract class ThumbnailMaker {
  /// A small JPEG of [photo], or null if it could not be made (the photo is then simply shown
  /// from the full picture).
  Future<Uint8List?> make(Uint8List photo);
}

class CompressThumbnailMaker implements ThumbnailMaker {
  const CompressThumbnailMaker();

  @override
  Future<Uint8List?> make(Uint8List photo) async {
    try {
      final small = await FlutterImageCompress.compressWithList(photo, minWidth: 400, minHeight: 400, quality: 70, format: CompressFormat.jpeg);
      return small.isEmpty ? null : small;
    } catch (_) {
      return null;
    }
  }
}

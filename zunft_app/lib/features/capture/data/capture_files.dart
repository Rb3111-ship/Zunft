import 'dart:io';
import 'dart:typed_data';

/// Access to the recordings stored on the device. Behind an interface so tests do not touch
/// the real disk (real file I/O cannot complete inside a widget test's simulated clock).
abstract class CaptureFiles {
  /// Throws [FileSystemException] if the file does not exist or cannot be read.
  Future<Uint8List> read(String path);

  /// Deletes the file if it exists. Never throws for a missing file.
  Future<void> delete(String path);
}

class DiskCaptureFiles implements CaptureFiles {
  const DiskCaptureFiles();

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

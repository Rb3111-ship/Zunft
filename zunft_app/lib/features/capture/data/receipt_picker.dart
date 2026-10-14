import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

/// camera: the document scanner (finds the paper, straightens and brightens it); gallery: a photo
/// from the phone; file: a PDF or image file (e.g. an invoice a supplier sent by e-mail); photo: the
/// plain camera, for pictures of the work on a job.
enum ReceiptSource { camera, gallery, file, photo }

/// Takes or chooses the photo (or PDF) of a receipt (Beleg). Behind an interface so tests do not
/// need a camera.
abstract class ReceiptPicker {
  /// The path of a private copy (it stays until it is sent or thrown away), or null if the user
  /// cancelled.
  Future<String?> pick(ReceiptSource source);
}

/// Is [path] a PDF (as opposed to a photo)?
bool isPdfPath(String path) => path.toLowerCase().endsWith('.pdf');

class ImagePickerReceiptPicker implements ReceiptPicker {
  ImagePickerReceiptPicker(this._directory);

  final Future<String> Function() _directory;

  @override
  Future<String?> pick(ReceiptSource source) async {
    final original = switch (source) {
      ReceiptSource.camera => await _scan(),
      ReceiptSource.gallery => await _fromGallery(),
      ReceiptSource.file => await _fromFile(),
      ReceiptSource.photo => await _fromCamera(),
    };
    if (original == null) return null;
    // Copy into the app's private storage: the picker's cache can be cleared by the system.
    final ext = p.extension(original).toLowerCase();
    final target = p.join(await _directory(), 'receipt_${DateTime.now().microsecondsSinceEpoch}${ext.isEmpty ? '.jpg' : ext}');
    await File(original).copy(target);
    return target;
  }

  /// The document scanner finds the edges of the paper and straightens it, which makes small print
  /// much easier to read. If it is not available on this phone, the plain camera is used.
  Future<String?> _scan() async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: {DocumentFormat.jpeg},
        pageLimit: 1,
        mode: ScannerMode.full,
        isGalleryImport: false,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      final images = result.images ?? const <String>[];
      return images.isEmpty ? null : images.first;
    } on PlatformException catch (e) {
      if ((e.message ?? '').toLowerCase().contains('cancel')) return null; // the user backed out
      return _fromCamera();
    } catch (_) {
      return _fromCamera();
    } finally {
      try {
        await scanner.close();
      } catch (_) {}
    }
  }

  // Scaled down and compressed: still sharp enough to read small print, but about 0.5 MB.
  Future<String?> _fromCamera() async => (await ImagePicker()
          .pickImage(source: ImageSource.camera, maxWidth: 2000, maxHeight: 2800, imageQuality: 85))
      ?.path;

  Future<String?> _fromGallery() async => (await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 2000, maxHeight: 2800, imageQuality: 85))
      ?.path;

  Future<String?> _fromFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    return files.isEmpty ? null : files.first.path;
  }
}

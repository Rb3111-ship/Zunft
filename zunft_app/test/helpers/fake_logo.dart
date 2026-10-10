import 'dart:convert';
import 'dart:typed_data';

import 'package:zunft_app/features/documents/data/logo_store.dart';

/// A tiny valid 1x1 PNG, so the PDF generator can really embed it.
final Uint8List onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

class FakeLogoStore implements LogoStore {
  final Map<String, Uint8List> files = {};
  final List<String> uploaded = [];
  bool failUpload = false;
  bool failLoad = false;

  @override
  Future<Uint8List?> load(String? path) async {
    if (path == null) return null;
    if (failLoad) throw Exception('offline');
    return files[path];
  }

  @override
  Future<String> upload(String businessId, Uint8List bytes, String extension) async {
    if (failUpload) throw Exception('offline');
    final path = '$businessId/logo/logo-${uploaded.length + 1}.$extension';
    files[path] = bytes;
    uploaded.add(path);
    return path;
  }
}

class FakeLogoPicker implements LogoPicker {
  ({Uint8List bytes, String extension})? next;

  @override
  Future<({Uint8List bytes, String extension})?> pick() async => next;
}

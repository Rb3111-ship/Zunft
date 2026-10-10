import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The logo of the business, printed on every PDF. Stored in the private "documents" bucket
/// (under "<business id>/logo/") and cached on the phone so a PDF can be made offline.
abstract class LogoStore {
  /// The bytes of the logo at [path], or null if there is none or it cannot be loaded (a PDF is
  /// then made without a logo; it must never fail because of this).
  Future<Uint8List?> load(String? path);

  /// Stores a new logo and returns its path.
  Future<String> upload(String businessId, Uint8List bytes, String extension);
}

class SupabaseLogoStore implements LogoStore {
  SupabaseLogoStore(this._client, this._cacheDirectory);

  final SupabaseClient _client;
  final Future<String> Function() _cacheDirectory;

  static const _timeout = Duration(seconds: 15);

  Future<File> _cacheFile(String path) async =>
      File(p.join(await _cacheDirectory(), path.replaceAll(RegExp(r'[\/]'), '_')));

  @override
  Future<Uint8List?> load(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final cached = await _cacheFile(path);
      if (await cached.exists()) return await cached.readAsBytes();
      final bytes = await _client.storage.from('documents').download(path).timeout(_timeout);
      await cached.writeAsBytes(bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> upload(String businessId, Uint8List bytes, String extension) async {
    final ext = extension.toLowerCase() == 'png' ? 'png' : 'jpg';
    final path = '$businessId/logo/logo-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('documents').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'),
        ).timeout(_timeout);
    final cached = await _cacheFile(path);
    await cached.writeAsBytes(bytes);
    return path;
  }
}

/// Chooses the logo image from the phone's gallery. Behind an interface so tests need no gallery.
abstract class LogoPicker {
  Future<({Uint8List bytes, String extension})?> pick();
}

class GalleryLogoPicker implements LogoPicker {
  @override
  Future<({Uint8List bytes, String extension})?> pick() async {
    // Scaled down: a logo does not need more, and it keeps the PDF small.
    final file =
        await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 400, imageQuality: 90);
    if (file == null) return null;
    return (bytes: await file.readAsBytes(), extension: p.extension(file.path).replaceFirst('.', ''));
  }
}

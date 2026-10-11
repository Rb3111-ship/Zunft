import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/receipt_entry.dart';

/// The receipts could not be read (usually: no connection).
class ReceiptsException implements Exception {
  const ReceiptsException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Server access for the receipt archive. Faked in tests.
abstract class ReceiptsRemote {
  /// Every photographed receipt of the business (billed, open and removed ones), newest first.
  Future<List<ReceiptEntry>> fetchAll();

  /// The stored photo.
  Future<Uint8List> downloadPhoto(String imagePath);
}

class SupabaseReceiptsRemote implements ReceiptsRemote {
  SupabaseReceiptsRemote(this._client);

  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 30);

  @override
  Future<List<ReceiptEntry>> fetchAll() async {
    try {
      final rows = await _client
          .from('capture_logs')
          .select('id, created_at, created_by_name, job_id, document_id, discarded_at, photo_storage_paths, '
              'ai_parsed_json, profiles(full_name), jobs(title), documents(doc_number)')
          .not('image_sha256', 'is', null)
          .order('created_at', ascending: false)
          .limit(2000)
          .timeout(_timeout);
      return [
        for (final r in rows)
          if (((r['photo_storage_paths'] as List?) ?? const []).isNotEmpty)
            ReceiptEntry.fromRow(Map<String, dynamic>.from(r))
      ];
    } catch (_) {
      throw const ReceiptsException('Die Belege konnten nicht geladen werden. Bitte Internetverbindung prüfen.');
    }
  }

  @override
  Future<Uint8List> downloadPhoto(String imagePath) =>
      _client.storage.from('captures').download(imagePath).timeout(_timeout);
}

/// Hands a finished file to the share sheet of the phone (mail, Drive, WhatsApp, ...). Faked in tests.
abstract class FileSharer {
  Future<void> share(Uint8List bytes, String fileName, {String? subject, String mimeType = 'application/zip'});
}

class SharePlusFileSharer implements FileSharer {
  @override
  Future<void> share(Uint8List bytes, String fileName, {String? subject, String mimeType = 'application/zip'}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mimeType)], subject: subject));
  }
}

import '../../../core/i18n/i18n.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// No usable network. The operation did not happen (or its result is unknown) - retry later.
class DocumentOfflineException implements Exception {
  const DocumentOfflineException([this.cause]);
  final Object? cause;
}

/// The login is no longer valid.
class DocumentAuthException implements Exception {
  const DocumentAuthException();
}

/// The server refused the request. [message] is German and safe to show.
class DocumentRejectedException implements Exception {
  const DocumentRejectedException(this.message);
  final String message;
}

/// Server calls for issued documents. Faked in tests.
abstract class DocumentsRemote {
  /// Calls create_document(): validates, computes totals, issues the number and stores the
  /// document in one transaction. Repeating the call with the same `id` returns the same row.
  Future<Map<String, dynamic>> createDocument(Map<String, dynamic> payload);

  /// Calls cancel_document(): issues a Stornorechnung (negative copy) for an invoice and marks the
  /// invoice cancelled. Returns {cancellation: row, original: row}. Repeating it with the same id is safe.
  Future<Map<String, dynamic>> cancelDocument(String id, String originalId);

  /// Moves the status forward (sent / paid). The database enforces the allowed transitions.
  Future<void> updateStatus(String id, String status);

  Future<void> uploadPdf(String path, Uint8List bytes);

  Future<void> setPdfPath(String id, String path);

  Future<Uint8List> downloadPdf(String path);
}

class SupabaseDocumentsRemote implements DocumentsRemote {
  SupabaseDocumentsRemote(this._client);

  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 30);

  @override
  Future<Map<String, dynamic>> createDocument(Map<String, dynamic> payload) => _guard(() async {
        final res = await _client.rpc('create_document', params: {'p': payload});
        return Map<String, dynamic>.from(res as Map);
      });

  @override
  Future<Map<String, dynamic>> cancelDocument(String id, String originalId) => _guard(() async {
        final res = await _client.rpc('cancel_document', params: {
          'p': {'id': id, 'original_id': originalId}
        });
        return Map<String, dynamic>.from(res as Map);
      });

  @override
  Future<void> updateStatus(String id, String status) =>
      _guard(() async => _client.from('documents').update({'status': status}).eq('id', id));

  @override
  Future<void> uploadPdf(String path, Uint8List bytes) => _guard(() async {
        await _client.storage.from('documents').uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
            );
      });

  @override
  Future<void> setPdfPath(String id, String path) =>
      _guard(() async => _client.from('documents').update({'pdf_url': path}).eq('id', id));

  @override
  Future<Uint8List> downloadPdf(String path) => _guard(() => _client.storage.from('documents').download(path));

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(_timeout);
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (e.code == 'PGRST301' || e.code == 'PGRST303' || msg.contains('jwt')) throw const DocumentAuthException();
      throw DocumentRejectedException(_germanMessage(msg));
    } on StorageException catch (e) {
      if (e.statusCode == '401') throw const DocumentAuthException();
      final code = int.tryParse(e.statusCode ?? '');
      if (code != null && code >= 400 && code < 500)
        throw DocumentRejectedException('Die Datei wurde abgelehnt.'.tr);
      throw DocumentOfflineException(e);
    } on AuthException {
      throw const DocumentAuthException();
    } catch (e) {
      throw DocumentOfflineException(e);
    }
  }

  /// The database's validation messages, translated for the user.
  static String _germanMessage(String message) {
    if (message.contains('business address is incomplete')) {
      return 'Bitte zuerst die Anschrift deines Betriebs unter „Betrieb“ eintragen.'.tr;
    }
    if (message.contains('tax number or vat id')) {
      return 'Bitte zuerst Steuernummer oder USt-IdNr. unter „Betrieb“ eintragen.'.tr;
    }
    if (message.contains('recipient address is required')) {
      return 'Bei Rechnungen über 250 € muss die Anschrift des Kunden angegeben werden.'.tr;
    }
    if (message.contains('already paid')) {
      return 'Die Rechnung ist schon als bezahlt markiert. Bitte zuerst mit dem Steuerberater klären, wie sie zu korrigieren ist.'.tr;
    }
    if (message.contains('already cancelled')) return 'Diese Rechnung wurde schon storniert.'.tr;
    if (message.contains('only invoices')) return 'Nur Rechnungen können storniert werden.'.tr;
    if (message.contains('recipient name')) return 'Bitte den Namen des Kunden angeben.'.tr;
    if (message.contains('customer does not belong')) return 'Dieser Kunde existiert nicht mehr.'.tr;
    if (message.contains('job does not belong')) return 'Dieser Auftrag existiert nicht mehr.'.tr;
    if (message.contains('date_issued')) return 'Das Datum liegt außerhalb des erlaubten Bereichs.'.tr;
    if (message.contains('line item') || message.contains('line_items')) {
      return 'Mindestens eine Position ist ungültig (Menge, Preis oder Bezeichnung).'.tr;
    }
    if (message.contains('not allowed')) return 'Dafür fehlt die Berechtigung.'.tr;
    return 'Das Dokument konnte nicht erstellt werden.'.tr;
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'storage_status.dart';

/// No usable network, or the server did not answer. Keep the capture queued and retry later.
class CaptureOfflineException implements Exception {
  const CaptureOfflineException([this.cause]);
  final Object? cause;
}

/// The login is no longer valid. Stop and wait for the user to sign in again.
class CaptureAuthException implements Exception {
  const CaptureAuthException();
}

/// A temporary server problem (5xx, overloaded AI). Worth a few automatic retries.
class CaptureTransientException implements Exception {
  const CaptureTransientException(this.message);
  final String message;
}

/// The server will not accept this input as it is (too long, nothing understood, not allowed).
/// Retrying the same input without the user does not help.
class CaptureRejectedException implements Exception {
  const CaptureRejectedException(this.message);
  final String message;
}

/// What the process-capture Edge Function sends back.
class CaptureResponse {
  const CaptureResponse(this.json);
  final Map<String, dynamic> json;

  String? get jobId => json['jobId'] as String?;
}

/// The two server calls the capture flow needs. Faked in tests.
abstract class CaptureRemote {
  /// Uploads the recording to private storage at [path] ("<business id>/<user id>/<capture id>.m4a").
  /// Uploading the same path twice is not an error (a retry after a lost answer).
  Future<void> uploadAudio(String path, Uint8List bytes);

  /// Uploads the photo (or PDF) of a receipt to private storage at [path] ("<business id>/<user id>/<capture id>.jpg").
  Future<void> uploadImage(String path, Uint8List bytes);

  /// Used and included storage of the business.
  Future<StorageStatus> storageStatus();

  /// Asks the Edge Function to transcribe and structure a note and to store it on [jobId].
  /// [captureId] makes the call idempotent: the server returns the stored result instead of
  /// storing the note twice.
  Future<CaptureResponse> process({
    required String captureId,
    required String jobId,
    String? audioStoragePath,
    String? imageStoragePath,
    String? transcript,
  });
}

class SupabaseCaptureRemote implements CaptureRemote {
  SupabaseCaptureRemote(this._client);

  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 90); // speech recognition + AI can take a while

  @override
  Future<StorageStatus> storageStatus() async {
    try {
      final res = await _client.rpc('storage_status').timeout(_timeout);
      return StorageStatus.fromJson(Map<String, dynamic>.from(res as Map));
    } on AuthException {
      throw const CaptureAuthException();
    } catch (e) {
      throw CaptureOfflineException(e);
    }
  }

  @override
  Future<void> uploadAudio(String path, Uint8List bytes) => _upload(path, bytes, 'audio/mp4', 'Die Aufnahme');

  @override
  Future<void> uploadImage(String path, Uint8List bytes) {
    final ext = path.toLowerCase().split('.').last;
    final type = switch (ext) { 'pdf' => 'application/pdf', 'png' => 'image/png', _ => 'image/jpeg' };
    return _upload(path, bytes, type, 'Die Datei');
  }

  Future<void> _upload(String path, Uint8List bytes, String contentType, String what) async {
    try {
      await _client.storage
          .from('captures')
          .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: false))
          .timeout(_timeout);
    } on StorageException catch (e) {
      final code = int.tryParse(e.statusCode ?? '');
      if (code == 409 || (e.message.toLowerCase().contains('already exists'))) return; // already there
      if (code == 401) throw const CaptureAuthException();
      if (code == 403) {
        // Refused: is the plan's storage full? Then say so instead of a vague "rejected".
        try {
          if ((await storageStatus()).full) {
            throw const CaptureRejectedException(
                'Der Speicher deines Pakets ist voll. Für neue Aufnahmen und Belege wird ein größeres Paket gebraucht.');
          }
        } on CaptureRejectedException {
          rethrow;
        } catch (_) {}
      }
      if (code == 403 || code == 400 || code == 413) {
        throw CaptureRejectedException(code == 413 ? '$what ist zu groß.' : 'Der Upload wurde abgelehnt.');
      }
      if (code != null && code >= 500) throw const CaptureTransientException('Der Server ist gerade nicht erreichbar.');
      throw CaptureOfflineException(e);
    } on AuthException {
      throw const CaptureAuthException();
    } catch (e) {
      throw CaptureOfflineException(e);
    }
  }

  @override
  Future<CaptureResponse> process({
    required String captureId,
    required String jobId,
    String? audioStoragePath,
    String? imageStoragePath,
    String? transcript,
  }) async {
    try {
      final res = await _client.functions.invoke('process-capture', body: {
        'captureId': captureId,
        'jobId': jobId,
        if (audioStoragePath != null) 'audioStoragePath': audioStoragePath,
        if (imageStoragePath != null) 'imageStoragePath': imageStoragePath,
        if (transcript != null) 'directTranscript': transcript,
      }).timeout(_timeout);

      final data = res.data;
      if (data is Map && data['success'] == true) return CaptureResponse(Map<String, dynamic>.from(data));
      throw const CaptureTransientException('Unerwartete Antwort vom Server.');
    } on FunctionException catch (e) {
      throw _fromStatus(e.status, e.details);
    } on CaptureTransientException {
      rethrow;
    } on AuthException {
      throw const CaptureAuthException();
    } catch (e) {
      throw CaptureOfflineException(e);
    }
  }

  static Exception _fromStatus(int status, Object? details) {
    final serverMessage = details is Map && details['error'] is String ? details['error'] as String : null;
    if (status == 401) return const CaptureAuthException();
    if (status == 413) return const CaptureRejectedException('Die Datei ist zu groß.');
    if (status == 400 || status == 403 || status == 404) {
      return CaptureRejectedException(serverMessage ?? 'Die Notiz konnte nicht verarbeitet werden.');
    }
    if (status == 422) {
      // The AI could not make a usable draft this time. The user can try again or type it.
      return CaptureRejectedException(serverMessage ?? 'Aus der Notiz konnte kein Entwurf erstellt werden.');
    }
    return CaptureTransientException(serverMessage ?? 'Der Server ist gerade nicht erreichbar.');
  }
}

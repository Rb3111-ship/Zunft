import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/i18n/i18n.dart';
import '../domain/job_photo.dart';

/// The photos could not be read or changed (usually: no connection).
class JobPhotosException implements Exception {
  const JobPhotosException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Server access for the photos of jobs. Faked in tests. (Adding a photo goes through the capture
/// queue, because it must also work without a connection on site.)
abstract class JobPhotosRemote {
  /// The photos of one job, oldest first (RLS: only jobs the person can see).
  Future<List<JobPhoto>> fetchForJob(String jobId);

  /// Every photo of the business (boss and office), for the full export.
  Future<List<JobPhoto>> fetchAll();

  /// The stored picture.
  Future<Uint8List> download(String path);

  /// Removes the photo and its file.
  Future<void> delete(String id);
}

class SupabaseJobPhotosRemote implements JobPhotosRemote {
  SupabaseJobPhotosRemote(this._client);

  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 30);
  static const _columns = 'id, job_id, kind, storage_path, created_by, created_by_name, created_at';

  @override
  Future<List<JobPhoto>> fetchForJob(String jobId) async {
    try {
      final rows = await _client.from('job_photos').select(_columns).eq('job_id', jobId).order('created_at', ascending: true).timeout(_timeout);
      return [for (final r in rows) JobPhoto.fromRow(Map<String, dynamic>.from(r))];
    } catch (_) {
      throw JobPhotosException('Die Fotos konnten nicht geladen werden. Bitte Internetverbindung prüfen.'.tr);
    }
  }

  @override
  Future<List<JobPhoto>> fetchAll() async {
    try {
      final rows = await _client.from('job_photos').select(_columns).order('created_at', ascending: true).limit(5000).timeout(_timeout);
      return [for (final r in rows) JobPhoto.fromRow(Map<String, dynamic>.from(r))];
    } catch (_) {
      throw JobPhotosException('Die Fotos konnten nicht geladen werden. Bitte Internetverbindung prüfen.'.tr);
    }
  }

  @override
  Future<Uint8List> download(String path) => _client.storage.from('captures').download(path).timeout(_timeout);

  @override
  Future<void> delete(String id) async {
    try {
      final path = await _client.rpc('delete_job_photo', params: {'p_id': id}).timeout(_timeout) as String;
      try {
        await _client.storage.from('captures').remove([path]); // best effort: the row is already gone
      } catch (_) {}
    } on PostgrestException {
      throw JobPhotosException('Das Foto kann nicht entfernt werden.'.tr);
    } catch (_) {
      throw JobPhotosException('Keine Verbindung. Bitte später erneut versuchen.'.tr);
    }
  }
}

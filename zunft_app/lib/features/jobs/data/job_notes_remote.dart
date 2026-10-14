import '../../data/domain/full_export.dart' show ExportNote;
import '../../../core/i18n/i18n.dart';
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/job_notes.dart';

/// The notes could not be read or changed (usually: no connection).
class JobNotesException implements Exception {
  const JobNotesException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Server access for a job's notes. Faked in tests.
abstract class JobNotesRemote {
  /// Notes of [jobId] that are not yet part of a document and not discarded, oldest first.
  Future<List<JobNote>> fetchOpenNotes(String jobId);

  /// Every voice or typed note of the business (not receipts), oldest first, with its status: for
  /// the full data export.
  Future<List<ExportNote>> fetchAllNotes();

  /// Hides a note that has not been invoiced yet (it stays in the audit log).
  Future<void> discard(String noteId);

  /// A temporary link to a stored recording or receipt photo (the bucket is private).
  Future<String> audioUrl(String audioPath);
}

class SupabaseJobNotesRemote implements JobNotesRemote {
  SupabaseJobNotesRemote(this._client);

  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 20);

  @override
  Future<List<JobNote>> fetchOpenNotes(String jobId) async {
    try {
      final rows = await _client
          .from('capture_logs')
          .select('id, created_at, created_by, created_by_name, raw_transcript, audio_storage_path, audio_deleted_at, photo_storage_paths, ai_parsed_json, profiles(full_name)')
          .eq('job_id', jobId)
          .isFilter('document_id', null)
          .isFilter('discarded_at', null)
          .order('created_at', ascending: true)
          .timeout(_timeout);
      return [for (final r in rows) JobNote.fromRow(Map<String, dynamic>.from(r))];
    } catch (_) {
      throw JobNotesException('Die Notizen konnten nicht geladen werden. Bitte Internetverbindung prüfen.'.tr);
    }
  }

  @override
  Future<List<ExportNote>> fetchAllNotes() async {
    try {
      final rows = await _client
          .from('capture_logs')
          .select('created_at, created_by_name, raw_transcript, document_id, discarded_at, jobs(title), profiles(full_name)')
          .isFilter('image_sha256', null)
          .order('created_at', ascending: true)
          .limit(5000)
          .timeout(const Duration(seconds: 30));
      return [
        for (final r in rows)
          ExportNote(
            createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
            jobTitle: (r['jobs'] is Map ? (r['jobs'] as Map)['title'] as String? : null) ?? '',
            author: (r['profiles'] is Map ? (r['profiles'] as Map)['full_name'] as String? : null) ??
                (r['created_by_name'] as String?) ??
                '',
            status: r['discarded_at'] != null ? 'Entfernt' : (r['document_id'] != null ? 'Abgerechnet' : 'Offen'),
            text: (r['raw_transcript'] as String?) ?? '',
          ),
      ];
    } catch (_) {
      throw JobNotesException('Die Notizen konnten nicht geladen werden. Bitte Internetverbindung prüfen.'.tr);
    }
  }

  @override
  Future<String> audioUrl(String audioPath) async {
    try {
      return await _client.storage.from('captures').createSignedUrl(audioPath, 600).timeout(_timeout);
    } catch (_) {
      throw JobNotesException('Die Aufnahme konnte nicht geladen werden. Bitte Internetverbindung prüfen.'.tr);
    }
  }

  @override
  Future<void> discard(String noteId) async {
    try {
      await _client.rpc('discard_capture_log', params: {'p_id': noteId}).timeout(_timeout);
    } on PostgrestException {
      throw JobNotesException('Die Notiz kann nicht mehr entfernt werden (bereits abgerechnet?).'.tr);
    } catch (_) {
      throw JobNotesException('Keine Verbindung. Bitte später erneut versuchen.'.tr);
    }
  }
}

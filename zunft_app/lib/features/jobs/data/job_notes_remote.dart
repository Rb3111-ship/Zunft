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

  /// Hides a note that has not been invoiced yet (it stays in the audit log).
  Future<void> discard(String noteId);
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
          .select('id, created_at, created_by, raw_transcript, ai_parsed_json, profiles(full_name)')
          .eq('job_id', jobId)
          .isFilter('document_id', null)
          .isFilter('discarded_at', null)
          .order('created_at', ascending: true)
          .timeout(_timeout);
      return [for (final r in rows) JobNote.fromRow(Map<String, dynamic>.from(r))];
    } catch (_) {
      throw const JobNotesException('Die Notizen konnten nicht geladen werden. Bitte Internetverbindung prüfen.');
    }
  }

  @override
  Future<void> discard(String noteId) async {
    try {
      await _client.rpc('discard_capture_log', params: {'p_id': noteId}).timeout(_timeout);
    } on PostgrestException {
      throw const JobNotesException('Die Notiz kann nicht mehr entfernt werden (bereits abgerechnet?).');
    } catch (_) {
      throw const JobNotesException('Keine Verbindung. Bitte später erneut versuchen.');
    }
  }
}

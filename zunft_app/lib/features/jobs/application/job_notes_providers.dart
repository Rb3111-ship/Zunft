import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../capture/application/capture_providers.dart';
import '../data/job_notes_remote.dart';
import '../domain/job_notes.dart';

final jobNotesRemoteProvider = Provider<JobNotesRemote>((ref) => SupabaseJobNotesRemote(Supabase.instance.client));

/// The open notes of one job, read from the server (the source of truth for all workers).
///
/// Reloads whenever this phone's queue changes: when a queued note has been stored on the server,
/// its row leaves the queue and the stored note shows up here.
final jobNotesProvider = FutureProvider.autoDispose.family<List<JobNote>, String>((ref, jobId) {
  ref.watch(capturesProvider);
  return ref.watch(jobNotesRemoteProvider).fetchOpenNotes(jobId);
});

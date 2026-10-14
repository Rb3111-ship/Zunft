import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../capture/application/capture_providers.dart';
import '../data/job_photos_remote.dart';
import '../domain/job_photo.dart';

/// Tests override this with a fake.
final jobPhotosRemoteProvider = Provider<JobPhotosRemote>((ref) => SupabaseJobPhotosRemote(Supabase.instance.client));

/// The photos of one job. Reloads when this phone's upload queue changes (a photo just arrived on
/// the server). Offline or refused: no photos are known, the job screen still works.
final jobPhotosProvider = FutureProvider.autoDispose.family<List<JobPhoto>, String>((ref, jobId) async {
  ref.watch(capturesProvider);
  try {
    return await ref.watch(jobPhotosRemoteProvider).fetchForJob(jobId);
  } catch (_) {
    return const [];
  }
});

/// The picture of one photo (downloaded when it scrolls into view, dropped when it leaves).
final jobPhotoBytesProvider = FutureProvider.autoDispose.family<Uint8List, String>(
  (ref, path) => ref.watch(jobPhotosRemoteProvider).download(path),
);

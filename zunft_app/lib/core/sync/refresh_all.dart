import '../../features/jobs/application/job_photos_providers.dart' show jobPhotosProvider;
import '../../features/jobs/application/job_notes_providers.dart' show jobNotesProvider;
import '../../features/subscription/application/subscription_providers.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_providers.dart';
import '../../features/documents/application/document_providers.dart';
import 'sync_controller.dart';

/// Pull-down refresh and "app came back": fetch the latest data from the server and reload the
/// lists that are read directly from it.
Future<void> refreshAll(WidgetRef ref) async {
  ref.invalidate(issuedDocumentsProvider);
  ref.invalidate(jobPhotosProvider); // photos and notes of other people on the job
  ref.invalidate(jobNotesProvider);
  ref.invalidate(subscriptionProvider); // a renewal (or an expiry) shows up at once
  unawaited(refreshAuthData(ref)); // also learns about a changed role or switched-off access
  try {
    await ref.read(syncControllerProvider.notifier).syncNow();
  } catch (_) {
    // Offline: the lists keep showing what is on the phone.
  }
}

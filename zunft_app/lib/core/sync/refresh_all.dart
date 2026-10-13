import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_providers.dart';
import '../../features/documents/application/document_providers.dart';
import 'sync_controller.dart';

/// Pull-down refresh and "app came back": fetch the latest data from the server and reload the
/// lists that are read directly from it.
Future<void> refreshAll(WidgetRef ref) async {
  ref.invalidate(issuedDocumentsProvider);
  unawaited(refreshAuthData(ref)); // also learns about a changed role or switched-off access
  try {
    await ref.read(syncControllerProvider.notifier).syncNow();
  } catch (_) {
    // Offline: the lists keep showing what is on the phone.
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_providers.dart';
import '../../capture/application/capture_providers.dart';
import '../../data/data_providers.dart';
import '../data/document_service.dart';
import '../data/documents_remote.dart';

/// Tests override this with a fake.
final documentsRemoteProvider = Provider<DocumentsRemote>((ref) => SupabaseDocumentsRemote(Supabase.instance.client));

/// Issued quotes and invoices (the local copy, kept up to date by sync).
final issuedDocumentsProvider = StreamProvider<List<IssuedDocument>>((ref) async* {
  final db = await ref.watch(scopedDatabaseProvider.future);
  yield* db.watchDocuments();
});

final documentServiceProvider = FutureProvider<DocumentService>((ref) async {
  final db = await ref.watch(scopedDatabaseProvider.future);
  return DocumentService(
    db,
    ref.watch(documentsRemoteProvider),
    data: await ref.watch(dataRepositoryProvider.future),
    captures: await ref.watch(captureRepositoryProvider.future),
  );
});

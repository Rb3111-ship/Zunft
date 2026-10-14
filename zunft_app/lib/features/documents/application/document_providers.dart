import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_providers.dart';
import '../../data/data_providers.dart';
import '../data/document_service.dart';
import '../data/documents_remote.dart';
import '../data/logo_store.dart';

/// Tests override this with a fake.
final documentsRemoteProvider = Provider<DocumentsRemote>((ref) => SupabaseDocumentsRemote(Supabase.instance.client));

/// Issued quotes and invoices (the local copy, kept up to date by sync).
final issuedDocumentsProvider = StreamProvider<List<IssuedDocument>>((ref) async* {
  final db = await ref.watch(scopedDatabaseProvider.future);
  yield* db.watchDocuments();
});

/// "Now" for the open-invoices list (how late an invoice is). Tests override it.
final documentsClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The e-mail address of a customer (null if none is saved), to address the mail when sending.
final customerEmailLookupProvider = Provider<Future<String?> Function(String customerId)>((ref) {
  return (customerId) async {
    final db = await ref.read(scopedDatabaseProvider.future);
    return (await db.customerById(customerId))?.email;
  };
});

/// Where the business logo is stored and cached. Tests override this with a fake.
final logoStoreProvider = Provider<LogoStore>((ref) => SupabaseLogoStore(Supabase.instance.client, () async {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(base.path, 'logo'));
      await dir.create(recursive: true);
      return dir.path;
    }));

/// Chooses the logo from the gallery. Tests override this with a fake.
final logoPickerProvider = Provider<LogoPicker>((ref) => GalleryLogoPicker());

final documentServiceProvider = FutureProvider<DocumentService>((ref) async {
  final db = await ref.watch(scopedDatabaseProvider.future);
  return DocumentService(
    db,
    ref.watch(documentsRemoteProvider),
    data: await ref.watch(dataRepositoryProvider.future),
    logos: ref.watch(logoStoreProvider),
  );
});

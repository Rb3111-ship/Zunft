import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/sync/sync_controller.dart';
import '../../core/sync/sync_providers.dart';
import '../auth/application/auth_providers.dart';
import 'data_repository.dart';

final customersProvider = StreamProvider<List<Customer>>((ref) async* {
  final db = await ref.watch(scopedDatabaseProvider.future);
  yield* db.watchCustomers();
});

final jobsProvider = StreamProvider<List<Job>>((ref) async* {
  final db = await ref.watch(scopedDatabaseProvider.future);
  yield* db.watchJobs();
});

/// Changes not yet sent to the server.
final pendingChangesProvider = StreamProvider<int>((ref) async* {
  final db = await ref.watch(scopedDatabaseProvider.future);
  yield* db.watchPendingCount();
});

/// Write access to customers and jobs. Edits are saved locally first, then synced.
final dataRepositoryProvider = FutureProvider<DataRepository>((ref) async {
  final db = await ref.watch(scopedDatabaseProvider.future);
  final profile = await ref.watch(profileProvider.future);
  return DataRepository(
    db,
    businessId: profile!.businessId,
    onChanged: () => ref.read(syncControllerProvider.notifier).requestSync(),
  );
});

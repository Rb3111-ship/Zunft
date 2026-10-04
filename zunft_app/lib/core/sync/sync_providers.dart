import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/application/auth_providers.dart';
import '../database/app_database.dart';
import 'sync_engine.dart';
import 'sync_remote.dart';

/// The on-device database. Tests override this with an in-memory database.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(driftDatabase(name: 'zunft'));
  ref.onDispose(db.close);
  return db;
});

/// The database, guaranteed to belong to the signed-in user in their business. If a different
/// business OR a different person used this device before, the cached data is wiped first
/// (a colleague sharing the phone must not see the previous person's jobs, even offline).
final scopedDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null) throw StateError('No business yet');
  final db = ref.watch(appDatabaseProvider);
  await db.ensureBusiness('${profile.businessId}:${profile.id}');
  return db;
});

final syncRemoteProvider = Provider<SyncRemote>((ref) => SupabaseSyncRemote(Supabase.instance.client));

final syncEngineProvider = FutureProvider<SyncEngine>((ref) async {
  final db = await ref.watch(scopedDatabaseProvider.future);
  return SyncEngine(db, ref.watch(syncRemoteProvider));
});

/// Online/offline changes from the OS; overridden in tests.
final connectivityChangesProvider = Provider<Stream<bool>>((ref) {
  return Connectivity().onConnectivityChanged.map((r) => r.any((c) => c != ConnectivityResult.none));
});

/// Pause before a sync that follows a local edit, so rapid edits are sent together.
final syncDebounceProvider = Provider<Duration>((ref) => const Duration(seconds: 2));

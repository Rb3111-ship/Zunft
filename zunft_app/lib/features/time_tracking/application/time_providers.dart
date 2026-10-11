import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_providers.dart';
import '../../auth/application/auth_providers.dart';

/// The working time entries this person may see (everything for boss and office, only their own
/// for an employee), newest first.
final timeEntriesProvider = StreamProvider<List<TimeEntry>>((ref) async* {
  final db = await ref.watch(scopedDatabaseProvider.future);
  yield* db.watchTimeEntries();
});

/// My timer, if one is running.
final myRunningTimerProvider = Provider<TimeEntry?>((ref) {
  final me = ref.watch(profileProvider).valueOrNull?.id;
  if (me == null) return null;
  final all = ref.watch(timeEntriesProvider).valueOrNull ?? const <TimeEntry>[];
  return all.where((t) => t.userId == me && t.endedAt == null).firstOrNull;
});

/// The clock of the app. Tests replace it with a fixed time.
final timeClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Once a second while something listens (a running timer on screen). Tests replace this so no
/// real timer is left running.
final tickStreamProvider = Provider<Stream<void>>((ref) => Stream.periodic(const Duration(seconds: 1)));

/// The current time, ticking. Use only where a clock is shown.
final tickProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  final clock = ref.watch(timeClockProvider);
  yield clock();
  await for (final _ in ref.watch(tickStreamProvider)) {
    yield clock();
  }
});

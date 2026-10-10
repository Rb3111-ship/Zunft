import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_providers.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/team_models.dart';
import '../data/appointments_remote.dart';

/// Tests override this with a fake.
final appointmentsRemoteProvider =
    Provider<AppointmentsRemote>((ref) => SupabaseAppointmentsRemote(Supabase.instance.client));

/// The calendar: the local copy of the appointments this person may see, earliest first.
final appointmentsProvider = StreamProvider<List<Appointment>>((ref) async* {
  final db = await ref.watch(scopedDatabaseProvider.future);
  yield* db.watchAppointments();
});

/// The people of the business (for names on appointments and for choosing who goes). A failure
/// (offline) gives an empty list: the calendar still works, names just fall back to "Mitarbeiter".
final teamMembersProvider = FutureProvider<List<TeamMember>>((ref) async {
  try {
    return (await ref.watch(teamRemoteProvider).fetchOverview()).members;
  } catch (_) {
    return const [];
  }
});

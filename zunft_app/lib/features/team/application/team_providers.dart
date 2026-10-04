import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/team_remote.dart';
import '../domain/team_models.dart';

/// Tests override this with a fake.
final teamRemoteProvider = Provider<TeamRemote>((ref) => SupabaseTeamRemote(Supabase.instance.client));

/// People, open invitations and seats. Reload with `ref.invalidate(teamOverviewProvider)`.
final teamOverviewProvider = FutureProvider.autoDispose<TeamOverview>((ref) => ref.watch(teamRemoteProvider).fetchOverview());

/// The people one job is assigned to.
final jobAssigneesProvider =
    FutureProvider.autoDispose.family<Set<String>, String>((ref, jobId) => ref.watch(teamRemoteProvider).fetchAssignees(jobId));

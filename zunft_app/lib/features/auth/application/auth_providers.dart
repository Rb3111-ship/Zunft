import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';
import '../data/business_models.dart';

/// Override in tests with a fake. The default talks to Supabase.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(Supabase.instance.client),
);

/// Current user id, null when signed out.
final sessionUserIdProvider = StreamProvider<String?>(
  (ref) => ref.watch(authRepositoryProvider).userIdChanges(),
);

/// The signed-in user's profile; null until onboarding created the business.
/// Re-runs whenever the user changes, so switching accounts never shows stale data.
final profileProvider = FutureProvider<UserProfile?>((ref) async {
  final userId = await ref.watch(sessionUserIdProvider.future);
  if (userId == null) return null;
  return ref.watch(authRepositoryProvider).fetchProfile();
});

/// The signed-in user's business (sender data for quotes and invoices).
final businessProvider = FutureProvider<Business>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null) throw const AuthFailure('Kein Betrieb vorhanden.');
  return ref.watch(authRepositoryProvider).fetchBusiness();
});

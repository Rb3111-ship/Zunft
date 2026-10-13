import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_cache.dart';
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
  final cache = ref.watch(authCacheProvider);
  try {
    final fresh = await ref.watch(authRepositoryProvider).fetchProfile().timeout(_fetchTimeout);
    await cache.saveProfile(userId, fresh);
    return fresh;
  } catch (_) {
    // No network (or too slow): the last known profile, so the app opens at the workplace.
    final cached = await cache.profile(userId);
    if (cached != null) return cached;
    rethrow; // the very first start needs a connection
  }
});

/// How long the app waits for the server at start before it works with what the phone knows.
const _fetchTimeout = Duration(seconds: 6);

/// The last known profile and business, kept on the phone. Tests replace this.
final authCacheProvider = Provider<AuthCache>((ref) => SharedPrefsAuthCache());

/// The signed-in user's business (sender data for quotes and invoices).
final businessProvider = FutureProvider<Business>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null) throw const AuthFailure('Kein Betrieb vorhanden.');
  final cache = ref.watch(authCacheProvider);
  try {
    final fresh = await ref.watch(authRepositoryProvider).fetchBusiness().timeout(_fetchTimeout);
    await cache.saveBusiness(profile.id, fresh);
    return fresh;
  } catch (_) {
    final cached = await cache.business(profile.id);
    if (cached != null && cached.id == profile.businessId) return cached;
    rethrow;
  }
});

/// Back online (or the app came to the front): has the server something new about this person or
/// the business (a changed role, access switched off, a new setting)? Only then the app reloads
/// them; otherwise nothing is disturbed. No network: nothing happens.
Future<void> refreshAuthData(WidgetRef ref) async {
  final repo = ref.read(authRepositoryProvider);
  final cache = ref.read(authCacheProvider);
  final userId = ref.read(sessionUserIdProvider).valueOrNull;
  if (userId == null) return;
  try {
    final freshProfile = await repo.fetchProfile().timeout(_fetchTimeout);
    final current = ref.read(profileProvider).valueOrNull;
    if ((freshProfile == null) != (current == null) || (freshProfile != null && !freshProfile.sameAs(current))) {
      await cache.saveProfile(userId, freshProfile);
      ref.invalidate(profileProvider);
      return;
    }
    if (freshProfile == null) return;
    final freshBusiness = await repo.fetchBusiness().timeout(_fetchTimeout);
    final shown = ref.read(businessProvider).valueOrNull;
    if (shown == null || jsonEncode(shown.toCacheJson()) != jsonEncode(freshBusiness.toCacheJson())) {
      await cache.saveBusiness(userId, freshBusiness);
      ref.invalidate(businessProvider);
    }
  } catch (_) {
    // offline: keep what the phone knows
  }
}

/// May this person create customers and jobs? Boss and office always; employees only if the owner
/// allowed it for the business.
final canCreateRecordsProvider = Provider<bool>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  if (profile == null) return false;
  if (profile.isManager) return true;
  return ref.watch(businessProvider).valueOrNull?.employeesCanCreate ?? false;
});

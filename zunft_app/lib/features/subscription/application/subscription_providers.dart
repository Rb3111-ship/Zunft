import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/application/auth_providers.dart';
import '../data/subscription_remote.dart';
import '../domain/subscription.dart';

/// Override in tests with a fake.
final subscriptionRemoteProvider = Provider<SubscriptionRemote>((ref) => SupabaseSubscriptionRemote(Supabase.instance.client));

const _timeout = Duration(seconds: 6);

/// The business's subscription. Offline, the last answer that was seen is used, so a business whose
/// access ended is still told so; if nothing is known the app shows no banner (the server refuses
/// new records anyway).
final subscriptionProvider = FutureProvider<Subscription?>((ref) async {
  final userId = await ref.watch(sessionUserIdProvider.future);
  if (userId == null) return null;
  final cache = ref.watch(authCacheProvider);
  try {
    final fresh = await ref.watch(subscriptionRemoteProvider).fetch().timeout(_timeout);
    try {
      await cache.saveSubscription(userId, fresh.toJson());
    } catch (_) {}
    return fresh;
  } catch (_) {
    try {
      final saved = await cache.subscription(userId);
      if (saved != null) return Subscription.fromJson(saved);
    } catch (_) {}
    return null;
  }
});

/// True when the business's access has ended: nothing new can be created.
final readOnlyProvider = Provider<bool>((ref) => ref.watch(subscriptionProvider).valueOrNull?.isReadOnly ?? false);

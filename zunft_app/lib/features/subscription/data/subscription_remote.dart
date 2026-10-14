import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/subscription.dart';

abstract class SubscriptionRemote {
  /// The subscription of the signed-in person's business. Throws when offline.
  Future<Subscription> fetch();
}

class SupabaseSubscriptionRemote implements SubscriptionRemote {
  SupabaseSubscriptionRemote(this._client);

  final SupabaseClient _client;

  @override
  Future<Subscription> fetch() async {
    final json = await _client.rpc('subscription_status');
    return Subscription.fromJson(Map<String, dynamic>.from(json as Map));
  }
}

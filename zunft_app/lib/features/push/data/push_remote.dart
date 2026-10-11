import 'dart:async';
import 'dart:io' show Platform;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Tells the server which phone belongs to the signed-in person. Faked in tests.
abstract class PushRemote {
  /// This phone's address, for the signed-in person (replaces an earlier owner of the same phone).
  Future<void> register(String token);

  /// Removes the address (sign-out, push switched off).
  Future<void> unregister(String token);
}

class SupabasePushRemote implements PushRemote {
  SupabasePushRemote(this._client);

  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 15);

  @override
  Future<void> register(String token) => _client
      .rpc('register_device_token', params: {'p_token': token, 'p_platform': Platform.isIOS ? 'ios' : 'android'})
      .timeout(_timeout);

  @override
  Future<void> unregister(String token) => _client.rpc('unregister_device_token', params: {'p_token': token}).timeout(_timeout);
}

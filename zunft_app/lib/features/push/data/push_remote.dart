import 'dart:async';
import 'dart:io' show Platform;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Tells the server which phone belongs to the signed-in person. Faked in tests.
abstract class PushRemote {
  /// This phone's address, for the signed-in person (replaces an earlier owner of the same phone).
  /// [language] is the app language: the server writes the message in it.
  Future<void> register(String token, String language);

  /// Removes the address (sign-out, push switched off).
  Future<void> unregister(String token);
}

class SupabasePushRemote implements PushRemote {
  SupabasePushRemote(this._client);

  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 15);

  @override
  Future<void> register(String token, String language) => _client
      .rpc('register_device_token',
          params: {'p_token': token, 'p_platform': Platform.isIOS ? 'ios' : 'android', 'p_language': language})
      .timeout(_timeout);

  @override
  Future<void> unregister(String token) => _client.rpc('unregister_device_token', params: {'p_token': token}).timeout(_timeout);
}

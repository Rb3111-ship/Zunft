import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'business_models.dart';

/// The last known profile and business of the signed-in person, kept on the phone so that the app
/// opens without network (the data of the business is on the phone anyway). The server stays the
/// truth: whenever the phone is online the values are fetched again and replaced.
abstract class AuthCache {
  Future<UserProfile?> profile(String userId);
  Future<void> saveProfile(String userId, UserProfile? profile);

  Future<Business?> business(String userId);
  Future<void> saveBusiness(String userId, Business business);

  /// The last subscription answer of the server (a plain map).
  Future<Map<String, dynamic>?> subscription(String userId);
  Future<void> saveSubscription(String userId, Map<String, dynamic> json);

  /// Forgets everything (sign-out: the next person on this phone must not inherit it).
  Future<void> clear();
}

class SharedPrefsAuthCache implements AuthCache {
  static const _profileKey = 'auth_cache_profile';
  static const _businessKey = 'auth_cache_business';
  static const _subscriptionKey = 'auth_cache_subscription';

  Future<Map<String, dynamic>?> _read(String key, String userId) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m['user'] == userId ? (m['data'] as Map).cast<String, dynamic>() : null;
    } catch (_) {
      return null; // unreadable cache: as if there were none
    }
  }

  Future<void> _write(String key, String userId, Map<String, dynamic>? data) async {
    final p = await SharedPreferences.getInstance();
    if (data == null) {
      await p.remove(key);
    } else {
      await p.setString(key, jsonEncode({'user': userId, 'data': data}));
    }
  }

  @override
  Future<UserProfile?> profile(String userId) async {
    final j = await _read(_profileKey, userId);
    return j == null ? null : UserProfile.fromJson(j);
  }

  @override
  Future<void> saveProfile(String userId, UserProfile? profile) => _write(_profileKey, userId, profile?.toJson());

  @override
  Future<Business?> business(String userId) async {
    final j = await _read(_businessKey, userId);
    return j == null ? null : Business.fromJson(j);
  }

  @override
  Future<void> saveBusiness(String userId, Business business) => _write(_businessKey, userId, business.toCacheJson());

  @override
  Future<Map<String, dynamic>?> subscription(String userId) => _read(_subscriptionKey, userId);

  @override
  Future<void> saveSubscription(String userId, Map<String, dynamic> json) => _write(_subscriptionKey, userId, json);

  @override
  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_profileKey);
    await p.remove(_businessKey);
    await p.remove(_subscriptionKey);
  }
}

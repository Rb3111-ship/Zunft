import 'package:zunft_app/features/auth/data/auth_cache.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';

/// The phone's memory of the last profile and business, in memory for tests.
class FakeAuthCache implements AuthCache {
  FakeAuthCache({this.cachedProfile, this.cachedBusiness, this.cachedSubscription, this.user = 'u1'});

  UserProfile? cachedProfile;
  Business? cachedBusiness;
  String user;
  int clears = 0;
  Map<String, dynamic>? cachedSubscription;

  @override
  Future<UserProfile?> profile(String userId) async => userId == user ? cachedProfile : null;

  @override
  Future<void> saveProfile(String userId, UserProfile? profile) async {
    user = userId;
    cachedProfile = profile;
  }

  @override
  Future<Business?> business(String userId) async => userId == user ? cachedBusiness : null;

  @override
  Future<void> saveBusiness(String userId, Business business) async {
    user = userId;
    cachedBusiness = business;
  }

  @override
  Future<Map<String, dynamic>?> subscription(String userId) async => userId == user ? cachedSubscription : null;

  @override
  Future<void> saveSubscription(String userId, Map<String, dynamic> json) async {
    user = userId;
    cachedSubscription = json;
  }

  @override
  Future<void> clear() async {
    clears++;
    cachedSubscription = null;
    cachedProfile = null;
    cachedBusiness = null;
  }
}

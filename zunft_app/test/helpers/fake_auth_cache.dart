import 'package:zunft_app/features/auth/data/auth_cache.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';

/// The phone's memory of the last profile and business, in memory for tests.
class FakeAuthCache implements AuthCache {
  FakeAuthCache({this.cachedProfile, this.cachedBusiness, this.user = 'u1'});

  UserProfile? cachedProfile;
  Business? cachedBusiness;
  String user;
  int clears = 0;

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
  Future<void> clear() async {
    clears++;
    cachedProfile = null;
    cachedBusiness = null;
  }
}

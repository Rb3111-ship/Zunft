import 'dart:async';

import 'package:zunft_app/features/auth/data/auth_repository.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';

/// In-memory AuthRepository for widget tests.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({String? userId, this.profile, Business? business})
      : _userId = userId,
        business = business ?? sampleBusiness() {
    _controller.add(_userId);
  }

  final _controller = StreamController<String?>.broadcast(sync: true);
  String? _userId;
  UserProfile? profile;
  Business business;

  // Programmable behavior
  AuthFailure? signInError;
  SignUpResult signUpResult = SignUpResult.signedIn;
  AuthFailure? createBusinessError;
  AuthFailure? updateBusinessError;
  AuthFailure? joinError;
  AuthFailure? leaveError;
  AuthFailure? deleteError;

  // Recorded calls
  final signIns = <String>[];
  final signUps = <String>[];
  Map<String, String>? createdBusiness;
  Map<String, String>? joined;
  int leaves = 0;
  int deletions = 0;
  Business? updatedBusiness;
  int signOuts = 0;

  /// A business that may issue invoices: address and tax number are filled in.
  static Business completeBusiness() => const Business(
        id: 'b1',
        name: 'Elektro Test GmbH',
        ownerName: 'Erika Test',
        tradeCategory: 'elektro',
        addressStreet: 'Hauptstraße 1',
        addressZip: '20095',
        addressCity: 'Hamburg',
        taxNumber: '48/123/45678',
        iban: 'DE89370400440532013000',
        defaultHourlyRateCents: 6800,
        defaultVatRate: 19,
      );

  static Business sampleBusiness() => const Business(
        id: 'b1',
        name: 'Elektro Test GmbH',
        ownerName: 'Erika Test',
        tradeCategory: 'elektro',
        defaultHourlyRateCents: 6800,
        defaultVatRate: 19,
      );

  @override
  Stream<String?> userIdChanges() async* {
    yield _userId;
    yield* _controller.stream;
  }

  @override
  Future<void> signIn(String email, String password) async {
    if (signInError != null) throw signInError!;
    signIns.add(email);
    _userId = 'u1';
    _controller.add(_userId);
  }

  @override
  Future<SignUpResult> signUp(String email, String password) async {
    signUps.add(email);
    if (signUpResult == SignUpResult.signedIn) {
      _userId = 'u1';
      _controller.add(_userId);
    }
    return signUpResult;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    _userId = null;
    _controller.add(null);
  }

  @override
  Future<UserProfile?> fetchProfile() async => profile;

  @override
  Future<void> createBusiness({
    required String businessName,
    required String ownerName,
    required String tradeCategory,
  }) async {
    if (createBusinessError != null) throw createBusinessError!;
    createdBusiness = {'name': businessName, 'owner': ownerName, 'trade': tradeCategory};
    profile = UserProfile(id: 'u1', businessId: 'b1', fullName: ownerName, role: 'owner');
  }

  @override
  Future<void> leaveBusiness() async {
    if (leaveError != null) throw leaveError!;
    leaves++;
    profile = null; // the account stays, the link is gone
  }

  @override
  Future<void> deleteAccount() async {
    if (deleteError != null) throw deleteError!;
    deletions++;
    profile = null;
    _userId = null;
    _controller.add(null);
  }

  @override
  Future<void> joinBusiness({required String code, required String fullName}) async {
    if (joinError != null) throw joinError!;
    joined = {'code': code, 'name': fullName};
    profile = UserProfile(id: 'u1', businessId: 'b1', fullName: fullName, role: 'geselle');
  }

  @override
  Future<Business> fetchBusiness() async => business;

  @override
  Future<Business> setEmployeesCanCreate(bool value) async {
    if (updateBusinessError != null) throw updateBusinessError!;
    return business = business.withEmployeesCanCreate(value);
  }

  @override
  Future<Business> updateBusiness(Business b) async {
    if (updateBusinessError != null) throw updateBusinessError!;
    updatedBusiness = b;
    business = b;
    return b;
  }
}

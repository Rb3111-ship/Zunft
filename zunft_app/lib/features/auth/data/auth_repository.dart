import '../../../core/i18n/i18n.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'business_models.dart';

/// Outcome of a sign-up: with e-mail confirmation enabled there is no session yet.
enum SignUpResult { signedIn, confirmationRequired }

/// User-facing failure with a German message (never raw server text).
class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);
  @override
  String toString() => message;
}

/// Everything the auth/onboarding UI needs from the backend. Faked in widget tests.
abstract class AuthRepository {
  /// Emits the current user id (or null when signed out) now and on every change.
  Stream<String?> userIdChanges();

  Future<void> signIn(String email, String password);
  Future<SignUpResult> signUp(String email, String password);
  Future<void> signOut();

  /// The caller's profile, or null if onboarding is not done yet.
  Future<UserProfile?> fetchProfile();

  /// Creates the business and the owner profile in one transaction.
  Future<void> createBusiness({
    required String businessName,
    required String ownerName,
    required String tradeCategory,
  });

  /// Ends the link to the business (not for the owner). The account stays.
  Future<void> leaveBusiness();

  /// Erases the account itself (not for an owner: invoices must be kept by law).
  Future<void> deleteAccount();

  /// Joins an existing business with the code from its owner (the person has no business yet).
  Future<void> joinBusiness({required String code, required String fullName});

  Future<Business> fetchBusiness();
  Future<Business> updateBusiness(Business business);

  /// Owner only: may Meister and Geselle create their own customers and jobs?
  Future<Business> setEmployeesCanCreate(bool value);
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<String?> userIdChanges() async* {
    yield _client.auth.currentUser?.id;
    yield* _client.auth.onAuthStateChange.map((s) => s.session?.user.id).distinct();
  }

  @override
  Future<void> signIn(String email, String password) => _guard(() async {
        await _client.auth.signInWithPassword(email: email.trim(), password: password);
      });

  @override
  Future<SignUpResult> signUp(String email, String password) => _guard(() async {
        final res = await _client.auth.signUp(email: email.trim(), password: password);
        return res.session == null ? SignUpResult.confirmationRequired : SignUpResult.signedIn;
      });

  @override
  Future<void> signOut() => _guard(() => _client.auth.signOut());

  @override
  Future<UserProfile?> fetchProfile() => _guard(() async {
        final uid = _client.auth.currentUser?.id;
        if (uid == null) return null;
        final row = await _client
            .from('profiles')
            .select('id, business_id, full_name, role, active')
            .eq('id', uid)
            .maybeSingle();
        return row == null ? null : UserProfile.fromJson(row);
      });

  @override
  Future<void> createBusiness({
    required String businessName,
    required String ownerName,
    required String tradeCategory,
  }) =>
      _guard(() async {
        await _client.rpc('create_business_for_user', params: {
          'p_business_name': businessName,
          'p_owner_name': ownerName,
          'p_trade_category': tradeCategory,
        });
      });

  @override
  Future<void> leaveBusiness() => _guard(() async {
        await _client.rpc('leave_business');
      });

  @override
  Future<void> deleteAccount() => _guard(() async {
        await _client.rpc('delete_my_account');
        // The login no longer exists on the server: end the session on this phone only.
        await _client.auth.signOut(scope: SignOutScope.local);
      });

  @override
  Future<void> joinBusiness({required String code, required String fullName}) => _guard(() async {
        await _client.rpc('join_business', params: {'p_code': code, 'p_full_name': fullName});
      });

  @override
  Future<Business> fetchBusiness() => _guard(() async {
        final row = await _client.from('businesses').select(Business.columns).single();
        return Business.fromJson(row);
      });

  @override
  Future<Business> updateBusiness(Business business) => _guard(() async {
        final row = await _client
            .from('businesses')
            .update(business.toUpdateJson())
            .eq('id', business.id)
            .select(Business.columns)
            .single();
        return Business.fromJson(row);
      });

  @override
  Future<Business> setEmployeesCanCreate(bool value) => _guard(() async {
        final profile = await fetchProfile();
        final row = await _client
            .from('businesses')
            .update({'employees_can_create': value})
            .eq('id', profile!.businessId)
            .select(Business.columns)
            .single();
        return Business.fromJson(row);
      });

  /// Maps backend errors to short German messages; keeps raw details out of the UI.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException catch (e) {
      throw AuthFailure(_authMessage(e));
    } on PostgrestException catch (e) {
      // Raised by our SQL functions (e.g. "user already belongs to a business").
      if (e.message.contains('invalid invitation')) {
        throw AuthFailure(
            'Der Code ist ungültig, abgelaufen oder schon benutzt. Bitte beim Chef einen neuen Code holen.'.tr);
      }
      if (e.message.contains('owner cannot')) {
        throw AuthFailure('Das ist für den Inhaber eines Betriebs nicht möglich.'.tr);
      }
      if (e.message.contains('no free seat')) {
        throw AuthFailure('Im Paket des Betriebs ist kein Platz mehr frei. Bitte den Chef fragen.'.tr);
      }
      if (e.message.contains('already belongs')) {
        throw AuthFailure('Für dieses Konto existiert bereits ein Betrieb.'.tr);
      }
      if (e.code == '42501' || e.message.contains('row-level security')) {
        throw AuthFailure('Dafür fehlt die Berechtigung.'.tr);
      }
      throw AuthFailure('Der Server hat die Anfrage abgelehnt. Bitte später erneut versuchen.'.tr);
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw AuthFailure('Keine Verbindung. Bitte Internet prüfen und erneut versuchen.'.tr);
    }
  }

  static String _authMessage(AuthException e) {
    final code = e.code ?? '';
    final msg = e.message.toLowerCase();
    if (code == 'invalid_credentials' || msg.contains('invalid login')) {
      return 'E-Mail oder Passwort ist falsch.'.tr;
    }
    if (code == 'email_not_confirmed' || msg.contains('not confirmed')) {
      return 'Bitte zuerst die E-Mail-Adresse bestätigen (Link in der E-Mail).'.tr;
    }
    if (code == 'user_already_exists' || msg.contains('already registered')) {
      return 'Mit dieser E-Mail gibt es bereits ein Konto.'.tr;
    }
    if (code == 'weak_password' || msg.contains('password')) {
      return 'Das Passwort ist zu schwach.'.tr;
    }
    if (code == 'over_request_rate_limit' || code == 'over_email_send_rate_limit' || msg.contains('rate limit')) {
      return 'Zu viele Versuche. Bitte einen Moment warten.'.tr;
    }
    return 'Anmeldung fehlgeschlagen. Bitte erneut versuchen.'.tr;
  }
}

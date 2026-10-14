import '../../../core/i18n/i18n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/navigation/navigator_key.dart';
import '../../../core/sync/sync_controller.dart';
import '../../appointments/presentation/appointment_detail_screen.dart';
import '../../auth/application/auth_providers.dart';
import '../data/push_remote.dart';
import '../data/push_service.dart';

/// What this phone remembers about push: switched on, and which address it gave the server.
class PushPrefs {
  const PushPrefs({this.enabled = false, this.registeredToken, this.registeredLanguage = 'de'});
  final bool enabled;
  final String? registeredToken;

  /// The language the server was told for this phone (its messages are written in it).
  final String registeredLanguage;
}

abstract class PushPrefsStore {
  Future<PushPrefs> load();
  Future<void> save(PushPrefs prefs);
}

class SharedPrefsPushStore implements PushPrefsStore {
  @override
  Future<PushPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    return PushPrefs(
        enabled: p.getBool('push_enabled') ?? false,
        registeredToken: p.getString('push_token'),
        registeredLanguage: p.getString('push_language') ?? 'de');
  }

  @override
  Future<void> save(PushPrefs prefs) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('push_enabled', prefs.enabled);
    await p.setString('push_language', prefs.registeredLanguage);
    if (prefs.registeredToken == null) {
      await p.remove('push_token');
    } else {
      await p.setString('push_token', prefs.registeredToken!);
    }
  }
}

class PushState {
  const PushState({this.loaded = false, this.enabled = false, this.registeredToken, this.registeredLanguage = 'de'});
  final bool loaded;
  final bool enabled;
  final String? registeredToken;
  final String registeredLanguage;
}

/// Tests replace these.
final pushServiceProvider = Provider<PushService>((ref) => FirebasePushService());
final pushRemoteProvider = Provider<PushRemote>((ref) => SupabasePushRemote(Supabase.instance.client));
final pushPrefsStoreProvider = Provider<PushPrefsStore>((ref) => SharedPrefsPushStore());

final pushProvider = StateNotifierProvider<PushController, PushState>(
    (ref) => PushController(ref.watch(pushPrefsStoreProvider), ref.watch(pushServiceProvider), ref.watch(pushRemoteProvider)));

/// Switches push on and off for this phone and keeps the server's list of phones right.
///
/// Consent belongs to the person on the phone: signing out switches push off again, so the next
/// person who signs in on the same phone does not receive someone else's messages.
class PushController extends StateNotifier<PushState> {
  PushController(this._store, this._service, this._remote) : super(const PushState()) {
    _load();
  }

  final PushPrefsStore _store;
  final PushService _service;
  final PushRemote _remote;

  Future<void> _load() async {
    final p = await _store.load();
    if (mounted) {
      state = PushState(loaded: true, enabled: p.enabled, registeredToken: p.registeredToken, registeredLanguage: p.registeredLanguage);
    }
  }

  Future<void> _save({bool? enabled, Object? token = _keep, String? language}) async {
    final next = PushState(
      loaded: true,
      enabled: enabled ?? state.enabled,
      registeredToken: identical(token, _keep) ? state.registeredToken : token as String?,
      registeredLanguage: language ?? state.registeredLanguage,
    );
    await _store.save(PushPrefs(enabled: next.enabled, registeredToken: next.registeredToken, registeredLanguage: next.registeredLanguage));
    if (mounted) state = next;
  }

  static const _keep = Object();

  /// Switching on asks the phone for permission and tells the server this phone's address.
  /// Returns null if done, otherwise the reason it was not.
  Future<String?> setEnabled(bool on) async {
    if (!on) {
      await forgetPhone();
      return null;
    }
    if (!await _service.requestPermission()) {
      return 'Die Erlaubnis für Benachrichtigungen fehlt. Bitte in den Handy-Einstellungen für Zunft erlauben.'.tr;
    }
    final token = await _service.token();
    if (token == null) return 'Dieses Handy hat keine Adresse für Meldungen bekommen. Bitte später noch einmal versuchen.'.tr;
    try {
      await _remote.register(token, I18n.current);
    } catch (_) {
      return 'Keine Verbindung. Zum Einschalten wird Internet gebraucht.'.tr;
    }
    await _save(enabled: true, token: token, language: I18n.current);
    return null;
  }

  /// Every start with push on: make sure the server has this phone's current address (it may have
  /// changed while the app was closed). A failure is tried again at the next start.
  Future<void> ensureRegistered() async {
    if (!state.enabled) return;
    final token = await _service.token();
    // also when the language changed since the server was told: its messages follow the app language
    if (token == null || (token == state.registeredToken && state.registeredLanguage == I18n.current)) return;
    await registerToken(token);
  }

  /// The phone got a new address.
  Future<void> registerToken(String token) async {
    if (!state.enabled) return;
    try {
      await _remote.register(token, I18n.current);
      await _save(token: token, language: I18n.current);
    } catch (_) {
      // offline: the next start tries again
    }
  }

  /// Takes this phone off the server's list and switches push off here. Best effort: if the server
  /// cannot be reached, the address expires on its own when the app is removed or the phone resets,
  /// and the push service rejects a deleted address.
  Future<void> forgetPhone() async {
    final token = state.registeredToken;
    if (token != null) {
      try {
        await _remote.unregister(token);
      } catch (_) {}
      await _service.deleteToken();
    }
    await _save(enabled: false, token: null);
  }
}

/// Active while the signed-in app is on screen: registers the phone, follows address changes, and
/// fetches fresh data when a message arrives. With push off it clears any address left behind by
/// an earlier person on this phone.
final pushSyncProvider = Provider<void>((ref) {
  final push = ref.watch(pushProvider);
  ref.watch(languageProvider); // a new app language is told to the server
  if (!push.loaded) return;
  final controller = ref.read(pushProvider.notifier);
  final service = ref.read(pushServiceProvider);

  if (!push.enabled) {
    if (push.registeredToken != null) unawaited(controller.forgetPhone());
    return;
  }
  unawaited(controller.ensureRegistered());
  final subs = [
    service.tokenChanges.listen((t) => controller.registerToken(t), onError: (_) {}),
    service.messages.listen((m) => unawaited(_onMessage(ref, m)), onError: (_) {}),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
  });
});

/// A message came: fetch the news first, then (if the person tapped the notification) open the
/// appointment it is about.
Future<void> _onMessage(Ref ref, PushMessage m) async {
  try {
    await ref.read(syncControllerProvider.notifier).syncNow();
  } catch (_) {}
  if (!m.opened || !m.opensAppointment) return;
  final navigator = ref.read(navigatorKeyProvider).currentState;
  navigator?.push(MaterialPageRoute<void>(builder: (_) => AppointmentDetailScreen(appointmentId: m.appointmentId!)));
}

/// Signs out. Before that the phone is taken off the server's list (while the login still works),
/// so the next person on this phone does not receive this person's messages.
Future<void> signOutAndForgetPhone(WidgetRef ref) async {
  try {
    await ref.read(pushProvider.notifier).forgetPhone().timeout(const Duration(seconds: 4));
  } catch (_) {}
  try {
    await ref.read(authCacheProvider).clear(); // the next person must not inherit the profile
  } catch (_) {}
  await ref.read(authRepositoryProvider).signOut();
}

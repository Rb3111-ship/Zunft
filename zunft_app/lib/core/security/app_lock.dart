import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/application/auth_providers.dart';
import '../theme/app_theme.dart';

/// Asks the phone to confirm that it is the owner: fingerprint, face, or (as a fallback) the PIN /
/// pattern of the phone. Behind an interface so tests need no phone.
abstract class DeviceAuthenticator {
  /// Does this phone have a screen lock or biometrics at all?
  Future<bool> isSupported();

  /// true only if the person was confirmed. Cancelling or any error is false.
  Future<bool> authenticate(String reason);
}

class LocalAuthAuthenticator implements DeviceAuthenticator {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason);
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}

/// The lock settings of THIS phone (not synced: every device decides for itself).
class AppLockPrefs {
  const AppLockPrefs({this.enabled = false, this.timeoutSeconds = 60});
  final bool enabled;
  final int timeoutSeconds;
}

abstract class AppLockStore {
  Future<AppLockPrefs> load();
  Future<void> save(AppLockPrefs prefs);
}

class SharedPrefsAppLockStore implements AppLockStore {
  @override
  Future<AppLockPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    return AppLockPrefs(
      enabled: p.getBool('app_lock_enabled') ?? false,
      timeoutSeconds: p.getInt('app_lock_timeout') ?? 60,
    );
  }

  @override
  Future<void> save(AppLockPrefs prefs) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('app_lock_enabled', prefs.enabled);
    await p.setInt('app_lock_timeout', prefs.timeoutSeconds);
  }
}

class AppLockState {
  const AppLockState({this.loaded = false, this.enabled = false, this.timeoutSeconds = 60, this.locked = false});

  final bool loaded;
  final bool enabled;
  final int timeoutSeconds;

  /// The lock screen is showing.
  final bool locked;

  AppLockState copyWith({bool? loaded, bool? enabled, int? timeoutSeconds, bool? locked}) => AppLockState(
        loaded: loaded ?? this.loaded,
        enabled: enabled ?? this.enabled,
        timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
        locked: locked ?? this.locked,
      );
}

/// Tests replace these.
final deviceAuthenticatorProvider = Provider<DeviceAuthenticator>((ref) => LocalAuthAuthenticator());
final appLockStoreProvider = Provider<AppLockStore>((ref) => SharedPrefsAppLockStore());
final appLockClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final appLockProvider = StateNotifierProvider<AppLockController, AppLockState>((ref) => AppLockController(
      ref.watch(appLockStoreProvider),
      ref.watch(deviceAuthenticatorProvider),
      ref.watch(appLockClockProvider),
    ));

/// Locks the app after it was in the background for a while (and on a cold start). The lock only
/// hides the screen; it never signs out and it never blocks signing out.
class AppLockController extends StateNotifier<AppLockState> {
  AppLockController(this._store, this._device, this._now) : super(const AppLockState()) {
    _load();
  }

  final AppLockStore _store;
  final DeviceAuthenticator _device;
  final DateTime Function() _now;

  DateTime? _pausedAt;
  bool _authenticating = false;

  Future<void> _load() async {
    final prefs = await _store.load();
    if (!mounted) return;
    // A cold start with the lock on begins locked.
    state = AppLockState(
        loaded: true, enabled: prefs.enabled, timeoutSeconds: prefs.timeoutSeconds, locked: prefs.enabled);
  }

  /// The app went to the background.
  void paused() {
    if (_authenticating) return;
    _pausedAt ??= _now();
  }

  /// The app came back. Locks if it was away for at least the timeout.
  void resumed() {
    final at = _pausedAt;
    _pausedAt = null;
    if (_authenticating || !state.enabled || state.locked || at == null) return;
    if (_now().difference(at).inSeconds >= state.timeoutSeconds) state = state.copyWith(locked: true);
  }

  /// Shows the phone's prompt; unlocks if it is confirmed. Returns whether it worked.
  Future<bool> unlock() async {
    if (_authenticating) return false;
    _authenticating = true;
    try {
      final ok = await _device.authenticate('Zunft entsperren');
      if (ok && mounted) state = state.copyWith(locked: false);
      return ok;
    } finally {
      _authenticating = false;
      _pausedAt = null;
    }
  }

  /// Switches the lock on or off. Switching on first needs a phone with a screen lock and a
  /// successful confirmation, so a person cannot lock themselves out with a lock that cannot open.
  /// Returns null if done, otherwise the reason it was not.
  Future<String?> setEnabled(bool enabled) async {
    if (enabled) {
      if (!await _device.isSupported()) {
        return 'Auf diesem Handy ist keine Bildschirmsperre (PIN, Muster, Fingerabdruck oder Gesicht) eingerichtet. Bitte zuerst in den Handy-Einstellungen einrichten.';
      }
      _authenticating = true;
      final ok = await _device.authenticate('Bitte bestätige, dass du die App-Sperre einschalten möchtest');
      _authenticating = false;
      _pausedAt = null;
      if (!ok) return 'Die Bestätigung hat nicht geklappt. Die App-Sperre bleibt aus.';
    }
    await _store.save(AppLockPrefs(enabled: enabled, timeoutSeconds: state.timeoutSeconds));
    if (mounted) state = state.copyWith(enabled: enabled, locked: false);
    return null;
  }

  Future<void> setTimeout(int seconds) async {
    await _store.save(AppLockPrefs(enabled: state.enabled, timeoutSeconds: seconds));
    if (mounted) state = state.copyWith(timeoutSeconds: seconds);
  }
}

/// Use as `MaterialApp(builder: appLockBuilder)`: the lock screen then covers every screen of the
/// app, including the ones opened on top of the home screen.
Widget appLockBuilder(BuildContext context, Widget? child) => AppLockGate(child: child ?? const SizedBox());

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider.notifier);
    if (state == AppLifecycleState.paused) lock.paused();
    if (state == AppLifecycleState.resumed) lock.resumed();
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final signedIn = ref.watch(sessionUserIdProvider).valueOrNull != null;
    final showLock = lock.loaded && lock.enabled && lock.locked && signedIn;
    return Stack(
      children: [
        // Screen readers must not read the hidden app while the lock is showing.
        ExcludeSemantics(excluding: showLock, child: widget.child),
        if (showLock) const Positioned.fill(child: LockScreen()),
      ],
    );
  }
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Ask right away; the button is for when the prompt was cancelled.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    final ok = await ref.read(appLockProvider.notifier).unlock();
    if (!ok && mounted) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.primaryDark,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 56, color: AppTheme.accentAmber),
                const SizedBox(height: 16),
                const Text('Zunft ist gesperrt', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  _failed
                      ? 'Das hat nicht geklappt. Bitte erneut versuchen.'
                      : 'Bitte mit Fingerabdruck, Gesicht oder PIN entsperren.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                    onPressed: _unlock, icon: const Icon(Icons.fingerprint), label: const Text('Entsperren')),
                const SizedBox(height: 8),
                // Never trap someone: signing out works without unlocking.
                TextButton(
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  child: const Text('Abmelden'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

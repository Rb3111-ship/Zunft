import 'package:zunft_app/core/security/app_lock.dart';

class FakeDeviceAuthenticator implements DeviceAuthenticator {
  bool supported = true;
  bool succeeds = true;
  int prompts = 0;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return succeeds;
  }
}

class FakeAppLockStore implements AppLockStore {
  FakeAppLockStore([this.prefs = const AppLockPrefs()]);
  AppLockPrefs prefs;

  @override
  Future<AppLockPrefs> load() async => prefs;

  @override
  Future<void> save(AppLockPrefs p) async => prefs = p;
}

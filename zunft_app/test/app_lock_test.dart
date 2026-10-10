import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/security/app_lock.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';

import 'helpers/fake_app_lock.dart';
import 'helpers/fake_auth_repository.dart';
import 'helpers/test_app.dart';

/// A real app goes resumed -> inactive -> hidden -> paused (and back the same way).
void background(WidgetTester tester) {
  for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

void foreground(WidgetTester tester) {
  for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

void main() {
  group('the lock controller', () {
    late FakeDeviceAuthenticator device;
    late FakeAppLockStore store;
    late DateTime now;

    AppLockController make() => AppLockController(store, device, () => now);

    setUp(() {
      device = FakeDeviceAuthenticator();
      store = FakeAppLockStore();
      now = DateTime(2026, 10, 11, 8);
    });

    test('off by default: nothing is locked, ever', () async {
      final c = make();
      await Future<void>.delayed(Duration.zero);
      expect(c.state.loaded, isTrue);
      c.paused();
      now = now.add(const Duration(hours: 5));
      c.resumed();
      expect(c.state.locked, isFalse);
    });

    test('switching on needs a phone with a screen lock and a successful confirmation', () async {
      final c = make();
      await Future<void>.delayed(Duration.zero);

      device.supported = false;
      expect(await c.setEnabled(true), contains('keine Bildschirmsperre'));
      expect(c.state.enabled, isFalse);
      expect(store.prefs.enabled, isFalse);

      device
        ..supported = true
        ..succeeds = false;
      expect(await c.setEnabled(true), contains('Bestätigung'));
      expect(c.state.enabled, isFalse);

      device.succeeds = true;
      expect(await c.setEnabled(true), isNull);
      expect(c.state.enabled, isTrue);
      expect(c.state.locked, isFalse); // the person just proved who they are
      expect(store.prefs.enabled, isTrue);
    });

    test('switching off needs no confirmation here (the person is already inside the unlocked app)', () async {
      store.prefs = const AppLockPrefs(enabled: true);
      final c = make();
      await Future<void>.delayed(Duration.zero);
      await c.unlock();
      final before = device.prompts;
      expect(await c.setEnabled(false), isNull);
      expect(c.state.enabled, isFalse);
      expect(device.prompts, before);
    });

    test('a cold start with the lock on begins locked', () async {
      store.prefs = const AppLockPrefs(enabled: true);
      final c = make();
      await Future<void>.delayed(Duration.zero);
      expect(c.state.locked, isTrue);
    });

    test('back after less than the timeout: still open; after the timeout: locked', () async {
      store.prefs = const AppLockPrefs(enabled: true, timeoutSeconds: 60);
      final c = make();
      await Future<void>.delayed(Duration.zero);
      await c.unlock();
      expect(c.state.locked, isFalse);

      c.paused();
      now = now.add(const Duration(seconds: 59));
      c.resumed();
      expect(c.state.locked, isFalse);

      c.paused();
      now = now.add(const Duration(seconds: 61));
      c.resumed();
      expect(c.state.locked, isTrue);
    });

    test('the timeout is the one the person chose', () async {
      store.prefs = const AppLockPrefs(enabled: true, timeoutSeconds: 60);
      final c = make();
      await Future<void>.delayed(Duration.zero);
      await c.unlock();
      await c.setTimeout(300);
      expect(store.prefs.timeoutSeconds, 300);
      c.paused();
      now = now.add(const Duration(minutes: 4));
      c.resumed();
      expect(c.state.locked, isFalse);
      c.paused();
      now = now.add(const Duration(minutes: 6));
      c.resumed();
      expect(c.state.locked, isTrue);
    });

    test('a failed or cancelled unlock stays locked; the next try can succeed', () async {
      store.prefs = const AppLockPrefs(enabled: true);
      final c = make();
      await Future<void>.delayed(Duration.zero);
      device.succeeds = false;
      expect(await c.unlock(), isFalse);
      expect(c.state.locked, isTrue);
      device.succeeds = true;
      expect(await c.unlock(), isTrue);
      expect(c.state.locked, isFalse);
    });
  });

  group('on the screen', () {
    FakeAuthRepository owner() => FakeAuthRepository(
          userId: 'u1',
          profile: const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: 'owner'),
        );

    testApp('the switch under Betrieb turns the lock on; a phone without a screen lock explains why not', (tester) async {
      final device = FakeDeviceAuthenticator()..supported = false;
      final store = FakeAppLockStore();
      await pumpApp(tester, owner(), deviceAuth: device, lockStore: store);
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('App-Sperre'), 200, scrollable: find.byType(Scrollable).first);

      await tester.tap(find.text('App-Sperre'));
      await tester.pumpAndSettle();
      expect(find.textContaining('keine Bildschirmsperre'), findsOneWidget);
      expect(store.prefs.enabled, isFalse);

      device.supported = true;
      await tester.pumpAndSettle(const Duration(seconds: 5)); // let the snack bar go
      await tester.tap(find.text('App-Sperre'));
      await tester.pumpAndSettle();
      expect(store.prefs.enabled, isTrue);
      expect(find.text('nach 1 Minute'), findsOneWidget); // the timeout choice appears
    });

    testApp('back from the background after the timeout: the lock screen covers the app until unlocked', (tester) async {
      var now = DateTime(2026, 10, 11, 8);
      final device = FakeDeviceAuthenticator();
      final store = FakeAppLockStore(const AppLockPrefs(enabled: true, timeoutSeconds: 60));
      device.succeeds = false; // the cold-start prompt is cancelled
      await pumpApp(tester, owner(), deviceAuth: device, lockStore: store, lockClock: () => now);

      // locked on start
      expect(find.text('Zunft ist gesperrt'), findsOneWidget);
      expect(find.text('Das hat nicht geklappt. Bitte erneut versuchen.'), findsOneWidget);

      device.succeeds = true;
      await tester.tap(find.text('Entsperren'));
      await tester.pumpAndSettle();
      expect(find.text('Zunft ist gesperrt'), findsNothing);
      expect(find.text('ERFASSEN'), findsOneWidget);

      // away for 2 minutes
      background(tester);
      now = now.add(const Duration(minutes: 2));
      foreground(tester);
      await tester.pump();
      expect(find.text('Zunft ist gesperrt'), findsOneWidget);
      await tester.pumpAndSettle(); // the prompt appears by itself and succeeds
      expect(find.text('Zunft ist gesperrt'), findsNothing);
    });

    testApp('away for a few seconds only: no lock', (tester) async {
      var now = DateTime(2026, 10, 11, 8);
      final store = FakeAppLockStore(const AppLockPrefs(enabled: true, timeoutSeconds: 60));
      await pumpApp(tester, owner(), lockStore: store, lockClock: () => now);
      expect(find.text('Zunft ist gesperrt'), findsNothing); // the start prompt succeeded

      background(tester);
      now = now.add(const Duration(seconds: 10));
      foreground(tester);
      await tester.pumpAndSettle();
      expect(find.text('Zunft ist gesperrt'), findsNothing);
    });

    testApp('signing out works from the lock screen without unlocking', (tester) async {
      final device = FakeDeviceAuthenticator()..succeeds = false;
      final repo = owner();
      await pumpApp(tester, repo, deviceAuth: device, lockStore: FakeAppLockStore(const AppLockPrefs(enabled: true)));
      expect(find.text('Zunft ist gesperrt'), findsOneWidget);
      await tester.tap(find.text('Abmelden'));
      await tester.pumpAndSettle();
      expect(find.text('Zunft ist gesperrt'), findsNothing); // signed out: the login screen, no lock over it
      expect(find.text('Anmelden'), findsWidgets);
    });
  });
}

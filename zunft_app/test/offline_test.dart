import 'package:drift/native.dart';
import 'package:flutter/material.dart' show TextFormField;
import 'package:flutter/widgets.dart' show AppLifecycleState, Scrollable;
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/data/data_repository.dart';

import 'helpers/fake_auth_cache.dart';
import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/test_app.dart';

const owner = UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: 'owner');

FakeAuthRepository repo({bool offline = false, UserProfile profile = owner}) =>
    FakeAuthRepository(userId: 'u1', profile: profile, business: FakeAuthRepository.completeBusiness())..offline = offline;

/// A phone that has been used before: the business is on the phone, with a customer and a job.
Future<AppDatabase> usedPhone(WidgetTester tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  await tester.runAsync(() async {
    await db.ensureBusiness('b1:u1');
    final data = DataRepository(db, businessId: 'b1', onChanged: () {});
    final c = await data.saveCustomer(name: 'Müller', firstName: 'Thomas', street: 'Hauptstraße 5', zip: '20095', city: 'Hamburg');
    await data.saveJob(id: 'job-1', title: 'Steckdose Keller', customerId: c);
  });
  return db;
}

void foreground(WidgetTester tester) {
  for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

void main() {
  group('opening the app without network', () {
    testApp('a phone that was used before opens with the data it has, and the business name', (tester) async {
      final db = await usedPhone(tester);
      final cache = FakeAuthCache(cachedProfile: owner, cachedBusiness: FakeAuthRepository.completeBusiness());
      await pumpApp(tester, repo(offline: true), remote: FakeSyncRemote()..offline = true, database: db, authCache: cache);

      expect(find.text('ERFASSEN'), findsOneWidget);
      expect(find.text('Steckdose Keller'), findsOneWidget); // the job is on the phone
      expect(find.text('Elektro Test GmbH'), findsOneWidget); // the business name in the bar, from the cache
      expect(find.text('Profil konnte nicht geladen werden.'), findsNothing);
    });

    testApp('the very first start without network (nothing known yet) says so and offers to retry', (tester) async {
      final r = repo(offline: true);
      await pumpApp(tester, r, remote: FakeSyncRemote()..offline = true);
      expect(find.text('Profil konnte nicht geladen werden.'), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsOneWidget);

      r.offline = false; // the network is back
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();
      expect(find.text('ERFASSEN'), findsOneWidget);
    });

    testApp('with network the profile and the business are remembered for the next start', (tester) async {
      final cache = FakeAuthCache();
      await pumpApp(tester, repo(), authCache: cache);
      expect(cache.cachedProfile?.fullName, 'Erika');
      expect(cache.cachedBusiness?.name, 'Elektro Test GmbH');
      expect(cache.cachedBusiness?.defaultHourlyRateCents, 6800);
    });

    testApp('a working day without network: customers, jobs, appointments and time are saved and reach the server later', (tester) async {
      final db = await usedPhone(tester);
      final server = FakeSyncRemote()..offline = true;
      final cache = FakeAuthCache(cachedProfile: owner, cachedBusiness: FakeAuthRepository.completeBusiness());
      final app = await pumpApp(tester, repo(offline: true), remote: server, database: db, authCache: cache);

      // plan an appointment
      await tester.tap(find.text('Termine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Neuer Termin'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Titel'), 'Beim Kunden');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Beim Kunden'), findsOneWidget);

      // start and stop the timer on the job
      await tester.tap(find.text('Aufträge'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Steckdose Keller'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Zeit starten'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Zeit starten'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zeit stoppen'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect((await tester.runAsync(() => app.db.pendingOutbox()))!.map((o) => o.entity).toSet(),
          containsAll(['appointment', 'timeEntry', 'customer', 'job']));
      expect(server.tables[SyncEntity.appointment], isEmpty);

      // the network is back
      server.offline = false;
      foreground(tester);
      await tester.pumpAndSettle();
      expect(server.tables[SyncEntity.appointment]!.values.single['title'], 'Beim Kunden');
      expect(server.tables[SyncEntity.timeEntry]!.values.single['job_id'], 'job-1');
      expect(server.tables[SyncEntity.job]!.containsKey('job-1'), isTrue);
      expect(await tester.runAsync(() => app.db.pendingOutbox()), isEmpty);
    });
  });

  group('the server stays the truth', () {
    testApp('back online the app learns that access was switched off meanwhile', (tester) async {
      final r = repo(offline: true);
      final cache = FakeAuthCache(cachedProfile: owner, cachedBusiness: FakeAuthRepository.completeBusiness());
      await pumpApp(tester, r, remote: FakeSyncRemote()..offline = true, authCache: cache);
      expect(find.text('ERFASSEN'), findsOneWidget);

      r
        ..offline = false
        ..profile = const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: 'owner', active: false);
      foreground(tester);
      await tester.pumpAndSettle();
      expect(find.text('Dein Zugang wurde abgeschaltet.'), findsOneWidget);
      expect(cache.cachedProfile?.active, isFalse);
    });

    testApp('a changed setting on the server (the business) arrives when the app comes to the front', (tester) async {
      final r = repo();
      await pumpApp(tester, r);
      expect(find.text('Elektro Test GmbH'), findsOneWidget);
      r.business = Business.fromJson({...r.business.toCacheJson(), 'name': 'Elektro Neu GmbH'});
      foreground(tester);
      await tester.pumpAndSettle();
      expect(find.text('Elektro Neu GmbH'), findsOneWidget);
    });

    testApp('no change on the server: nothing is reloaded (no flicker on every return)', (tester) async {
      final r = repo();
      await pumpApp(tester, r);
      final before = r.profileFetches;
      foreground(tester);
      await tester.pumpAndSettle();
      expect(r.profileFetches - before, lessThanOrEqualTo(2)); // a check or two, not a reload of everything
      expect(find.text('ERFASSEN'), findsOneWidget);
    });

    testApp('a cache of another person is never used', (tester) async {
      final cache = FakeAuthCache(cachedProfile: owner, cachedBusiness: FakeAuthRepository.completeBusiness(), user: 'someone-else');
      await pumpApp(tester, repo(offline: true), remote: FakeSyncRemote()..offline = true, authCache: cache);
      expect(find.text('Profil konnte nicht geladen werden.'), findsOneWidget);
    });

    testApp('signing out forgets the profile and the business', (tester) async {
      final cache = FakeAuthCache(cachedProfile: owner, cachedBusiness: FakeAuthRepository.completeBusiness());
      await pumpApp(tester, repo(), authCache: cache);
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Abmelden'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Abmelden'));
      await tester.pumpAndSettle();
      expect(cache.clears, 1);
      expect(cache.cachedProfile, isNull);
      expect(cache.cachedBusiness, isNull);
    });
  });
}

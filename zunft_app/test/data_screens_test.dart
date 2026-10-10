import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/customers/presentation/customers_tab.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/test_app.dart';

FakeAuthRepository signedIn() => FakeAuthRepository(
      userId: 'u1',
      profile: const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: 'owner'),
    );

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextFormField, label), text);
}

void main() {
  group('customerMatches', () {
    Customer c({String name = 'Müller', String? first = 'Thomas', String? city = 'Hamburg', String? phone}) => Customer(
          id: '1',
          businessId: 'b1',
          name: name,
          firstName: first,
          city: city,
          phone: phone,
          updatedAt: DateTime(2026),
        );

    test('empty query matches everyone', () => expect(customerMatches(c(), '  '), isTrue));
    test('is case-insensitive and matches name, city and phone', () {
      expect(customerMatches(c(), 'müller'), isTrue);
      expect(customerMatches(c(), 'HAMBURG'), isTrue);
      expect(customerMatches(c(phone: '+49 171 1234567'), '1234567'), isTrue);
    });
    test('every word must match somewhere', () {
      expect(customerMatches(c(), 'thomas müller'), isTrue);
      expect(customerMatches(c(), 'thomas schmidt'), isFalse);
    });
  });

  group('empty states', () {
    testApp('jobs and customers show helpful empty messages', (tester) async {
      await pumpApp(tester, signedIn());
      expect(find.textContaining('Noch keine Aufträge'), findsOneWidget);
      await openTab(tester, 'Kunden');
      expect(find.textContaining('Noch keine Kunden'), findsOneWidget);
    });
  });

  group('customers', () {
    testApp('creating a customer saves locally, lists it, and syncs to the server', (tester) async {
      final app = await pumpApp(tester, signedIn());
      await openTab(tester, 'Kunden');

      await tester.tap(find.byTooltip('Kunde anlegen'));
      await tester.pumpAndSettle();
      await enter(tester, 'Vorname', 'Thomas');
      await enter(tester, 'Nachname / Firma', 'Müller');
      await enter(tester, 'Ort', 'Hamburg');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      expect(find.text('Thomas Müller'), findsOneWidget);
      final stored = await tester.runAsync(() => app.db.select(app.db.customers).get());
      expect(stored, hasLength(1));
      expect(stored!.single.businessId, 'b1');

      // Debounce is zero in tests, so the background sync has already pushed it.
      expect(app.remote.tables[SyncEntity.customer], hasLength(1));
      expect(app.remote.tables[SyncEntity.customer]!.values.single['name'], 'Müller');
    });

    testApp('a customer needs a name', (tester) async {
      final app = await pumpApp(tester, signedIn());
      await openTab(tester, 'Kunden');
      await tester.tap(find.byTooltip('Kunde anlegen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      expect(find.text('Name darf nicht leer sein'), findsOneWidget);
      expect(app.remote.tables[SyncEntity.customer], isEmpty);
    });

    testApp('search narrows the list', (tester) async {
      final remote = FakeSyncRemote()
        ..seed(SyncEntity.customer, {...remoteCustomer('c1', name: 'Müller'), 'first_name': 'Thomas'})
        ..seed(SyncEntity.customer, {...remoteCustomer('c2', name: 'Schmidt'), 'first_name': 'Sabine'});
      await pumpApp(tester, signedIn(), remote: remote);
      await openTab(tester, 'Kunden');
      expect(find.text('Thomas Müller'), findsOneWidget);
      expect(find.text('Sabine Schmidt'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'schmidt');
      await tester.pumpAndSettle();
      expect(find.text('Thomas Müller'), findsNothing);
      expect(find.text('Sabine Schmidt'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'gibtsnicht');
      await tester.pumpAndSettle();
      expect(find.text('Kein Kunde gefunden.'), findsOneWidget);
    });

    testApp('deleting a customer asks first, then removes it here and on the server', (tester) async {
      final remote = FakeSyncRemote()..seed(SyncEntity.customer, remoteCustomer('c1', name: 'Müller'));
      final app = await pumpApp(tester, signedIn(), remote: remote);
      await openTab(tester, 'Kunden');

      await tester.tap(find.text('Müller'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(remote.tables[SyncEntity.customer], hasLength(1)); // cancelled: nothing happened

      await tester.tap(find.byTooltip('Löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Löschen'));
      await tester.pumpAndSettle();

      expect(find.text('Müller'), findsNothing);
      expect(remote.tables[SyncEntity.customer], isEmpty);
      final left = await tester.runAsync(() => app.db.select(app.db.customers).get());
      expect(left, isEmpty);
    });
  });

  group('jobs', () {
    testApp('open and finished jobs are on separate tabs, work in progress first', (tester) async {
      final remote = FakeSyncRemote()
        ..seed(SyncEntity.job, remoteJob('j1', title: 'Neu angelegt'))
        ..seed(SyncEntity.job, {...remoteJob('j2', title: 'Läuft gerade'), 'status': 'in_progress'})
        ..seed(SyncEntity.job, {...remoteJob('j3', title: 'Fertig ungebucht'), 'status': 'completed'})
        ..seed(SyncEntity.job, {...remoteJob('j4', title: 'Längst bezahlt'), 'status': 'invoiced'});
      await pumpApp(tester, signedIn(), remote: remote);

      expect(find.text('Offen (2)'), findsOneWidget);
      expect(find.text('Erledigt (2)'), findsOneWidget);
      expect(find.text('Neu angelegt'), findsOneWidget);
      expect(find.text('Läuft gerade'), findsOneWidget);
      expect(find.text('Fertig ungebucht'), findsNothing);
      expect(tester.getTopLeft(find.text('Läuft gerade')).dy, lessThan(tester.getTopLeft(find.text('Neu angelegt')).dy));

      await tester.tap(find.text('Erledigt (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Neu angelegt'), findsNothing);
      expect(find.text('Fertig ungebucht'), findsOneWidget);
      expect(find.text('Längst bezahlt'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Fertig ungebucht')).dy, lessThan(tester.getTopLeft(find.text('Längst bezahlt')).dy));
    });

    testApp('an empty tab says so instead of showing nothing', (tester) async {
      final remote = FakeSyncRemote()..seed(SyncEntity.job, remoteJob('j1', title: 'Neu angelegt'));
      await pumpApp(tester, signedIn(), remote: remote);
      await tester.tap(find.text('Erledigt (0)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Noch keine erledigten Aufträge'), findsOneWidget);
    });

    testApp('a job is created for a customer, shown with status, and synced', (tester) async {
      final remote = FakeSyncRemote()
        ..seed(SyncEntity.customer, {...remoteCustomer('c1', name: 'Müller'), 'first_name': 'Thomas'});
      await pumpApp(tester, signedIn(), remote: remote);

      await tester.tap(find.text('Neuer Auftrag'));
      await tester.pumpAndSettle();
      await enter(tester, 'Titel', 'Steckdose Keller');
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thomas Müller').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      expect(find.text('Steckdose Keller'), findsOneWidget);
      expect(find.text('Thomas Müller'), findsOneWidget);
      expect(find.text('Entwurf'), findsWidgets);
      final job = remote.tables[SyncEntity.job]!.values.single;
      expect(job['title'], 'Steckdose Keller');
      expect(job['customer_id'], 'c1');
      expect(job['status'], 'draft');
    });

    testApp('a job needs a title', (tester) async {
      await pumpApp(tester, signedIn());
      await tester.tap(find.text('Neuer Auftrag'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Titel darf nicht leer sein'), findsOneWidget);
    });

    testApp('server jobs appear after the first sync, and the tabs count them by status', (tester) async {
      final remote = FakeSyncRemote()
        ..seed(SyncEntity.job, {...remoteJob('j1', title: 'A'), 'status': 'draft'})
        ..seed(SyncEntity.job, {...remoteJob('j2', title: 'B'), 'status': 'in_progress'})
        ..seed(SyncEntity.job, {...remoteJob('j3', title: 'C'), 'status': 'in_progress'});
      await pumpApp(tester, signedIn(), remote: remote);

      expect(find.text('A'), findsOneWidget);
      expect(find.text('Kein Kunde zugeordnet'), findsNWidgets(3));
      expect(find.text('Offen (3)'), findsOneWidget);
      expect(find.text('Erledigt (0)'), findsOneWidget);
    });

    testApp('finishing a job closes it for notes; reopening brings the record button back', (tester) async {
      final remote = FakeSyncRemote()..seed(SyncEntity.job, remoteJob('j1', title: 'Auftrag'));
      await pumpApp(tester, signedIn(), remote: remote);

      await tester.tap(find.text('Auftrag'));
      await tester.pumpAndSettle();
      expect(find.text('Notiz zu diesem Auftrag aufnehmen'), findsOneWidget);
      await tester.tap(find.text('Auftrag abschließen'));
      await tester.pumpAndSettle();

      expect(remote.row(SyncEntity.job, 'j1')!['status'], 'completed');
      expect(find.text('Notiz zu diesem Auftrag aufnehmen'), findsNothing);
      expect(find.textContaining('abgeschlossen'), findsWidgets);

      await tester.tap(find.text('Auftrag wieder öffnen'));
      await tester.pumpAndSettle();
      expect(remote.row(SyncEntity.job, 'j1')!['status'], 'in_progress');
      expect(find.text('Notiz zu diesem Auftrag aufnehmen'), findsOneWidget);
    });
  });

  group('sync status tile', () {
    testApp('shows synchronised state with the last sync time', (tester) async {
      await pumpApp(tester, signedIn());
      await openTab(tester, 'Betrieb');
      expect(find.text('Synchronisiert'), findsOneWidget);
      expect(find.textContaining('Letzter Sync:'), findsOneWidget);
    });

    testApp('offline: says so and counts changes waiting for upload', (tester) async {
      final remote = FakeSyncRemote()..offline = true;
      await pumpApp(tester, signedIn(), remote: remote);
      await openTab(tester, 'Kunden');
      await tester.tap(find.byTooltip('Kunde anlegen'));
      await tester.pumpAndSettle();
      await enter(tester, 'Nachname / Firma', 'Offline GmbH');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      // Still visible locally even though the server is unreachable.
      expect(find.text('Offline GmbH'), findsOneWidget);

      await openTab(tester, 'Betrieb');
      expect(find.text('Offline'), findsOneWidget);
      expect(find.textContaining('1 Änderung wartet auf Upload'), findsOneWidget);

      // Back online: tapping the tile syncs and clears the queue.
      remote.offline = false;
      await tester.tap(find.text('Offline'));
      await tester.pumpAndSettle();
      expect(find.text('Synchronisiert'), findsOneWidget);
      expect(find.textContaining('wartet auf Upload'), findsNothing);
      expect(remote.tables[SyncEntity.customer], hasLength(1));
    });
  });
}

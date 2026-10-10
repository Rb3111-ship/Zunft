import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/core/utils/customer_duplicates.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/data/data_repository.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/test_app.dart';

Customer cust(String id,
        {String name = 'Müller', String? first, String? phone, String? email, String? street, String? zip}) =>
    Customer(
        id: id,
        businessId: 'b1',
        name: name,
        firstName: first,
        phone: phone,
        email: email,
        street: street,
        zip: zip,
        updatedAt: DateTime(2026));

void main() {
  group('pairs of possible duplicates', () {
    test('the same phone number under a different name is a soft hint', () {
      final pairs = findDuplicatePairs([
        cust('1', name: 'Müller', first: 'Thomas', phone: '0171 1234567'),
        cust('2', name: 'Mueller', first: 'Th.', phone: '+49 171 1234567'),
      ]);
      expect(pairs, hasLength(1));
      expect(pairs.single.strong, isFalse);
      expect(pairs.single.sharedContact, 'Telefonnummer');
    });

    test('the same e-mail under a different name is a soft hint', () {
      final pairs = findDuplicatePairs([
        cust('1', name: 'Schmidt', email: 'info@schmidt.de'),
        cust('2', name: 'Schmidt Bau GmbH', email: 'INFO@schmidt.de'),
      ]);
      expect(pairs.single.sharedContact, 'E-Mail-Adresse');
    });

    test('the same name at different addresses is NOT a pair', () {
      expect(
          findDuplicatePairs([
            cust('1', first: 'Thomas', street: 'Hauptstraße 5', zip: '20095'),
            cust('2', first: 'Thomas', street: 'Elbchaussee 118', zip: '22763'),
          ]),
          isEmpty);
    });

    test('different names, different contacts: nothing', () {
      expect(findDuplicatePairs([cust('1', name: 'Müller', phone: '0171 1111111'), cust('2', name: 'Schulz', phone: '0171 2222222')]),
          isEmpty);
    });

    test('same name and same address is a strong pair, listed first', () {
      final pairs = findDuplicatePairs([
        cust('1', name: 'Schmidt', phone: '0171 1234567'),
        cust('2', name: 'Meier', phone: '0171 1234567'),
        cust('3', first: 'Thomas', street: 'Hauptstraße 5', zip: '20095'),
        cust('4', first: 'Thomas', street: 'Hauptstr. 5', zip: '20095'),
      ]);
      expect(pairs.first.strong, isTrue);
      expect(pairs, hasLength(2));
    });
  });

  group('merging two customers', () {
    late AppDatabase db;
    late DataRepository data;
    var ids = 0;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      ids = 0;
      data = DataRepository(db, businessId: 'b1', onChanged: () {}, newId: () => 'id-${++ids}');
    });
    tearDown(() => db.close());

    test('the jobs move over, missing details are filled in, different ones go into the notes', () async {
      final keep = await data.saveCustomer(name: 'Müller', firstName: 'Thomas', phone: '0171 1111111', notes: 'Hund im Haus');
      final gone = await data.saveCustomer(
          name: 'Mueller', firstName: 'Th.', phone: '0171 2222222', email: 'tm@example.de', street: 'Hauptstraße 5', zip: '20095', city: 'Hamburg');
      await data.saveJob(id: 'j1', title: 'Steckdose', customerId: gone);
      await data.saveJob(id: 'j2', title: 'Licht', customerId: keep);

      await data.mergeCustomers(keepId: keep, removeId: gone);

      final k = (await db.customerById(keep))!;
      expect(k.email, 'tm@example.de'); // was missing: filled in
      expect(k.street, 'Hauptstraße 5');
      expect(k.phone, '0171 1111111'); // the kept customer's own value wins
      expect(k.notes, contains('Hund im Haus'));
      expect(k.notes, contains('Zusammengeführt mit „Th. Mueller“'));
      expect(k.notes, contains('Telefon 0171 2222222')); // nothing is lost
      expect((await db.jobById('j1'))!.customerId, keep);
      expect((await db.jobById('j2'))!.customerId, keep);
    });

    test('the merged customer is hidden but not deleted, and the change is queued for the server', () async {
      final keep = await data.saveCustomer(name: 'Müller', firstName: 'Thomas');
      final gone = await data.saveCustomer(name: 'Mueller', firstName: 'Thomas');
      await data.mergeCustomers(keepId: keep, removeId: gone);

      expect((await db.allCustomers()).map((c) => c.id), [keep]);
      expect((await db.customerById(gone))!.mergedInto, keep); // still there for documents
      final queued = await db.select(db.outbox).get();
      expect(queued.map((o) => o.entityId), containsAll([keep, gone]));
    });

    test('merging a customer into itself or into an already merged one is refused', () async {
      final a = await data.saveCustomer(name: 'A');
      final b = await data.saveCustomer(name: 'B');
      final c = await data.saveCustomer(name: 'C');
      await data.mergeCustomers(keepId: a, removeId: b);
      expect(() => data.mergeCustomers(keepId: a, removeId: a), throwsA(isA<ValidationFailure>()));
      expect(() => data.mergeCustomers(keepId: c, removeId: b), throwsA(isA<ValidationFailure>()));
    });

    test('a customer with an issued document cannot be deleted (the document is frozen by law)', () async {
      final id = await data.saveCustomer(name: 'Müller');
      await db.upsertDocument(IssuedDocumentsCompanion.insert(
        id: 'd1',
        businessId: 'b1',
        customerId: Value(id),
        docType: 'invoice',
        docNumber: 'RE-2026-0001',
        status: 'issued',
        dateIssued: '2026-10-01',
        subtotalLaborCents: 100,
        subtotalMaterialCents: 0,
        totalNetCents: 100,
        vatRate: 19,
        vatAmountCents: 19,
        totalGrossCents: 119,
        lineItemsJson: '[]',
        recipientName: 'Müller',
        updatedAt: DateTime(2026),
      ));
      expect(() => data.deleteCustomer(id), throwsA(isA<ValidationFailure>()));
      expect(await db.customerById(id), isNotNull);
    });
  });

  group('the screens', () {
    FakeAuthRepository owner() => FakeAuthRepository(
          userId: 'u1',
          profile: const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: 'owner'),
        );

    FakeSyncRemote twoWithSamePhone() => FakeSyncRemote()
      ..seed(SyncEntity.customer, {...remoteCustomer('c1', name: 'Müller'), 'first_name': 'Thomas', 'phone': '0171 1234567'})
      ..seed(SyncEntity.customer, {...remoteCustomer('c2', name: 'Mueller'), 'first_name': 'Th.', 'phone': '0171 1234567'})
      ..seed(SyncEntity.job, remoteJob('j1', title: 'Steckdose', customerId: 'c2'));

    testApp('the boss sees a hint, compares the two and merges; the duplicate disappears from the list', (tester) async {
      final app = await pumpApp(tester, owner(), remote: twoWithSamePhone());
      await tester.tap(find.text('Kunden'));
      await tester.pumpAndSettle();
      expect(find.text('1 möglicher Doppelter'), findsOneWidget);

      await tester.tap(find.text('1 möglicher Doppelter'));
      await tester.pumpAndSettle();
      expect(find.text('Gleiche Telefonnummer'), findsOneWidget);
      await tester.tap(find.text('Gleiche Telefonnummer'));
      await tester.pumpAndSettle();
      expect(find.text('BLEIBT'), findsOneWidget);
      expect(find.text('WIRD ZUSAMMENGEFÜHRT'), findsOneWidget);

      await tester.tap(find.text('Zusammenführen'));
      await tester.pumpAndSettle();

      expect(find.text('Kunden zusammengeführt.'), findsOneWidget);
      expect(find.text('1 möglicher Doppelter'), findsNothing);
      final customers = await tester.runAsync(() => app.db.allCustomers());
      expect(customers, hasLength(1));
      final job = await tester.runAsync(() => app.db.jobById('j1'));
      expect(job!.customerId, customers!.single.id);
    });

    testApp('an employee does not see the hint', (tester) async {
      final employee = FakeAuthRepository(
        userId: 'u2',
        profile: const UserProfile(id: 'u2', businessId: 'b1', fullName: 'Hans', role: 'geselle'),
      );
      await pumpApp(tester, employee, remote: twoWithSamePhone());
      await tester.tap(find.text('Kunden'));
      await tester.pumpAndSettle();
      expect(find.textContaining('möglicher Doppelter'), findsNothing);
    });
  });
}

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/core/utils/customer_duplicates.dart';
import 'package:zunft_app/features/data/data_repository.dart';
import 'package:zunft_app/features/documents/data/document_service.dart';
import 'package:zunft_app/features/review/models/draft_models.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_documents.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/job_app.dart';
import 'helpers/test_app.dart';

Customer c(
  String id, {
  String name = 'Müller',
  String? first = 'Thomas',
  String? street,
  String? zip,
  String? phone,
  String? email,
}) =>
    Customer(
        id: id,
        businessId: 'b1',
        name: name,
        firstName: first,
        street: street,
        zip: zip,
        phone: phone,
        email: email,
        updatedAt: DateTime(2026));

List<DuplicateMatch> dupes(List<Customer> existing,
        {String name = 'Müller',
        String? first = 'Thomas',
        String? street,
        String? zip,
        String? phone,
        String? email,
        String? excludeId}) =>
    findDuplicateCustomers(existing,
        name: name, firstName: first, street: street, zip: zip, phone: phone, email: email, excludeId: excludeId);

void main() {
  group('a name alone does not identify a customer', () {
    test('same name at a DIFFERENT address is a different person: no warning', () {
      final existing = [c('1', street: 'Hauptstraße 5', zip: '20095')];
      expect(dupes(existing, street: 'Elbchaussee 118', zip: '22763'), isEmpty);
      expect(dupes(existing, street: 'Hauptstraße 5', zip: '22763'), isEmpty); // same street name, other town
    });

    test('same name and same address is a strong match', () {
      final m = dupes([c('1', street: 'Hauptstraße 5', zip: '20095')], street: 'Hauptstraße 5', zip: '20095').single;
      expect(m.strong, isTrue);
      expect(m.customer.id, '1');
    });

    test('same name and same phone or e-mail is a strong match, whatever the formatting', () {
      expect(dupes([c('1', phone: '+49 171 1234567')], phone: '0171/1234567').single.strong, isTrue);
      expect(dupes([c('1', email: 'Thomas@Mueller.de')], email: 'thomas@mueller.de').single.strong, isTrue);
    });

    test('same name with details missing on either side is only a possible match', () {
      expect(dupes([c('1')]).single.strong, isFalse); // nothing known about either
      expect(dupes([c('1', street: 'Hauptstraße 5', zip: '20095')]).single.strong, isFalse); // new one has no address
      expect(
          dupes([c('1')], street: 'Hauptstraße 5', zip: '20095').single.strong, isFalse); // existing one has no address
    });

    test('a different name never matches, even at the same address', () {
      expect(
          dupes([c('1', first: 'Sabine', street: 'Hauptstraße 5', zip: '20095')],
              street: 'Hauptstraße 5', zip: '20095'),
          isEmpty);
      expect(
          dupes([c('1', name: 'Schmidt', street: 'Hauptstraße 5', zip: '20095')],
              street: 'Hauptstraße 5', zip: '20095'),
          isEmpty);
    });

    test('a tiny phone number fragment is not used for matching', () {
      expect(dupes([c('1', phone: '123', street: 'A 1', zip: '11111')], phone: '123', street: 'B 2', zip: '22222'),
          isEmpty);
    });
  });

  group('spelling differences', () {
    test('order, case, umlauts and ß are ignored in names', () {
      expect(dupes([c('1', name: 'Müller', first: 'Thomas')], name: 'Mueller', first: 'thomas').length, 1);
      expect(dupes([c('1', name: 'Thomas Müller', first: null)], name: 'Müller', first: 'Thomas').length,
          1); // voice-created
      expect(dupes([c('1', name: 'Müller, Thomas', first: null)], name: 'Thomas Müller', first: null).length, 1);
      expect(dupes([c('1', name: 'Strauß', first: null)], name: 'Strauss', first: null).length, 1);
    });

    test('"Straße" and "Str." are the same street', () {
      expect(dupes([c('1', street: 'Hauptstraße 5', zip: '20095')], street: 'Hauptstr. 5', zip: '20095').single.strong,
          isTrue);
      expect(dupes([c('1', street: 'Hauptstr.5', zip: '20095')], street: 'hauptstrasse 5', zip: '20095').single.strong,
          isTrue);
    });

    test('house number matters: no. 5 and no. 7 are different addresses', () {
      expect(dupes([c('1', street: 'Hauptstraße 5', zip: '20095')], street: 'Hauptstraße 7', zip: '20095'), isEmpty);
    });
  });

  group('the customer being edited is not its own duplicate; strong matches come first', () {
    test(
        'excludeId',
        () =>
            expect(dupes([c('1', street: 'A 1', zip: '11111')], street: 'A 1', zip: '11111', excludeId: '1'), isEmpty));

    test('ordering', () {
      final m =
          dupes([c('weak'), c('strong', street: 'Hauptstraße 5', zip: '20095')], street: 'Hauptstraße 5', zip: '20095');
      expect(m.map((x) => x.customer.id), ['strong', 'weak']);
    });

    test('an empty name finds nothing', () => expect(dupes([c('1')], name: ' ', first: ''), isEmpty));
  });

  group('creating a customer by hand', () {
    FakeSyncRemote existing() => FakeSyncRemote()
      ..seed(SyncEntity.customer, {
        ...remoteCustomer('c1', name: 'Müller'),
        'first_name': 'Thomas',
        'street': 'Hauptstraße 5',
        'zip': '20095',
        'city': 'Hamburg',
      });

    Future<void> create(WidgetTester tester, {String street = '', String zip = ''}) async {
      await tester.tap(find.text('Kunden'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Kunde anlegen'));
      await tester.pumpAndSettle();
      Future<void> enter(String label, String text) =>
          tester.enterText(find.widgetWithText(TextFormField, label), text);
      await enter('Vorname', 'Thomas');
      await enter('Nachname / Firma', 'Müller');
      if (street.isNotEmpty) await enter('Straße und Hausnummer', street);
      if (zip.isNotEmpty) await enter('PLZ', zip);
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
    }

    testApp('same name and address: clear warning; cancelling creates nothing', (tester) async {
      final app = await pumpApp(tester, signedInOwner(), remote: existing());
      await create(tester, street: 'Hauptstraße 5', zip: '20095');

      expect(find.text('Diesen Kunden gibt es schon'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect((await tester.runAsync(() => app.db.select(app.db.customers).get()))!, hasLength(1));
    });

    testApp('same name and address: the user may still create it deliberately', (tester) async {
      final app = await pumpApp(tester, signedInOwner(), remote: existing());
      await create(tester, street: 'Hauptstraße 5', zip: '20095');
      await tester.tap(find.text('Trotzdem anlegen'));
      await tester.pumpAndSettle();
      expect((await tester.runAsync(() => app.db.select(app.db.customers).get()))!, hasLength(2));
    });

    testApp('same name at another address: no warning at all', (tester) async {
      final app = await pumpApp(tester, signedInOwner(), remote: existing());
      await create(tester, street: 'Elbchaussee 118', zip: '22763');
      expect(find.textContaining('gibt es'), findsNothing);
      expect((await tester.runAsync(() => app.db.select(app.db.customers).get()))!, hasLength(2));
    });

    testApp('same name without an address: a softer question', (tester) async {
      await pumpApp(tester, signedInOwner(), remote: existing());
      await create(tester);
      expect(find.text('Gibt es diesen Kunden schon?'), findsOneWidget);
      expect(find.text('Nein, neu anlegen'), findsOneWidget);
    });
  });

  group('invoicing for someone who already exists', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late AppDatabase db;
    late FakeDocumentsRemote remote;
    late DataRepository data;
    late DocumentService service;
    var ids = 0;
    final business = FakeAuthRepository.completeBusiness();

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      remote = FakeDocumentsRemote();
      ids = 0;
      data = DataRepository(db, businessId: 'b1', onChanged: () {}, newId: () => 'id-${++ids}');
      service = DocumentService(db, remote, data: data);
    });
    tearDown(() => db.close());

    DraftDocument draft(
            {String name = 'Thomas Müller', String? address = 'Hauptstraße 5, 20095 Hamburg', String? jobId}) =>
        DraftDocument(
          jobId: jobId,
          title: 'Auftrag',
          documentType: 'invoice',
          customer: CustomerMatch(extractedName: name, extractedAddress: address, confidence: 'new'),
          lineItems: [
            DraftLineItem(
                id: '1', type: 'labor', description: 'Arbeit', quantity: 1, unit: 'Std', unitPriceNetCents: 6800)
          ],
        );

    FinalizeRequest request(DraftDocument d, String id) =>
        FinalizeRequest(documentId: id, draft: d, business: business, issueDate: DateTime(2026, 10, 1));

    test('the same person is not created twice: the document and the job use the existing customer', () async {
      final existing = await data.saveCustomer(
          name: 'Müller', firstName: 'Thomas', street: 'Hauptstraße 5', zip: '20095', city: 'Hamburg');
      await data.saveJob(id: 'j1', title: 'Neuer Auftrag');

      await service.finalize(request(draft(jobId: 'j1'), 'd1'));

      expect(await db.allCustomers(), hasLength(1));
      expect(remote.createCalls.single['customer_id'], existing);
      expect((await db.jobById('j1'))!.customerId, existing);
    });

    test('same name at another address is a new customer', () async {
      await data.saveCustomer(
          name: 'Müller', firstName: 'Thomas', street: 'Elbchaussee 118', zip: '22763', city: 'Hamburg');
      await service.finalize(request(draft(), 'd1'));
      expect(await db.allCustomers(), hasLength(2));
      expect(remote.createCalls.single['customer_id'], isNull);
    });

    test('same name but unknown address is NOT merged automatically (too risky)', () async {
      await data.saveCustomer(name: 'Müller', firstName: 'Thomas');
      await service.finalize(request(draft(), 'd1'));
      expect(await db.allCustomers(), hasLength(2));
    });
  });
}

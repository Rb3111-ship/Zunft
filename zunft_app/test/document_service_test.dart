import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/core/sync/sync_engine.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/data/data_repository.dart';
import 'package:zunft_app/features/documents/data/document_service.dart';
import 'package:zunft_app/features/documents/data/documents_remote.dart';
import 'package:zunft_app/features/review/models/draft_models.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_documents.dart';
import 'helpers/fake_sync_remote.dart';

DraftDocument draft({
  String type = 'invoice',
  String name = 'Thomas Müller',
  String? address = 'Elbchaussee 118, 22763 Hamburg',
  String? matched,
  String? jobId,
  List<DraftLineItem>? items,
}) =>
    DraftDocument(
      jobId: jobId,
      title: 'Steckdose Keller',
      documentType: type,
      customer: CustomerMatch(
          extractedName: name,
          extractedAddress: address,
          matchedCustomerId: matched,
          confidence: matched == null ? 'new' : 'exact'),
      lineItems: items ??
          [
            DraftLineItem(
                id: '1',
                type: 'labor',
                description: 'Steckdose montiert',
                quantity: 2,
                unit: 'Std',
                unitPriceNetCents: 6800),
            DraftLineItem(
                id: '2',
                type: 'material',
                description: 'Doppelsteckdose',
                quantity: 1,
                unit: 'Stk',
                unitPriceNetCents: 4000),
          ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // PDF fonts come from the asset bundle

  late AppDatabase db;
  late FakeDocumentsRemote remote;
  late DataRepository data;
  late DocumentService service;
  final business = FakeAuthRepository.completeBusiness();
  var changes = 0;
  var ids = 0;

  FinalizeRequest request(DraftDocument d,
          {String id = 'doc-1', bool createCustomer = true, List<String> noteIds = const [], Business? biz}) =>
      FinalizeRequest(
        documentId: id,
        draft: d,
        business: biz ?? business,
        issueDate: DateTime(2026, 10, 1),
        deliveryPeriod: '01.10.2026',
        createCustomer: createCustomer,
        captureLogIds: noteIds,
      );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    remote = FakeDocumentsRemote();
    changes = 0;
    ids = 0;
    data = DataRepository(db, businessId: 'b1', onChanged: () => changes++, newId: () => 'id-${++ids}');
    service = DocumentService(db, remote, data: data);
  });

  tearDown(() => db.close());

  group('blockReason (checked before any network call)', () {
    test('a complete draft passes', () => expect(DocumentService.blockReason(draft(), business), isNull));

    test('no positions, blank customer, blank description, zero quantity', () {
      expect(DocumentService.blockReason(draft(items: []), business), contains('Position'));
      expect(DocumentService.blockReason(draft(name: '  '), business), contains('Namen'));
      expect(
        DocumentService.blockReason(
            draft(items: [
              DraftLineItem(id: '1', type: 'labor', description: ' ', quantity: 1, unit: 'Std', unitPriceNetCents: 100)
            ]),
            business),
        contains('Bezeichnung'),
      );
      expect(
        DocumentService.blockReason(
            draft(items: [
              DraftLineItem(id: '1', type: 'labor', description: 'x', quantity: 0, unit: 'Std', unitPriceNetCents: 100)
            ]),
            business),
        contains('Menge'),
      );
    });

    test('an invoice needs the business address and a tax number (but not the IBAN)', () {
      final noAddress = Business.fromJson({...business.toUpdateJson(), 'id': 'b1', 'address_street': null});
      final noTax = Business.fromJson({...business.toUpdateJson(), 'id': 'b1', 'tax_number': null, 'vat_id': null});
      final noIban = Business.fromJson({...business.toUpdateJson(), 'id': 'b1', 'iban': null});
      expect(DocumentService.blockReason(draft(), noAddress), contains('Anschrift'));
      expect(DocumentService.blockReason(draft(), noTax), contains('Steuernummer'));
      expect(DocumentService.blockReason(draft(), noIban), isNull);
      // a quote has no such requirement
      expect(DocumentService.blockReason(draft(type: 'quote'), noAddress), isNull);
    });

    test('over 250 EUR gross the customer address is required for invoices, not for quotes', () {
      final big = [
        DraftLineItem(id: '1', type: 'labor', description: 'x', quantity: 4, unit: 'Std', unitPriceNetCents: 6800)
      ]; // 323,68 gross
      expect(DocumentService.blockReason(draft(address: null, items: big), business), contains('250'));
      expect(DocumentService.blockReason(draft(address: '  ', items: big), business), contains('250'));
      expect(DocumentService.blockReason(draft(address: 'Straße 1, 20095 Hamburg', items: big), business), isNull);
      expect(DocumentService.blockReason(draft(type: 'quote', address: null, items: big), business), isNull);
      // small invoices may omit it
      final small = [
        DraftLineItem(id: '1', type: 'labor', description: 'x', quantity: 1, unit: 'Std', unitPriceNetCents: 10000)
      ]; // 119,00 gross
      expect(DocumentService.blockReason(draft(address: null, items: small), business), isNull);
    });

    test('the limit uses the business VAT rate', () {
      // 210,00 net: gross is 249,90 at 19 % (allowed without address) but 224,70... at 7 % and 210 at 0 %
      final items = [
        DraftLineItem(id: '1', type: 'material', description: 'x', quantity: 1, unit: 'Stk', unitPriceNetCents: 21000)
      ];
      expect(DocumentService.blockReason(draft(address: null, items: items), business), isNull); // 249,90
      final items2 = [
        DraftLineItem(id: '1', type: 'material', description: 'x', quantity: 1, unit: 'Stk', unitPriceNetCents: 21100)
      ];
      expect(DocumentService.blockReason(draft(address: null, items: items2), business), contains('250')); // 251,09
    });
  });

  group('finalize', () {
    test('issues a numbered document, stores it locally, makes the PDF and uploads a copy', () async {
      final result = await service.finalize(request(draft(jobId: 'job-9')));

      final doc = result.document;
      expect(doc.docNumber, 'RE-2026-0001');
      expect(doc.status, 'issued');
      expect(doc.recipientName, 'Thomas Müller');
      expect(doc.recipientAddress, 'Elbchaussee 118, 22763 Hamburg');
      expect(doc.totalNetCents, 17600);
      expect(doc.totalGrossCents, 20944); // the server's numbers
      expect(doc.title, 'Steckdose Keller');
      expect(doc.dateIssued, '2026-10-01');
      expect(doc.dateDue, '2026-10-15'); // + 14 days

      expect(String.fromCharCodes(result.pdf.take(5)), '%PDF-');
      expect(result.pdfUploaded, isTrue);
      expect(doc.pdfPath, 'b1/RE-2026-0001.pdf');
      expect(remote.storedPdfs.keys, ['b1/RE-2026-0001.pdf']);
      expect(remote.documents['doc-1']!['pdf_url'], 'b1/RE-2026-0001.pdf');
    });

    test('the request sent to the server contains the content but no totals or numbers', () async {
      await service.finalize(request(draft(jobId: 'job-9', matched: 'cust-1')));
      final sent = remote.createCalls.single;
      expect(
          sent.keys,
          containsAll([
            'id',
            'doc_type',
            'title',
            'job_id',
            'customer_id',
            'date_issued',
            'date_due',
            'delivery_period',
            'recipient_snapshot',
            'line_items'
          ]));
      expect(sent.keys, isNot(contains('doc_number')));
      expect(sent.keys, isNot(contains('total_gross_cents')));
      expect(sent.keys, isNot(contains('vat_rate')));
      expect(sent['job_id'], 'job-9');
      expect(sent['customer_id'], 'cust-1');
      expect((sent['recipient_snapshot'] as Map)['address'], 'Elbchaussee 118, 22763 Hamburg');
    });

    test('a quote gets an ANG number, no delivery period, and a validity date', () async {
      final result = await service.finalize(FinalizeRequest(
        documentId: 'q1',
        draft: draft(type: 'quote'),
        business: business,
        issueDate: DateTime(2026, 10, 1),
        paymentDays: 30,
        deliveryPeriod: 'sollte ignoriert werden',
      ));
      expect(result.document.docNumber, 'ANG-2026-0001');
      expect(result.document.dateDue, '2026-10-31'); // 30 calendar days, although the clocks change on 25 Oct
      expect(remote.createCalls.single.containsKey('delivery_period'), isFalse);
    });

    test('numbers continue without gaps across documents', () async {
      final a = await service.finalize(request(draft(), id: 'a'));
      final b = await service.finalize(request(draft(), id: 'b'));
      expect([a.document.docNumber, b.document.docNumber], ['RE-2026-0001', 'RE-2026-0002']);
    });

    test('retrying with the same document id returns the same number (no second number issued)', () async {
      final first = await service.finalize(request(draft(), id: 'same'));
      final again = await service.finalize(request(draft(), id: 'same'));
      expect(again.document.docNumber, first.document.docNumber);
      final next = await service.finalize(request(draft(), id: 'other'));
      expect(next.document.docNumber, 'RE-2026-0002');
    });

    test('a blocked draft never reaches the server', () async {
      await expectLater(service.finalize(request(draft(items: []))), throwsA(isA<FinalizeBlocked>()));
      expect(remote.createCalls, isEmpty);
    });
  });

  group('when things go wrong', () {
    test('offline: nothing is stored and the customer list is untouched; the retry sends the same notes', () async {
      remote.createError = const DocumentOfflineException();

      await expectLater(
          service.finalize(request(draft(), noteIds: ['n1', 'n2'])), throwsA(isA<DocumentOfflineException>()));
      expect(await db.select(db.issuedDocuments).get(), isEmpty);
      expect(await db.select(db.customers).get(), isEmpty); // no customer created for a document that does not exist

      remote.createError = null;
      final ok = await service.finalize(request(draft(), noteIds: ['n1', 'n2']));
      expect(ok.document.docNumber, 'RE-2026-0001');
      expect(remote.createCalls.last['capture_log_ids'], ['n1', 'n2']);
    });

    test('rejections and expired logins are passed on with their message', () async {
      remote.createError =
          const DocumentRejectedException('Bitte zuerst die Anschrift deines Betriebs unter „Betrieb“ eintragen.');
      await expectLater(service.finalize(request(draft())),
          throwsA(isA<DocumentRejectedException>().having((e) => e.message, 'message', contains('Anschrift'))));
      remote.createError = const DocumentAuthException();
      await expectLater(service.finalize(request(draft())), throwsA(isA<DocumentAuthException>()));
    });

    test('a failed PDF upload does not undo the document; the PDF is still returned', () async {
      remote.uploadError = const DocumentOfflineException();
      final result = await service.finalize(request(draft()));
      expect(result.pdfUploaded, isFalse);
      expect(result.pdf, isNotEmpty);
      expect(result.document.pdfPath, isNull);
      expect(await db.documentById('doc-1'), isNotNull);
    });
  });

  group('housekeeping after issuing', () {
    test('a new customer is added with the address split into street, ZIP and city', () async {
      await service.finalize(request(draft()));
      final c = (await db.select(db.customers).get()).single;
      expect((c.name, c.street, c.zip, c.city), ('Thomas Müller', 'Elbchaussee 118', '22763', 'Hamburg'));
      expect(changes, greaterThan(0)); // sync was nudged
    });

    test('no customer is added when the user opted out or the customer already exists', () async {
      await service.finalize(request(draft(), id: 'a', createCustomer: false));
      await service.finalize(request(draft(matched: 'known'), id: 'b'));
      expect(await db.select(db.customers).get(), isEmpty);
    });

    test('the job moves forward: invoice -> invoiced, quote -> quote sent', () async {
      await data.saveJob(id: 'j1', title: 'Auftrag A');
      await data.saveJob(id: 'j2', title: 'Auftrag B');
      await service.finalize(request(draft(jobId: 'j1'), id: 'a'));
      await service.finalize(request(draft(jobId: 'j2', type: 'quote'), id: 'b'));
      expect((await db.jobById('j1'))!.status, JobStatus.invoiced);
      expect((await db.jobById('j2'))!.status, JobStatus.quoteSent);
    });

    test('the job never moves backwards', () async {
      await data.saveJob(id: 'j1', title: 'A', status: JobStatus.completed);
      await data.saveJob(id: 'j2', title: 'B', status: JobStatus.invoiced);
      await service.finalize(request(draft(jobId: 'j1', type: 'quote'), id: 'a'));
      await service.finalize(request(draft(jobId: 'j2', type: 'quote'), id: 'b'));
      expect((await db.jobById('j1'))!.status, JobStatus.completed);
      expect((await db.jobById('j2'))!.status, JobStatus.invoiced);
    });

    test('a job that is not in the local cache yet does not break finalizing', () async {
      final result = await service.finalize(request(draft(jobId: 'not-synced-yet')));
      expect(result.document.docNumber, isNotEmpty);
    });

    test('the job notes that went into the document are sent along, so the server can use them up', () async {
      await service.finalize(request(draft(), noteIds: ['n1', 'n2', 'n3']));
      expect(remote.createCalls.single['capture_log_ids'], ['n1', 'n2', 'n3']);
    });

    test('without notes no note list is sent', () async {
      await service.finalize(request(draft()));
      expect(remote.createCalls.single.containsKey('capture_log_ids'), isFalse);
    });

    test('a customer created while issuing is linked to the job that had none', () async {
      await data.saveJob(id: 'j1', title: 'Auftrag A');
      await service.finalize(request(draft(jobId: 'j1')));
      final customer = (await db.select(db.customers).get()).single;
      expect((await db.jobById('j1'))!.customerId, customer.id);
    });

    test('a job that already has a customer keeps it', () async {
      final existing = await data.saveCustomer(name: 'Schiller');
      await data.saveJob(id: 'j1', title: 'Auftrag A', customerId: existing);
      await service.finalize(request(draft(jobId: 'j1', matched: existing), id: 'x'));
      expect((await db.jobById('j1'))!.customerId, existing);
    });
  });

  group('status changes and the PDF', () {
    test('markStatus updates the server and the local copy', () async {
      await service.finalize(request(draft()));
      await service.markStatus('doc-1', 'sent');
      expect(remote.statusChanges, ['doc-1:sent']);
      expect((await db.documentById('doc-1'))!.status, 'sent');
    });

    test('offline: the local status stays unchanged', () async {
      await service.finalize(request(draft()));
      remote.statusError = const DocumentOfflineException();
      await expectLater(service.markStatus('doc-1', 'paid'), throwsA(isA<DocumentOfflineException>()));
      expect((await db.documentById('doc-1'))!.status, 'issued');
    });

    test('pdfFor returns the stored original, or recreates it when it cannot be downloaded', () async {
      final result = await service.finalize(request(draft()));
      final doc = result.document;
      expect(await service.pdfFor(doc, business), result.pdf); // the original from storage

      remote.downloadError = const DocumentOfflineException();
      final recreated = await service.pdfFor(doc, business);
      expect(String.fromCharCodes(recreated.take(5)), '%PDF-');

      final noPath = (await db.documentById('doc-1'))!;
      await db.updateDocument(noPath.id, const IssuedDocumentsCompanion(pdfPath: Value(null)));
      remote.downloadError = null;
      expect(
          String.fromCharCodes((await service.pdfFor((await db.documentById('doc-1'))!, business)).take(5)), '%PDF-');
    });
  });

  group('syncing documents from the server', () {
    late FakeSyncRemote syncRemote;
    late SyncEngine engine;

    setUp(() {
      syncRemote = FakeSyncRemote();
      engine = SyncEngine(db, syncRemote);
    });

    test('documents from other devices arrive, with their status and amounts', () async {
      syncRemote.seed(SyncEntity.document, remoteDocument('d1', number: 'RE-2026-0001'));
      syncRemote.seed(SyncEntity.document, remoteDocument('d2', number: 'RE-2026-0002', status: 'paid'));

      final result = await engine.run();

      expect(result.ok, isTrue);
      final docs = await db.select(db.issuedDocuments).get();
      expect(docs.map((d) => d.docNumber).toSet(), {'RE-2026-0001', 'RE-2026-0002'});
      expect(docs.firstWhere((d) => d.id == 'd2').status, 'paid');
      expect(docs.first.totalGrossCents, 20944);
      expect(docs.first.vatRate, 19.0);
    });

    test('a status change on the server shows up on the next sync', () async {
      syncRemote.seed(SyncEntity.document, remoteDocument('d1'));
      await engine.run();
      syncRemote.seed(SyncEntity.document, remoteDocument('d1', status: 'paid'));
      await engine.run();
      expect((await db.documentById('d1'))!.status, 'paid');
    });

    test('documents are never pushed (there is no outbox entry for them)', () async {
      await service.finalize(request(draft()));
      // (the new customer is queued, the document itself is not)
      expect((await db.pendingOutbox()).where((o) => o.entity == 'document'), isEmpty);
    });

    test('a document issued while a sync was running is not pruned (the server id list predates it)', () async {
      // Sync: the server has d1.
      syncRemote.seed(SyncEntity.document, remoteDocument('d1'));
      await engine.run();
      // This phone then issues d2: it exists on the server and in the local cache ...
      await service.finalize(request(draft(), id: 'd2'));
      expect(await db.documentById('d2'), isNotNull);
      // ... while a sync that fetched the server ids BEFORE d2 existed reaches its prune step.
      await db.pruneDocuments({'d1'}, knownUpTo: DateTime.utc(2026, 1, 1, 0, 0, 5));
      expect(await db.documentById('d2'), isNotNull);
    });

    test('nothing is pruned before a first pull has set a timestamp', () async {
      await service.finalize(request(draft(), id: 'd3'));
      await db.pruneDocuments(<String>{}, knownUpTo: null);
      expect(await db.documentById('d3'), isNotNull);
    });

    test('a document that disappeared on the server is removed locally', () async {
      syncRemote.seed(SyncEntity.document, remoteDocument('d1'));
      await engine.run();
      syncRemote.tables[SyncEntity.document]!.clear();
      await engine.run();
      expect(await db.documentById('d1'), isNull);
    });
  });
}

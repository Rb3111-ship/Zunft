import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/documents/data/documents_remote.dart';
import 'package:zunft_app/features/documents/presentation/pdf_preview_screen.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_job_notes.dart';
import 'helpers/job_app.dart';
import 'helpers/fake_documents.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/test_app.dart';

FakeAuthRepository signedIn({Business? business}) => FakeAuthRepository(
      userId: 'u1',
      profile: const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: 'owner'),
      business: business ?? FakeAuthRepository.completeBusiness(),
    );

Business withVat(double rate) =>
    Business.fromJson({...FakeAuthRepository.completeBusiness().toUpdateJson(), 'id': 'b1', 'default_vat_rate': rate});

/// Opens the job "Steckdose Keller" and from there the review of all its notes.
Future<void> openReview(WidgetTester tester) async {
  await openReviewFromJob(tester);
  expect(find.text('Rechnung prüfen'), findsOneWidget);
}

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

String previewTitle(WidgetTester tester) =>
    tester.widget<PdfPreviewScreen>(find.byType(PdfPreviewScreen)).documentTitle;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('finalizing', () {
    testApp('review -> Fertigstellen -> numbered PDF; the notes are used up and the document appears under Belege',
        (tester) async {
      final app = await pumpJobApp(tester);
      await openReview(tester);

      await scrollTo(tester, find.text('Rechnung fertigstellen'));
      await tester.tap(find.text('Rechnung fertigstellen'));
      await tester.pumpAndSettle();
      expect(find.text('Rechnung fertigstellen?'), findsOneWidget);
      await tester.tap(find.text('Fertigstellen'));
      await tester.pumpAndSettle();

      // The PDF preview opens with the issued number.
      expect(find.byType(PdfPreviewScreen), findsOneWidget);
      expect(previewTitle(tester), matches(RegExp(r'^RE-\d{4}-0001 - Thomas Müller$')));
      expect(app.documents.createCalls, hasLength(1));
      expect(app.documents.storedPdfs, hasLength(1));

      await tester.pageBack();
      await tester.pumpAndSettle();

      // Back on the job: its notes are used up, nothing is left to bill twice.
      expect(find.textContaining('Noch keine Notizen'), findsOneWidget);
      expect(find.text('Alle Notizen prüfen und abrechnen'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // The notes went into this document and are used up on the server...
      expect(app.documents.createCalls.single['capture_log_ids'], ['n1']);
      expect(await app.jobNotes.fetchOpenNotes('j1'), isEmpty);
      // ...the job's own customer is used (no second "Müller" is created)...
      final customers = await tester.runAsync(() => app.db.select(app.db.customers).get());
      expect(customers!.single.name, 'Müller');
      expect(app.documents.createCalls.single['customer_id'], 'c1');
      // ...and the document is listed under Belege.
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();
      expect(find.textContaining(RegExp(r'RE-\d{4}-0001')), findsWidgets);
      expect(find.text('Erstellt'), findsOneWidget);
    });

    testApp('the dialog asks for the leistungszeitraum and payment term, and sends them', (tester) async {
      final app = await pumpJobApp(tester);
      await openReview(tester);
      await scrollTo(tester, find.text('Rechnung fertigstellen'));
      await tester.tap(find.text('Rechnung fertigstellen'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Leistungszeitraum / Leistungsdatum'), 'September 2026');
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 Tagen').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fertigstellen'));
      await tester.pumpAndSettle();

      final sent = app.documents.createCalls.single;
      expect(sent['delivery_period'], 'September 2026');
      final issued = DateTime.parse(sent['date_issued'] as String);
      final due = DateTime.parse(sent['date_due'] as String);
      expect(
          DateTime(due.year, due.month, due.day).difference(DateTime(issued.year, issued.month, issued.day)).inHours ~/
              24,
          closeTo(30, 1));
    });

    testApp('cancelling the dialog issues nothing', (tester) async {
      final app = await pumpJobApp(tester);
      await openReview(tester);
      await scrollTo(tester, find.text('Rechnung fertigstellen'));
      await tester.tap(find.text('Rechnung fertigstellen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(app.documents.createCalls, isEmpty);
      expect(find.text('Rechnung prüfen'), findsOneWidget);
    });

    testApp('items still marked "Preis prüfen" must be confirmed before Fertigstellen is possible', (tester) async {
      final notes = FakeJobNotesRemote()..add('j1', FakeJobNotesRemote.note(id: 'n1', checkFirstItem: true));
      final app = await pumpJobApp(tester, notes: notes);
      await openReview(tester);
      expect(find.text('Preis prüfen'), findsOneWidget);

      await scrollTo(tester, find.text('Rechnung fertigstellen'));
      await tester.tap(find.text('Rechnung fertigstellen'));
      await tester.pumpAndSettle();

      final confirm = find.widgetWithText(FilledButton, 'Fertigstellen');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull); // disabled
      await tester.tap(find.textContaining('kontrolliert'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(app.documents.createCalls, hasLength(1));
    });

    testApp('an incomplete business is explained, with a way to fix it', (tester) async {
      final app = await pumpJobApp(tester, business: FakeAuthRepository.sampleBusiness());
      await openReview(tester);
      await scrollTo(tester, find.text('Rechnung fertigstellen'));
      await tester.tap(find.text('Rechnung fertigstellen'));
      await tester.pumpAndSettle();

      expect(find.text('Noch nicht möglich'), findsOneWidget);
      expect(find.textContaining('Anschrift'), findsOneWidget);
      expect(app.documents.createCalls, isEmpty); // never reached the server

      await tester.tap(find.text('Betriebsdaten öffnen'));
      await tester.pumpAndSettle();
      expect(find.text('Betriebsdaten'), findsOneWidget); // the settings screen
    });

    testApp('offline: explained, nothing lost; the retry reuses the same id and succeeds once', (tester) async {
      final documents = FakeDocumentsRemote()..createError = const DocumentOfflineException();
      final app = await pumpJobApp(tester, documents: documents);
      await openReview(tester);
      await scrollTo(tester, find.text('Rechnung fertigstellen'));

      await tester.tap(find.text('Rechnung fertigstellen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fertigstellen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Keine Verbindung'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Rechnung prüfen'), findsOneWidget); // still on the review screen, edits intact

      documents.createError = null;
      await tester.tap(find.text('Rechnung fertigstellen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fertigstellen'));
      await tester.pumpAndSettle();

      expect(find.byType(PdfPreviewScreen), findsOneWidget);
      final ids = app.documents.createCalls.map((c) => c['id']).toSet();
      expect(ids, hasLength(1), reason: 'the retry must carry the same document id');
      expect(app.documents.documents, hasLength(1));
    });

    testApp('a server rejection is shown in plain German', (tester) async {
      final documents = FakeDocumentsRemote()
        ..createError = const DocumentRejectedException(
            'Bei Rechnungen über 250 € muss die Anschrift des Kunden angegeben werden.');
      await pumpJobApp(tester, documents: documents);
      await openReview(tester);
      await scrollTo(tester, find.text('Rechnung fertigstellen'));
      await tester.tap(find.text('Rechnung fertigstellen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fertigstellen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('über 250 €'), findsOneWidget);
    });

    testApp('a quote can be made too, with its own number series', (tester) async {
      final app = await pumpJobApp(tester);
      await openReview(tester);
      await scrollTo(tester, find.text('In Angebot umwandeln'));
      await tester.tap(find.text('In Angebot umwandeln'));
      await tester.pumpAndSettle();
      expect(find.text('Angebot prüfen'), findsOneWidget);

      await scrollTo(tester, find.text('Angebot fertigstellen'));
      await tester.tap(find.text('Angebot fertigstellen'));
      await tester.pumpAndSettle();
      expect(find.text('Leistungszeitraum / Leistungsdatum'), findsNothing); // invoices only
      await tester.tap(find.text('Fertigstellen'));
      await tester.pumpAndSettle();

      expect(previewTitle(tester), matches(RegExp(r'^ANG-\d{4}-0001 ')));
      expect(app.documents.createCalls.single['doc_type'], 'quote');
    });
  });

  group('review screen', () {
    testApp('the VAT rate comes from the business settings', (tester) async {
      await pumpJobApp(tester, business: withVat(7));
      await openReview(tester);
      await scrollTo(tester, find.textContaining('MwSt.'));
      expect(find.text('zzgl. 7 % MwSt.:'), findsOneWidget);
      expect(find.textContaining('19 %'), findsNothing);
    });

    testApp('a small business (0 %) is labelled § 19 UStG', (tester) async {
      await pumpJobApp(tester, business: withVat(0));
      await openReview(tester);
      await scrollTo(tester, find.textContaining('Umsatzsteuer'));
      expect(find.text('Umsatzsteuer (§ 19 UStG):'), findsOneWidget);
    });

    testApp('editing a position accepts a German decimal comma and recalculates', (tester) async {
      await pumpJobApp(tester);
      await openReview(tester);

      await tester.tap(find.byTooltip('Position bearbeiten').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Menge'), '1,5');
      await tester.enterText(find.widgetWithText(TextField, 'Einzelpreis netto (€)'), '70,50');
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();

      expect(find.text('1,5 Std à 70,50 €'), findsOneWidget);
      expect(find.text('105,75 €'), findsWidgets); // 1,5 x 70,50
    });

    testApp('the type of a position can be corrected (labor <-> material)', (tester) async {
      await pumpJobApp(tester);
      await openReview(tester);
      expect(find.text('Material'), findsOneWidget);

      await tester.tap(find.byTooltip('Position bearbeiten').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Material').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();

      expect(find.text('Material'), findsNWidgets(2));
      expect(find.text('Arbeitslohn (§ 35a)'), findsNothing);
    });

    testApp('invalid input in the position dialog is explained and nothing changes', (tester) async {
      await pumpJobApp(tester);
      await openReview(tester);
      await tester.tap(find.byTooltip('Position bearbeiten').first);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Bezeichnung'), '  ');
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(find.text('Bitte eine Bezeichnung eingeben.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Bezeichnung'), 'Montage');
      await tester.enterText(find.widgetWithText(TextField, 'Menge'), '0');
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('gültige Menge'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Menge'), '2');
      await tester.enterText(find.widgetWithText(TextField, 'Einzelpreis netto (€)'), 'abc');
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('gültigen Preis'), findsOneWidget);
    });

    testApp('a new position is added through the dialog, and a position can be deleted', (tester) async {
      await pumpJobApp(tester);
      await openReview(tester);

      await tester.tap(find.text('Hinzufügen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Bezeichnung'), 'Kabelkanal');
      await tester.enterText(find.widgetWithText(TextField, 'Einzelpreis netto (€)'), '12,90');
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(find.text('Kabelkanal'), findsOneWidget);

      await tester.tap(find.byTooltip('Position löschen').last);
      await tester.pumpAndSettle();
      expect(find.text('Kabelkanal'), findsNothing);
    });

    testApp('the customer name and address can be corrected and are used for the document', (tester) async {
      final app = await pumpJobApp(tester);
      await openReview(tester);

      await tester.tap(find.byTooltip('Kunden anpassen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name des Kunden'), 'Müller GmbH');
      await tester.enterText(find.widgetWithText(TextField, 'Anschrift'), 'Hafenstraße 5, 20359 Hamburg');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Müller GmbH'), findsOneWidget);

      await scrollTo(tester, find.text('Rechnung fertigstellen'));
      await tester.tap(find.text('Rechnung fertigstellen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fertigstellen'));
      await tester.pumpAndSettle();

      final recipient = app.documents.createCalls.single['recipient_snapshot'] as Map;
      expect(recipient['name'], 'Müller GmbH');
      expect(recipient['address'], 'Hafenstraße 5, 20359 Hamburg');
    });

    testApp('the draft preview is clearly a draft and cannot be sent', (tester) async {
      await pumpJobApp(tester);
      await openReview(tester);
      await scrollTo(tester, find.text('Vorschau als PDF (Entwurf)'));
      await tester.tap(find.text('Vorschau als PDF (Entwurf)'));
      await tester.pumpAndSettle();

      expect(previewTitle(tester), 'Vorschau - Thomas Müller');
      expect(find.byIcon(Icons.share), findsNothing);
      expect(find.byIcon(Icons.print), findsNothing);
    });
  });

  group('Belege tab', () {
    testApp('shows an empty state, then documents from the server with a summary of open invoices', (tester) async {
      await pumpApp(tester, signedIn());
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Noch keine Belege'), findsOneWidget);
    });

    testApp('lists synced documents and totals the open invoices', (tester) async {
      final sync = FakeSyncRemote()
        ..seed(SyncEntity.document, remoteDocument('d1', number: 'RE-2026-0001', gross: 20944))
        ..seed(SyncEntity.document,
            remoteDocument('d2', number: 'RE-2026-0002', status: 'paid', recipient: 'Sabine Schmidt', gross: 11900))
        ..seed(SyncEntity.document,
            remoteDocument('d3', number: 'ANG-2026-0001', type: 'quote', recipient: 'Café Alsterperle', gross: 5000));
      await pumpApp(tester, signedIn(), remote: sync);
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();

      expect(find.text('RE-2026-0001'), findsOneWidget);
      expect(find.text('Sabine Schmidt'), findsOneWidget);
      expect(find.text('Bezahlt'), findsOneWidget);
      // open invoices: only d1 (d2 is paid, d3 is a quote)
      expect(find.text('1'), findsOneWidget);
      expect(find.text('209,44 €'), findsNWidgets(2)); // the list entry and the "open amount" summary
    });

    testApp('detail: shows the content, and "bezahlt" is saved on the server and here', (tester) async {
      final sync = FakeSyncRemote()..seed(SyncEntity.document, remoteDocument('d1'));
      final app = await pumpApp(tester, signedIn(), remote: sync);
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RE-2026-0001'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Steckdose montiert'), findsOneWidget);
      expect(find.text('Elbchaussee 118, 22763 Hamburg'), findsOneWidget);
      expect(find.textContaining('festgeschrieben'), findsOneWidget);

      await tester.tap(find.text('Als bezahlt markieren'));
      await tester.pumpAndSettle();

      expect(app.documents.statusChanges, ['d1:paid']);
      expect(find.text('Bezahlt'), findsOneWidget);
      expect(find.text('Als bezahlt markieren'), findsNothing);
    });

    testApp('offline: the status cannot change and the user is told', (tester) async {
      final sync = FakeSyncRemote()..seed(SyncEntity.document, remoteDocument('d1'));
      final documents = FakeDocumentsRemote()..statusError = const DocumentOfflineException();
      await pumpApp(tester, signedIn(), remote: sync, documents: documents);
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RE-2026-0001'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Als versendet markieren'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Keine Verbindung'), findsOneWidget);
      expect(find.text('Erstellt'), findsOneWidget); // unchanged
    });

    testApp('detail: the PDF opens (original from storage, or recreated)', (tester) async {
      final sync = FakeSyncRemote()..seed(SyncEntity.document, remoteDocument('d1'));
      await pumpApp(tester, signedIn(), remote: sync);
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RE-2026-0001'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('PDF ansehen und senden'));
      await tester.pumpAndSettle();

      expect(find.byType(PdfPreviewScreen), findsOneWidget);
      expect(previewTitle(tester), 'RE-2026-0001 - Thomas Müller');
      expect(find.byIcon(Icons.share), findsOneWidget); // an issued document can be sent
    });

    testApp('newest first, and the search finds an older entry by number, customer, status or amount', (tester) async {
      final sync = FakeSyncRemote()
        ..seed(SyncEntity.document,
            remoteDocument('d1', number: 'RE-2026-0001', recipient: 'Jürgen Fischer', date: '2026-09-01'))
        ..seed(SyncEntity.document,
            remoteDocument('d2', number: 'RE-2026-0002', recipient: 'Sabine Köhler', date: '2026-10-05', gross: 11900))
        ..seed(SyncEntity.document,
            remoteDocument('d3', number: 'RE-2026-0003', recipient: 'Aylin Demir', date: '2026-10-03', status: 'paid'));
      await pumpApp(tester, signedIn(), remote: sync);
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();

      double y(String number) => tester.getTopLeft(find.text(number)).dy;
      expect(y('RE-2026-0002') < y('RE-2026-0003'), isTrue); // 5 Oct above 3 Oct
      expect(y('RE-2026-0003') < y('RE-2026-0001'), isTrue); // ...above 1 Sep

      Future<void> search(String text) async {
        await tester.enterText(find.byType(TextField), text);
        await tester.pumpAndSettle();
      }

      await search('fischer');
      expect(find.text('RE-2026-0001'), findsOneWidget);
      expect(find.text('RE-2026-0002'), findsNothing);

      await search('0003');
      expect(find.text('RE-2026-0003'), findsOneWidget);
      expect(find.text('RE-2026-0001'), findsNothing);

      await search('bezahlt demir');
      expect(find.text('RE-2026-0003'), findsOneWidget);

      await search('119,00');
      expect(find.text('RE-2026-0002'), findsOneWidget);
      expect(find.text('RE-2026-0003'), findsNothing);

      await search('gibtesnicht');
      expect(find.text('Nichts gefunden.'), findsOneWidget);

      await tester.tap(find.byTooltip('Suche löschen'));
      await tester.pumpAndSettle();
      expect(find.text('RE-2026-0001'), findsOneWidget);
      expect(find.text('RE-2026-0003'), findsOneWidget);
    });

    testApp('sending a document hands the e-mail address of the customer, subject and text to the mail app',
        (tester) async {
      final sync = FakeSyncRemote()
        ..seed(SyncEntity.customer, remoteCustomer('c1', name: 'Müller', email: 'mueller@example.de'))
        ..seed(SyncEntity.document, remoteDocument('d1', customerId: 'c1'));
      await pumpApp(tester, signedIn(), remote: sync);
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RE-2026-0001'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PDF ansehen und senden'));
      await tester.pumpAndSettle();

      final screen = tester.widget<PdfPreviewScreen>(find.byType(PdfPreviewScreen));
      expect(screen.customerEmail, 'mueller@example.de');
      expect(screen.shareSubject, startsWith('Rechnung RE-2026-0001 von '));
      expect(screen.shareBody, contains('RE-2026-0001'));
    });

    testApp('quotes cannot be marked as paid', (tester) async {
      final sync = FakeSyncRemote()
        ..seed(SyncEntity.document, remoteDocument('q1', number: 'ANG-2026-0001', type: 'quote'));
      await pumpApp(tester, signedIn(), remote: sync);
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ANG-2026-0001'));
      await tester.pumpAndSettle();
      expect(find.text('Als bezahlt markieren'), findsNothing);
      expect(find.text('Als versendet markieren'), findsOneWidget);
    });
  });
}

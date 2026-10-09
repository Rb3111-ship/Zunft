import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/features/jobs/data/job_notes_remote.dart';
import 'package:zunft_app/features/jobs/domain/job_notes.dart';
import 'package:zunft_app/features/jobs/presentation/note_replay.dart' show highlightNumbers;

import 'helpers/fake_job_notes.dart';
import 'helpers/job_app.dart';
import 'helpers/test_app.dart';

Job aJob({String? customerId}) => Job(
      id: 'j1',
      businessId: 'b1',
      customerId: customerId,
      title: 'Schiller Bad',
      status: 'draft',
      updatedAt: DateTime(2026, 10, 1),
    );

Customer aCustomer({String? street, String? zip, String? city}) => Customer(
      id: 'c1',
      businessId: 'b1',
      name: 'Schiller',
      firstName: 'Hans',
      street: street,
      zip: zip,
      city: city,
      updatedAt: DateTime(2026, 10, 1),
    );

void main() {
  group('material markup on receipts', () {
    final voice = FakeJobNotesRemote.note(id: 'v1');
    final receipt = FakeJobNotesRemote.note(id: 'r1', imagePath: 'b1/u1/r1.jpg', items: const [
      (type: 'material', text: 'Kabel', qty: 50, unit: 'm', cents: 100),
      (type: 'material', text: 'Dose', qty: 6, unit: 'Stk', cents: 122),
    ]);

    test('only the positions that come from a receipt get the markup', () {
      final draft = buildJobDraft(job: aJob(), notes: [voice, receipt], materialMarkupPercent: 10);
      final prices = {for (final i in draft.lineItems) i.description: i.unitPriceNetCents};
      expect(prices['Steckdose montiert'], 6800); // labor, spoken
      expect(prices['Doppelsteckdose'], 4000); // material, spoken: not from a receipt
      expect(prices['Kabel'], 110);
      expect(prices['Dose'], 134); // 122 * 1.1 = 134.2
      expect(draft.warnings, contains('Material aus Belegen ist mit 10 % Aufschlag berechnet.'));
    });

    test('0 % changes nothing and adds no warning; the stored note is untouched', () {
      final draft = buildJobDraft(job: aJob(), notes: [receipt]);
      expect(draft.lineItems.first.unitPriceNetCents, 100);
      expect(draft.warnings, isEmpty);
      buildJobDraft(job: aJob(), notes: [receipt], materialMarkupPercent: 25);
      expect(receipt.draft.lineItems.first.unitPriceNetCents, 100);
    });

    test('a fractional percentage is shown with a comma', () {
      final draft = buildJobDraft(job: aJob(), notes: [receipt], materialMarkupPercent: 12.5);
      expect(draft.warnings.single, contains('12,5 %'));
    });
  });

  group('buildJobDraft: all notes of a job become ONE draft', () {
    test('a receipt row carries its photo path; voice and typed notes do not', () {
      final row = {
        'id': 'n1',
        'created_at': '2026-10-07T12:00:00Z',
        'raw_transcript': 'Beleg von Baumarkt',
        'photo_storage_paths': ['b1/u1/n1.jpg'],
        'ai_parsed_json': <String, dynamic>{},
      };
      expect(JobNote.fromRow(row).imagePath, 'b1/u1/n1.jpg');
      expect(JobNote.fromRow(row).isReceipt, isTrue);
      expect(JobNote.fromRow({...row, 'photo_storage_paths': <String>[]}).isReceipt, isFalse);
      expect(JobNote.fromRow({...row, 'photo_storage_paths': null}).isReceipt, isFalse);
    });

    test('positions of every note are combined, in order, across days and workers', () {
      final draft = buildJobDraft(job: aJob(customerId: 'c1'), customer: aCustomer(), notes: [
        FakeJobNotesRemote.note(id: 'mo', author: 'Thorsten', items: const [
          (type: 'labor', text: 'Montag Arbeit', qty: 4, unit: 'Std', cents: 6800),
        ]),
        FakeJobNotesRemote.note(id: 'di', author: 'Gesa', items: const [
          (type: 'labor', text: 'Dienstag Arbeit', qty: 3, unit: 'Std', cents: 6800),
          (type: 'material', text: 'Fliesen', qty: 12, unit: 'Stk', cents: 900),
        ]),
      ]);

      expect(draft.lineItems.map((i) => i.description), ['Montag Arbeit', 'Dienstag Arbeit', 'Fliesen']);
      expect(draft.lineItems.map((i) => i.id).toSet(), hasLength(3));
      expect(draft.financialSummary.subtotalLaborCents, 7 * 6800);
      expect(draft.financialSummary.subtotalMaterialCents, 12 * 900);
      expect(draft.title, 'Schiller Bad');
      expect(draft.jobId, 'j1');
      // who said what stays visible
      expect(draft.rawTranscript, contains('Thorsten'));
      expect(draft.rawTranscript, contains('Gesa'));
    });

    test('the customer comes from the job, never from what the AI heard', () {
      final draft = buildJobDraft(
        job: aJob(customerId: 'c1'),
        customer: aCustomer(street: 'Hafenstraße 5', zip: '20359', city: 'Hamburg'),
        notes: [FakeJobNotesRemote.note(id: 'n', hintName: 'Frau Müller')], // the speaker said another name
      );
      expect(draft.customer.matchedCustomerId, 'c1');
      expect(draft.customer.extractedName, 'Hans Schiller');
      expect(draft.customer.extractedAddress, 'Hafenstraße 5, 20359 Hamburg');
      expect(draft.customerHintName, isNull); // no suggestion needed: the job has a customer
    });

    test('a job without a customer starts empty and only OFFERS the spoken name', () {
      final draft = buildJobDraft(
          job: aJob(), customer: null, notes: [FakeJobNotesRemote.note(id: 'n', hintName: 'Frau Müller')]);
      expect(draft.customer.matchedCustomerId, isNull);
      expect(draft.customer.extractedName, isEmpty);
      expect(draft.customerHintName, 'Frau Müller');
    });

    test('a customer without address data gives no address', () {
      final draft =
          buildJobDraft(job: aJob(customerId: 'c1'), customer: aCustomer(), notes: [FakeJobNotesRemote.note(id: 'n')]);
      expect(draft.customer.extractedAddress, isNull);
    });

    test('one invoice note makes an invoice; only all-quote notes make a quote', () {
      typeOf(List<String> types) => buildJobDraft(
            job: aJob(),
            customer: null,
            notes: [for (final (i, t) in types.indexed) FakeJobNotesRemote.note(id: 'n$i', documentType: t)],
          ).documentType;
      expect(typeOf(['quote', 'quote']), 'quote');
      expect(typeOf(['quote', 'invoice']), 'invoice');
      expect(typeOf(['invoice']), 'invoice');
    });

    test('the same warning from two notes is shown once', () {
      final draft = buildJobDraft(job: aJob(), customer: null, notes: [
        FakeJobNotesRemote.note(id: 'a', warnings: ['Materialpreis geschätzt']),
        FakeJobNotesRemote.note(id: 'b', warnings: ['Materialpreis geschätzt', 'Anschrift fehlt']),
      ]);
      expect(draft.warnings, ['Materialpreis geschätzt', 'Anschrift fehlt']);
    });
  });

  group('JobNote.fromRow (what the server returns)', () {
    test('reads author, time, transcript and the AI result', () {
      final n = JobNote.fromRow({
        'id': 'n1',
        'created_at': '2026-10-05T07:30:00Z',
        'created_by': 'u2',
        'raw_transcript': 'Steckdose gesetzt',
        'profiles': {'full_name': 'Gesa Geselle'},
        'ai_parsed_json': {
          'title': 'x',
          'document_type': 'invoice',
          'customer_hint': {'name': 'Müller', 'address': null},
          'line_items': [
            {'type': 'labor', 'description': 'Arbeit', 'quantity': 1.5, 'unit': 'Std', 'unit_price_net_cents': 6800},
          ],
          'warnings': ['a'],
          'financial_summary': {'total_net_cents': 10200},
          'model': 'gemini',
        },
      });
      expect(n.author, 'Gesa Geselle');
      expect(n.transcript, 'Steckdose gesetzt');
      expect(n.draft.lineItems.single.quantity, 1.5);
      expect(n.draft.customerHintName, 'Müller');
    });

    test('a missing author or missing AI data does not crash', () {
      final n = JobNote.fromRow({
        'id': 'n',
        'created_at': '2026-10-05T07:30:00Z',
        'created_by': null,
        'raw_transcript': null,
        'profiles': null,
        'ai_parsed_json': null
      });
      expect(n.author, 'Mitarbeiter');
      expect(n.transcript, '');
      expect(n.draft.lineItems, isEmpty);
    });
  });

  group('job screen', () {
    testApp('shows every note with its author, the positions and a total', (tester) async {
      final notes = FakeJobNotesRemote()
        ..add('j1', FakeJobNotesRemote.note(id: 'a', author: 'Thorsten', at: DateTime(2026, 10, 5, 9, 30)))
        ..add(
            'j1',
            FakeJobNotesRemote.note(id: 'b', author: 'Gesa', at: DateTime(2026, 10, 6, 14, 5), items: const [
              (type: 'labor', text: 'Fliesen verlegt', qty: 3, unit: 'Std', cents: 6800),
            ]));
      await pumpJobApp(tester, notes: notes);
      await openJob(tester);

      expect(find.text('Thorsten - 05.10.2026 09:30'), findsOneWidget);
      expect(find.text('Gesa - 06.10.2026 14:05'), findsOneWidget);
      expect(find.textContaining('Fliesen verlegt'), findsOneWidget);
      // 2 x 68 + 40 + 3 x 68 = 380 EUR net, from 3 positions in 2 notes
      expect(find.textContaining('3 Positionen aus 2 Notizen'), findsOneWidget);
      expect(find.textContaining(RegExp(r'380,00\s€')), findsWidgets); // the euro format uses a non-breaking space
      expect(find.text('Thomas Müller'), findsOneWidget); // the job's customer
    });

    testApp('an empty job explains what to do', (tester) async {
      await pumpJobApp(tester, withNote: false);
      await openJob(tester);
      expect(find.textContaining('Noch keine Notizen'), findsOneWidget);
      expect(find.text('Alle Notizen prüfen und abrechnen'), findsNothing);
    });

    testApp('"Was wurde gesagt?" shows the transcript, so the AI can be checked', (tester) async {
      await pumpJobApp(tester);
      await openJob(tester);
      expect(find.textContaining('"Steckdose im Keller gesetzt"'), findsNothing);
      await tester.tap(find.text('Was wurde gesagt?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"Steckdose im Keller gesetzt"'), findsOneWidget);
    });

    testApp('a voice note can be played again from the job; a typed note has no play button', (tester) async {
      final notes = FakeJobNotesRemote()
        ..add('j1', FakeJobNotesRemote.note(id: 'n1', audioPath: 'b1/u1/n1.m4a'))
        ..add('j1', FakeJobNotesRemote.note(id: 'n2', transcript: 'getippt'));
      final app = await pumpJobApp(tester, notes: notes);
      await openJob(tester);
      for (final t in tester.widgetList<TextButton>(find.widgetWithText(TextButton, 'Was wurde gesagt?'))) {
        t.onPressed!();
      }
      await tester.pumpAndSettle();

      expect(find.text('Aufnahme anhören'), findsOneWidget); // only the voice note
      await tester.tap(find.text('Aufnahme anhören'));
      await tester.pumpAndSettle();
      expect(app.player.played.single, 'https://audio.test/b1/u1/n1.m4a');
      expect(find.text('Anhalten'), findsOneWidget);

      app.player.finish();
      await tester.pumpAndSettle();
      expect(find.text('Aufnahme anhören'), findsOneWidget);
    });

    testApp('if the recording cannot be loaded the user sees why', (tester) async {
      final notes = FakeJobNotesRemote()..add('j1', FakeJobNotesRemote.note(id: 'n1', audioPath: 'b1/u1/n1.m4a'));
      final app = await pumpJobApp(tester, notes: notes);
      await openJob(tester);
      await tester.tap(find.text('Was wurde gesagt?'));
      await tester.pumpAndSettle();
      notes.error = const JobNotesException('Die Aufnahme konnte nicht geladen werden. Bitte Internetverbindung prüfen.');

      await tester.tap(find.text('Aufnahme anhören'));
      await tester.pumpAndSettle();

      expect(find.textContaining('konnte nicht geladen werden'), findsOneWidget);
      expect(app.player.played, isEmpty);
    });

    testApp('removing a note asks first, then hides it from the job', (tester) async {
      final app = await pumpJobApp(tester);
      await openJob(tester);

      await tester.tap(find.byTooltip('Notiz entfernen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Steckdose montiert'), findsOneWidget); // cancelled: still there

      await tester.tap(find.byTooltip('Notiz entfernen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();

      expect(app.jobNotes.discarded, ['n1']);
      expect(find.textContaining('Steckdose montiert'), findsNothing);
      expect(find.textContaining('Noch keine Notizen'), findsOneWidget);
    });

    testApp('offline: the notes cannot be loaded, the user is told, and can retry', (tester) async {
      final notes = FakeJobNotesRemote()
        ..add('j1', FakeJobNotesRemote.note(id: 'n1'))
        ..error = const JobNotesException('Die Notizen konnten nicht geladen werden. Bitte Internetverbindung prüfen.');
      await pumpJobApp(tester, notes: notes);
      await openJob(tester);

      expect(find.textContaining('konnten nicht geladen werden'), findsOneWidget);
      expect(find.text('Alle Notizen prüfen und abrechnen'), findsNothing); // never bill from an incomplete list

      notes.error = null;
      await tester.tap(find.textContaining('konnten nicht geladen werden'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Steckdose montiert'), findsOneWidget);
    });

    testApp('a note that is still waiting to be processed is flagged as not yet included', (tester) async {
      final app = await pumpJobApp(tester);
      // a note recorded offline, still in this phone's queue
      await tester.runAsync(() => app.db.insertCapture(PendingCapturesCompanion.insert(
            id: 'q1',
            kind: 'text',
            createdAt: DateTime(2026, 10, 5),
            transcript: const Value('Wartet noch'),
            jobId: const Value('j1'),
          )));
      await tester.pumpAndSettle();
      await openJob(tester);

      expect(find.textContaining('wartet noch auf die Verarbeitung'), findsOneWidget);
      expect(find.text('Wartet noch'), findsOneWidget);
    });
  });

  group('billing a whole job', () {
    testApp('notes from two workers become ONE document, and both are used up', (tester) async {
      final notes = FakeJobNotesRemote()
        ..add(
            'j1',
            FakeJobNotesRemote.note(id: 'a', author: 'Thorsten', items: const [
              (type: 'labor', text: 'Montag Arbeit', qty: 4, unit: 'Std', cents: 6800),
            ]))
        ..add(
            'j1',
            FakeJobNotesRemote.note(id: 'b', author: 'Gesa', items: const [
              (type: 'labor', text: 'Dienstag Arbeit', qty: 3, unit: 'Std', cents: 6800),
            ]));
      final app = await pumpJobApp(tester, notes: notes);
      await openReviewFromJob(tester);

      expect(find.text('Rechnung prüfen'), findsOneWidget);
      expect(find.text('Kunde aus dem Auftrag'), findsOneWidget);
      expect(find.text('Thomas Müller'), findsOneWidget);
      expect(find.textContaining('Montag Arbeit'), findsOneWidget);
      expect(find.textContaining('Dienstag Arbeit'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Rechnung fertigstellen'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Rechnung fertigstellen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fertigstellen'));
      await tester.pumpAndSettle();

      final sent = app.documents.createCalls.single;
      expect(sent['capture_log_ids'], ['a', 'b']);
      expect((sent['line_items'] as List).map((i) => (i as Map)['description']), ['Montag Arbeit', 'Dienstag Arbeit']);
      expect(sent['customer_id'], 'c1');
      expect(app.documents.documents, hasLength(1));
      expect(await app.jobNotes.fetchOpenNotes('j1'), isEmpty);
    });

    testApp('notes recorded after the invoice start the next document, without the old positions', (tester) async {
      final app = await pumpJobApp(tester);
      await openReviewFromJob(tester);
      await tester.scrollUntilVisible(find.text('Rechnung fertigstellen'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Rechnung fertigstellen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fertigstellen'));
      await tester.pumpAndSettle();
      await tester.pageBack(); // PDF -> job
      await tester.pumpAndSettle();

      // a later note for the same job
      app.jobNotes.add(
          'j1',
          FakeJobNotesRemote.note(id: 'later', items: const [
            (type: 'labor', text: 'Nachbesserung', qty: 1, unit: 'Std', cents: 6800),
          ]));
      await tester.pageBack(); // job -> list
      await tester.pumpAndSettle();
      await openJob(tester);

      expect(find.textContaining('Nachbesserung'), findsOneWidget);
      expect(find.textContaining('Steckdose montiert'), findsNothing); // already billed
    });

    testApp('a job without a customer: the spoken name is only offered, and a name is required', (tester) async {
      final notes = FakeJobNotesRemote()..add('j1', FakeJobNotesRemote.note(id: 'n1', hintName: 'Frau Neumann'));
      final app = await pumpJobApp(tester, withCustomer: false, notes: notes);
      await openReviewFromJob(tester);

      expect(find.text('Noch kein Kunde'), findsOneWidget);
      expect(find.textContaining('kein Kunde zugeordnet'), findsOneWidget);
      expect(find.textContaining('In der Notiz genannt: "Frau Neumann"'), findsOneWidget);

      // without a name nothing can be issued
      await tester.scrollUntilVisible(find.text('Rechnung fertigstellen'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Rechnung fertigstellen'));
      await tester.pumpAndSettle();
      expect(find.text('Noch nicht möglich'), findsOneWidget);
      expect(find.textContaining('Namen'), findsOneWidget);
      expect(app.documents.createCalls, isEmpty);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // accept the suggestion: now it works, creates the customer and links the job to it
      await tester.scrollUntilVisible(find.textContaining('In der Notiz genannt'), -200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.textContaining('In der Notiz genannt'));
      await tester.pumpAndSettle();
      expect(find.text('Frau Neumann'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Rechnung fertigstellen'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Rechnung fertigstellen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fertigstellen'));
      await tester.pumpAndSettle();

      expect(app.documents.createCalls.single['customer_id'], isNull);
      expect((app.documents.createCalls.single['recipient_snapshot'] as Map)['name'], 'Frau Neumann');
      final customers = (await tester.runAsync(() => app.db.select(app.db.customers).get()))!;
      final neumann = customers.singleWhere((c) => c.name == 'Frau Neumann');
      expect((await tester.runAsync(() => app.db.jobById('j1')))!.customerId, neumann.id);
    });
  });

  group('number highlighting', () {
    test('digits and spoken numbers are marked, other words are not', () {
      const base = TextStyle();
      final spans = highlightNumbers('Leuchten je fünfzehn Euro, 3 Stunden, anderthalb Std', base);
      final marked = [for (final sp in spans) if (sp.style?.fontWeight == FontWeight.bold) sp.text];
      expect(marked, ['fünfzehn', '3', 'anderthalb']);
      expect(spans.map((e) => e.text).join(), 'Leuchten je fünfzehn Euro, 3 Stunden, anderthalb Std');
    });
  });
}

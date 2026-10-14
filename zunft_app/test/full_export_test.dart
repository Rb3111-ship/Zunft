import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/core/sync/sync_mapping.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/data/domain/full_export.dart';
import 'package:zunft_app/features/jobs/data/job_notes_remote.dart';
import 'package:zunft_app/features/receipts/domain/receipt_entry.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_documents.dart';
import 'helpers/fake_job_notes.dart';
import 'helpers/fake_receipts.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/test_app.dart';

final _now = DateTime(2026, 10, 14, 15, 30);

Customer customer(String id, String name, {String? first, String? leitweg, String? merged, String? email}) => Customer(
      id: id, businessId: 'b1', name: name, firstName: first, email: email, leitwegId: leitweg, mergedInto: merged,
      street: 'Elbchaussee 118', zip: '22763', city: 'Hamburg', updatedAt: DateTime(2026),
    );

Archive unzip(Uint8List bytes) => ZipDecoder().decodeBytes(bytes);

String read(Archive a, String name) => utf8.decode(a.findFile(name)!.content as List<int>);

List<String> lines(String csv) => csv.replaceFirst('\u{FEFF}', '').trim().split('\r\n');

FullExportData data({List<IssuedDocument>? docs, List<ReceiptEntry>? receipts}) => FullExportData(
      businessName: 'Elektro Test GmbH',
      now: _now,
      customers: [
        customer('c1', 'Müller', first: 'Thomas', email: 'thomas@mueller.example'),
        customer('c2', 'Bezirksamt Altona', leitweg: '04011000-1234512345-06'),
        customer('c3', 'Mueller', first: 'Tom', merged: 'c1'),
      ],
      jobs: [
        Job(id: 'j1', businessId: 'b1', customerId: 'c1', title: 'Steckdose Keller', description: 'Zwei; Steckdosen "neu"', status: 'in_progress', updatedAt: DateTime(2026, 10, 5, 9)),
      ],
      documents: docs ?? [document('RE-2026-0001'), document('RE-2026-0002', status: 'paid', leitweg: '04011000-1234512345-06')],
      appointments: [
        Appointment(
            id: 'a1', businessId: 'b1', jobId: 'j1', customerId: 'c1', kind: 'job', title: 'Frank kommt', location: 'Keller',
            startsAt: DateTime.utc(2026, 10, 15, 6), endsAt: DateTime.utc(2026, 10, 15, 8), status: 'planned',
            assigneeIds: '["u2","u9"]', updatedAt: DateTime(2026)),
      ],
      timeEntries: [
        TimeEntry(
            id: 't1', businessId: 'b1', userId: 'u2', userName: 'Gesa', jobId: 'j1', startedAt: DateTime.utc(2026, 10, 14, 6),
            endedAt: DateTime.utc(2026, 10, 14, 10, 30), breakMinutes: 30, createdBy: 'u1', documentId: 'd1', updatedAt: DateTime(2026)),
        TimeEntry(id: 't2', businessId: 'b1', userId: 'u2', userName: 'Gesa', jobId: 'j1', startedAt: DateTime.utc(2026, 10, 14, 12), breakMinutes: 0, createdBy: 'u2', updatedAt: DateTime(2026)),
      ],
      notes: [
        ExportNote(createdAt: DateTime(2026, 10, 5, 9, 30), jobTitle: 'Steckdose Keller', author: 'Thorsten', status: 'Abgerechnet', text: 'Steckdose; im Keller "gesetzt"'),
      ],
      receipts: receipts ?? [aReceipt(id: 'r1-abcdef', supplier: 'Baumarkt Hansen')],
      memberNames: const {'u2': 'Gesa Geselle'},
    );

IssuedDocument document(String number, {String status = 'issued', String? leitweg}) => IssuedDocument(
      id: 'id-$number', businessId: 'b1', docType: 'invoice', docNumber: number, status: status, title: 'Steckdose Keller',
      dateIssued: '2026-10-01', dateDue: '2026-10-15', deliveryPeriod: '01.10.2026', subtotalLaborCents: 13600, subtotalMaterialCents: 4000,
      totalNetCents: 17600, vatRate: 19, vatAmountCents: 3344, totalGrossCents: 20944,
      lineItemsJson: jsonEncode([
        {'type': 'labor', 'description': 'Steckdose montiert', 'quantity': 2, 'unit': 'Std', 'unit_price_net_cents': 6800, 'total_net_cents': 13600},
        {'type': 'material', 'description': 'Doppelsteckdose', 'quantity': 1.5, 'unit': 'Stk', 'unit_price_net_cents': 4000, 'total_net_cents': 6000},
      ]),
      recipientName: 'Thomas Müller', recipientAddress: 'Elbchaussee 118, 22763 Hamburg', buyerReference: leitweg, eInvoice: leitweg != null,
      updatedAt: DateTime(2026),
    );

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

Future<FullExport> build(FullExportData d, {Set<String> failingPdfs = const {}, Set<String> failingPhotos = const {}, void Function(int, int)? onProgress}) =>
    buildFullExport(
      d,
      fetchPdf: (doc) async {
        if (failingPdfs.contains(doc.docNumber)) throw Exception('gone');
        return bytes('%PDF ${doc.docNumber}');
      },
      fetchPhoto: (path) async {
        if (failingPhotos.contains(path)) throw Exception('gone');
        return bytes('photo $path');
      },
      onProgress: onProgress,
    );

void main() {
  group('the export file', () {
    test('contains every list and the files, named by number and by month', () async {
      final result = await build(data());
      final a = unzip(result.zip);
      final names = a.files.map((f) => f.name).toList();
      for (final n in ['LIESMICH.txt', 'kunden.csv', 'auftraege.csv', 'notizen.csv', 'rechnungen.csv', 'positionen.csv', 'belege.csv', 'termine.csv', 'zeiten.csv']) {
        expect(names, contains(n));
      }
      expect(names, containsAll(['rechnungen/RE-2026-0001.pdf', 'rechnungen/RE-2026-0002.pdf']));
      expect(names.where((n) => n.startsWith('belege/')).length, 1);
      expect(read(a, 'rechnungen/RE-2026-0001.pdf'), '%PDF RE-2026-0001');
      expect(result.counts, {'Kunden': 3, 'Aufträge': 1, 'Notizen': 1, 'Dokumente': 2, 'Belege': 1, 'Termine': 1, 'Zeiteinträge': 2});
      expect(result.missingFiles, isEmpty);
    });

    test('the CSV files open in Excel: byte order mark, semicolons, German numbers, awkward text in quotes', () async {
      final a = unzip((await build(data())).zip);
      final raw = a.findFile('rechnungen.csv')!.content as List<int>;
      expect(raw.take(3), [0xEF, 0xBB, 0xBF]); // the byte order mark Excel needs
      final rows = lines(read(a, 'rechnungen.csv'));
      expect(rows.first, startsWith('Nummer;Art;Datum;Fällig;Kunde;Anschrift;Leitweg-ID;'));
      expect(rows[1], contains('RE-2026-0001;Rechnung;01.10.2026;15.10.2026;Thomas Müller;Elbchaussee 118, 22763 Hamburg;;Steckdose Keller;01.10.2026;Erstellt;136,00;40,00;176,00;19 %;33,44;209,44;nein;rechnungen/RE-2026-0001.pdf'));
      expect(rows[2], contains(';04011000-1234512345-06;'));
      expect(rows[2], contains(';Bezahlt;'));
      expect(rows[2], contains(';ja;rechnungen/RE-2026-0002.pdf'));
      // a text with ; and " stays one cell
      expect(read(a, 'auftraege.csv'), contains('"Zwei; Steckdosen ""neu"""'));
      expect(read(a, 'notizen.csv'), contains('"Steckdose; im Keller ""gesetzt"""'));
    });

    test('customers: all of them, the Leitweg-ID, and a merged one says into whom it was merged', () async {
      final rows = lines(read(unzip((await build(data())).zip), 'kunden.csv'));
      expect(rows.length, 4);
      expect(rows[2], contains('Bezirksamt Altona'));
      expect(rows[2], contains('04011000-1234512345-06'));
      expect(rows[3], endsWith(';Thomas Müller'));
    });

    test('positions: one line per position with the sums', () async {
      final rows = lines(read(unzip((await build(data())).zip), 'positionen.csv'));
      expect(rows[1], 'RE-2026-0001;1;Arbeit;Steckdose montiert;2;Std;68,00;136,00');
      expect(rows[2], 'RE-2026-0001;2;Material;Doppelsteckdose;1,5;Stk;40,00;60,00');
      expect(rows.length, 5); // header + 2 documents x 2 positions
    });

    test('appointments name the people; time entries show hours, running timer, billed and "entered by the business"', () async {
      final a = unzip((await build(data())).zip);
      expect(lines(read(a, 'termine.csv'))[1], contains('Gesa Geselle, u9')); // an unknown id stays as it is
      final times = lines(read(a, 'zeiten.csv'));
      expect(times[1], contains(';4:00;')); // 4:30 hours minus 30 minutes break
      expect(times[1], endsWith(';ja;ja')); // billed; entered by the boss (createdBy differs)
      expect(times[2], contains(';läuft;'));
      expect(times[2], endsWith(';nein;nein'));
    });

    test('a file that cannot be fetched is named in the README and the rest is still delivered', () async {
      final r = await build(data(), failingPdfs: {'RE-2026-0002'}, failingPhotos: {'b1/u1/r1-abcdef.jpg'});
      final a = unzip(r.zip);
      expect(a.findFile('rechnungen/RE-2026-0002.pdf'), isNull);
      expect(a.findFile('rechnungen/RE-2026-0001.pdf'), isNotNull);
      expect(r.missingFiles.length, greaterThanOrEqualTo(1));
      expect(read(a, 'LIESMICH.txt'), contains('RE-2026-0002 (PDF)'));
      // the list still names the document, without a PDF
      expect(lines(read(a, 'rechnungen.csv'))[2], endsWith(';ja;'));
    });

    test('progress counts every file; an empty business still gives a valid file', () async {
      final seen = <String>[];
      await build(data(), onProgress: (d, t) => seen.add('$d/$t'));
      expect(seen, ['1/3', '2/3', '3/3']);
      final empty = await build(FullExportData(
          businessName: 'Leer', now: _now, customers: const [], jobs: const [], documents: const [], appointments: const [],
          timeEntries: const [], notes: const [], receipts: const [], memberNames: const {}));
      expect(read(unzip(empty.zip), 'kunden.csv'), startsWith('Anrede;'));
      expect(empty.counts['Dokumente'], 0);
    });

    test('the README says what is inside, when, and that invoices must be kept', () async {
      final text = read(unzip((await build(data())).zip), 'LIESMICH.txt');
      expect(text, contains('Datenexport von Elektro Test GmbH'));
      expect(text, contains('14.10.2026 15:30'));
      expect(text, contains('Kunden 3'));
      expect(text, contains('gesetzlich aufbewahrt'));
      expect(text, contains('die Tonaufnahmen sind nicht enthalten'));
    });

    test('a cell that starts with = is neutralised (no formula in Excel)', () async {
      final d = data();
      final evil = FullExportData(
          businessName: d.businessName, now: d.now, customers: [customer('c9', '=HYPERLINK("x")')], jobs: const [],
          documents: const [], appointments: const [], timeEntries: const [], notes: const [], receipts: const [], memberNames: const {});
      expect(read(unzip((await build(evil)).zip), 'kunden.csv'), contains("'=HYPERLINK"));
    });

    test('the file name carries the date', () => expect(fullExportFileName(_now), 'Zunft_Datenexport_2026-10-14.zip'));
  });

  group('on the screen', () {
    FakeAuthRepository owner() => FakeAuthRepository(
          userId: 'u1',
          profile: const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: 'owner'),
          business: FakeAuthRepository.completeBusiness(),
        );

    FakeSyncRemote remote() => FakeSyncRemote()
      ..seed(SyncEntity.customer, remoteCustomer('c1', name: 'Müller'))
      ..seed(SyncEntity.job, remoteJob('j1', title: 'Steckdose Keller', customerId: 'c1'))
      ..seed(SyncEntity.document, remoteDocument('d1', number: 'RE-2026-0001'));

    Future<void> openTile(WidgetTester tester) async {
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('full-export')), 300, scrollable: find.byType(Scrollable).first);
    }

    testApp('the owner exports everything: a question first, then a ZIP goes to the share sheet', (tester) async {
      final receipts = FakeReceiptsRemote()..entries.add(aReceipt(id: 'r1-abcdef', supplier: 'Baumarkt Hansen'));
      final notes = FakeJobNotesRemote()
        ..allNotes.add(ExportNote(createdAt: DateTime(2026, 10, 5), jobTitle: 'Steckdose Keller', author: 'Thorsten', status: 'Offen', text: 'Nur ein Test'));
      final app = await pumpApp(tester, owner(), remote: remote(), receipts: receipts, jobNotes: notes);
      await openTile(tester);
      await tester.tap(find.byKey(const ValueKey('full-export')));
      await tester.pumpAndSettle();
      expect(find.text('Alle Daten exportieren?'), findsOneWidget);
      expect(app.sharer.shared, isEmpty); // nothing yet

      await tester.tap(find.text('Exportieren'));
      await tester.pumpAndSettle();
      final shared = app.sharer.shared.single;
      expect(shared.name, 'Zunft_Datenexport_2026-10-14.zip');
      expect(shared.mimeType, 'application/zip');
      final a = unzip(shared.bytes);
      expect(a.findFile('kunden.csv'), isNotNull);
      expect(read(a, 'kunden.csv'), contains('Müller'));
      expect(read(a, 'notizen.csv'), contains('Nur ein Test'));
      expect(read(a, 'rechnungen.csv'), contains('RE-2026-0001'));
      expect(a.files.any((f) => f.name.startsWith('rechnungen/') && f.name.endsWith('.pdf')), isTrue);
      expect(a.files.any((f) => f.name.startsWith('belege/')), isTrue);
    });

    testApp('cancelling the question exports nothing', (tester) async {
      final app = await pumpApp(tester, owner(), remote: remote());
      await openTile(tester);
      await tester.tap(find.byKey(const ValueKey('full-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(app.sharer.shared, isEmpty);
      expect(find.text('Alle Daten exportieren?'), findsNothing);
    });

    testApp('no connection: a clear message, nothing shared, the button works again', (tester) async {
      final notes = FakeJobNotesRemote()..error = const JobNotesException('offline');
      final app = await pumpApp(tester, owner(), remote: remote(), jobNotes: notes);
      await openTile(tester);
      await tester.tap(find.byKey(const ValueKey('full-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exportieren'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Der Export ist fehlgeschlagen'), findsOneWidget);
      expect(app.sharer.shared, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      notes.error = null;
      await tester.tap(find.byKey(const ValueKey('full-export')));
      await tester.pumpAndSettle();
      expect(find.text('Alle Daten exportieren?'), findsOneWidget);
    });

    testApp('it also works when the subscription has ended (it only reads)', (tester) async {
      // the export screen has no subscription check; an ended business exports like any other
      final app = await pumpApp(tester, owner(), remote: remote());
      await openTile(tester);
      await tester.tap(find.byKey(const ValueKey('full-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exportieren'));
      await tester.pumpAndSettle();
      expect(app.sharer.shared, hasLength(1));
    });

    testApp('an employee does not see it', (tester) async {
      final geselle = FakeAuthRepository(
        userId: 'u1',
        profile: const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Gesa', role: 'geselle'),
        business: FakeAuthRepository.completeBusiness(),
      );
      await pumpApp(tester, geselle, remote: remote());
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('full-export')), findsNothing);
    });
  });
}

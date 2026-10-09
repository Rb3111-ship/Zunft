import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/features/receipts/data/receipts_remote.dart';
import 'package:zunft_app/features/receipts/domain/receipt_entry.dart';
import 'package:zunft_app/features/receipts/domain/receipt_export.dart';

import 'helpers/fake_documents.dart';
import 'helpers/fake_receipts.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/job_app.dart';
import 'helpers/test_app.dart';

Map<String, String> unzipText(List<int> zip) {
  final out = <String, String>{};
  for (final f in ZipDecoder().decodeBytes(zip)) {
    if (f.isFile) out[f.name] = f.name.endsWith('.jpg') ? '<jpg>' : utf8.decode(f.content as List<int>);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReceiptEntry', () {
    Map<String, dynamic> row({Map<String, dynamic>? over}) => {
          'id': 'r1',
          'created_at': '2026-10-08T07:00:00Z',
          'photo_storage_paths': ['b1/u1/r1.jpg'],
          'job_id': 'j1',
          'document_id': null,
          'discarded_at': null,
          'jobs': {'title': 'Bad Schiller'},
          'documents': null,
          'profiles': {'full_name': 'Thorsten'},
          'ai_parsed_json': {
            'receipt': {
              'supplier': 'Baumarkt Hansen',
              'receipt_date': '2026-10-07',
              'receipt_number': '4711',
              'total_printed_cents': 10600
            },
            'financial_summary': {'total_net_cents': 8908, 'vat_amount_cents': 1693, 'total_gross_cents': 10601},
            'line_items': [
              {'description': 'Kabel', 'quantity': 50, 'unit': 'm', 'unit_price_net_cents': 100}
            ],
            'warnings': ['Pfand'],
          },
          ...?over,
        };

    test('reads what the server stored', () {
      final r = ReceiptEntry.fromRow(row());
      expect(r.supplier, 'Baumarkt Hansen');
      expect(r.date, DateTime(2026, 10, 7));
      expect(r.monthKey, '2026-10');
      expect(r.grossCents, 10600); // the printed total wins over the calculated one
      expect(r.jobTitle, 'Bad Schiller');
      expect(r.authorName, 'Thorsten');
      expect(r.lines.single.totalNetCents, 5000);
      expect(r.status, ReceiptStatus.open);
      expect(r.warnings, ['Pfand']);
    });

    test('status: billed (with the invoice number) or removed', () {
      final billed = ReceiptEntry.fromRow(row(over: {'document_id': 'd1', 'documents': {'doc_number': 'RE-2026-0007'}}));
      expect(billed.status, ReceiptStatus.billed);
      expect(billed.statusLabel, 'Abgerechnet in RE-2026-0007');
      final removed = ReceiptEntry.fromRow(row(over: {'discarded_at': '2026-10-09T08:00:00Z'}));
      expect(removed.status, ReceiptStatus.removed);
    });

    test('without a readable date the day it was added counts; without a total the positions do', () {
      final r = ReceiptEntry.fromRow(row(over: {
        'ai_parsed_json': {
          'receipt': {'supplier': null, 'receipt_date': 'gestern'},
          'financial_summary': {'total_gross_cents': 5000},
        }
      }));
      expect(r.receiptDate, isNull);
      expect(r.monthKey, '2026-10');
      expect(r.grossCents, 5000);
      expect(r.supplierLabel, 'Unbekannter Lieferant');
    });

    test('search: every word must match something', () {
      final r = aReceipt();
      expect(receiptMatches(r, ''), isTrue);
      expect(receiptMatches(r, 'hansen'), isTrue);
      expect(receiptMatches(r, 'hansen 0093'), isTrue);
      expect(receiptMatches(r, 'keller thorsten'), isTrue);
      expect(receiptMatches(r, '106,00'), isTrue);
      expect(receiptMatches(r, '07.10.2026'), isTrue);
      expect(receiptMatches(r, 'nym-j'), isTrue); // a position
      expect(receiptMatches(r, 'obi'), isFalse);
      expect(receiptMatches(r, 'hansen obi'), isFalse);
    });

    test('month names in German', () {
      expect(monthLabel('2026-03'), 'März 2026');
      expect(monthLabel('2026-10'), 'Oktober 2026');
    });
  });

  group('export', () {
    test('the CSV uses semicolons, German numbers, quotes and a byte order mark', () {
      final csv = receiptsCsv(
        [aReceipt(supplier: 'Müller; "Söhne"', total: 123456), aReceipt(id: 'r2-xxxxxx', supplier: '=SUMME(A1)')],
        {'r1-abcdef': 'belege/2026-10/a.jpg'},
      );
      expect(csv.startsWith('﻿'), isTrue);
      final lines = csv.substring(1).trim().split('\r\n');
      expect(lines.first, startsWith('Belegdatum;Lieferant;Belegnummer;Auftrag'));
      expect(lines[1], contains('"Müller; ""Söhne"""'));
      expect(lines[1], contains(';1234,56;')); // printed total, German decimal comma
      expect(lines[1], endsWith('belege/2026-10/a.jpg'));
      expect(lines[2], contains("'=SUMME(A1)")); // never a live formula
    });

    test('the ZIP holds photos by month, the CSV, the readme; equal names are kept apart', () async {
      final result = await buildReceiptExport(
        receipts: [aReceipt(), aReceipt(id: 'r2-abcdef')],
        documents: const [],
        fetchPhoto: (_) async => Uint8List.fromList([1, 2, 3]),
        periodLabel: 'Oktober 2026',
      );
      final files = unzipText(result.zip);
      expect(files.keys.where((k) => k.endsWith('.jpg')), hasLength(2));
      expect(files.keys, contains('belege/2026-10/2026-10-07_Baumarkt-Hansen_20457-0093.jpg'));
      expect(files.keys.any((k) => k.contains('_r2-abc')), isTrue);
      expect(files.keys, containsAll(['belege.csv', 'LIESMICH.txt']));
      expect(files.keys, isNot(contains('ausgangsrechnungen.csv'))); // none given
      expect(result.missingPhotos, 0);
    });

    test('a photo that cannot be fetched is listed instead of failing the export', () async {
      final result = await buildReceiptExport(
        receipts: [aReceipt(), aReceipt(id: 'r2-abcdef', supplier: 'Elektro Nord')],
        documents: const [],
        fetchPhoto: (p) async => p.contains('r2') ? throw StateError('gone') : Uint8List.fromList([1]),
        periodLabel: 'alle',
      );
      expect(result.missingPhotos, 1);
      final files = unzipText(result.zip);
      expect(files['LIESMICH.txt'], contains('Elektro Nord'));
      expect(files['belege.csv'], contains('Elektro Nord')); // still listed, with an empty file column
    });
  });

  group('the Einkaufsbelege list', () {
    Future<TestApp> openArchive(WidgetTester tester, {List<ReceiptEntry>? entries, FakeSyncRemote? remote}) async {
      final receipts = FakeReceiptsRemote()
        ..entries.addAll(entries ??
            [
              aReceipt(),
              aReceipt(id: 'r2-abcdef', supplier: 'Elektro Nord', date: DateTime(2026, 9, 20), total: 5950, job: 'Bad Schiller'),
              aReceipt(
                  id: 'r3-abcdef',
                  supplier: 'Hagebau',
                  date: DateTime(2026, 10, 2),
                  total: 2000,
                  status: ReceiptStatus.billed,
                  docNumber: 'RE-2026-0004'),
            ]);
      final app = await pumpJobApp(tester, receipts: receipts, remote: remote);
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Einkaufsbelege'));
      await tester.pumpAndSettle();
      return app;
    }

    testApp('lists the receipts, newest first, with the total and each one\'s status', (tester) async {
      await openArchive(tester);
      expect(find.text('Baumarkt Hansen'), findsOneWidget);
      expect(find.text('Elektro Nord'), findsOneWidget);
      expect(find.text('Noch nicht abgerechnet'), findsNWidgets(2));
      expect(find.text('Abgerechnet in RE-2026-0004'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // count
      expect(find.textContaining('185,50'), findsOneWidget); // 106,00 + 59,50 + 20,00
      final order = ['Baumarkt Hansen', 'Hagebau', 'Elektro Nord'].map((n) => tester.getTopLeft(find.text(n)).dy).toList();
      expect(order, [...order]..sort()); // 7.10., 2.10., 20.9.
    });

    testApp('search narrows the list and the total; a month can be chosen', (tester) async {
      await openArchive(tester);
      await tester.enterText(find.byType(TextField), 'schiller');
      await tester.pumpAndSettle();
      expect(find.text('Elektro Nord'), findsOneWidget);
      expect(find.text('Baumarkt Hansen'), findsNothing);
      await tester.enterText(find.byType(TextField), 'gibtesnicht');
      await tester.pumpAndSettle();
      expect(find.text('Nichts gefunden.'), findsOneWidget);
      await tester.tap(find.byTooltip('Suche löschen'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('September 2026').last);
      await tester.pumpAndSettle();
      expect(find.text('Elektro Nord'), findsOneWidget);
      expect(find.text('Baumarkt Hansen'), findsNothing);
    });

    testApp('Exportieren shares one ZIP with photos, the list and the invoices of the month', (tester) async {
      final sync = FakeSyncRemote()..seed(SyncEntity.document, remoteDocument('d1', date: '2026-10-01'));
      final app = await openArchive(tester, remote: sync);
      await tester.tap(find.text('Exportieren'));
      await tester.pumpAndSettle();

      final shared = app.sharer.shared.single;
      expect(shared.name, 'Zunft_Belege_alle.zip');
      final files = unzipText(shared.bytes);
      expect(files.keys.where((k) => k.endsWith('.jpg')), hasLength(3));
      expect(files['belege.csv'], contains('Hagebau'));
      expect(files['ausgangsrechnungen.csv'], contains('RE-2026-0001'));
      expect(app.receipts.downloads, hasLength(3));
    });

    testApp('with a month chosen only that month is exported', (tester) async {
      final sync = FakeSyncRemote()
        ..seed(SyncEntity.document, remoteDocument('d1', date: '2026-10-01'))
        ..seed(SyncEntity.document, remoteDocument('d2', number: 'RE-2026-0002', date: '2026-09-15'));
      final app = await openArchive(tester, remote: sync);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('September 2026').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exportieren'));
      await tester.pumpAndSettle();

      final shared = app.sharer.shared.single;
      expect(shared.name, 'Zunft_Belege_2026-09.zip');
      final files = unzipText(shared.bytes);
      expect(files.keys.where((k) => k.endsWith('.jpg')), hasLength(1));
      expect(files['ausgangsrechnungen.csv'], contains('RE-2026-0002'));
      expect(files['ausgangsrechnungen.csv'], isNot(contains('RE-2026-0001')));
    });

    testApp('a failing share is explained', (tester) async {
      final app = await openArchive(tester);
      app.sharer.error = StateError('no share target');
      await tester.tap(find.text('Exportieren'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Der Export ist fehlgeschlagen'), findsOneWidget);
    });

    testApp('tapping a receipt shows what was read, and the photo', (tester) async {
      await openArchive(tester);
      await tester.tap(find.text('Baumarkt Hansen'));
      await tester.pumpAndSettle();
      expect(find.text('20457-0093'), findsOneWidget);
      expect(find.text('Steckdose Keller'), findsOneWidget);
      expect(find.textContaining('Mantelleitung NYM-J 3x1,5'), findsOneWidget);
      expect(find.textContaining('Maßgeblich ist immer das Foto'), findsOneWidget);
      await tester.tap(find.text('Foto öffnen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('BELEGBILD https://audio.test/b1/u1/r1-abcdef.jpg'), findsOneWidget);
    });

    testApp('an empty archive explains how receipts get here', (tester) async {
      await openArchive(tester, entries: []);
      expect(find.textContaining('Noch keine Einkaufsbelege'), findsOneWidget);
    });

    testApp('a load error can be retried', (tester) async {
      final receipts = FakeReceiptsRemote()..error = const ReceiptsException('Die Belege konnten nicht geladen werden.');
      final app = await pumpJobApp(tester, receipts: receipts);
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Einkaufsbelege'));
      await tester.pumpAndSettle();
      expect(find.textContaining('konnten nicht geladen werden'), findsOneWidget);
      app.receipts.error = null;
      app.receipts.entries.add(aReceipt());
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();
      expect(find.text('Baumarkt Hansen'), findsOneWidget);
    });

    testApp('employees have no Belege tab at all', (tester) async {
      await pumpJobApp(tester, role: 'geselle');
      expect(find.text('Belege'), findsNothing);
      expect(find.text('Einkaufsbelege'), findsNothing);
    });
  });
}

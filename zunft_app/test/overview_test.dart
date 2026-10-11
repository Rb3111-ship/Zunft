import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/core/utils/currency_formatter.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/overview/domain/period_export.dart';
import 'package:zunft_app/features/overview/domain/period_summary.dart';
import 'package:zunft_app/features/receipts/data/receipts_remote.dart';
import 'package:zunft_app/features/receipts/domain/receipt_entry.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_documents.dart';
import 'helpers/fake_receipts.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/test_app.dart';

IssuedDocument doc(
  String id,
  String date, {
  String type = 'invoice',
  String status = 'issued',
  int net = 10000,
  int labor = 6000,
  int material = 4000,
  double rate = 19,
}) {
  final sign = type == 'cancellation' ? -1 : 1;
  final vat = (net * rate / 100).round();
  return IssuedDocument(
    id: id,
    businessId: 'b1',
    docType: type,
    docNumber: 'N-$id',
    status: status,
    dateIssued: date,
    subtotalLaborCents: sign * labor,
    subtotalMaterialCents: sign * material,
    totalNetCents: sign * net,
    vatRate: rate,
    vatAmountCents: sign * vat,
    totalGrossCents: sign * (net + vat),
    lineItemsJson: jsonEncode([]),
    recipientName: 'Kunde',
    eInvoice: false,
    updatedAt: DateTime(2026),
  );
}

String fmt(int cents) => CurrencyFormatter.formatCents(cents);

void main() {
  group('adding up a month', () {
    test('invoices of the month: count, net, VAT per rate, gross, labour and material', () {
      final s = summarize(
        documents: [
          doc('a', '2026-10-01'), // 100,00 net, 19 VAT
          doc('b', '2026-10-31', net: 20000, labor: 20000, material: 0),
          doc('c', '2026-10-15', net: 10000, rate: 7), // another rate in the same month
        ],
        receipts: const [],
        year: 2026,
        month: 10,
      );
      expect(s.invoiceCount, 3);
      expect(s.netCents, 40000);
      expect(s.vatCents, 1900 + 3800 + 700);
      expect(s.grossCents, 40000 + 6400);
      expect(s.laborNetCents, 6000 + 20000 + 6000);
      expect(s.materialNetCents, 4000 + 0 + 4000);
      expect(s.byRate.map((g) => (g.rate, g.netCents, g.vatCents, g.count)), [(19.0, 30000, 5700, 2), (7.0, 10000, 700, 1)]);
    });

    test('other months and years are not in it; the border days belong to their month', () {
      final all = [doc('sep', '2026-09-30'), doc('oct1', '2026-10-01'), doc('oct31', '2026-10-31'), doc('nov', '2026-11-01'), doc('old', '2025-10-15')];
      expect(summarize(documents: all, receipts: const [], year: 2026, month: 10).invoiceCount, 2);
      expect(summarize(documents: all, receipts: const [], year: 2026, month: 9).invoiceCount, 1);
      expect(summarize(documents: all, receipts: const [], year: 2025, month: 10).invoiceCount, 1);
    });

    test('quotes are not revenue', () {
      final s = summarize(documents: [doc('q', '2026-10-05', type: 'quote'), doc('i', '2026-10-06')], receipts: const [], year: 2026, month: 10);
      expect(s.invoiceCount, 1);
      expect(s.netCents, 10000);
    });

    test('a cancellation is negative and offsets in the month it was issued; the cancelled invoice stays in its own', () {
      final docs = [
        doc('inv', '2026-09-20', status: 'canceled'),
        doc('st', '2026-10-02', type: 'cancellation', status: 'issued'),
        doc('new', '2026-10-02'),
      ];
      final sep = summarize(documents: docs, receipts: const [], year: 2026, month: 9);
      expect(sep.netCents, 10000); // the invoice, before it was cancelled
      expect(sep.invoiceCount, 1);
      final oct = summarize(documents: docs, receipts: const [], year: 2026, month: 10);
      expect(oct.cancellationCount, 1);
      expect(oct.invoiceCount, 1);
      expect(oct.netCents, 0); // minus the cancelled one, plus the new invoice
      expect(oct.vatCents, 0);
      final year = summarize(documents: docs, receipts: const [], year: 2026);
      expect(year.netCents, 10000); // over the year only the new invoice remains
    });

    test('paid and open: of the invoices of the period; cancelled ones and cancellations count for neither', () {
      final s = summarize(
        documents: [
          doc('p', '2026-10-01', status: 'paid'),
          doc('o1', '2026-10-02', status: 'issued'),
          doc('o2', '2026-10-03', status: 'sent'),
          doc('c', '2026-10-04', status: 'canceled'),
          doc('st', '2026-10-05', type: 'cancellation'),
        ],
        receipts: const [],
        year: 2026,
        month: 10,
      );
      expect(s.paidGrossCents, 11900);
      expect(s.openGrossCents, 23800);
    });

    test('Kleinunternehmer: a 0 % group without VAT', () {
      final s = summarize(documents: [doc('k', '2026-10-05', rate: 0)], receipts: const [], year: 2026, month: 10);
      expect(s.vatCents, 0);
      expect(s.byRate.single.rate, 0);
      expect(s.grossCents, 10000);
    });

    test('the receipts of the period: how many and what the photos say, by receipt date', () {
      final s = summarize(
        documents: const [],
        receipts: [
          aReceipt(id: 'r1', date: DateTime(2026, 10, 7), total: 10600),
          aReceipt(id: 'r2', date: DateTime(2026, 10, 31), total: 5000),
          aReceipt(id: 'r3', date: DateTime(2026, 9, 30), total: 9999),
        ],
        year: 2026,
        month: 10,
      );
      expect(s.receiptCount, 2);
      expect(s.receiptsGrossCents, 15600);
    });

    test('a whole year lists the twelve months', () {
      final s = summarize(documents: [doc('a', '2026-03-10'), doc('b', '2026-03-20'), doc('c', '2026-12-31')], receipts: const [], year: 2026);
      expect(s.months, hasLength(12));
      expect(s.months[2].count, 2);
      expect(s.months[2].netCents, 20000);
      expect(s.months[11].count, 1);
      expect(s.months[5].count, 0);
      expect(s.netCents, 30000);
    });

    test('nothing at all: empty', () {
      expect(summarize(documents: const [], receipts: const <ReceiptEntry>[], year: 2026, month: 10).isEmpty, isTrue);
    });
  });

  group('the file', () {
    test('a CSV with the sums, the disclaimer, and the invoices one per line (one byte order mark only)', () {
      final docs = [doc('a', '2026-10-01'), doc('b', '2026-10-02', status: 'paid')];
      final s = summarize(documents: docs, receipts: [aReceipt(total: 10600, date: DateTime(2026, 10, 7))], year: 2026, month: 10);
      final bytes = periodCsv(s, docs);
      final text = utf8.decode(bytes);
      expect(text, contains('Zeitraum;Oktober 2026'));
      expect(text, contains('Rechnungen (Anzahl);2'));
      expect(text, contains('Netto;200,00'));
      expect(text, contains('Brutto;238,00'));
      expect(text, contains('Steuersatz 19 %;Netto 200,00;Steuer 38,00;Belege 2'));
      expect(text, contains('Einkaufsbelege (Anzahl);1'));
      expect(text, contains('keine Steuerberechnung'));
      expect(text, contains('Nummer;Art;Datum;Kunde;Status;Netto;MwSt.;Brutto'));
      expect(text, contains('N-a;Rechnung;01.10.2026;Kunde;Erstellt;100,00;19,00;119,00'));
      var boms = 0; // the byte order mark (EF BB BF) appears once, at the start of the file
      for (var i = 0; i + 2 < bytes.length; i++) {
        if (bytes[i] == 0xEF && bytes[i + 1] == 0xBB && bytes[i + 2] == 0xBF) boms++;
      }
      expect(boms, 1);
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    });

    test('names and file names', () {
      expect(periodLabel(2026, 10), 'Oktober 2026');
      expect(periodLabel(2026, null), '2026');
      expect(periodFileStem(2026, 3), 'uebersicht-2026-03');
      expect(periodFileStem(2026, null), 'uebersicht-2026');
    });
  });

  group('on the screen', () {
    FakeAuthRepository owner() => FakeAuthRepository(
          userId: 'u1',
          profile: const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: 'owner'),
        );
    FakeAuthRepository geselle() => FakeAuthRepository(
          userId: 'u2',
          profile: const UserProfile(id: 'u2', businessId: 'b1', fullName: 'Hans', role: 'geselle'),
        );
    final now = DateTime.now();
    String iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Übersicht'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Übersicht'));
      await tester.pumpAndSettle();
    }

    testApp('the boss sees this month: sums, VAT, paid and open, the receipts and the disclaimer', (tester) async {
      final receipts = FakeReceiptsRemote()..entries.add(aReceipt(date: DateTime(now.year, now.month, 1), total: 10600));
      await pumpApp(
        tester,
        owner(),
        remote: FakeSyncRemote()
          ..seed(SyncEntity.document, remoteDocument('d1', number: 'RE-1', date: iso(now), gross: 20944))
          ..seed(SyncEntity.document, remoteDocument('d2', number: 'RE-2', date: iso(now), status: 'paid', gross: 20944)),
        receipts: receipts,
      );
      await open(tester);
      expect(find.text('Übersicht'), findsWidgets);
      expect(find.text('Netto'), findsOneWidget);
      expect(find.text(fmt(35200)), findsOneWidget); // 2 x 176,00 net
      expect(find.text('Umsatzsteuer 19 %'), findsOneWidget);
      expect(find.text(fmt(6688)), findsOneWidget); // 2 x 33,44
      expect(find.text(fmt(41888)), findsOneWidget); // gross
      expect(find.text('Bezahlt'), findsOneWidget);
      expect(find.text('Noch offen'), findsOneWidget);
      expect(find.text(fmt(10600)), findsOneWidget); // the receipt as printed
      expect(find.textContaining('keine Steuerberechnung'), findsOneWidget);
    });

    testApp('the arrows move through the months; the year view lists the months with invoices', (tester) async {
      final lastMonth = DateTime(now.year, now.month - 1, 15);
      await pumpApp(
        tester,
        owner(),
        remote: FakeSyncRemote()..seed(SyncEntity.document, remoteDocument('d1', number: 'RE-1', date: iso(lastMonth), gross: 20944)),
      );
      await open(tester);
      expect(find.text('In diesem Zeitraum gibt es keine Rechnungen und keine Belege.'), findsOneWidget);
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      expect(find.text(fmt(17600)), findsWidgets);
      await tester.tap(find.text('Jahr'));
      await tester.pumpAndSettle();
      expect(find.text('Monat für Monat'.toUpperCase()), findsOneWidget);
      expect(find.textContaining('brutto ${fmt(20944)}'), findsOneWidget);
    });

    testApp('the receipts could not be loaded: said so, the invoices still show', (tester) async {
      final receipts = FakeReceiptsRemote()..error = const ReceiptsException('offline');
      await pumpApp(tester, owner(), remote: FakeSyncRemote()..seed(SyncEntity.document, remoteDocument('d1', date: iso(now))), receipts: receipts);
      await open(tester);
      expect(find.textContaining('Belege konnten nicht geladen werden'), findsOneWidget);
      expect(find.text(fmt(17600)), findsWidgets);
    });

    testApp('sharing hands the CSV to the share sheet', (tester) async {
      final app = await pumpApp(tester, owner(), remote: FakeSyncRemote()..seed(SyncEntity.document, remoteDocument('d1', date: iso(now))));
      await open(tester);
      await tester.scrollUntilVisible(find.text('Als Datei teilen (CSV)'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Als Datei teilen (CSV)'));
      await tester.pumpAndSettle();
      final f = app.sharer.shared.single;
      expect(f.mimeType, 'text/csv');
      expect(f.name, 'uebersicht-${now.year}-${now.month.toString().padLeft(2, '0')}.csv');
      expect(utf8.decode(f.bytes), contains('Rechnungen (Anzahl);1'));
    });

    testApp('a worker does not get the overview', (tester) async {
      await pumpApp(tester, geselle(), remote: FakeSyncRemote());
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      expect(find.text('Übersicht'), findsNothing);
    });
  });
}

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/core/sync/sync_mapping.dart';
import 'package:zunft_app/core/utils/currency_formatter.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/documents/domain/document_data.dart';
import 'package:zunft_app/features/documents/domain/open_invoices.dart';

import 'helpers/fake_appointments.dart';
import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_documents.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/test_app.dart';

final now = DateTime(2026, 10, 14, 15, 30);

IssuedDocument doc(String number, {String type = 'invoice', String status = 'issued', String due = '2026-10-15', int gross = 20944, String who = 'Thomas Müller'}) =>
    IssuedDocument(
      id: 'id-$number', businessId: 'b1', docType: type, docNumber: number, status: status, dateIssued: '2026-10-01', dateDue: due,
      subtotalLaborCents: 0, subtotalMaterialCents: 0, totalNetCents: 0, vatRate: 19, vatAmountCents: 0, totalGrossCents: gross,
      lineItemsJson: '[]', recipientName: who, eInvoice: false, updatedAt: DateTime(2026),
    );

CompanyDetails company({String iban = 'DE89370400440532013000', String phone = '040 1234567'}) => CompanyDetails(
    name: 'Elektro Test GmbH', ownerName: 'Erika Test', iban: iban, bic: 'COBADEFFXXX', bankName: 'Commerzbank', phone: phone);

FakeAuthRepository owner() => FakeAuthRepository(
      userId: 'u1',
      profile: const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: 'owner'),
      business: FakeAuthRepository.completeBusiness(),
    );

void main() {
  group('which invoices are open and how late they are', () {
    test('only unpaid invoices: not quotes, cancellations, paid or canceled ones', () {
      final list = openInvoices([
        doc('RE-1'),
        doc('RE-2', status: 'sent'),
        doc('RE-3', status: 'paid'),
        doc('RE-4', status: 'canceled'),
        doc('AN-1', type: 'quote'),
        doc('ST-1', type: 'cancellation'),
      ], now);
      expect(list.map((o) => o.document.docNumber), ['RE-1', 'RE-2']);
    });

    test('days are calendar days: due today is 0, yesterday 1, tomorrow -1; the time of day does not matter', () {
      int days(String due, DateTime at) => openInvoices([doc('RE-1', due: due)], at).single.daysOverdue;
      expect(days('2026-10-14', now), 0);
      expect(days('2026-10-13', now), 1);
      expect(days('2026-10-15', now), -1);
      expect(days('2026-10-14', DateTime(2026, 10, 14, 0, 1)), 0);
      expect(days('2026-10-14', DateTime(2026, 10, 14, 23, 59)), 0);
      expect(days('2026-10-14', DateTime(2026, 10, 15, 0, 1)), 1);
      // across the daylight-saving change (25 October 2026): 3 calendar days, not 71 hours
      expect(days('2026-10-24', DateTime(2026, 10, 27, 10)), 3);
      expect(openInvoices([doc('RE-1', due: '2026-10-14')], now).single.overdue, isFalse);
      expect(openInvoices([doc('RE-1', due: '2026-10-13')], now).single.overdue, isTrue);
    });

    test('the most overdue first, not yet due last; the same lateness by number', () {
      final list = openInvoices([
        doc('RE-5', due: '2026-10-20'),
        doc('RE-3', due: '2026-09-01'),
        doc('RE-4', due: '2026-10-10'),
        doc('RE-2', due: '2026-10-10'),
      ], now);
      expect(list.map((o) => o.document.docNumber), ['RE-3', 'RE-2', 'RE-4', 'RE-5']);
    });

    test('the sums: everything open, and what is overdue', () {
      final s = summarizeOpen(openInvoices([
        doc('RE-1', due: '2026-10-01', gross: 10000),
        doc('RE-2', due: '2026-10-14', gross: 5000),
        doc('RE-3', due: '2026-11-01', gross: 2500),
      ], now));
      expect((s.count, s.openCents), (3, 17500));
      expect((s.overdueCount, s.overdueCents), (1, 10000));
      expect(summarizeOpen(const []).openCents, 0);
    });

    test('a missing due date counts from the issue date', () {
      final d = doc('RE-1').copyWith(dateDue: const Value(null));
      expect(openInvoices([d], now).single.due, DateTime(2026, 10, 1));
    });
  });

  group('the payment reminder text (it goes to the customer: German, friendly, no threats)', () {
    OpenInvoice open(int daysLate) => OpenInvoice(doc('RE-2026-0007', due: '2026-10-01'), daysLate);

    test('a little late: friendly, payment may be on its way, 7 days, bank details, reference', () {
      final t = paymentReminderText(invoice: open(5), company: company(), now: now);
      expect(t, startsWith('Guten Tag,'));
      expect(t, contains('Rechnung RE-2026-0007 vom 01.10.2026 über 209,44'));
      expect(t, contains('fällig am 01.10.2026'));
      expect(t, contains('Vielleicht ist die Zahlung schon unterwegs'));
      expect(t, contains('bis zum 21.10.2026')); // today + 7 days
      expect(t, contains('IBAN: DE89370400440532013000'));
      expect(t, contains('BIC: COBADEFFXXX'));
      expect(t, contains('Kontoinhaber: Elektro Test GmbH'));
      expect(t, contains('Verwendungszweck: RE-2026-0007'));
      expect(t, contains('unter 040 1234567'));
      expect(t, endsWith('Mit freundlichen Grüßen\nElektro Test GmbH'));
    });

    test('long overdue: says how many days, still polite', () {
      final t = paymentReminderText(invoice: open(30), company: company(), now: now);
      expect(t, contains('seit 30 Tagen noch offen'));
      expect(t, contains('Bitte überweisen Sie den Betrag bis zum 21.10.2026'));
      expect(t, isNot(contains('Vielleicht ist die Zahlung schon unterwegs')));
      expect(t, contains('gegenstandslos'));
    });

    test('the tone changes after 14 days, not before', () {
      expect(paymentReminderText(invoice: open(14), company: company(), now: now), contains('Vielleicht'));
      expect(paymentReminderText(invoice: open(15), company: company(), now: now), contains('seit 15 Tagen'));
    });

    test('no fees, no interest, no legal words: this is a reminder, not a Mahnung', () {
      for (final late in [1, 14, 15, 90]) {
        final t = paymentReminderText(invoice: open(late), company: company(), now: now).toLowerCase();
        for (final word in ['mahngebühr', 'verzugszins', 'inkasso', 'rechtlich', 'anwalt', 'klage', 'gebühr', 'zinsen']) {
          expect(t, isNot(contains(word)), reason: '$late days: $word');
        }
      }
      expect(paymentReminderSubject(doc('RE-2026-0007')), 'Zahlungserinnerung zur Rechnung RE-2026-0007');
    });

    test('without bank details or phone nothing odd is printed', () {
      final t = paymentReminderText(invoice: open(5), company: company(iban: '', phone: ''), now: now);
      expect(t, isNot(contains('IBAN')));
      expect(t, isNot(contains('unter ')));
      expect(t, contains('Bei Fragen melden Sie sich gern.'));
      expect(t, contains('Verwendungszweck: RE-2026-0007'));
    });
  });

  group('the screen', () {
    // 14 October 2026 is "today" in the tests.
    FakeSyncRemote remote() => FakeSyncRemote()
      ..seed(SyncEntity.document, remoteDocument('d1', number: 'RE-2026-0001', recipient: 'Müller', due: '2026-10-01', gross: 20944))
      ..seed(SyncEntity.document, remoteDocument('d2', number: 'RE-2026-0002', recipient: 'Schmidt', due: '2026-10-13', gross: 11900, status: 'sent'))
      ..seed(SyncEntity.document, remoteDocument('d3', number: 'RE-2026-0003', recipient: 'Meier', due: '2026-10-28', gross: 5000))
      ..seed(SyncEntity.document, remoteDocument('d4', number: 'RE-2026-0004', recipient: 'Bezahlt GmbH', due: '2026-09-01', status: 'paid'))
      ..seed(SyncEntity.document, remoteDocument('d5', number: 'ANG-2026-0001', type: 'quote', recipient: 'Nur Angebot', due: '2026-09-01'));

    Future<FakeAppResult> open(WidgetTester tester, {FakeSyncRemote? sync, FakeExternalActions? actions}) async {
      final app = await pumpApp(tester, owner(), remote: sync ?? remote(), actions: actions);
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-card')));
      await tester.pumpAndSettle();
      return FakeAppResult(app);
    }

    testApp('the summary card of the Belege tab shows what is overdue and opens the list', (tester) async {
      await pumpApp(tester, owner(), remote: remote());
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const ValueKey('open-card')), matching: find.text('Überfällig')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('open-card')));
      await tester.pumpAndSettle();
      expect(find.text('Offene Rechnungen'), findsWidgets);
      expect(find.byKey(const ValueKey('open-summary')), findsOneWidget);
    });

    testApp('with nothing overdue the card shows no red number', (tester) async {
      final sync = FakeSyncRemote()..seed(SyncEntity.document, remoteDocument('d3', due: '2026-10-28'));
      await pumpApp(tester, owner(), remote: sync);
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const ValueKey('open-card')), matching: find.text('Überfällig')), findsNothing);
    });

    testApp('lists only open invoices, the most overdue first, with how late each is and the sums', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('open-RE-2026-0001')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-RE-2026-0002')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-RE-2026-0003')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-RE-2026-0004')), findsNothing); // paid
      expect(find.textContaining('ANG-2026-0001'), findsNothing); // a quote
      expect(find.textContaining('seit 13 Tagen überfällig'), findsOneWidget);
      expect(find.textContaining('seit 1 Tag überfällig'), findsOneWidget);
      expect(find.textContaining('in 14 Tagen'), findsOneWidget);
      final first = tester.getTopLeft(find.byKey(const ValueKey('open-RE-2026-0001'))).dy;
      final second = tester.getTopLeft(find.byKey(const ValueKey('open-RE-2026-0002'))).dy;
      final third = tester.getTopLeft(find.byKey(const ValueKey('open-RE-2026-0003'))).dy;
      expect(first < second && second < third, isTrue);
      // open: 209,44 + 119,00 + 50,00 = 378,44; overdue: 328,44
      expect(find.text(CurrencyFormatter.formatCents(37844)), findsOneWidget);
      expect(find.text(CurrencyFormatter.formatCents(32844)), findsOneWidget);
    });

    testApp('an overdue invoice offers the reminder; one that is not yet due does not', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('remind-RE-2026-0001')), findsOneWidget);
      expect(find.byKey(const ValueKey('remind-RE-2026-0002')), findsOneWidget);
      expect(find.byKey(const ValueKey('remind-RE-2026-0003')), findsNothing);
    });

    testApp('the reminder opens the share sheet with the German text, whatever the app language', (tester) async {
      final actions = FakeExternalActions();
      await open(tester, actions: actions);
      await tester.tap(find.byKey(const ValueKey('remind-RE-2026-0001')));
      await tester.pumpAndSettle();
      final sent = actions.texts.single;
      expect(sent.subject, 'Zahlungserinnerung zur Rechnung RE-2026-0001');
      expect(sent.text, contains('Rechnung RE-2026-0001'));
      expect(sent.text, contains('konnten wir noch keinen Zahlungseingang feststellen')); // 13 days late: still the friendly tone
      expect(sent.text, contains('Verwendungszweck: RE-2026-0001'));
      expect(sent.text, contains('Elektro Test GmbH'));
    });

    testApp('"paid" asks first, then saves; the invoice leaves the list and the sums drop', (tester) async {
      final result = await open(tester);
      await tester.tap(find.byKey(const ValueKey('paid-RE-2026-0001')));
      await tester.pumpAndSettle();
      expect(find.textContaining('können nicht storniert werden'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(result.app.documents.statusChanges, isEmpty);
      expect(find.byKey(const ValueKey('open-RE-2026-0001')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('paid-RE-2026-0001')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Als bezahlt markieren')));
      await tester.pumpAndSettle();
      expect(result.app.documents.statusChanges, ['d1:paid']);
      expect(find.byKey(const ValueKey('open-RE-2026-0001')), findsNothing);
      expect(find.text(CurrencyFormatter.formatCents(32844)), findsNothing); // the old overdue sum
      expect(find.text(CurrencyFormatter.formatCents(11900)), findsWidgets); // the overdue sum is now just RE-2026-0002
    });

    testApp('when everything is paid the screen says so', (tester) async {
      final sync = FakeSyncRemote()..seed(SyncEntity.document, remoteDocument('d1', status: 'paid'));
      await pumpApp(tester, owner(), remote: sync);
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-card')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Alles bezahlt'), findsOneWidget);
    });

    testApp('tapping an invoice opens it', (tester) async {
      await open(tester);
      await tester.tap(find.text('Müller'));
      await tester.pumpAndSettle();
      expect(find.text('PDF ansehen und senden'), findsOneWidget);
    });

    testApp('the list follows the date: a day later the same invoice is one day later', (tester) async {
      final sync = FakeSyncRemote()..seed(SyncEntity.document, remoteDocument('d1', number: 'RE-2026-0001', due: '2026-10-13'));
      await pumpApp(tester, owner(), remote: sync, documentsNow: DateTime(2026, 10, 20, 8));
      await tester.tap(find.text('Belege'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-card')));
      await tester.pumpAndSettle();
      expect(find.textContaining('seit 7 Tagen überfällig'), findsOneWidget);
    });
  });
}

/// Keeps the app handle and gives the tests a short name for it.
class FakeAppResult {
  FakeAppResult(this.app);
  final TestApp app;
}

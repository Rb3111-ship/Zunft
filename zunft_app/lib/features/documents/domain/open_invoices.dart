import '../../../core/database/app_database.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import 'document_data.dart';

/// An invoice that is not paid yet: how late it is (negative: days until it is due).
class OpenInvoice {
  const OpenInvoice(this.document, this.daysOverdue);

  final IssuedDocument document;

  /// Calendar days past the due date; 0 = due today; negative = not due yet.
  final int daysOverdue;

  bool get overdue => daysOverdue > 0;
  DateTime get due => dueDateOf(document);
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// The day the invoice had to be paid (an invoice always has one; the issue date if it is missing).
DateTime dueDateOf(IssuedDocument d) => _day(DateTime.parse(d.dateDue ?? d.dateIssued));

/// Calendar days from [from] to [to] (not 24-hour blocks: safe across a daylight-saving change).
int _daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// Unpaid invoices, the most overdue first, then by due date. Quotes, cancellations, paid and
/// canceled invoices are not open.
List<OpenInvoice> openInvoices(Iterable<IssuedDocument> documents, DateTime now) {
  final today = _day(now);
  final list = [
    for (final d in documents)
      if (d.docType == 'invoice' && (d.status == 'issued' || d.status == 'sent'))
        OpenInvoice(d, _daysBetween(dueDateOf(d), today)),
  ];
  list.sort((a, b) {
    final byLate = b.daysOverdue.compareTo(a.daysOverdue);
    return byLate != 0 ? byLate : a.document.docNumber.compareTo(b.document.docNumber);
  });
  return list;
}

class OpenSummary {
  const OpenSummary({required this.count, required this.openCents, required this.overdueCount, required this.overdueCents});

  final int count;
  final int openCents;
  final int overdueCount;
  final int overdueCents;
}

OpenSummary summarizeOpen(List<OpenInvoice> open) => OpenSummary(
      count: open.length,
      openCents: open.fold(0, (s, o) => s + o.document.totalGrossCents),
      overdueCount: open.where((o) => o.overdue).length,
      overdueCents: open.where((o) => o.overdue).fold(0, (s, o) => s + o.document.totalGrossCents),
    );

/// After this many days overdue the message is a little firmer (still polite).
const firmReminderAfterDays = 14;

/// How many days the customer gets to pay after a reminder.
const reminderGraceDays = 7;

/// The subject of the reminder (for the mail or the share sheet).
String paymentReminderSubject(IssuedDocument d) => 'Zahlungserinnerung zur Rechnung ${d.docNumber}';

/// A friendly payment reminder in German (it goes to the customer, so it is German whatever the
/// language of the app). No fees, no interest, no legal threats: this is not a Mahnung in the legal
/// sense. After [firmReminderAfterDays] days the tone is a little firmer.
String paymentReminderText({
  required OpenInvoice invoice,
  required CompanyDetails company,
  required DateTime now,
}) {
  final d = invoice.document;
  final today = _day(now);
  final payBy = DateFormatter.formatDate(today.add(const Duration(days: reminderGraceDays)));
  final amount = CurrencyFormatter.formatCents(d.totalGrossCents);
  final issued = DateFormatter.formatDate(DateTime.parse(d.dateIssued));
  final due = DateFormatter.formatDate(invoice.due);
  final late = invoice.daysOverdue;

  final intro = late > firmReminderAfterDays
      ? 'unsere Rechnung ${d.docNumber} vom $issued über $amount war am $due fällig und ist seit $late Tagen noch offen.'
      : 'zu unserer Rechnung ${d.docNumber} vom $issued über $amount (fällig am $due) konnten wir noch keinen Zahlungseingang feststellen.';
  final middle = late > firmReminderAfterDays
      ? 'Bitte überweisen Sie den Betrag bis zum $payBy. Falls Sie bereits gezahlt haben, betrachten Sie diese Nachricht bitte als gegenstandslos.'
      : 'Vielleicht ist die Zahlung schon unterwegs - dann betrachten Sie diese Nachricht bitte als gegenstandslos. Andernfalls bitten wir Sie, den Betrag bis zum $payBy zu überweisen.';

  final bank = [
    if (company.iban.trim().isNotEmpty) 'IBAN: ${company.iban.trim()}',
    if (company.bic.trim().isNotEmpty) 'BIC: ${company.bic.trim()}',
    if (company.bankName.trim().isNotEmpty) 'Bank: ${company.bankName.trim()}',
    'Kontoinhaber: ${company.name}',
    'Verwendungszweck: ${d.docNumber}',
  ];

  return [
    'Guten Tag,',
    '',
    '$intro $middle',
    '',
    ...bank,
    '',
    'Bei Fragen melden Sie sich gern${company.phone.isEmpty ? '' : ' unter ${company.phone}'}.',
    '',
    'Mit freundlichen Grüßen',
    company.name,
  ].join('\n');
}

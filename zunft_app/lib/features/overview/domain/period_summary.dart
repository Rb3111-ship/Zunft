import '../../../core/database/app_database.dart';
import '../../receipts/domain/receipt_entry.dart';

/// Sums per VAT rate.
class VatGroup {
  const VatGroup({required this.rate, required this.netCents, required this.vatCents, required this.count});

  final double rate;
  final int netCents;
  final int vatCents;
  final int count;

  int get grossCents => netCents + vatCents;
}

/// One month of a year.
class MonthRow {
  const MonthRow({required this.month, required this.count, required this.netCents, required this.vatCents});

  final int month;
  final int count;
  final int netCents;
  final int vatCents;

  int get grossCents => netCents + vatCents;
}

/// Plain sums of the issued invoices and the purchase receipts of a month or a year. Nothing here
/// is a tax figure: it adds up what is stored, by invoice date (not by payment date).
class PeriodSummary {
  const PeriodSummary({
    required this.year,
    required this.month,
    required this.invoiceCount,
    required this.cancellationCount,
    required this.netCents,
    required this.vatCents,
    required this.laborNetCents,
    required this.materialNetCents,
    required this.byRate,
    required this.paidGrossCents,
    required this.openGrossCents,
    required this.receiptCount,
    required this.receiptsGrossCents,
    required this.months,
  });

  final int year;

  /// null = the whole year.
  final int? month;

  /// Invoices issued in the period (without cancellations).
  final int invoiceCount;
  final int cancellationCount;

  /// Invoices plus cancellations (which are negative): what remains.
  final int netCents;
  final int vatCents;
  final int laborNetCents;
  final int materialNetCents;
  final List<VatGroup> byRate;

  /// Of the invoices of the period: paid / still open (cancelled ones count for neither).
  final int paidGrossCents;
  final int openGrossCents;

  final int receiptCount;

  /// The totals printed on the receipts of the period, as read from the photos.
  final int receiptsGrossCents;

  /// Month by month (only for a whole year).
  final List<MonthRow> months;

  int get grossCents => netCents + vatCents;
  bool get isEmpty => invoiceCount == 0 && cancellationCount == 0 && receiptCount == 0;
}

DateTime? _issued(IssuedDocument d) => DateTime.tryParse(d.dateIssued);

/// Adds up [documents] (invoices and cancellations; quotes are not revenue) and [receipts] of a
/// month, or of the whole year when [month] is null.
///
/// - A cancellation is a negative document, so it reduces the sum in the month it was issued.
/// - A cancelled invoice stays in its own month; the cancellation offsets it where it was issued.
/// - Quotes are ignored.
PeriodSummary summarize({
  required Iterable<IssuedDocument> documents,
  required Iterable<ReceiptEntry> receipts,
  required int year,
  int? month,
}) {
  bool inPeriod(DateTime d) => d.year == year && (month == null || d.month == month);

  final docs = <IssuedDocument>[
    for (final d in documents)
      if ((d.docType == 'invoice' || d.docType == 'cancellation') && _issued(d) != null && inPeriod(_issued(d)!)) d,
  ];

  var net = 0, vat = 0, labor = 0, material = 0, invoices = 0, cancellations = 0, paid = 0, open = 0;
  final rates = <double, List<int>>{}; // rate -> [net, vat, count]
  for (final d in docs) {
    net += d.totalNetCents;
    vat += d.vatAmountCents;
    labor += d.subtotalLaborCents;
    material += d.subtotalMaterialCents;
    final g = rates.putIfAbsent(d.vatRate, () => [0, 0, 0]);
    g[0] += d.totalNetCents;
    g[1] += d.vatAmountCents;
    g[2] += 1;
    if (d.docType == 'cancellation') {
      cancellations++;
    } else {
      invoices++;
      if (d.status == 'paid') paid += d.totalGrossCents;
      if (d.status == 'issued' || d.status == 'sent') open += d.totalGrossCents;
    }
  }

  final rows = <MonthRow>[];
  if (month == null) {
    for (var m = 1; m <= 12; m++) {
      final inMonth = docs.where((d) => _issued(d)!.month == m).toList();
      rows.add(MonthRow(
        month: m,
        count: inMonth.length,
        netCents: inMonth.fold<int>(0, (s, d) => s + d.totalNetCents),
        vatCents: inMonth.fold<int>(0, (s, d) => s + d.vatAmountCents),
      ));
    }
  }

  final rs = [for (final r in receipts) if (inPeriod(r.date)) r];

  return PeriodSummary(
    year: year,
    month: month,
    invoiceCount: invoices,
    cancellationCount: cancellations,
    netCents: net,
    vatCents: vat,
    laborNetCents: labor,
    materialNetCents: material,
    byRate: [
      for (final e in (rates.entries.toList()..sort((a, b) => b.key.compareTo(a.key))))
        VatGroup(rate: e.key, netCents: e.value[0], vatCents: e.value[1], count: e.value[2]),
    ],
    paidGrossCents: paid,
    openGrossCents: open,
    receiptCount: rs.length,
    receiptsGrossCents: rs.fold<int>(0, (s, r) => s + r.grossCents),
    months: rows,
  );
}

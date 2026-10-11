import 'dart:convert';
import 'dart:typed_data';

import '../../../core/database/app_database.dart';
import '../../appointments/domain/appointment_models.dart' show monthNames;
import '../../receipts/domain/receipt_export.dart';
import 'period_summary.dart';

String periodLabel(int year, int? month) => month == null ? '$year' : '${monthNames[month - 1]} $year';

String periodFileStem(int year, int? month) =>
    month == null ? 'uebersicht-$year' : 'uebersicht-$year-${month.toString().padLeft(2, '0')}';

String _rate(double r) => (r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString()).replaceAll('.', ',');

const periodDisclaimer = 'Zusammenstellung, keine Steuerberechnung. Maßgeblich sind die Rechnungen und Belege. '
    'Die Summen folgen dem Rechnungsdatum, nicht dem Zahlungseingang. Die Beträge der Einkaufsbelege wurden automatisch '
    'aus den Fotos gelesen.';

/// The overview as a CSV file (German format, opens in Excel): the sums first, then the invoices
/// of the period one per line.
Uint8List periodCsv(PeriodSummary s, List<IssuedDocument> documentsInPeriod) {
  final rows = <List<String>>[
    ['Zeitraum', periodLabel(s.year, s.month)],
    ['Rechnungen (Anzahl)', '${s.invoiceCount}'],
    ['Stornorechnungen (Anzahl)', '${s.cancellationCount}'],
    ['Netto', euroText(s.netCents)],
    ['Umsatzsteuer', euroText(s.vatCents)],
    ['Brutto', euroText(s.grossCents)],
    ['davon Arbeit netto', euroText(s.laborNetCents)],
    ['davon Material netto', euroText(s.materialNetCents)],
    for (final g in s.byRate)
      ['Steuersatz ${_rate(g.rate)} %', 'Netto ${euroText(g.netCents)}', 'Steuer ${euroText(g.vatCents)}', 'Belege ${g.count}'],
    ['Bezahlt (brutto)', euroText(s.paidGrossCents)],
    ['Offen (brutto)', euroText(s.openGrossCents)],
    ['Einkaufsbelege (Anzahl)', '${s.receiptCount}'],
    ['Einkaufsbelege laut Foto (brutto)', euroText(s.receiptsGrossCents)],
    [periodDisclaimer],
  ];
  if (s.months.isNotEmpty) {
    rows.add(['']);
    rows.add(['Monat', 'Anzahl', 'Netto', 'Steuer', 'Brutto']);
    for (final m in s.months) {
      rows.add([monthNames[m.month - 1], '${m.count}', euroText(m.netCents), euroText(m.vatCents), euroText(m.grossCents)]);
    }
  }
  final summary = csvText(rows);
  if (documentsInPeriod.isEmpty) return Uint8List.fromList(utf8.encode(summary));
  // The invoice list repeats the byte order mark of its own file: drop it.
  final list = documentsCsv(documentsInPeriod).replaceFirst('﻿', '');
  return Uint8List.fromList(utf8.encode('$summary\r\n$list'));
}

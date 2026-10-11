import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../appointments/domain/appointment_models.dart' show monthNames;
import '../../documents/application/document_providers.dart';
import '../../receipts/application/receipt_providers.dart';
import '../../receipts/domain/receipt_entry.dart';
import '../domain/period_export.dart';
import '../domain/period_summary.dart';

/// Monthly and yearly sums of the issued invoices and the receipts. Plain addition of what is
/// stored: no VAT-payable figure, no profit calculation.
class OverviewScreen extends ConsumerStatefulWidget {
  const OverviewScreen({super.key});

  @override
  ConsumerState<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends ConsumerState<OverviewScreen> {
  late int _year = DateTime.now().year;
  int? _month = DateTime.now().month; // null = the whole year

  void _move(int step) => setState(() {
        if (_month == null) {
          _year += step;
        } else {
          final d = DateTime(_year, _month! + step);
          _year = d.year;
          _month = d.month;
        }
      });

  String _eur(int cents) => CurrencyFormatter.formatCents(cents);

  String _rate(double r) => (r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString()).replaceAll('.', ',');

  Future<void> _share(PeriodSummary s, List<IssuedDocument> docs) async {
    final bytes = periodCsv(s, docs);
    try {
      await ref.read(fileSharerProvider).share(bytes, '${periodFileStem(_year, _month)}.csv',
          subject: 'Zunft Übersicht ${periodLabel(_year, _month)}', mimeType: 'text/csv');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Die Datei konnte nicht geteilt werden.')));
    }
  }

  Widget _card(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.toUpperCase(),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );

  Widget _line(String label, String value, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null))),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(issuedDocumentsProvider);
    final receiptsAsync = ref.watch(receiptArchiveProvider);
    final docs = docsAsync.valueOrNull ?? const <IssuedDocument>[];
    final receipts = receiptsAsync.valueOrNull ?? const <ReceiptEntry>[];
    final s = summarize(documents: docs, receipts: receipts, year: _year, month: _month);
    final inPeriod = [
      for (final d in docs)
        if ((d.docType == 'invoice' || d.docType == 'cancellation') &&
            (DateTime.tryParse(d.dateIssued)?.year == _year) &&
            (_month == null || DateTime.tryParse(d.dateIssued)?.month == _month))
          d,
    ]..sort((a, b) => a.dateIssued.compareTo(b.dateIssued));

    return Scaffold(
      appBar: AppBar(title: const Text('Übersicht')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Monat')),
                ButtonSegment(value: false, label: Text('Jahr')),
              ],
              selected: {_month != null},
              onSelectionChanged: (v) => setState(() => _month = v.first ? DateTime.now().month : null),
            ),
            Row(
              children: [
                IconButton(tooltip: 'Zurück', onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text(periodLabel(_year, _month),
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                IconButton(tooltip: 'Weiter', onPressed: () => _move(1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
            if (s.isEmpty && !docsAsync.isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('In diesem Zeitraum gibt es keine Rechnungen und keine Belege.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
              ),
            _card('Rechnungen', [
              _line('Anzahl', '${s.invoiceCount}${s.cancellationCount > 0 ? '  +  ${s.cancellationCount} Storno' : ''}'),
              _line('Netto', _eur(s.netCents)),
              if (s.byRate.isEmpty) _line('Umsatzsteuer', _eur(s.vatCents)),
              for (final g in s.byRate)
                _line(g.rate == 0 ? 'Umsatzsteuer (kein Ausweis, § 19 UStG)' : 'Umsatzsteuer ${_rate(g.rate)} %', _eur(g.vatCents)),
              const Divider(),
              _line('Brutto', _eur(s.grossCents), bold: true),
            ]),
            _card('Davon', [
              _line('Arbeit (netto)', _eur(s.laborNetCents)),
              _line('Material (netto)', _eur(s.materialNetCents)),
            ]),
            _card('Zahlung (Rechnungen dieses Zeitraums, brutto)', [
              _line('Bezahlt', _eur(s.paidGrossCents), color: AppTheme.accentGreen),
              _line('Noch offen', _eur(s.openGrossCents), color: s.openGrossCents > 0 ? AppTheme.accentAmber : null),
            ]),
            if (s.months.isNotEmpty)
              _card('Monat für Monat', [
                for (final m in s.months)
                  if (m.count > 0)
                    _line('${monthNames[m.month - 1]}  (${m.count})', 'netto ${_eur(m.netCents)}   brutto ${_eur(m.grossCents)}'),
                if (s.months.every((m) => m.count == 0)) const Text('Keine Rechnungen in diesem Jahr.'),
              ]),
            _card('Einkaufsbelege', [
              if (receiptsAsync.hasError)
                const Text('Die Belege konnten nicht geladen werden. Bitte Internetverbindung prüfen.',
                    style: TextStyle(color: AppTheme.accentAmber))
              else ...[
                _line('Anzahl', '${s.receiptCount}'),
                _line('Summe laut Foto (brutto)', _eur(s.receiptsGrossCents)),
              ],
            ]),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.accentAmber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: const Text(periodDisclaimer, style: TextStyle(fontSize: 12.5)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: s.isEmpty ? null : () => _share(s, inPeriod),
              icon: const Icon(Icons.ios_share),
              label: const Text('Als Datei teilen (CSV)'),
            ),
          ],
        ),
      ),
    );
  }
}

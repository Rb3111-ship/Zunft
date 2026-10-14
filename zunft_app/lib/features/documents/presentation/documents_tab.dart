import 'open_invoices_screen.dart';
import '../domain/open_invoices.dart';
import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/refresh_all.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../application/document_providers.dart';
import '../../receipts/presentation/receipts_archive.dart';
import 'document_detail_screen.dart';

String documentStatusLabel(String status) => switch (status) {
      'issued' => 'Erstellt'.tr,
      'sent' => 'Versendet'.tr,
      'paid' => 'Bezahlt'.tr,
      'canceled' => 'Storniert'.tr,
      _ => status,
    };

Color documentStatusColor(String status) => switch (status) {
      'issued' => AppTheme.accentAmber,
      'sent' => AppTheme.accentBlue,
      'paid' => AppTheme.accentGreen,
      _ => AppTheme.textSecondary,
    };

/// Does [d] match what the user typed? Looks at number, customer, title, status, date and amount,
/// every typed word must be found somewhere ("müller 2026", "0016", "bezahlt", "321,30").
bool documentMatches(IssuedDocument d, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final haystack = [
    d.docNumber,
    d.recipientName,
    d.title ?? '',
    documentStatusLabel(d.status),
    d.docType == 'quote' ? 'angebot' : (d.docType == 'cancellation' ? 'storno stornorechnung'.tr : 'rechnung'),
    DateFormatter.formatDate(DateTime.parse(d.dateIssued)),
    CurrencyFormatter.formatCents(d.totalGrossCents),
  ].join(' ').toLowerCase();
  return words.every(haystack.contains);
}

/// All issued quotes and invoices, newest first, with a search box.
class DocumentsTab extends ConsumerStatefulWidget {
  const DocumentsTab({super.key});

  @override
  ConsumerState<DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends ConsumerState<DocumentsTab> {
  final _search = TextEditingController();
  String _query = '';
  bool _showReceipts = false; // false: our documents (Rechnungen), true: purchase receipts (Einkaufsbelege)

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text('Rechnungen'.tr), icon: Icon(Icons.receipt_long_outlined)),
              ButtonSegment(value: true, label: Text('Einkaufsbelege'.tr), icon: Icon(Icons.shopping_bag_outlined)),
            ],
            selected: {_showReceipts},
            onSelectionChanged: (v) => setState(() => _showReceipts = v.first),
          ),
        ),
        Expanded(child: _showReceipts ? const ReceiptsArchive() : _documentsList()),
      ],
    );
  }

  Widget _documentsList() {
    final docs = ref.watch(issuedDocumentsProvider);

    return RefreshIndicator(
      onRefresh: () => refreshAll(ref),
      child: docs.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accentAmber)),
      error: (e, _) => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(issuedDocumentsProvider),
          child: Text('Belege konnten nicht geladen werden. Erneut versuchen'.tr),
        ),
      ),
      data: (all) {
        if (all.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Noch keine Belege. Diktiere einen Auftrag, prüfe den Entwurf und tippe auf „Fertigstellen“.'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          );
        }
        final shown = all.where((d) => documentMatches(d, _query)).toList();
        final open = openInvoices(all, ref.watch(documentsClockProvider)());
        final openSum = summarizeOpen(open);

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Card(
              key: const ValueKey('open-card'),
              color: AppTheme.primaryDark,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OpenInvoicesScreen())),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _metric('Offene Rechnungen'.tr, '${openSum.count}', AppTheme.accentBlue),
                      Container(height: 36, width: 1, color: AppTheme.dividerColor),
                      _metric('Offener Betrag'.tr, CurrencyFormatter.formatCents(openSum.openCents), AppTheme.accentAmber),
                      if (openSum.overdueCount > 0) ...[
                        Container(height: 36, width: 1, color: AppTheme.dividerColor),
                        _metric('Überfällig'.tr, '${openSum.overdueCount}', AppTheme.accentRed),
                      ],
                      const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Suchen: Nummer, Kunde, Datum, Betrag...'.tr,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Suche löschen'.tr,
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nichts gefunden.'.tr,
                    textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
              ),
            for (final d in shown) _tile(context, d),
          ],
        );
      },
    ));
  }

  Widget _metric(String label, String value, Color color) => Column(
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        ],
      );

  Widget _tile(BuildContext context, IssuedDocument d) {
    final color = documentStatusColor(d.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(d.docNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(d.recipientName, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            Text(
                '${d.docType == 'cancellation' ? 'Stornorechnung'.tr + ' - ' : ''}${DateFormatter.formatDate(DateTime.parse(d.dateIssued))}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
              child: Text(documentStatusLabel(d.status),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(CurrencyFormatter.formatCents(d.totalGrossCents),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary),
          ],
        ),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentDetailScreen(documentId: d.id))),
      ),
    );
  }
}

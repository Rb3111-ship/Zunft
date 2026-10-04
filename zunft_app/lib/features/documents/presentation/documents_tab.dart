import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../application/document_providers.dart';
import 'document_detail_screen.dart';

String documentStatusLabel(String status) => switch (status) {
      'issued' => 'Erstellt',
      'sent' => 'Versendet',
      'paid' => 'Bezahlt',
      'canceled' => 'Storniert',
      _ => status,
    };

Color documentStatusColor(String status) => switch (status) {
      'issued' => AppTheme.accentAmber,
      'sent' => AppTheme.accentBlue,
      'paid' => AppTheme.accentGreen,
      _ => AppTheme.textSecondary,
    };

/// All issued quotes and invoices, newest first.
class DocumentsTab extends ConsumerWidget {
  const DocumentsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(issuedDocumentsProvider);

    return docs.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accentAmber)),
      error: (e, _) => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(issuedDocumentsProvider),
          child: const Text('Belege konnten nicht geladen werden. Erneut versuchen'),
        ),
      ),
      data: (all) {
        if (all.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Noch keine Belege. Diktiere einen Auftrag, prüfe den Entwurf und tippe auf „Fertigstellen“.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          );
        }
        final openInvoices = all.where((d) => d.docType == 'invoice' && (d.status == 'issued' || d.status == 'sent'));
        final openCents = openInvoices.fold<int>(0, (sum, d) => sum + d.totalGrossCents);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Card(
              color: AppTheme.primaryDark,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metric('Offene Rechnungen', '${openInvoices.length}', AppTheme.accentBlue),
                    Container(height: 36, width: 1, color: AppTheme.dividerColor),
                    _metric('Offener Betrag', CurrencyFormatter.formatCents(openCents), AppTheme.accentAmber),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            for (final d in all) _tile(context, d),
          ],
        );
      },
    );
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
            Text(DateFormatter.formatDate(DateTime.parse(d.dateIssued)),
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

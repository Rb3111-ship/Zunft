import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../jobs/presentation/note_replay.dart' show ReceiptViewScreen;
import '../domain/receipt_entry.dart';

/// One receipt: what was read from it, which job and invoice it belongs to, and the photo.
class ReceiptDetailScreen extends StatelessWidget {
  const ReceiptDetailScreen({super.key, required this.receipt});

  final ReceiptEntry receipt;

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    String qty(double q) => (q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString()).replaceAll('.', ',');

    return Scaffold(
      appBar: AppBar(title: Text(r.supplierLabel, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row('Belegdatum'.tr, r.receiptDate == null ? 'nicht lesbar'.tr : DateFormatter.formatDate(r.receiptDate!)),
                  if ((r.receiptNumber ?? '').isNotEmpty) _row('Belegnummer'.tr, r.receiptNumber!),
                  _row('Auftrag'.tr, r.jobTitle ?? '–'),
                  _row('Status'.tr, r.statusLabel),
                  _row('Erfasst von'.tr, '${r.authorName ?? '–'}, ${DateFormatter.formatDateTime(r.createdAt)}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (final l in r.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Text('${qty(l.quantity)} ${l.unit}  ${l.description}', style: const TextStyle(fontSize: 13))),
                          const SizedBox(width: 8),
                          Text(CurrencyFormatter.formatCents(l.totalNetCents),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                    ),
                  const Divider(color: AppTheme.dividerColor),
                  _row('Positionen netto'.tr, CurrencyFormatter.formatCents(r.netCents)),
                  if (r.totalPrintedCents != null)
                    _row('Gesamtbetrag laut Beleg'.tr, CurrencyFormatter.formatCents(r.totalPrintedCents!), bold: true),
                ],
              ),
            ),
          ),
          if (r.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Hinweis: {0}'.trf([r.warnings.join('; ')]),
                style: const TextStyle(color: AppTheme.accentAmber, fontSize: 12.5)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => ReceiptViewScreen(imagePath: r.imagePath))),
            icon: const Icon(Icons.image_outlined),
            label: Text('Foto öffnen'.tr),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          ),
          const SizedBox(height: 10),
          Text('Die Beträge wurden automatisch aus dem Foto gelesen. Maßgeblich ist immer das Foto.'.tr,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, fontSize: bold ? 15 : 13)),
            ),
          ],
        ),
      );
}

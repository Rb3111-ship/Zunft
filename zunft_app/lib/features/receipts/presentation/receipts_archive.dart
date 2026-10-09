import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart' show IssuedDocument;
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../documents/application/document_providers.dart';
import '../application/receipt_providers.dart';
import '../data/receipts_remote.dart';
import '../domain/receipt_entry.dart';
import '../domain/receipt_export.dart';
import 'receipt_detail_screen.dart';

/// All receipts (Einkaufsbelege) of the business, whatever job they belong to: search, filter by
/// month, and export as a ZIP for the tax advisor.
class ReceiptsArchive extends ConsumerStatefulWidget {
  const ReceiptsArchive({super.key});

  @override
  ConsumerState<ReceiptsArchive> createState() => _ReceiptsArchiveState();
}

class _ReceiptsArchiveState extends ConsumerState<ReceiptsArchive> {
  final _search = TextEditingController();
  String _query = '';
  String? _month; // "2026-10" or null = all
  bool _exporting = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _export(List<ReceiptEntry> shown) async {
    setState(() => _exporting = true);
    try {
      final remote = ref.read(receiptsRemoteProvider);
      final all = ref.read(issuedDocumentsProvider).valueOrNull ?? const <IssuedDocument>[];
      final docs = [
        for (final d in all)
          if (_month == null || d.dateIssued.startsWith(_month!)) d
      ]..sort((a, b) => a.dateIssued.compareTo(b.dateIssued));
      final label = _month == null ? 'alle Belege' : monthLabel(_month!);

      final result = await buildReceiptExport(
        receipts: shown,
        documents: docs,
        fetchPhoto: remote.downloadPhoto,
        periodLabel: label,
      );
      await ref.read(fileSharerProvider).share(
            result.zip,
            'Zunft_Belege_${_month ?? 'alle'}.zip',
            subject: 'Zunft: Belege $label',
          );
      if (mounted && result.missingPhotos > 0) {
        _snack('${result.missingPhotos} Foto(s) konnten nicht geladen werden und fehlen im Export.');
      }
    } catch (_) {
      _snack('Der Export ist fehlgeschlagen. Bitte Internetverbindung prüfen und erneut versuchen.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final archive = ref.watch(receiptArchiveProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(receiptArchiveProvider),
      child: archive.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accentAmber)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e is ReceiptsException ? e.message : 'Die Belege konnten nicht geladen werden.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () => ref.invalidate(receiptArchiveProvider), child: const Text('Erneut versuchen')),
              ],
            ),
          ),
        ),
        data: (all) {
          if (all.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Noch keine Einkaufsbelege. Fotografiere einen Beleg in einem Auftrag („Beleg fotografieren oder hochladen“), dann erscheint er hier.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              ],
            );
          }
          final months = {for (final r in all) r.monthKey}.toList()..sort((a, b) => b.compareTo(a));
          final month = months.contains(_month) ? _month : null;
          final shown = all.where((r) => (month == null || r.monthKey == month) && receiptMatches(r, _query)).toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          final sum = shown.fold<int>(0, (s, r) => s + r.grossCents);

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              Card(
                color: AppTheme.primaryDark,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _metric('Belege', '${shown.length}', AppTheme.accentBlue),
                      Container(height: 36, width: 1, color: AppTheme.dividerColor),
                      _metric('Summe laut Beleg', CurrencyFormatter.formatCents(sum), AppTheme.accentAmber),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Suchen: Lieferant, Auftrag, Nummer, Betrag...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Suche löschen',
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
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey('month-$month'),
                      initialValue: month,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Monat', border: OutlineInputBorder(), isDense: true),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Alle Monate')),
                        for (final m in months) DropdownMenuItem<String?>(value: m, child: Text(monthLabel(m))),
                      ],
                      onChanged: (v) => setState(() => _month = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _exporting || shown.isEmpty ? null : () => _export(shown),
                    icon: _exporting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.ios_share, size: 18),
                    label: const Text('Exportieren'),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Der Export (ZIP) enthält die angezeigten Belege als Fotos und Liste (CSV) sowie die ausgestellten Rechnungen des Monats.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nichts gefunden.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
                ),
              for (final r in shown) _tile(context, r),
            ],
          );
        },
      ),
    );
  }

  Widget _metric(String label, String value, Color color) => Column(
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        ],
      );

  Widget _tile(BuildContext context, ReceiptEntry r) {
    final color = switch (r.status) {
      ReceiptStatus.open => AppTheme.accentAmber,
      ReceiptStatus.billed => AppTheme.accentGreen,
      ReceiptStatus.removed => AppTheme.textSecondary,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(Icons.receipt_long, color: AppTheme.accentAmber),
        title: Text(r.supplierLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${DateFormatter.formatDate(r.date)}${r.jobTitle == null ? '' : ' - ${r.jobTitle}'}',
                style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
              child: Text(r.statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            ),
          ],
        ),
        trailing: Text(CurrencyFormatter.formatCents(r.grossCents),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptDetailScreen(receipt: r))),
      ),
    );
  }
}

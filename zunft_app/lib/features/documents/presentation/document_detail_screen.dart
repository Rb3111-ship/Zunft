import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/refresh_all.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../auth/application/auth_providers.dart';
import '../application/document_providers.dart';
import '../data/documents_remote.dart';
import '../domain/document_data.dart';
import 'documents_tab.dart';
import 'pdf_preview_screen.dart';

/// One issued document: what it says, its status, and the PDF.
class DocumentDetailScreen extends ConsumerStatefulWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  ConsumerState<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  bool _busy = false;

  /// One id per cancellation attempt: if the connection drops and the user taps again, the server
  /// returns the same Stornorechnung instead of issuing a second number.
  String? _cancelId;

  Future<void> _openPdf(IssuedDocument doc) async {
    final business = ref.read(businessProvider).valueOrNull;
    if (business == null) return _snack('Die Betriebsdaten werden noch geladen.');
    setState(() => _busy = true);
    try {
      final service = await ref.read(documentServiceProvider.future);
      final bytes = await service.pdfFor(doc, business);
      final customerId = doc.customerId;
      final customer = customerId == null ? null : await ref.read(customerEmailLookupProvider)(customerId);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfPreviewScreen(
            pdfBytes: bytes,
            documentTitle: '${doc.docNumber} - ${doc.recipientName}',
            customerEmail: customer,
            shareSubject: shareSubject(doc, business),
            shareBody: shareBody(doc, business),
            onShared: doc.status == 'issued' ? () => service.markStatus(doc.id, 'sent').catchError((_) {}) : null,
          ),
        ),
      );
    } catch (_) {
      _snack('Das PDF konnte nicht erstellt werden.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelInvoice(IssuedDocument doc) async {
    final business = ref.read(businessProvider).valueOrNull;
    if (business == null) return _snack('Die Betriebsdaten werden noch geladen.');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${doc.docNumber} stornieren?'),
        content: const Text(
          'Es wird eine Stornorechnung mit eigener Nummer erstellt, die diese Rechnung aufhebt. '
          'Die Rechnung selbst bleibt unverändert gespeichert und wird als „Storniert“ markiert.\n\n'
          'Die Notizen des Auftrags werden wieder frei. Danach kannst du den Auftrag erneut prüfen, '
          'korrigieren und eine neue Rechnung erstellen.\n\n'
          'Das kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Stornieren', style: TextStyle(color: AppTheme.accentRed))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final service = await ref.read(documentServiceProvider.future);
      final result = await service.cancelInvoice(doc, business, _cancelId ??= const Uuid().v4());
      _cancelId = null;
      refreshAll(ref); // the job is open again on the server
      final cancellation = result.document;
      final customerId = cancellation.customerId;
      final email = customerId == null ? null : await ref.read(customerEmailLookupProvider)(customerId);
      if (!mounted) return;
      _snack('${cancellation.docNumber} wurde erstellt. Die Notizen des Auftrags sind wieder offen.');
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfPreviewScreen(
            pdfBytes: result.pdf,
            documentTitle: '${cancellation.docNumber} - ${cancellation.recipientName}',
            customerEmail: email,
            shareSubject: shareSubject(cancellation, business),
            shareBody: shareBody(cancellation, business),
            onShared: () => service.markStatus(cancellation.id, 'sent').catchError((_) {}),
          ),
        ),
      );
    } on DocumentOfflineException {
      _snack('Keine Verbindung. Bitte später noch einmal versuchen.');
    } on DocumentRejectedException catch (e) {
      _cancelId = null;
      _snack(e.message);
    } catch (_) {
      _snack('Die Rechnung konnte nicht storniert werden.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(IssuedDocument doc, String status) async {
    setState(() => _busy = true);
    try {
      final service = await ref.read(documentServiceProvider.future);
      await service.markStatus(doc.id, status);
    } on DocumentOfflineException {
      _snack('Keine Verbindung. Der Status kann nur online geändert werden.');
    } on DocumentRejectedException {
      _snack('Der Status konnte nicht geändert werden.');
    } catch (_) {
      _snack('Der Status konnte nicht geändert werden.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(issuedDocumentsProvider).valueOrNull ?? const <IssuedDocument>[];
    final doc = docs.where((d) => d.id == widget.documentId).firstOrNull;

    if (doc == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Beleg')),
          body: const Center(child: Text('Dieser Beleg ist nicht mehr vorhanden.')));
    }

    final lines = (jsonDecode(doc.lineItemsJson) as List<dynamic>)
        .map((e) => DocumentLine.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final isInvoice = doc.docType == 'invoice';
    final isCancellation = doc.docType == 'cancellation';
    final color = documentStatusColor(doc.status);

    return Scaffold(
      appBar: AppBar(title: Text(doc.docNumber)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text(documentKindLabel(doc.docType),
                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration:
                            BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                        child: Text(documentStatusLabel(doc.status),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(doc.recipientName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  if ((doc.recipientAddress ?? '').isNotEmpty)
                    Text(doc.recipientAddress!, style: const TextStyle(color: AppTheme.textSecondary)),
                  if ((doc.title ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(doc.title!, style: const TextStyle(fontStyle: FontStyle.italic)),
                  ],
                  const SizedBox(height: 10),
                  _row('Datum', DateFormatter.formatDate(DateTime.parse(doc.dateIssued))),
                  if (doc.dateDue != null)
                    _row(isInvoice ? 'Zahlbar bis' : 'Gültig bis',
                        DateFormatter.formatDate(DateTime.parse(doc.dateDue!))),
                  if (isInvoice && (doc.deliveryPeriod ?? '').isNotEmpty)
                    _row('Leistungszeitraum', doc.deliveryPeriod!),
                  if (doc.eInvoice) _row('E-Rechnung', 'Ja (ZUGFeRD, EN 16931)'),
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
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Text('${_qty(l.quantity)} ${l.unit}  ${l.description}',
                                  style: const TextStyle(fontSize: 13))),
                          const SizedBox(width: 8),
                          Text(CurrencyFormatter.formatCents(l.totalNetCents),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                    ),
                  const Divider(color: AppTheme.dividerColor),
                  _row('Netto', CurrencyFormatter.formatCents(doc.totalNetCents)),
                  _row(doc.vatRate == 0 ? 'Umsatzsteuer (§ 19 UStG)' : 'MwSt. ${_rate(doc.vatRate)} %',
                      CurrencyFormatter.formatCents(doc.vatAmountCents)),
                  _row('Gesamt', CurrencyFormatter.formatCents(doc.totalGrossCents), bold: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : () => _openPdf(doc),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('PDF ansehen und senden'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          ),
          const SizedBox(height: 10),
          if (doc.status == 'issued')
            OutlinedButton(
                onPressed: _busy ? null : () => _setStatus(doc, 'sent'), child: const Text('Als versendet markieren')),
          if (isInvoice && (doc.status == 'issued' || doc.status == 'sent'))
            OutlinedButton(
                onPressed: _busy ? null : () => _setStatus(doc, 'paid'), child: const Text('Als bezahlt markieren')),
          if (isInvoice && (doc.status == 'issued' || doc.status == 'sent'))
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _cancelInvoice(doc),
              icon: const Icon(Icons.undo, color: AppTheme.accentRed),
              label: const Text('Rechnung stornieren', style: TextStyle(color: AppTheme.accentRed)),
            ),
          if (isInvoice && doc.status == 'canceled')
            const Text(
              'Diese Rechnung wurde storniert. Die zugehörige Stornorechnung steht unter Belege.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.accentRed),
            ),
          if (isCancellation)
            const Text(
              'Diese Stornorechnung hebt die im Titel genannte Rechnung auf.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          if (isInvoice && doc.status == 'paid')
            const Text(
              'Bezahlte Rechnungen können nicht storniert werden. Bitte mit dem Steuerberater klären, wie sie korrigiert wird.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          const SizedBox(height: 12),
          const Text(
            'Dieses Dokument ist festgeschrieben und kann nicht mehr geändert werden. Für Korrekturen wird ein neues Dokument erstellt.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  static String _qty(double q) => (q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString()).replaceAll('.', ',');
  static String _rate(double r) => (r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString()).replaceAll('.', ',');

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            Text(value,
                style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, fontSize: bold ? 16 : 13)),
          ],
        ),
      );
}

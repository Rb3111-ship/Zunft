import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/trade_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/data/business_models.dart';
import '../../auth/presentation/business_settings_screen.dart';
import '../../documents/application/document_providers.dart';
import '../../documents/data/document_service.dart';
import '../../documents/data/documents_remote.dart';
import '../../documents/domain/document_data.dart';
import '../../documents/pdf_generator/din_5008_invoice_template.dart';
import '../../documents/presentation/pdf_preview_screen.dart';
import '../../jobs/application/job_notes_providers.dart';
import '../../jobs/presentation/note_replay.dart';
import '../models/draft_models.dart';

/// Review and correct the draft of a whole job (all its open notes), then finalize it into ONE
/// numbered quote or invoice.
class ReviewDraftScreen extends ConsumerStatefulWidget {
  final DraftDocument draft;

  /// The job's notes that went into this draft. The server marks them as used when the document
  /// is issued, so they do not show up again.
  final List<String> noteIds;

  const ReviewDraftScreen({super.key, required this.draft, this.noteIds = const []});

  @override
  ConsumerState<ReviewDraftScreen> createState() => _ReviewDraftScreenState();
}

class _ReviewDraftScreenState extends ConsumerState<ReviewDraftScreen> {
  late DraftDocument _draft;
  bool _showTranscript = false;
  bool _busy = false;

  /// One id per screen: if finalizing is retried after a dropped connection, the server
  /// recognises it and returns the same document instead of issuing a second number.
  final String _documentId = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    _showTranscript = _draft.sources.isNotEmpty; // job documents: show what was understood right away
  }

  @override
  Widget build(BuildContext context) {
    final business = ref.watch(businessProvider).valueOrNull;
    if (business != null) _draft.vatRate = business.defaultVatRate;

    final summary = _draft.financialSummary;
    final isInvoice = _draft.documentType == 'invoice';

    return Scaffold(
      appBar: AppBar(title: Text(isInvoice ? 'Rechnung prüfen' : 'Angebot prüfen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if ((_draft.rawTranscript ?? '').isNotEmpty) _transcriptCard(),
          if (_draft.warnings.isNotEmpty) _warningsCard(),
          const SizedBox(height: 12),
          _customerCard(),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'POSITIONEN',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppTheme.textSecondary),
              ),
              TextButton.icon(
                onPressed: _addNewItem,
                icon: const Icon(Icons.add, size: 16, color: AppTheme.accentAmber),
                label: const Text('Hinzufügen', style: TextStyle(color: AppTheme.accentAmber)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final (index, item) in _draft.lineItems.indexed) _itemCard(index, item),
          const SizedBox(height: 16),
          _summaryCard(summary),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _finalize,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.check_circle_outline),
            label: Text(isInvoice ? 'Rechnung fertigstellen' : 'Angebot fertigstellen'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 4),
          const Text(
            'Dabei wird die Nummer vergeben. Danach kann das Dokument nicht mehr geändert werden.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _preview,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Vorschau als PDF (Entwurf)'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _draft.documentType = isInvoice ? 'quote' : 'invoice'),
            child: Text(isInvoice ? 'In Angebot umwandeln' : 'In Rechnung umwandeln'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ---- cards -----------------------------------------------------------------------------

  Widget _transcriptCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.mic, color: AppTheme.accentAmber, size: 20),
                  const SizedBox(width: 8),
                  const Text('Notizen verstanden', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _showTranscript = !_showTranscript),
                    child: Text(_showTranscript ? 'Verbergen' : 'Anzeigen'),
                  ),
                ],
              ),
              if (_showTranscript) ...[
                const Divider(color: AppTheme.dividerColor),
                if (_draft.sources.isEmpty)
                  Text(
                    '"${_draft.rawTranscript}"',
                    style: const TextStyle(color: AppTheme.textSecondary, fontStyle: FontStyle.italic, fontSize: 13),
                  )
                else
                  for (final s in _draft.sources)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: NoteReplay(author: s.author, transcript: s.transcript, audioPath: s.audioPath),
                    ),
              ],
            ],
          ),
        ),
      );

  Widget _warningsCard() => Card(
        color: AppTheme.accentAmber.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber, color: AppTheme.accentAmber, size: 20),
                  SizedBox(width: 8),
                  Text('Bitte prüfen', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              for (final w in _draft.warnings) Text('• $w', style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      );

  Widget _customerCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.primaryDark, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.person, color: AppTheme.accentAmber),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('KUNDE',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(
                      _draft.customer.extractedName.isEmpty ? 'Noch kein Kunde' : _draft.customer.extractedName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if ((_draft.customer.extractedAddress ?? '').isNotEmpty)
                      Text(_draft.customer.extractedAddress!,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    if (_draft.customer.matchedCustomerId != null)
                      const Row(children: [
                        Icon(Icons.check_circle, size: 14, color: AppTheme.accentGreen),
                        SizedBox(width: 4),
                        Text('Kunde aus dem Auftrag', style: TextStyle(fontSize: 12, color: AppTheme.accentGreen)),
                      ])
                    else if (_draft.customer.extractedName.isEmpty)
                      const Row(children: [
                        Icon(Icons.info_outline, size: 14, color: AppTheme.accentAmber),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text('Dem Auftrag ist kein Kunde zugeordnet - bitte eintragen.',
                              style: TextStyle(fontSize: 12, color: AppTheme.accentAmber)),
                        ),
                      ])
                    else
                      const Row(children: [
                        Icon(Icons.info_outline, size: 14, color: AppTheme.accentAmber),
                        SizedBox(width: 4),
                        Text('Neuer Kunde', style: TextStyle(fontSize: 12, color: AppTheme.accentAmber)),
                      ]),
                    if (_draft.customer.extractedName.isEmpty && (_draft.customerHintName ?? '').isNotEmpty)
                      TextButton(
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero, minimumSize: const Size(0, 30), alignment: Alignment.centerLeft),
                        onPressed: () => setState(() {
                          _draft.customer.extractedName = _draft.customerHintName!;
                          _draft.customer.extractedAddress ??= _draft.customerHintAddress;
                        }),
                        child: Text('In der Notiz genannt: "${_draft.customerHintName}" - übernehmen?',
                            style: const TextStyle(fontSize: 12.5)),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Kunden anpassen',
                icon: const Icon(Icons.edit, color: AppTheme.textSecondary, size: 20),
                onPressed: _editCustomer,
              ),
            ],
          ),
        ),
      );

  Widget _itemCard(int index, DraftLineItem item) {
    final service = item.type == 'labor' || item.type == 'flat_fee';
    final color = service ? AppTheme.accentAmber : AppTheme.accentBlue;
    final label = switch (item.type) {
      'labor' => 'Arbeitslohn (§ 35a)',
      'flat_fee' => 'Pauschale (§ 35a)',
      _ => 'Material',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color, width: 0.8),
                  ),
                  child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                ),
                const Spacer(),
                Text(CurrencyFormatter.formatCents(item.totalNetCents),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(item.description, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Flexible(
                  child: Text(
                    '${_formatQty(item.quantity)} ${item.unit} à ${CurrencyFormatter.formatCents(item.unitPriceNetCents)}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ),
                if (item.requiresConfirmation) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppTheme.accentAmber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                    child: const Row(children: [
                      Icon(Icons.warning_amber, size: 12, color: AppTheme.accentAmber),
                      SizedBox(width: 4),
                      Text('Preis prüfen',
                          style: TextStyle(fontSize: 11, color: AppTheme.accentAmber, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ],
                const Spacer(),
                IconButton(
                  tooltip: 'Position bearbeiten',
                  icon: const Icon(Icons.edit, size: 18, color: AppTheme.textSecondary),
                  onPressed: () => _editItem(index),
                ),
                IconButton(
                  tooltip: 'Position löschen',
                  icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.accentRed),
                  onPressed: () => setState(() => _draft.lineItems.removeAt(index)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(FinancialSummary summary) {
    final smallBusiness = summary.vatRate == 0;
    return Card(
      color: AppTheme.primaryDark,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _summaryRow('Lohnanteil (§ 35a EStG):', CurrencyFormatter.formatCents(summary.subtotalLaborCents)),
            const SizedBox(height: 6),
            _summaryRow('Materialanteil:', CurrencyFormatter.formatCents(summary.subtotalMaterialCents)),
            const Divider(color: AppTheme.dividerColor, height: 16),
            _summaryRow('Zwischensumme netto:', CurrencyFormatter.formatCents(summary.totalNetCents)),
            const SizedBox(height: 6),
            _summaryRow(
              smallBusiness ? 'Umsatzsteuer (§ 19 UStG):' : 'zzgl. ${_formatRate(summary.vatRate)} % MwSt.:',
              CurrencyFormatter.formatCents(summary.vatAmountCents),
            ),
            const Divider(color: AppTheme.dividerColor, height: 16),
            _summaryRow('Gesamtbetrag (brutto):', CurrencyFormatter.formatCents(summary.totalGrossCents),
                isBold: true, fontSize: 18, color: AppTheme.accentAmber),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isBold = false, double fontSize = 14, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(label,
              style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  color: color ?? AppTheme.textSecondary)),
        ),
        Text(value,
            style: TextStyle(
                fontSize: fontSize,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: color ?? AppTheme.textPrimary)),
      ],
    );
  }

  static String _formatQty(double q) =>
      (q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString()).replaceAll('.', ',');
  static String _formatRate(double r) =>
      (r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString()).replaceAll('.', ',');

  // ---- editing ---------------------------------------------------------------------------

  Future<void> _editCustomer() async {
    final result = await showDialog<({String name, String address})>(
      context: context,
      builder: (_) =>
          _CustomerDialog(name: _draft.customer.extractedName, address: _draft.customer.extractedAddress ?? ''),
    );
    if (result == null) return;
    setState(() {
      _draft.customer.extractedName = result.name;
      _draft.customer.extractedAddress = result.address.isEmpty ? null : result.address;
    });
  }

  Future<void> _editItem(int index) async {
    final result = await showDialog<DraftLineItem>(
        context: context, builder: (_) => _ItemDialog(item: _draft.lineItems[index], title: 'Position bearbeiten'));
    if (result != null) setState(() => _draft.lineItems[index] = result);
  }

  Future<void> _addNewItem() async {
    final blank = DraftLineItem(
        id: const Uuid().v4(), type: 'material', description: '', quantity: 1, unit: 'Stk', unitPriceNetCents: 0);
    final result = await showDialog<DraftLineItem>(
        context: context, builder: (_) => _ItemDialog(item: blank, title: 'Neue Position'));
    if (result != null) setState(() => _draft.lineItems.add(result));
  }

  // ---- preview and finalize --------------------------------------------------------------

  Future<void> _preview() async {
    final business = ref.read(businessProvider).valueOrNull;
    if (business == null) return _info('Die Betriebsdaten werden noch geladen.');
    final bytes = await Din5008PdfGenerator.generate(
      PdfDocumentData.preview(draft: _draft, business: business, issueDate: DateTime.now()),
    );
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PdfPreviewScreen(
              pdfBytes: bytes, documentTitle: 'Vorschau - ${_draft.customer.extractedName}', showActions: false)),
    );
  }

  Future<void> _finalize() async {
    final business = ref.read(businessProvider).valueOrNull;
    if (business == null) return _info('Die Betriebsdaten werden noch geladen.');

    final reason = DocumentService.blockReason(_draft, business);
    if (reason != null) return _blocked(reason, business);

    final choices = await showDialog<_FinalizeChoices>(
      context: context,
      builder: (_) => _FinalizeDialog(draft: _draft, business: business),
    );
    if (choices == null || !mounted) return;

    setState(() => _busy = true);
    FinalizeResult? result;
    DocumentService? service;
    String? blockedMessage;
    String? problem;
    try {
      final svc = await ref.read(documentServiceProvider.future);
      service = svc;
      result = await svc.finalize(FinalizeRequest(
        documentId: _documentId,
        draft: _draft,
        business: business,
        issueDate: DateTime.now(),
        paymentDays: choices.days,
        deliveryPeriod: choices.deliveryPeriod,
        createCustomer: choices.createCustomer,
        captureLogIds: widget.noteIds,
      ));
    } on FinalizeBlocked catch (e) {
      blockedMessage = e.message;
    } on DocumentOfflineException {
      problem =
          'Keine Verbindung. Zum Fertigstellen wird Internet gebraucht, weil die Nummer vom Server vergeben wird. '
          'Deine Änderungen bleiben erhalten - bitte später noch einmal versuchen.';
    } on DocumentAuthException {
      problem = 'Bitte melde dich erneut an.';
    } on DocumentRejectedException catch (e) {
      problem = e.message;
    } catch (_) {
      problem = 'Das hat leider nicht geklappt. Bitte später erneut versuchen.';
    }

    // Stop the spinner BEFORE any dialog: a dialog is awaited until the user closes it.
    if (!mounted) return;
    setState(() => _busy = false);

    if (blockedMessage != null) return _blocked(blockedMessage, business);
    if (problem != null) return _info(problem);

    final jobId = _draft.jobId;
    if (jobId != null) ref.invalidate(jobNotesProvider(jobId)); // the used notes are gone from the job

    final issued = result!.document;
    final pdf = result.pdf;
    final finalizer = service!;
    final messenger = ScaffoldMessenger.of(context);
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          pdfBytes: pdf,
          documentTitle: '${issued.docNumber} - ${issued.recipientName}',
          onShared: () => finalizer.markStatus(issued.id, 'sent').catchError((_) {}),
        ),
      ),
    );
    messenger.showSnackBar(SnackBar(content: Text('${issued.docNumber} erstellt.')));
  }

  Future<void> _blocked(String message, Business business) async {
    final missingBusiness = _draft.documentType == 'invoice' && business.missingInvoiceFields.any((f) => f != 'IBAN');
    final profile = ref.read(profileProvider).valueOrNull;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Noch nicht möglich'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('OK')),
          if (missingBusiness)
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Betriebsdaten öffnen')),
        ],
      ),
    );
    if (open == true && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => BusinessSettingsScreen(business: business, canEdit: profile?.canEditBusiness ?? false)),
      );
    }
  }

  Future<void> _info(String message) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
}

// ---------------------------------------------------------------------------------------------
// Dialogs. Each owns and disposes its own controllers.
// ---------------------------------------------------------------------------------------------

class _CustomerDialog extends StatefulWidget {
  const _CustomerDialog({required this.name, required this.address});
  final String name;
  final String address;

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.name);
  late final TextEditingController _address = TextEditingController(text: widget.address);

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kunden anpassen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name des Kunden')),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Anschrift', hintText: 'Straße Nr., PLZ Ort'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (name: _name.text.trim(), address: _address.text.trim())),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class _ItemDialog extends StatefulWidget {
  const _ItemDialog({required this.item, required this.title});
  final DraftLineItem item;
  final String title;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final TextEditingController _desc = TextEditingController(text: widget.item.description);
  late final TextEditingController _qty = TextEditingController(text: _fmt(widget.item.quantity));
  late final TextEditingController _price =
      TextEditingController(text: (widget.item.unitPriceNetCents / 100).toStringAsFixed(2).replaceAll('.', ','));
  late String _type = widget.item.type;
  late String _unit = widget.item.unit;
  String? _error;

  static String _fmt(double q) => (q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString()).replaceAll('.', ',');

  @override
  void dispose() {
    _desc.dispose();
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    final qty = double.tryParse(_qty.text.trim().replaceAll(',', '.'));
    final price = CurrencyFormatter.parseToCents(_price.text);
    if (_desc.text.trim().isEmpty) return setState(() => _error = 'Bitte eine Bezeichnung eingeben.');
    if (qty == null || qty <= 0) return setState(() => _error = 'Bitte eine gültige Menge eingeben (z.B. 1,5).');
    if (price == null) return setState(() => _error = 'Bitte einen gültigen Preis eingeben (z.B. 68,50).');

    Navigator.pop(
      context,
      DraftLineItem(
        id: widget.item.id,
        type: _type,
        description: _desc.text.trim(),
        quantity: qty,
        unit: _unit,
        unitPriceNetCents: price,
        requiresConfirmation: false, // the user has looked at it
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const numeric = TextInputType.numberWithOptions(decimal: true);
    final decimalOnly = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _desc,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Bezeichnung')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Art'),
              items: const [
                DropdownMenuItem(value: 'labor', child: Text('Arbeitslohn')),
                DropdownMenuItem(value: 'flat_fee', child: Text('Pauschale (z.B. Anfahrt)')),
                DropdownMenuItem(value: 'material', child: Text('Material')),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qty,
                    keyboardType: numeric,
                    inputFormatters: decimalOnly,
                    decoration: const InputDecoration(labelText: 'Menge'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: const InputDecoration(labelText: 'Einheit'),
                    items: [for (final u in TradeConstants.availableUnits) DropdownMenuItem(value: u, child: Text(u))],
                    onChanged: (v) => setState(() => _unit = v ?? _unit),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: numeric,
              inputFormatters: decimalOnly,
              decoration: const InputDecoration(labelText: 'Einzelpreis netto (€)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: AppTheme.accentRed, fontSize: 13)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(onPressed: _submit, child: const Text('Übernehmen')),
      ],
    );
  }
}

class _FinalizeChoices {
  const _FinalizeChoices({required this.days, required this.deliveryPeriod, required this.createCustomer});
  final int days;
  final String? deliveryPeriod;
  final bool createCustomer;
}

/// Last look before the number is issued: dates, and the two confirmations that matter.
class _FinalizeDialog extends StatefulWidget {
  const _FinalizeDialog({required this.draft, required this.business});
  final DraftDocument draft;
  final Business business;

  @override
  State<_FinalizeDialog> createState() => _FinalizeDialogState();
}

class _FinalizeDialogState extends State<_FinalizeDialog> {
  late final TextEditingController _period = TextEditingController(text: DateFormatter.formatDate(DateTime.now()));
  late int _days = widget.draft.documentType == 'invoice' ? 14 : 30;
  bool _createCustomer = true;
  bool _pricesChecked = false;

  bool get _isInvoice => widget.draft.documentType == 'invoice';
  bool get _hasUnchecked => widget.draft.lineItems.any((i) => i.requiresConfirmation);

  @override
  void dispose() {
    _period.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gross = widget.draft.financialSummary.totalGrossCents;
    final canSubmit = !_hasUnchecked || _pricesChecked;

    return AlertDialog(
      title: Text(_isInvoice ? 'Rechnung fertigstellen?' : 'Angebot fertigstellen?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.draft.customer.extractedName}\n${CurrencyFormatter.formatCents(gross)} brutto',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Es wird eine fortlaufende Nummer vergeben. Danach kann das Dokument nicht mehr geändert werden.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            if (_isInvoice) ...[
              TextField(
                  controller: _period,
                  decoration: const InputDecoration(labelText: 'Leistungszeitraum / Leistungsdatum')),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<int>(
              initialValue: _days,
              decoration: InputDecoration(labelText: _isInvoice ? 'Zahlbar innerhalb von' : 'Angebot gültig für'),
              items: [
                for (final d in (_isInvoice ? [7, 14, 30] : [14, 30, 60]))
                  DropdownMenuItem(value: d, child: Text('$d Tagen')),
              ],
              onChanged: (v) => setState(() => _days = v ?? _days),
            ),
            if (widget.draft.customer.matchedCustomerId == null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _createCustomer,
                onChanged: (v) => setState(() => _createCustomer = v ?? true),
                title: const Text('Neuen Kunden zur Kundenliste hinzufügen', style: TextStyle(fontSize: 13)),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            if (_hasUnchecked)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _pricesChecked,
                onChanged: (v) => setState(() => _pricesChecked = v ?? false),
                title: const Text('Ich habe alle mit „Preis prüfen“ markierten Positionen kontrolliert.',
                    style: TextStyle(fontSize: 13)),
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: canSubmit
              ? () => Navigator.pop(
                    context,
                    _FinalizeChoices(
                      days: _days,
                      deliveryPeriod: _isInvoice && _period.text.trim().isNotEmpty ? _period.text.trim() : null,
                      createCustomer: _createCustomer,
                    ),
                  )
              : null,
          child: const Text('Fertigstellen'),
        ),
      ],
    );
  }
}

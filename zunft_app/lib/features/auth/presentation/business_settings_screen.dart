import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/trade_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/validators.dart';
import '../application/auth_providers.dart';
import '../data/auth_repository.dart';
import '../data/business_models.dart';

/// Edit the sender data printed on every quote and invoice.
class BusinessSettingsScreen extends ConsumerStatefulWidget {
  const BusinessSettingsScreen({super.key, required this.business, required this.canEdit});

  final Business business;
  final bool canEdit;

  @override
  ConsumerState<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends ConsumerState<BusinessSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  late String _trade;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final b = widget.business;
    String t(String? v) => v ?? '';
    _trade = TradeConstants.tradeLabels.containsKey(b.tradeCategory) ? b.tradeCategory : TradeConstants.tradeElektro;
    _c = {
      'name': TextEditingController(text: b.name),
      'owner': TextEditingController(text: b.ownerName),
      'street': TextEditingController(text: t(b.addressStreet)),
      'zip': TextEditingController(text: t(b.addressZip)),
      'city': TextEditingController(text: t(b.addressCity)),
      'phone': TextEditingController(text: t(b.phone)),
      'email': TextEditingController(text: t(b.email)),
      'tax': TextEditingController(text: t(b.taxNumber)),
      'vat': TextEditingController(text: t(b.vatId)),
      'iban': TextEditingController(text: t(b.iban)),
      'bic': TextEditingController(text: t(b.bic)),
      'bank': TextEditingController(text: t(b.bankName)),
      'rate': TextEditingController(text: (b.defaultHourlyRateCents / 100).toStringAsFixed(2).replaceAll('.', ',')),
      'vatRate': TextEditingController(text: _formatRate(b.defaultVatRate)),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _formatRate(double r) => (r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString()).replaceAll('.', ',');

  String? _opt(String key) {
    final v = _c[key]!.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final b = widget.business;
    final updated = Business(
      id: b.id,
      name: _c['name']!.text.trim(),
      ownerName: _c['owner']!.text.trim(),
      tradeCategory: _trade,
      addressStreet: _opt('street'),
      addressZip: _opt('zip'),
      addressCity: _opt('city'),
      phone: _opt('phone'),
      email: _opt('email'),
      website: b.website,
      taxNumber: _opt('tax'),
      vatId: Validators.normalizeCompact(_c['vat']!.text).isEmpty ? null : Validators.normalizeCompact(_c['vat']!.text),
      iban: Validators.normalizeCompact(_c['iban']!.text).isEmpty ? null : Validators.normalizeCompact(_c['iban']!.text),
      bic: Validators.normalizeCompact(_c['bic']!.text).isEmpty ? null : Validators.normalizeCompact(_c['bic']!.text),
      bankName: _opt('bank'),
      defaultHourlyRateCents: CurrencyFormatter.parseToCents(_c['rate']!.text)!,
      defaultVatRate: Validators.parseRate(_c['vatRate']!.text)!,
    );

    try {
      await ref.read(authRepositoryProvider).updateBusiness(updated);
      ref.invalidate(businessProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String key,
    String label, {
    String? Function(String?)? validator,
    TextInputType? keyboard,
    TextCapitalization caps = TextCapitalization.none,
    List<TextInputFormatter>? formatters,
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: _c[key],
        enabled: widget.canEdit && !_busy,
        keyboardType: keyboard,
        textCapitalization: caps,
        inputFormatters: formatters,
        decoration: InputDecoration(labelText: label, helperText: helper, border: const OutlineInputBorder()),
        validator: validator,
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Text(
          title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Betriebsdaten'),
        actions: [
          if (widget.canEdit)
            TextButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Speichern'),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!widget.canEdit)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Nur Inhaber und Büro können die Betriebsdaten ändern.',
                      style: TextStyle(color: AppTheme.accentAmber)),
                ),
              _section('BETRIEB'),
              _field('name', 'Betriebsname', validator: (v) => Validators.required(v, 'Betriebsname'), caps: TextCapitalization.words),
              _field('owner', 'Inhaber', validator: (v) => Validators.required(v, 'Inhaber'), caps: TextCapitalization.words),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<String>(
                  initialValue: _trade,
                  decoration: const InputDecoration(labelText: 'Gewerk', border: OutlineInputBorder()),
                  items: [
                    for (final e in TradeConstants.tradeLabels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: widget.canEdit && !_busy ? (v) => setState(() => _trade = v ?? _trade) : null,
                ),
              ),
              _section('ANSCHRIFT & KONTAKT (erscheint auf der Rechnung)'),
              _field('street', 'Straße und Hausnummer', caps: TextCapitalization.words),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: _field('zip', 'PLZ', keyboard: TextInputType.number, formatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(5),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _field('city', 'Ort', caps: TextCapitalization.words)),
                ],
              ),
              _field('phone', 'Telefon', keyboard: TextInputType.phone),
              _field('email', 'E-Mail (Betrieb)', keyboard: TextInputType.emailAddress,
                  validator: (v) => (v == null || v.trim().isEmpty) ? null : Validators.email(v)),
              _section('STEUER & BANK'),
              _field('tax', 'Steuernummer', helper: 'z.B. 48/123/45678', keyboard: TextInputType.text),
              _field('vat', 'USt-IdNr.', helper: 'z.B. DE123456789', caps: TextCapitalization.characters, validator: Validators.vatId),
              _field('iban', 'IBAN', caps: TextCapitalization.characters, validator: Validators.iban),
              _field('bic', 'BIC', caps: TextCapitalization.characters),
              _field('bank', 'Bank'),
              _section('STANDARDWERTE'),
              _field('rate', 'Stundensatz netto (€ / Std)', keyboard: const TextInputType.numberWithOptions(decimal: true), validator: Validators.hourlyRate),
              _field('vatRate', 'Umsatzsteuersatz (%)', keyboard: const TextInputType.numberWithOptions(decimal: true), validator: Validators.vatRate,
                  helper: '19 % Standard. Kleinunternehmer (§ 19 UStG): 0 % – dann fehlt aber noch der Pflichthinweis auf der Rechnung.'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: AppTheme.accentRed)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

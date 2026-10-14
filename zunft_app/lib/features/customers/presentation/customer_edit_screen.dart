import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'customer_merge_screens.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/customer_duplicates.dart';
import '../../../core/utils/validators.dart';
import '../../auth/application/auth_providers.dart';
import '../../data/data_providers.dart';
import '../../data/data_repository.dart';

/// Create or edit a customer. Saves locally right away; sync happens in the background.
class CustomerEditScreen extends ConsumerStatefulWidget {
  const CustomerEditScreen({super.key, this.customer});

  final Customer? customer;

  @override
  ConsumerState<CustomerEditScreen> createState() => _CustomerEditScreenState();
}

class _CustomerEditScreenState extends ConsumerState<CustomerEditScreen> {
  static const _salutations = ['Herr', 'Frau', 'Firma'];

  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  late String _salutation;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.customer == null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    String t(String? v) => v ?? '';
    _salutation = _salutations.contains(c?.salutation) ? c!.salutation! : 'Herr';
    _c = {
      'name': TextEditingController(text: t(c?.name)),
      'first': TextEditingController(text: t(c?.firstName)),
      'email': TextEditingController(text: t(c?.email)),
      'phone': TextEditingController(text: t(c?.phone)),
      'street': TextEditingController(text: t(c?.street)),
      'zip': TextEditingController(text: t(c?.zip)),
      'city': TextEditingController(text: t(c?.city)),
      'notes': TextEditingController(text: t(c?.notes)),
      'leitweg': TextEditingController(text: t(c?.leitwegId)),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isNew && !await _confirmNoDuplicate()) return;
      final repo = await ref.read(dataRepositoryProvider.future);
      await repo.saveCustomer(
        id: widget.customer?.id,
        salutation: _salutation,
        name: _c['name']!.text,
        firstName: _c['first']!.text,
        email: _c['email']!.text,
        phone: _c['phone']!.text,
        street: _c['street']!.text,
        zip: _c['zip']!.text,
        city: _c['city']!.text,
        notes: _c['notes']!.text,
        leitwegId: _c['leitweg']!.text,
      );
      if (mounted) Navigator.of(context).pop();
    } on ValidationFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Speichern fehlgeschlagen.'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A name alone does not identify a customer, so only same name + same address/phone/e-mail is
  /// "this customer exists" (a clear warning); same name with missing details is a softer question;
  /// same name at a different address is a different person and is not mentioned.
  Future<bool> _confirmNoDuplicate() async {
    final db = ref.read(customersProvider).valueOrNull ?? const <Customer>[];
    final matches = findDuplicateCustomers(
      db,
      name: _c['name']!.text,
      firstName: _c['first']!.text,
      street: _c['street']!.text,
      zip: _c['zip']!.text,
      phone: _c['phone']!.text,
      email: _c['email']!.text,
      includeContactOnly: true,
    );
    if (matches.isEmpty) return true;
    final strong = matches.first.strong;
    final c = matches.first.customer;
    final where = [
      if ((c.street ?? '').isNotEmpty) c.street!,
      [c.zip, c.city].where((s) => (s ?? '').isNotEmpty).join(' '),
    ].where((s) => s.isNotEmpty).join(', ');
    final who = [
      [c.firstName, c.name].where((s) => (s ?? '').isNotEmpty).join(' '),
      if (where.isNotEmpty) where
    ].join('\n');

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strong ? 'Diesen Kunden gibt es schon'.tr : 'Gibt es diesen Kunden schon?'.tr),
        content: Text(strong
            ? '{0}\n\nName und Anschrift (oder Telefon/E-Mail) stimmen überein. Wirklich noch einmal anlegen?'.trf([who])
            : matches.first.sharedContact != null
                ? '{0}\n\nDie {1} ist gleich, der Name aber anders. Ist das dieselbe Person?'.trf([who, matches.first.sharedContact])
                : '{0}\n\nDer Name ist gleich, aber es fehlen Angaben zum Vergleich. Ist das dieselbe Person?'.trf([who])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Abbrechen'.tr)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(strong ? 'Trotzdem anlegen'.tr : 'Nein, neu anlegen'.tr)),
        ],
      ),
    );
    return proceed == true;
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Kunde löschen?'.tr),
        content: Text('Aufträge dieses Kunden bleiben erhalten, verlieren aber die Zuordnung.'.tr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Abbrechen'.tr)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Löschen'.tr, style: TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = await ref.read(dataRepositoryProvider.future);
    try {
      await repo.deleteCustomer(widget.customer!.id);
    } on ValidationFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _field(String key, String label,
      {TextInputType? keyboard,
      TextCapitalization caps = TextCapitalization.none,
      String? Function(String?)? validator,
      String? helper,
      int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: _c[key],
        enabled: !_busy,
        keyboardType: keyboard,
        textCapitalization: caps,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 3, border: const OutlineInputBorder()),
        validator: validator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Neuer Kunde'.tr : 'Kunde bearbeiten'.tr),
        actions: [
          if (!_isNew && (ref.watch(profileProvider).valueOrNull?.isManager ?? false))
            IconButton(
                tooltip: 'Mit anderem Kunden zusammenführen'.tr,
                onPressed: _busy
                    ? null
                    : () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => MergePickerScreen(customer: widget.customer!))),
                icon: const Icon(Icons.merge_type)),
          if (!_isNew)
            IconButton(tooltip: 'Löschen'.tr, onPressed: _busy ? null : _delete, icon: const Icon(Icons.delete_outline)),
          TextButton(onPressed: _busy ? null : _save, child: Text('Speichern'.tr)),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<String>(
                  initialValue: _salutation,
                  decoration: InputDecoration(labelText: 'Anrede'.tr, border: OutlineInputBorder()),
                  items: [for (final s in _salutations) DropdownMenuItem(value: s, child: Text(s.tr))],
                  onChanged: _busy ? null : (v) => setState(() => _salutation = v ?? _salutation),
                ),
              ),
              _field('first', 'Vorname'.tr, caps: TextCapitalization.words),
              _field('name', 'Nachname / Firma'.tr,
                  caps: TextCapitalization.words, validator: (v) => Validators.required(v, 'Name'.tr)),
              _field('street', 'Straße und Hausnummer'.tr, caps: TextCapitalization.words),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 110, child: _field('zip', 'PLZ'.tr, keyboard: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(child: _field('city', 'Ort'.tr, caps: TextCapitalization.words)),
                ],
              ),
              _field('phone', 'Telefon'.tr, keyboard: TextInputType.phone, validator: Validators.phone),
              _field('email', 'E-Mail'.tr,
                  keyboard: TextInputType.emailAddress,
                  validator: (v) => (v == null || v.trim().isEmpty) ? null : Validators.email(v)),
              _field('leitweg', 'Leitweg-ID (nur Behörden)'.tr,
                  helper: 'Für Rechnungen an Behörden und öffentliche Auftraggeber (XRechnung). Sonst leer lassen.'.tr,
                  validator: Validators.leitwegId),
              _field('notes', 'Notizen'.tr, maxLines: 3, caps: TextCapitalization.sentences),
              if (_error != null) Text(_error!, style: const TextStyle(color: AppTheme.accentRed)),
            ],
          ),
        ),
      ),
    );
  }
}

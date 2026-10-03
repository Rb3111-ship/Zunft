import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
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
      );
      if (mounted) Navigator.of(context).pop();
    } on ValidationFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Speichern fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kunde löschen?'),
        content: const Text('Aufträge dieses Kunden bleiben erhalten, verlieren aber die Zuordnung.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen', style: TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = await ref.read(dataRepositoryProvider.future);
    await repo.deleteCustomer(widget.customer!.id);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _field(String key, String label,
      {TextInputType? keyboard, TextCapitalization caps = TextCapitalization.none, String? Function(String?)? validator, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: _c[key],
        enabled: !_busy,
        keyboardType: keyboard,
        textCapitalization: caps,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: validator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Neuer Kunde' : 'Kunde bearbeiten'),
        actions: [
          if (!_isNew)
            IconButton(tooltip: 'Löschen', onPressed: _busy ? null : _delete, icon: const Icon(Icons.delete_outline)),
          TextButton(onPressed: _busy ? null : _save, child: const Text('Speichern')),
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
                  decoration: const InputDecoration(labelText: 'Anrede', border: OutlineInputBorder()),
                  items: [for (final s in _salutations) DropdownMenuItem(value: s, child: Text(s))],
                  onChanged: _busy ? null : (v) => setState(() => _salutation = v ?? _salutation),
                ),
              ),
              _field('first', 'Vorname', caps: TextCapitalization.words),
              _field('name', 'Nachname / Firma',
                  caps: TextCapitalization.words, validator: (v) => Validators.required(v, 'Name')),
              _field('street', 'Straße und Hausnummer', caps: TextCapitalization.words),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 110, child: _field('zip', 'PLZ', keyboard: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(child: _field('city', 'Ort', caps: TextCapitalization.words)),
                ],
              ),
              _field('phone', 'Telefon', keyboard: TextInputType.phone),
              _field('email', 'E-Mail',
                  keyboard: TextInputType.emailAddress,
                  validator: (v) => (v == null || v.trim().isEmpty) ? null : Validators.email(v)),
              _field('notes', 'Notizen', maxLines: 3, caps: TextCapitalization.sentences),
              if (_error != null) Text(_error!, style: const TextStyle(color: AppTheme.accentRed)),
            ],
          ),
        ),
      ),
    );
  }
}

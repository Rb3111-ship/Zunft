import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../customers/presentation/customers_tab.dart';
import '../../data/data_providers.dart';
import '../../data/data_repository.dart';

/// Create or edit a job. Saves locally right away; sync happens in the background.
/// Pops with the saved job's id (or null if the user left without saving).
class JobEditScreen extends ConsumerStatefulWidget {
  const JobEditScreen({super.key, this.job});

  final Job? job;

  @override
  ConsumerState<JobEditScreen> createState() => _JobEditScreenState();
}

class _JobEditScreenState extends ConsumerState<JobEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  String? _customerId;
  late String _status;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.job == null;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.job?.title ?? '');
    _description = TextEditingController(text: widget.job?.description ?? '');
    _customerId = widget.job?.customerId;
    _status = JobStatus.all.contains(widget.job?.status) ? widget.job!.status : JobStatus.draft;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
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
      final savedId = await repo.saveJob(
        id: widget.job?.id,
        customerId: _customerId,
        title: _title.text,
        description: _description.text,
        status: _status,
      );
      if (mounted) Navigator.of(context).pop(savedId);
    } on ValidationFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Speichern fehlgeschlagen.'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Auftrag löschen?'.tr),
        content: Text('Der Auftrag wird dauerhaft entfernt.'.tr),
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
    await repo.deleteJob(widget.job!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider).valueOrNull ?? const <Customer>[];
    // A job may point at a customer that is not in the list (yet); keep the selection valid.
    final selectable = customers.any((c) => c.id == _customerId) ? _customerId : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Neuer Auftrag'.tr : 'Auftrag bearbeiten'.tr),
        actions: [
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
                child: TextFormField(
                  controller: _title,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: 'Titel'.tr, border: OutlineInputBorder()),
                  validator: (v) => Validators.required(v, 'Titel'.tr),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<String?>(
                  initialValue: selectable,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Kunde'.tr, border: OutlineInputBorder()),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text('Kein Kunde'.tr)),
                    for (final c in customers)
                      DropdownMenuItem<String?>(
                          value: c.id, child: Text(customerDisplayName(c), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _customerId = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextFormField(
                  controller: _description,
                  enabled: !_busy,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Beschreibung / Notizen'.tr,
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (_error != null) Text(_error!, style: const TextStyle(color: AppTheme.accentRed)),
            ],
          ),
        ),
      ),
    );
  }
}

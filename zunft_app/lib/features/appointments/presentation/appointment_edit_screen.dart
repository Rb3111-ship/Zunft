import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../customers/presentation/customers_tab.dart' show customerDisplayName;
import '../../data/data_providers.dart';
import '../../data/data_repository.dart';
import '../../team/domain/team_models.dart';
import '../application/appointment_providers.dart';
import '../domain/appointment_models.dart';

/// Create or change an appointment. [job] pre-selects the job (from the job screen); [initialDay]
/// is the day shown in the calendar.
class AppointmentEditScreen extends ConsumerStatefulWidget {
  const AppointmentEditScreen({super.key, this.appointment, this.job, this.initialDay});

  final Appointment? appointment;
  final Job? job;
  final DateTime? initialDay;

  @override
  ConsumerState<AppointmentEditScreen> createState() => _AppointmentEditScreenState();
}

class _AppointmentEditScreenState extends ConsumerState<AppointmentEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _notes;

  late String _kind;
  String? _jobId;
  String? _customerId;
  late bool _allDay;
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;
  late Set<String> _assignees;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.appointment == null;

  @override
  void initState() {
    super.initState();
    final a = widget.appointment;
    final me = ref.read(profileProvider).valueOrNull?.id;
    _title = TextEditingController(text: a?.title ?? '');
    _location = TextEditingController(text: a?.location ?? '');
    _notes = TextEditingController(text: a?.notes ?? '');
    _kind = a?.kind ?? AppointmentKind.job;
    _jobId = a?.jobId ?? widget.job?.id;
    _customerId = a?.customerId ?? widget.job?.customerId;
    if (a != null) {
      final s = a.start;
      final e = a.end;
      // An all-day entry runs from midnight to midnight.
      _allDay = s.hour == 0 && s.minute == 0 && e.hour == 0 && e.minute == 0 && e.isAfter(s);
      _startDate = startOfDay(s);
      _startTime = TimeOfDay(hour: s.hour, minute: s.minute);
      final endInclusive = _allDay ? e.subtract(const Duration(days: 1)) : e;
      _endDate = startOfDay(endInclusive);
      _endTime = TimeOfDay(hour: e.hour, minute: e.minute);
      _assignees = a.assignees.toSet();
    } else {
      final day = startOfDay(widget.initialDay ?? DateTime.now());
      _allDay = false;
      _startDate = day;
      _startTime = const TimeOfDay(hour: 8, minute: 0);
      _endDate = day;
      _endTime = const TimeOfDay(hour: 9, minute: 0);
      _assignees = {if (me != null) me};
    }
    if (_isNew && widget.job != null) _fillFromJob(widget.job!, overwriteTitle: true);
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Choosing a job brings its customer along and suggests the title and the address.
  void _fillFromJob(Job job, {bool overwriteTitle = false}) {
    final customers = ref.read(customersProvider).valueOrNull ?? const <Customer>[];
    final customer = customers.where((c) => c.id == job.customerId).firstOrNull;
    _jobId = job.id;
    _customerId = job.customerId;
    if (overwriteTitle || _title.text.trim().isEmpty) _title.text = job.title;
    if (customer != null && _location.text.trim().isEmpty) {
      final address = [
        customer.street,
        [customer.zip, customer.city].where((s) => (s ?? '').isNotEmpty).join(' '),
      ].where((s) => (s ?? '').isNotEmpty).join(', ');
      if (address.isNotEmpty) _location.text = address;
    }
  }

  DateTime get _start => _allDay
      ? startOfDay(_startDate)
      : DateTime(_startDate.year, _startDate.month, _startDate.day, _startTime.hour, _startTime.minute);

  DateTime get _end => _allDay
      ? DateTime(_endDate.year, _endDate.month, _endDate.day + 1)
      : DateTime(_endDate.year, _endDate.month, _endDate.day, _endTime.hour, _endTime.minute);

  Future<void> _pickDate({required bool start}) async {
    final initial = start ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        // Keep the length: moving the start moves the end by the same amount.
        final shift = picked.difference(_startDate);
        _startDate = picked;
        _endDate = _endDate.add(shift);
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(context: context, initialTime: start ? _startTime : _endTime);
    if (picked == null) return;
    setState(() {
      if (start) {
        // Keep the length (an hour by default) when the start moves.
        final oldStart = _start;
        final length = _end.difference(oldStart);
        _startTime = picked;
        final newEnd = _start.add(length.isNegative || length == Duration.zero ? const Duration(hours: 1) : length);
        _endDate = startOfDay(newEnd);
        _endTime = TimeOfDay(hour: newEnd.hour, minute: newEnd.minute);
      } else {
        _endTime = picked;
      }
    });
  }

  Future<bool> _confirmConflicts(List<Appointment> conflicts, List<TeamMember> members) async {
    String who(Appointment a) => [
          for (final id in a.assignees)
            if (_assignees.contains(id)) members.where((m) => m.id == id).firstOrNull?.fullName ?? 'Mitarbeiter'.tr,
        ].join(', ');
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Doppelt eingeplant?'.tr),
        content: Text([
          for (final c in conflicts.take(4)) '${who(c)}: ${dateLabel(c.start)} ${rangeLabel(c)}  ${c.title}',
          if (conflicts.length > 4) '... und {0} weitere'.trf([conflicts.length - 4]),
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Zurück'.tr)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Trotzdem speichern'.tr)),
        ],
      ),
    );
    return go == true;
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final start = _start;
    final end = _end;
    if (!end.isAfter(start)) {
      setState(() => _error = 'Das Ende muss nach dem Beginn liegen.'.tr);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final all = ref.read(appointmentsProvider).valueOrNull ?? const <Appointment>[];
      final members = ref.read(teamMembersProvider).valueOrNull ?? const <TeamMember>[];
      final conflicts =
          findConflicts(all, start: start, end: end, assignees: _assignees, excludeId: widget.appointment?.id);
      if (conflicts.isNotEmpty && !await _confirmConflicts(conflicts, members)) return;

      final repo = await ref.read(dataRepositoryProvider.future);
      await repo.saveAppointment(
        id: widget.appointment?.id,
        kind: _kind,
        title: _title.text,
        location: _location.text,
        notes: _notes.text,
        start: start,
        end: end,
        jobId: _kind == AppointmentKind.job ? _jobId : null,
        customerId: _kind == AppointmentKind.job ? _customerId : null,
        status: widget.appointment?.status ?? AppointmentStatus.planned,
        assignees: _assignees,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ValidationFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Speichern fehlgeschlagen.'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Termin löschen?'.tr),
        content: Text('Der Termin verschwindet für alle. Der Auftrag bleibt erhalten.'.tr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Abbrechen'.tr)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Löschen'.tr, style: TextStyle(color: AppTheme.accentRed))),
        ],
      ),
    );
    if (go != true) return;
    final repo = await ref.read(dataRepositoryProvider.future);
    await repo.deleteAppointment(widget.appointment!.id);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Widget _dateTimeRow(String label, DateTime date, TimeOfDay time, {required bool start}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label, style: const TextStyle(color: AppTheme.textSecondary))),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy ? null : () => _pickDate(start: start),
              child: Text('${weekdayShort[date.weekday - 1]}, ${dateLabel(date)}'),
            ),
          ),
          if (!_allDay) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy ? null : () => _pickTime(start: start),
              child: Text('${two(time.hour)}:${two(time.minute)}'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final manager = profile?.isManager ?? false;
    final members = (ref.watch(teamMembersProvider).valueOrNull ?? const <TeamMember>[]).where((m) => m.active).toList();
    final jobs = (ref.watch(jobsProvider).valueOrNull ?? const <Job>[])
        .where((j) => !JobStatus.isClosed(j.status) || j.id == _jobId)
        .toList();
    final canDelete = !_isNew && (manager || widget.appointment!.createdBy == profile?.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Neuer Termin'.tr : 'Termin bearbeiten'.tr),
        actions: [
          if (canDelete)
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
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [for (final k in AppointmentKind.all) ButtonSegment(value: k, label: Text(AppointmentKind.label(k)))],
                selected: {_kind},
                onSelectionChanged: _busy ? null : (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _title,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                    labelText: _kind == AppointmentKind.absence ? 'Grund (z. B. Urlaub, krank)'.tr : 'Titel'.tr,
                    border: const OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Titel darf nicht leer sein'.tr : null,
              ),
              const SizedBox(height: 14),
              if (_kind == AppointmentKind.job) ...[
                DropdownButtonFormField<String?>(
                  initialValue: jobs.any((j) => j.id == _jobId) ? _jobId : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Auftrag (optional)'.tr, border: OutlineInputBorder()),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text('Kein Auftrag'.tr)),
                    for (final j in jobs) DropdownMenuItem<String?>(value: j.id, child: Text(j.title, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: _busy
                      ? null
                      : (id) => setState(() {
                            if (id == null) {
                              _jobId = null;
                            } else {
                              _fillFromJob(jobs.firstWhere((j) => j.id == id));
                            }
                          }),
                ),
                const SizedBox(height: 14),
                Builder(builder: (context) {
                  final customers = ref.watch(customersProvider).valueOrNull ?? const <Customer>[];
                  return DropdownButtonFormField<String?>(
                    key: ValueKey('customer-$_jobId-$_customerId'),
                    initialValue: customers.any((c) => c.id == _customerId) ? _customerId : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: 'Kunde (optional)'.tr, border: OutlineInputBorder()),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text('Kein Kunde'.tr)),
                      for (final c in customers)
                        DropdownMenuItem<String?>(value: c.id, child: Text(customerDisplayName(c), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: _busy ? null : (id) => setState(() => _customerId = id),
                  );
                }),
                const SizedBox(height: 14),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _allDay,
                onChanged: _busy ? null : (v) => setState(() => _allDay = v),
                title: Text('Ganztägig'.tr),
              ),
              _dateTimeRow(_allDay ? 'Von'.tr : 'Beginn'.tr, _startDate, _startTime, start: true),
              _dateTimeRow(_allDay ? 'Bis'.tr : 'Ende'.tr, _endDate, _endTime, start: false),
              TextFormField(
                controller: _location,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: 'Ort / Adresse'.tr, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              if (manager && members.length > 1) ...[
                Text('WER?'.tr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
                for (final m in members)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _assignees.contains(m.id),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => v == true ? _assignees.add(m.id) : _assignees.remove(m.id)),
                    title: Text(m.fullName),
                    subtitle: Text(Roles.label(m.role), style: const TextStyle(fontSize: 12)),
                  ),
                const SizedBox(height: 8),
              ],
              TextFormField(
                controller: _notes,
                enabled: !_busy,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: 'Notizen'.tr, border: OutlineInputBorder()),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: const TextStyle(color: AppTheme.accentRed)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

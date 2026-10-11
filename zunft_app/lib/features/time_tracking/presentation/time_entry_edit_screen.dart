import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../appointments/domain/appointment_models.dart' show dateLabel, startOfDay, two, weekdayShort;
import '../../auth/application/auth_providers.dart';
import '../../data/data_providers.dart';
import '../../data/data_repository.dart';
import '../../team/domain/team_models.dart';
import '../../appointments/application/appointment_providers.dart';
import '../domain/time_models.dart';
import '../application/time_providers.dart';

/// Add working time by hand, or correct an entry. A billed entry is shown but cannot be changed.
class TimeEntryEditScreen extends ConsumerStatefulWidget {
  const TimeEntryEditScreen({super.key, this.entry, this.job, this.initialDay});

  final TimeEntry? entry;
  final Job? job;
  final DateTime? initialDay;

  @override
  ConsumerState<TimeEntryEditScreen> createState() => _TimeEntryEditScreenState();
}

class _TimeEntryEditScreenState extends ConsumerState<TimeEntryEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _break;
  late final TextEditingController _note;

  String? _userId;
  String? _jobId;
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;
  late bool _running;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.entry == null;
  bool get _billed => widget.entry?.isBilled ?? false;

  @override
  void initState() {
    super.initState();
    final t = widget.entry;
    _break = TextEditingController(text: '${t?.breakMinutes ?? 0}');
    _note = TextEditingController(text: t?.note ?? '');
    _userId = t?.userId ?? ref.read(profileProvider).valueOrNull?.id;
    _jobId = t?.jobId ?? widget.job?.id;
    if (t != null) {
      final s = t.start;
      final e = t.end ?? DateTime.now();
      _running = t.isRunning;
      _startDate = startOfDay(s);
      _startTime = TimeOfDay(hour: s.hour, minute: s.minute);
      _endDate = startOfDay(e);
      _endTime = TimeOfDay(hour: e.hour, minute: e.minute);
    } else {
      final day = startOfDay(widget.initialDay ?? DateTime.now());
      _running = false;
      _startDate = day;
      _startTime = const TimeOfDay(hour: 8, minute: 0);
      _endDate = day;
      _endTime = const TimeOfDay(hour: 16, minute: 0);
    }
  }

  @override
  void dispose() {
    _break.dispose();
    _note.dispose();
    super.dispose();
  }

  DateTime get _start => DateTime(_startDate.year, _startDate.month, _startDate.day, _startTime.hour, _startTime.minute);
  DateTime get _end => DateTime(_endDate.year, _endDate.month, _endDate.day, _endTime.hour, _endTime.minute);

  Future<void> _pickDate({required bool start}) async {
    final picked = await showDatePicker(
        context: context, initialDate: start ? _startDate : _endDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked == null) return;
    setState(() {
      if (start) {
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
    setState(() => start ? _startTime = picked : _endTime = picked);
  }

  Future<void> _save() async {
    if (_busy || _billed || !_formKey.currentState!.validate()) return;
    final userId = _userId;
    if (userId == null) return;
    final members = ref.read(teamMembersProvider).valueOrNull ?? const <TeamMember>[];
    final me = ref.read(profileProvider).valueOrNull;
    final name = userId == me?.id
        ? me!.fullName
        : members.where((m) => m.id == userId).firstOrNull?.fullName ?? widget.entry?.userName ?? 'Mitarbeiter';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(dataRepositoryProvider.future);
      await repo.saveTimeEntry(
        id: widget.entry?.id,
        userId: userId,
        userName: name,
        jobId: _jobId,
        appointmentId: widget.entry?.appointmentId,
        start: _start,
        end: _running ? null : _end,
        breakMinutes: int.tryParse(_break.text.trim()) ?? 0,
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ValidationFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Speichern fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zeit löschen?'),
        content: const Text('Dieser Eintrag wird entfernt und nicht abgerechnet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Löschen', style: TextStyle(color: AppTheme.accentRed))),
        ],
      ),
    );
    if (go != true) return;
    try {
      final repo = await ref.read(dataRepositoryProvider.future);
      await repo.deleteTimeEntry(widget.entry!.id);
      if (mounted) Navigator.of(context).pop(true);
    } on ValidationFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Widget _row(String label, DateTime date, TimeOfDay time, {required bool start}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            SizedBox(width: 64, child: Text(label, style: const TextStyle(color: AppTheme.textSecondary))),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _busy || _billed ? null : () => _pickDate(start: start),
                child: Text('${weekdayShort[date.weekday - 1]}, ${dateLabel(date)}'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy || _billed ? null : () => _pickTime(start: start),
              child: Text('${two(time.hour)}:${two(time.minute)}'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final manager = profile?.isManager ?? false;
    final members = (ref.watch(teamMembersProvider).valueOrNull ?? const <TeamMember>[]).where((m) => m.active).toList();
    final jobs = (ref.watch(jobsProvider).valueOrNull ?? const <Job>[])
        .where((j) => !JobStatus.isClosed(j.status) || j.id == _jobId)
        .toList();
    final now = ref.watch(timeClockProvider)();
    final minutes = _running ? null : (_end.isAfter(_start) ? _end.difference(_start).inMinutes - (int.tryParse(_break.text.trim()) ?? 0) : null);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Zeit nachtragen' : 'Zeit bearbeiten'),
        actions: [
          if (!_isNew && !_billed)
            IconButton(tooltip: 'Löschen', onPressed: _busy ? null : _delete, icon: const Icon(Icons.delete_outline)),
          if (!_billed) TextButton(onPressed: _busy ? null : _save, child: const Text('Speichern')),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_billed)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Diese Zeit wurde schon abgerechnet und kann nicht mehr geändert werden.',
                      style: TextStyle(color: AppTheme.accentAmber)),
                ),
              if (manager && members.length > 1 && !_billed)
                DropdownButtonFormField<String>(
                  initialValue: members.any((m) => m.id == _userId) ? _userId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Wer', border: OutlineInputBorder()),
                  items: [for (final m in members) DropdownMenuItem(value: m.id, child: Text(m.fullName))],
                  onChanged: _busy ? null : (v) => setState(() => _userId = v),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('Wer: ${widget.entry?.userName ?? profile?.fullName ?? ''}',
                      style: const TextStyle(color: AppTheme.textSecondary)),
                ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String?>(
                initialValue: jobs.any((j) => j.id == _jobId) ? _jobId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Auftrag', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Kein Auftrag')),
                  for (final j in jobs) DropdownMenuItem<String?>(value: j.id, child: Text(j.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: _busy || _billed ? null : (v) => setState(() => _jobId = v),
              ),
              const SizedBox(height: 14),
              _row('Beginn', _startDate, _startTime, start: true),
              if (_running)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Der Timer läuft noch.', style: TextStyle(color: AppTheme.accentAmber))),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _running = false;
                                  _endDate = startOfDay(now);
                                  _endTime = TimeOfDay(hour: now.hour, minute: now.minute);
                                }),
                        child: const Text('Jetzt beenden'),
                      ),
                    ],
                  ),
                )
              else
                _row('Ende', _endDate, _endTime, start: false),
              TextFormField(
                controller: _break,
                enabled: !_busy && !_billed,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Pause (Minuten)', border: OutlineInputBorder()),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  return (n == null || n < 0 || n > 1440) ? 'Bitte Minuten eintragen (0 oder mehr)' : null;
                },
                onChanged: (_) => setState(() {}),
              ),
              if (minutes != null && minutes > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Arbeitszeit: ${clockLabel(Duration(minutes: minutes))} Std (${hoursText(minutes)})',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _note,
                enabled: !_busy && !_billed,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Notiz (optional)', border: OutlineInputBorder()),
              ),
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: AppTheme.accentRed))),
            ],
          ),
        ),
      ),
    );
  }
}

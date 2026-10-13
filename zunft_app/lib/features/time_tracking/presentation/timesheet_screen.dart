import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../appointments/domain/appointment_models.dart';
import '../../auth/application/auth_providers.dart';
import '../../data/data_providers.dart';
import '../../receipts/application/receipt_providers.dart';
import '../application/time_providers.dart';
import '../domain/time_export.dart';
import '../domain/time_models.dart';
import 'time_entry_edit_screen.dart';

/// Who worked how long, week by week or month by month. The boss and the office see everyone; an
/// employee sees only their own times.
class TimesheetScreen extends ConsumerStatefulWidget {
  const TimesheetScreen({super.key});

  @override
  ConsumerState<TimesheetScreen> createState() => _TimesheetScreenState();
}

class _TimesheetScreenState extends ConsumerState<TimesheetScreen> {
  bool _month = false;

  /// The first day of the shown period: a Monday, or the 1st of the month.
  late DateTime _start = mondayOf(DateTime.now());

  DateTime get _end => _month ? DateTime(_start.year, _start.month + 1) : DateTime(_start.year, _start.month, _start.day + 7);

  void _setMode(bool month) => setState(() {
        _month = month;
        final today = DateTime.now();
        _start = month ? DateTime(today.year, today.month) : mondayOf(today);
      });

  void _move(int step) => setState(() {
        _start = _month ? DateTime(_start.year, _start.month + step) : DateTime(_start.year, _start.month, _start.day + 7 * step);
      });

  /// Today if it is in the shown period, otherwise its first day.
  DateTime _dayInPeriod(DateTime now) {
    final today = startOfDay(now);
    return (today.isBefore(_start) || !today.isBefore(_end)) ? _start : today;
  }

  Future<void> _share(List<TimeEntry> entries, List<Job> jobs, DateTime now) async {
    String jobTitle(String? id) => jobs.where((j) => j.id == id).firstOrNull?.title ?? 'Ohne Auftrag'.tr;
    final bytes = timesheetCsv(entries: entries, jobTitle: jobTitle, now: now, periodLabel: timesheetPeriodLabel(_start, _month));
    try {
      await ref.read(fileSharerProvider).share(bytes, '${timesheetFileStem(_start, _month)}.csv',
          subject: 'Arbeitszeiten {0}'.trf([timesheetPeriodLabel(_start, _month)]), mimeType: 'text/csv');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Die Datei konnte nicht geteilt werden.'.tr)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final manager = profile?.isManager ?? false;
    final all = ref.watch(timeEntriesProvider).valueOrNull ?? const <TimeEntry>[];
    final jobs = ref.watch(jobsProvider).valueOrNull ?? const <Job>[];
    final now = ref.watch(timeClockProvider)();

    final period = [
      for (final t in all)
        if (!t.start.isBefore(_start) && t.start.isBefore(_end)) t,
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final byPerson = <String, List<TimeEntry>>{};
    for (final t in period) {
      byPerson.putIfAbsent((t.userName ?? '').isEmpty ? 'Mitarbeiter'.tr : t.userName!, () => []).add(t);
    }
    final total = period.fold<int>(0, (s, t) => s + t.minutes(now));

    String jobTitle(TimeEntry t) => jobs.where((j) => j.id == t.jobId).firstOrNull?.title ?? 'Ohne Auftrag'.tr;

    return Scaffold(
      appBar: AppBar(title: Text(manager ? 'Arbeitszeiten'.tr : 'Meine Zeiten'.tr)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text('Woche'.tr)),
                ButtonSegment(value: true, label: Text('Monat'.tr)),
              ],
              selected: {_month},
              onSelectionChanged: (s) => _setMode(s.first),
            ),
            Row(
              children: [
                IconButton(tooltip: _month ? 'Voriger Monat'.tr : 'Vorige Woche'.tr, onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text(timesheetPeriodLabel(_start, _month),
                      textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                IconButton(tooltip: _month ? 'Nächster Monat'.tr : 'Nächste Woche'.tr, onPressed: () => _move(1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
            Center(
              child: Text(
                'Zusammen: {0} Std'.trf([clockLabel(Duration(minutes: total))]),
                key: const ValueKey('week-total'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accentAmber),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: period.isEmpty ? null : () => _share(period, jobs, now),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: Text('Als Datei teilen (CSV)'.tr),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => TimeEntryEditScreen(initialDay: _dayInPeriod(now)))),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('Zeit nachtragen'.tr),
                ),
              ],
            ),
            if (period.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(_month ? 'In diesem Monat ist keine Zeit erfasst.'.tr : 'In dieser Woche ist keine Zeit erfasst.'.tr,
                    textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary)),
              ),
            for (final person in byPerson.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  '{0}  ·  {1} STD'.trf([person.key.toUpperCase(), clockLabel(Duration(minutes: person.value.fold<int>(0, (s, t) => s + t.minutes(now))))]),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5),
                ),
              ),
              for (final t in person.value)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    title: Text('{0} {1}  {2}{3}  ·  {4} Std'.trf([weekdayShort[t.start.weekday - 1], dateLabel(t.start).substring(0, 6), timeLabel(t.start), t.isRunning ? ' - läuft'.tr : ' - ${timeLabel(t.end!)}', clockLabel(t.worked(now))])),
                    subtitle: Text([jobTitle(t), if (t.enteredByOthers) 'vom Betrieb eingetragen'.tr, if ((t.note ?? '').isNotEmpty) t.note!, if (t.isBilled) 'abgerechnet'].join(' · ')),
                    trailing: t.isBilled
                        ? const Icon(Icons.lock_outline, size: 18)
                        : (manager || t.userId == profile?.id)
                            ? const Icon(Icons.edit_outlined, size: 18)
                            : null,
                    onTap: !t.isBilled && (manager || t.userId == profile?.id)
                        ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => TimeEntryEditScreen(entry: t)))
                        : null,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

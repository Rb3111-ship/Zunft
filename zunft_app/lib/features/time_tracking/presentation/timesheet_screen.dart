import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../appointments/domain/appointment_models.dart';
import '../../auth/application/auth_providers.dart';
import '../../data/data_providers.dart';
import '../application/time_providers.dart';
import '../domain/time_models.dart';
import 'time_entry_edit_screen.dart';

/// Who worked how long, week by week. The boss and the office see everyone; an employee sees
/// only their own times.
class TimesheetScreen extends ConsumerStatefulWidget {
  const TimesheetScreen({super.key});

  @override
  ConsumerState<TimesheetScreen> createState() => _TimesheetScreenState();
}

class _TimesheetScreenState extends ConsumerState<TimesheetScreen> {
  late DateTime _monday = mondayOf(DateTime.now());

  /// Today if it is in the shown week, otherwise the nearest day of it.
  DateTime _dayInWeek(DateTime now, DateTime sunday) {
    final today = startOfDay(now);
    return today.isBefore(_monday) ? _monday : (today.isAfter(sunday) ? sunday : today);
  }

  void _move(int weeks) => setState(() => _monday = DateTime(_monday.year, _monday.month, _monday.day + 7 * weeks));

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final manager = profile?.isManager ?? false;
    final all = ref.watch(timeEntriesProvider).valueOrNull ?? const <TimeEntry>[];
    final jobs = ref.watch(jobsProvider).valueOrNull ?? const <Job>[];
    final now = ref.watch(timeClockProvider)();
    final sunday = _monday.add(const Duration(days: 6));
    final nextMonday = DateTime(_monday.year, _monday.month, _monday.day + 7);

    final week = [
      for (final t in all)
        if (!t.start.isBefore(_monday) && t.start.isBefore(nextMonday)) t,
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final byPerson = <String, List<TimeEntry>>{};
    for (final t in week) {
      byPerson.putIfAbsent((t.userName ?? '').isEmpty ? 'Mitarbeiter' : t.userName!, () => []).add(t);
    }
    final total = week.fold<int>(0, (s, t) => s + t.minutes(now));

    String jobTitle(TimeEntry t) => jobs.where((j) => j.id == t.jobId).firstOrNull?.title ?? 'Ohne Auftrag';

    return Scaffold(
      appBar: AppBar(title: Text(manager ? 'Arbeitszeiten' : 'Meine Zeiten')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                IconButton(tooltip: 'Vorige Woche', onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text('${dateLabel(_monday).substring(0, 6)} - ${dateLabel(sunday)}',
                      textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                IconButton(tooltip: 'Nächste Woche', onPressed: () => _move(1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
            Center(
              child: Text(
                'Zusammen: ${clockLabel(Duration(minutes: total))} Std',
                key: const ValueKey('week-total'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accentAmber),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TimeEntryEditScreen(initialDay: _dayInWeek(now, sunday)))),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Zeit nachtragen'),
              ),
            ),
            if (week.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('In dieser Woche ist keine Zeit erfasst.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
              ),
            for (final person in byPerson.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  '${person.key.toUpperCase()}  ·  ${clockLabel(Duration(minutes: person.value.fold<int>(0, (s, t) => s + t.minutes(now))))} STD',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5),
                ),
              ),
              for (final t in person.value)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    title: Text('${weekdayShort[t.start.weekday - 1]} ${dateLabel(t.start).substring(0, 6)}  ${timeLabel(t.start)}${t.isRunning ? ' - läuft' : ' - ${timeLabel(t.end!)}'}  ·  ${clockLabel(t.worked(now))} Std'),
                    subtitle: Text([jobTitle(t), if ((t.note ?? '').isNotEmpty) t.note!, if (t.isBilled) 'abgerechnet'].join(' · ')),
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

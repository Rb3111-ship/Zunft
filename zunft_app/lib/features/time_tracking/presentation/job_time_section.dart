import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../appointments/domain/appointment_models.dart' show dateLabel, timeLabel, weekdayShort;
import '../../auth/application/auth_providers.dart';
import '../../data/data_repository.dart';
import '../application/time_providers.dart';
import '../domain/time_models.dart';
import 'time_entry_edit_screen.dart';
import 'timer_controls.dart';

/// On the job screen: start or stop the timer, the time already recorded, and "add by hand".
class JobTimeSection extends ConsumerWidget {
  const JobTimeSection({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(timeEntriesProvider).valueOrNull ?? const <TimeEntry>[];
    final profile = ref.watch(profileProvider).valueOrNull;
    final running = ref.watch(myRunningTimerProvider);
    final now = ref.watch(timeClockProvider)();
    final mine = all.where((t) => t.jobId == job.id).toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final runningHere = running != null && running.jobId == job.id;
    final billable = billableEntries(all, job.id);
    final billableMinutes = billable.fold<int>(0, (s, t) => s + t.minutes(now));
    final manager = profile?.isManager ?? false;
    final closed = JobStatus.isClosed(job.status);

    bool canEdit(TimeEntry t) => !t.isBilled && (manager || t.userId == profile?.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text('ZEIT'.tr,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        if (runningHere)
          FilledButton.icon(
            onPressed: () => stopTimerNow(ref, running),
            icon: const Icon(Icons.stop),
            label: Text('Zeit stoppen'.tr),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: AppTheme.accentRed),
          )
        else if (!closed)
          OutlinedButton.icon(
            onPressed: () => startTimerFor(context, ref, job: job),
            icon: const Icon(Icons.play_arrow),
            label: Text('Zeit starten'.tr),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        if (billable.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Noch nicht abgerechnet: {0} Std ({1})'.trf([clockLabel(Duration(minutes: billableMinutes)), hoursText(billableMinutes)]),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        if (manager && billable.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              minutesByPerson(billable, now).entries.map((e) => '${e.key} ${clockLabel(Duration(minutes: e.value))}').join('  ·  '),
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
            ),
          ),
        const SizedBox(height: 6),
        for (final t in mine.take(8))
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text(
                t.isRunning
                    ? '{0} {1} {2} - läuft'.trf([weekdayShort[t.start.weekday - 1], dateLabel(t.start).substring(0, 6), timeLabel(t.start)])
                    : '{0} {1} {2} - {3}  ·  {4} Std'.trf([weekdayShort[t.start.weekday - 1], dateLabel(t.start).substring(0, 6), timeLabel(t.start), timeLabel(t.end!), clockLabel(t.worked(now))]),
              ),
              subtitle: Text([
                if (manager || t.userId != profile?.id) t.userName ?? 'Mitarbeiter'.tr,
                if (t.enteredByOthers) 'vom Betrieb eingetragen'.tr,
                if ((t.note ?? '').isNotEmpty) t.note!,
                if (t.isBilled) 'abgerechnet',
              ].join(' · ')),
              trailing: canEdit(t) ? const Icon(Icons.edit_outlined, size: 18) : (t.isBilled ? const Icon(Icons.lock_outline, size: 18) : null),
              onTap: canEdit(t)
                  ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => TimeEntryEditScreen(entry: t)))
                  : null,
            ),
          ),
        TextButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TimeEntryEditScreen(job: job))),
          icon: const Icon(Icons.add, size: 18),
          label: Text('Zeit nachtragen'.tr),
        ),
      ],
    );
  }
}

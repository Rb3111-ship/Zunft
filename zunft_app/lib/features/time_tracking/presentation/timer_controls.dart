import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../data/data_providers.dart';
import '../../data/data_repository.dart';
import '../../jobs/presentation/job_detail_screen.dart';
import '../application/time_providers.dart';
import '../domain/time_models.dart';

/// Starts my timer for [job] (and [appointment]). A running timer is stopped first and the screen
/// says so. A closed job cannot be timed.
Future<void> startTimerFor(BuildContext context, WidgetRef ref, {Job? job, Appointment? appointment}) async {
  final messenger = ScaffoldMessenger.of(context);
  final profile = ref.read(profileProvider).valueOrNull;
  if (profile == null) return;
  if (job != null && JobStatus.isClosed(job.status)) {
    messenger.showSnackBar(const SnackBar(content: Text('Dieser Auftrag ist abgeschlossen. Zeit kann nur nachgetragen werden.')));
    return;
  }
  final repo = await ref.read(dataRepositoryProvider.future);
  final result = await repo.startTimer(
    userId: profile.id,
    userName: profile.fullName,
    jobId: job?.id ?? appointment?.jobId,
    appointmentId: appointment?.id,
  );
  final stopped = result.stopped;
  if (stopped != null) {
    final jobs = ref.read(jobsProvider).valueOrNull ?? const <Job>[];
    final title = jobs.where((j) => j.id == stopped.jobId).firstOrNull?.title ?? 'dem vorherigen Eintrag';
    final len = clockLabel(stopped.worked(DateTime.now()));
    messenger.showSnackBar(SnackBar(content: Text('Der laufende Timer für „$title“ wurde beendet ($len Std).')));
  }
}

Future<void> stopTimerNow(WidgetRef ref, TimeEntry running) async {
  final repo = await ref.read(dataRepositoryProvider.future);
  await repo.stopTimer(running.id);
}

/// A bar above every tab while my timer runs: what, for how long, and a Stopp button.
class TimerBanner extends ConsumerWidget {
  const TimerBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(myRunningTimerProvider);
    if (running == null) return const SizedBox.shrink();

    final now = ref.watch(tickProvider).valueOrNull ?? ref.read(timeClockProvider)();
    final elapsed = running.worked(now);
    final forgotten = elapsed > forgottenTimerAfter;
    final jobs = ref.watch(jobsProvider).valueOrNull ?? const <Job>[];
    final job = jobs.where((j) => j.id == running.jobId).firstOrNull;
    final color = forgotten ? AppTheme.accentRed : AppTheme.accentAmber;

    return Material(
      color: color.withValues(alpha: 0.18),
      child: InkWell(
        onTap: job == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailScreen(jobId: job.id))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              Icon(Icons.timer_outlined, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job?.title ?? 'Zeit läuft', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (forgotten)
                      const Text('Läuft seit über 12 Stunden. Vergessen zu stoppen?', style: TextStyle(fontSize: 12, color: AppTheme.accentRed)),
                  ],
                ),
              ),
              Text(elapsedLabel(elapsed), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.accentRed, minimumSize: const Size(0, 36)),
                onPressed: () => stopTimerNow(ref, running),
                child: const Text('Stopp'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

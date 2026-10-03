import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../data/data_providers.dart';
import '../application/capture_providers.dart';
import '../data/capture_processor.dart';

/// Notes of this phone that have not reached the server yet: waiting, processing, or failed.
/// Once the server stored a note it lives on its job. Renders nothing when the queue is empty.
///
/// [jobId] limits the list to one job (the job screen); without it all waiting notes show
/// (the Aufträge tab), each labelled with its job.
class CapturesSection extends ConsumerWidget {
  const CapturesSection({super.key, this.jobId});

  final String? jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(capturesProvider).valueOrNull ?? const <PendingCapture>[];
    final captures = jobId == null ? all : all.where((c) => c.jobId == jobId).toList();
    if (captures.isEmpty) return const SizedBox.shrink();
    final problem = ref.watch(captureControllerProvider).problem;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'WARTEN AUF VERARBEITUNG',
            style:
                TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5),
          ),
        ),
        for (final c in captures) CaptureTile(capture: c, problem: problem, showJob: jobId == null),
        const SizedBox(height: 12),
      ],
    );
  }
}

String captureLabel(PendingCapture c) {
  if (c.kind == 'text') {
    final t = (c.transcript ?? '').replaceAll('\n', ' ');
    return t.length > 60 ? '${t.substring(0, 60)}...' : t;
  }
  final s = c.durationSeconds;
  return 'Sprachnotiz ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class CaptureTile extends ConsumerWidget {
  const CaptureTile({super.key, required this.capture, this.problem, this.showJob = false});

  final PendingCapture capture;
  final CaptureProblem? problem;

  /// Show which job the note belongs to (in the cross-job list).
  final bool showJob;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = CaptureStatus.values.asNameMap()[capture.status] ?? CaptureStatus.failed;

    final (Widget leading, String subtitle, Color color) = switch (status) {
      CaptureStatus.queued => (
          Icon(
            problem == CaptureProblem.offline ? Icons.cloud_off : Icons.schedule,
            color: AppTheme.accentAmber,
          ),
          switch (problem) {
            CaptureProblem.offline => 'Wartet auf Internet - wird automatisch gesendet',
            CaptureProblem.authExpired => 'Bitte erneut anmelden',
            null =>
              capture.errorMessage == null ? 'Wartet auf Verarbeitung' : 'Neuer Versuch folgt: ${capture.errorMessage}',
          },
          AppTheme.accentAmber,
        ),
      CaptureStatus.processing => (
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          'Wird verarbeitet...',
          AppTheme.accentBlue,
        ),
      CaptureStatus.failed => (
          const Icon(Icons.error_outline, color: AppTheme.accentRed),
          capture.errorMessage ?? 'Die Verarbeitung ist fehlgeschlagen.',
          AppTheme.accentRed,
        ),
    };

    final jobs = showJob ? (ref.watch(jobsProvider).valueOrNull ?? const <Job>[]) : const <Job>[];
    final job = jobs.where((j) => j.id == capture.jobId).firstOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        leading: SizedBox(width: 28, child: Center(child: leading)),
        title: Text(
          captureLabel(capture),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          [if (job != null) 'Auftrag: ${job.title}', subtitle].join('\n'),
          style: TextStyle(color: color, fontSize: 12.5),
        ),
        isThreeLine: job != null,
        trailing: status == CaptureStatus.failed
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () async => (await ref.read(captureRepositoryProvider.future)).retry(capture.id),
                    child: const Text('Wiederholen'),
                  ),
                  IconButton(
                    tooltip: 'Verwerfen',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () async => (await ref.read(captureRepositoryProvider.future)).discard(capture.id),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

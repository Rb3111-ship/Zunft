import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../customers/presentation/customers_tab.dart';
import '../../data/data_providers.dart';
import '../../data/data_repository.dart';
import '../../jobs/presentation/job_edit_screen.dart';
import 'receipt_flow.dart';
import 'record_capture_sheet.dart';

/// Every note belongs to a job that the user picks first, so a note can never end up on the
/// wrong customer by accident. With [job] given (started from inside a job) the picker is skipped.
///
/// The recording sheet can send the user back to the picker ("Auftrag ändern").
Future<void> startRecordingFlow(BuildContext context, WidgetRef ref, {Job? job}) async {
  Job? current = job;
  while (true) {
    if (!context.mounted) return;
    current ??= await _pickJob(context, ref);
    if (current == null || !context.mounted) return;

    final customers = ref.read(customersProvider).valueOrNull ?? const <Customer>[];
    final customer = customers.where((c) => c.id == current!.customerId).firstOrNull;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          RecordCaptureSheet(job: current!, customerName: customer == null ? null : customerDisplayName(customer)),
    );
    if (result == RecordCaptureSheet.receipt) {
      if (context.mounted) await startReceiptFlow(context, ref, job: current);
      return;
    }
    if (result != RecordCaptureSheet.changeJob) return;
    current = null; // back to the picker
  }
}

/// Lets the user choose the job (or create one). Null if they cancelled.
Future<Job?> _pickJob(BuildContext context, WidgetRef ref) async {
  final choice = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const JobPickerSheet(),
  );
  if (choice is Job) return choice;
  if (choice == JobPickerSheet.newJob && context.mounted) {
    final id = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const JobEditScreen()));
    if (id == null) return null;
    final db = await ref.read(scopedDatabaseProvider.future);
    return db.jobById(id);
  }
  return null;
}

/// "Für welchen Auftrag?" - the open jobs, newest first, plus "Neuer Auftrag".
class JobPickerSheet extends ConsumerWidget {
  const JobPickerSheet({super.key});

  /// Returned when the user wants to create a new job.
  static const newJob = 'new-job';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs =
        (ref.watch(jobsProvider).valueOrNull ?? const <Job>[]).where((j) => !JobStatus.isClosed(j.status)).toList();
    final customers = ref.watch(customersProvider).valueOrNull ?? const <Customer>[];
    final byId = {for (final c in customers) c.id: c};

    // A Material (not a coloured box) so the list rows can show their tap effect.
    return Material(
      color: AppTheme.surfaceCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(color: AppTheme.dividerColor, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Für welchen Auftrag?'.tr, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Die Notiz wird diesem Auftrag und seinem Kunden zugeordnet.'.tr,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (ref.watch(canCreateRecordsProvider)) ...[
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, newJob),
                  icon: const Icon(Icons.add),
                  label: Text('Neuer Auftrag'.tr),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
                const SizedBox(height: 8),
              ],
              if (jobs.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('Noch kein offener Auftrag.'.tr, style: TextStyle(color: AppTheme.textSecondary)),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final j in jobs)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.assignment_outlined, color: AppTheme.accentAmber),
                          title: Text(j.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(byId[j.customerId] == null
                              ? 'Kein Kunde zugeordnet'.tr
                              : customerDisplayName(byId[j.customerId]!)),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary),
                          onTap: () => Navigator.pop(context, j),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

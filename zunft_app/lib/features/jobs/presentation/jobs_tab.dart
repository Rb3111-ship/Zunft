import '../../subscription/presentation/subscription_banner.dart';
import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/refresh_all.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../customers/presentation/customers_tab.dart';
import '../../data/data_providers.dart';
import '../../data/data_repository.dart';
import '../../capture/presentation/captures_section.dart';
import 'job_detail_screen.dart';
import 'job_edit_screen.dart';

Color jobStatusColor(String status) => switch (status) {
      JobStatus.draft => AppTheme.accentAmber,
      JobStatus.quoteSent => AppTheme.accentBlue,
      JobStatus.inProgress => AppTheme.accentBlue,
      JobStatus.completed => AppTheme.accentGreen,
      JobStatus.invoiced => AppTheme.accentGreen,
      _ => AppTheme.textSecondary,
    };

/// Which jobs the list shows: the ones still to be worked on, or the finished ones.
enum _JobFilter { open, done }

class JobsTab extends ConsumerStatefulWidget {
  const JobsTab({super.key});

  @override
  ConsumerState<JobsTab> createState() => _JobsTabState();
}

class _JobsTabState extends ConsumerState<JobsTab> {
  _JobFilter _filter = _JobFilter.open;

  Future<void> _open([Job? job]) async {
    if (job == null && !await ensureWritable(context, ref)) return;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => job == null ? const JobEditScreen() : JobDetailScreen(jobId: job.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(jobsProvider);
    final customers = ref.watch(customersProvider).valueOrNull ?? const <Customer>[];
    final byId = {for (final c in customers) c.id: c};
    final canCreate = ref.watch(canCreateRecordsProvider);

    return RefreshIndicator(
      onRefresh: () => refreshAll(ref),
      child: jobs.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accentAmber)),
        error: (e, _) => Center(
          child: TextButton(
              onPressed: () => ref.invalidate(jobsProvider),
              child: Text('${'Aufträge konnten nicht geladen werden. Erneut versuchen'.tr}\n\n$e', textAlign: TextAlign.center)),
        ),
        data: (all) {
          final openJobs = all.where((j) => !JobStatus.isClosed(j.status)).toList()
            // Work in progress first, then the ones not started yet.
            ..sort((a, b) =>
                (a.status == JobStatus.inProgress ? 0 : 1).compareTo(b.status == JobStatus.inProgress ? 0 : 1));
          final doneJobs = all.where((j) => JobStatus.isClosed(j.status)).toList()
            // Finished but not billed yet comes first: that is the money still to collect.
            ..sort((a, b) =>
                (a.status == JobStatus.completed ? 0 : 1).compareTo(b.status == JobStatus.completed ? 0 : 1));
          final shown = _filter == _JobFilter.open ? openJobs : doneJobs;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              const CapturesSection(),
              SegmentedButton<_JobFilter>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: _JobFilter.open, label: Text('Offen ({0})'.trf([openJobs.length]))),
                  ButtonSegment(value: _JobFilter.done, label: Text('Erledigt ({0})'.trf([doneJobs.length]))),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
              if (canCreate)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _open,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text('Neuer Auftrag'.tr),
                  ),
                ),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    _emptyText(all.isEmpty, canCreate),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              for (final j in shown) _jobCard(j, byId),
            ],
          );
        },
      ),
    );
  }

  String _emptyText(bool noJobsAtAll, bool canCreate) {
    if (noJobsAtAll) {
      return canCreate
          ? 'Noch keine Aufträge. Lege mit „Neuer Auftrag“ den ersten an, dann kannst du ihm Sprachnotizen hinzufügen.'.tr
          : 'Dir ist noch kein Auftrag zugewiesen. Sobald der Inhaber oder das Büro dir einen Auftrag zuweist, erscheint er hier.'.tr;
    }
    return _filter == _JobFilter.open
        ? 'Alles erledigt: Es gibt keine offenen Aufträge.'.tr
        : 'Noch keine erledigten Aufträge. Abgeschlossene und abgerechnete Aufträge erscheinen hier.'.tr;
  }

  Widget _jobCard(Job j, Map<String, Customer> byId) {
    final customer = byId[j.customerId];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(j.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              customer == null ? 'Kein Kunde zugeordnet'.tr : customerDisplayName(customer),
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: jobStatusColor(j.status).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                JobStatus.label(j.status),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: jobStatusColor(j.status)),
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary),
        onTap: () => _open(j),
      ),
    );
  }
}

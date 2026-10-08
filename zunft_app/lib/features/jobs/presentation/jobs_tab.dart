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

class JobsTab extends ConsumerWidget {
  const JobsTab({super.key});

  void _open(BuildContext context, [Job? job]) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => job == null ? const JobEditScreen() : JobDetailScreen(jobId: job.id)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            child: const Text('Aufträge konnten nicht geladen werden. Erneut versuchen')),
      ),
      data: (all) {
        int count(String s) => all.where((j) => j.status == s).length;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            const CapturesSection(),
            Card(
              color: AppTheme.primaryDark,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metric('Entwürfe', count(JobStatus.draft), AppTheme.accentAmber),
                    Container(height: 36, width: 1, color: AppTheme.dividerColor),
                    _metric('In Arbeit', count(JobStatus.inProgress), AppTheme.accentBlue),
                    Container(height: 36, width: 1, color: AppTheme.dividerColor),
                    _metric('Abgeschlossen', count(JobStatus.completed), AppTheme.accentGreen),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'AUFTRÄGE',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5),
                  ),
                ),
                if (canCreate)
                  TextButton.icon(
                    onPressed: () => _open(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Neuer Auftrag'),
                  ),
              ],
            ),
            if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  canCreate
                      ? 'Noch keine Aufträge. Lege mit „Neuer Auftrag“ den ersten an, dann kannst du ihm Sprachnotizen hinzufügen.'
                      : 'Dir ist noch kein Auftrag zugewiesen. Sobald der Inhaber oder das Büro dir einen Auftrag zuweist, erscheint er hier.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            for (final j in all)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(j.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        byId[j.customerId] == null ? 'Kein Kunde zugeordnet' : customerDisplayName(byId[j.customerId]!),
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
                  onTap: () => _open(context, j),
                ),
              ),
          ],
        );
      },
    ));
  }

  Widget _metric(String label, int value, Color color) {
    return Column(
      children: [
        Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }
}

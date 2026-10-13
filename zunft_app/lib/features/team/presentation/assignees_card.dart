import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/team_providers.dart';
import '../data/team_remote.dart';
import '../domain/team_models.dart';

/// Boss and office: who works on this job. Employees see only the jobs they are assigned to, so
/// this is where a job is handed to somebody. Not shown to a self-employed person alone in the
/// business (nobody to assign to).
class AssigneesCard extends ConsumerWidget {
  const AssigneesCard({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamOverviewProvider).valueOrNull;
    final assigned = ref.watch(jobAssigneesProvider(jobId));
    // Owner and office see every job anyway; only employees can be assigned.
    final employees = team?.members.where((m) => m.active && !Roles.managers.contains(m.role)) ?? const [];
    if (team == null || employees.isEmpty) return const SizedBox.shrink();

    final ids = assigned.valueOrNull ?? const <String>{};
    final names = [
      for (final m in employees)
        if (ids.contains(m.id)) m.fullName
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.group_outlined, color: AppTheme.accentAmber),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ZUGEWIESEN AN'.tr,
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 0.5)),
                  Text(
                    assigned.isLoading
                        ? '...'
                        : names.isEmpty
                            ? 'Niemand - nur Inhaber und Büro sehen den Auftrag'.tr
                            : names.join(', '),
                    style: TextStyle(fontWeight: FontWeight.bold, color: names.isEmpty ? AppTheme.textSecondary : null),
                  ),
                ],
              ),
            ),
            TextButton(
                onPressed: assigned.isLoading ? null : () => _edit(context, ref, employees, ids),
                child: Text('Zuweisen'.tr)),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Iterable<TeamMember> employees, Set<String> current) async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _AssignDialog(members: employees.toList(), selected: current),
    );
    if (result == null) return;
    try {
      await ref.read(teamRemoteProvider).setAssignees(jobId, result);
    } on TeamException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    ref.invalidate(jobAssigneesProvider(jobId));
  }
}

class _AssignDialog extends StatefulWidget {
  const _AssignDialog({required this.members, required this.selected});

  final List<TeamMember> members;
  final Set<String> selected;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Wer arbeitet an diesem Auftrag?'.tr),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mitarbeiter sehen nur Aufträge, die ihnen zugewiesen sind.'.tr,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            for (final m in widget.members)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _selected.contains(m.id),
                onChanged: (v) => setState(() => v == true ? _selected.add(m.id) : _selected.remove(m.id)),
                title: Text(m.fullName),
                subtitle: Text(Roles.label(m.role)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Abbrechen'.tr)),
        FilledButton(onPressed: () => Navigator.pop(context, _selected), child: Text('Speichern'.tr)),
      ],
    );
  }
}

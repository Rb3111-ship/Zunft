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
    if (team == null || team.activeMembers < 2) return const SizedBox.shrink();

    final ids = assigned.valueOrNull ?? const <String>{};
    final names = [
      for (final m in team.members)
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
                  const Text('ZUGEWIESEN AN',
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 0.5)),
                  Text(
                    assigned.isLoading
                        ? '...'
                        : names.isEmpty
                            ? 'Niemand - nur Inhaber und Büro sehen den Auftrag'
                            : names.join(', '),
                    style: TextStyle(fontWeight: FontWeight.bold, color: names.isEmpty ? AppTheme.textSecondary : null),
                  ),
                ],
              ),
            ),
            TextButton(
                onPressed: assigned.isLoading ? null : () => _edit(context, ref, team, ids),
                child: const Text('Zuweisen')),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, TeamOverview team, Set<String> current) async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _AssignDialog(members: team.members.where((m) => m.active).toList(), selected: current),
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
      title: const Text('Wer arbeitet an diesem Auftrag?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mitarbeiter sehen nur Aufträge, die ihnen zugewiesen sind.',
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(context, _selected), child: const Text('Speichern')),
      ],
    );
  }
}

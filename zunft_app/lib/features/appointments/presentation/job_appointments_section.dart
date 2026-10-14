import '../../subscription/presentation/subscription_banner.dart';
import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../team/domain/team_models.dart';
import '../application/appointment_providers.dart';
import 'appointment_edit_screen.dart';
import 'appointments_tab.dart' show AppointmentCard;

/// On the job screen: the appointments of this job, and a button to plan another one.
class JobAppointmentsSection extends ConsumerWidget {
  const JobAppointmentsSection({super.key, required this.job, required this.canCreate});

  final Job job;
  final bool canCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(appointmentsProvider).valueOrNull ?? const <Appointment>[];
    final members = ref.watch(teamMembersProvider).valueOrNull ?? const <TeamMember>[];
    final mine = all.where((a) => a.jobId == job.id).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    if (mine.isEmpty && !canCreate) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text('TERMINE'.tr,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        for (final a in mine.take(6)) AppointmentCard(appointment: a, members: members),
        if (canCreate)
          OutlinedButton.icon(
            onPressed: () async {
              if (!await ensureWritable(context, ref) || !context.mounted) return;
              Navigator.push(context, MaterialPageRoute(builder: (_) => AppointmentEditScreen(job: job)));
            },
            icon: const Icon(Icons.event_available_outlined),
            label: Text('Termin anlegen'.tr),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
      ],
    );
  }
}

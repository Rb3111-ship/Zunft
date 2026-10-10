import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../customers/presentation/customers_tab.dart' show customerDisplayName;
import '../../data/data_providers.dart';
import '../../jobs/presentation/job_detail_screen.dart';
import '../../team/domain/team_models.dart';
import '../application/appointment_actions.dart';
import '../application/appointment_providers.dart';
import '../data/appointments_remote.dart';
import '../data/external_actions.dart';
import '../domain/appointment_export.dart';
import '../domain/appointment_models.dart';
import 'appointment_edit_screen.dart';

class AppointmentDetailScreen extends ConsumerStatefulWidget {
  const AppointmentDetailScreen({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  ConsumerState<AppointmentDetailScreen> createState() => _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends ConsumerState<AppointmentDetailScreen> {
  bool _busy = false;

  void _say(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setStatus(Appointment a, String status, {required bool manager}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(dataRepositoryProvider.future);
      if (manager) {
        await repo.setAppointmentStatus(a.id, status);
      } else {
        // An employee may not edit appointments; the server marks it for them.
        await ref.read(appointmentsRemoteProvider).setStatus(a.id, status);
        await repo.applyServerAppointmentStatus(a.id, status);
      }
    } on AppointmentException catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Uri uri, String failMessage) async {
    final ok = await ref.read(externalActionsProvider).openUrl(uri);
    if (!ok) _say(failMessage);
  }

  Future<void> _addToCalendar(Appointment a, List<TeamMember> members) async {
    final ics = buildIcs([a], names: {for (final m in members) m.id: m.fullName}, now: DateTime.now());
    final slug = a.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    await ref
        .read(externalActionsProvider)
        .shareCalendarFile(Uint8List.fromList(utf8.encode(ics)), 'Termin-${slug.isEmpty ? 'Zunft' : slug}.ics');
  }

  Future<void> _confirmToCustomer(Appointment a, Customer? customer) async {
    final business = ref.read(businessProvider).valueOrNull;
    final text = confirmationText(
      a,
      businessName: business?.name ?? '',
      salutation: customer?.salutation,
      customerName: customer?.name,
      phone: business?.phone,
    );
    await ref.read(externalActionsProvider).shareText(text, subject: 'Terminbestätigung');
  }

  Widget _row(IconData icon, String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppTheme.accentAmber),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            if (trailing != null) trailing,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(appointmentsProvider).valueOrNull?.where((x) => x.id == widget.appointmentId).firstOrNull;
    final profile = ref.watch(profileProvider).valueOrNull;
    final manager = profile?.isManager ?? false;
    final members = ref.watch(teamMembersProvider).valueOrNull ?? const <TeamMember>[];
    final customers = ref.watch(customersProvider).valueOrNull ?? const <Customer>[];
    final jobs = ref.watch(jobsProvider).valueOrNull ?? const <Job>[];

    if (a == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Termin')),
        body: const Center(child: Text('Dieser Termin existiert nicht mehr.')),
      );
    }

    final customer = customers.where((c) => c.id == a.customerId).firstOrNull;
    final job = jobs.where((j) => j.id == a.jobId).firstOrNull;
    final mine = profile != null && a.assignees.contains(profile.id);
    final canMark = (manager || mine) && !a.isCanceled;
    final canEdit = manager || (a.createdBy == profile?.id && a.assignees.every((id) => id == profile?.id));
    final names = [for (final id in a.assignees) members.where((m) => m.id == id).firstOrNull?.fullName ?? 'Mitarbeiter'];
    final phone = customer?.phone;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppointmentKind.label(a.kind)),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Bearbeiten',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AppointmentEditScreen(appointment: a))),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(a.title,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    decoration: a.isCanceled ? TextDecoration.lineThrough : null)),
            const SizedBox(height: 6),
            Chip(
              label: Text(AppointmentStatus.label(a.status), style: const TextStyle(fontSize: 12)),
              backgroundColor: (a.isDone ? AppTheme.accentGreen : a.isCanceled ? AppTheme.textSecondary : AppTheme.accentAmber)
                  .withValues(alpha: 0.18),
            ),
            const SizedBox(height: 8),
            _row(Icons.schedule, '${longDateLabel(a.start)}\n${rangeLabel(a)}'),
            if (names.isNotEmpty) _row(Icons.person_outline, names.join(', ')),
            if (customer != null)
              _row(
                Icons.badge_outlined,
                customerDisplayName(customer),
                trailing: (phone ?? '').isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Anrufen',
                        onPressed: () => _open(telUri(phone!), 'Der Anruf konnte nicht gestartet werden.'),
                        icon: const Icon(Icons.call, color: AppTheme.accentGreen),
                      ),
              ),
            if ((a.location ?? '').isNotEmpty)
              _row(
                Icons.place_outlined,
                a.location!,
                trailing: IconButton(
                  tooltip: 'Route',
                  onPressed: () => _open(mapsUri(a.location!), 'Die Karte konnte nicht geöffnet werden.'),
                  icon: const Icon(Icons.directions, color: AppTheme.accentBlue),
                ),
              ),
            if ((a.notes ?? '').isNotEmpty) _row(Icons.notes, a.notes!),
            if (job != null)
              _row(
                Icons.assignment_outlined,
                'Auftrag: ${job.title}',
                trailing: TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailScreen(jobId: job.id))),
                  child: const Text('Öffnen'),
                ),
              ),
            const SizedBox(height: 12),
            if (canMark)
              FilledButton.icon(
                onPressed: _busy ? null : () => _setStatus(a, a.isDone ? AppointmentStatus.planned : AppointmentStatus.done, manager: manager),
                icon: Icon(a.isDone ? Icons.undo : Icons.check),
                label: Text(a.isDone ? 'Wieder öffnen' : 'Als erledigt markieren'),
              ),
            if (manager)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _setStatus(a, a.isCanceled ? AppointmentStatus.planned : AppointmentStatus.canceled, manager: true),
                icon: Icon(a.isCanceled ? Icons.restore : Icons.event_busy),
                label: Text(a.isCanceled ? 'Wieder planen' : 'Absagen'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _addToCalendar(a, members),
              icon: const Icon(Icons.event_available),
              label: const Text('In Kalender übernehmen'),
            ),
            if (customer != null && !a.isAbsence)
              OutlinedButton.icon(
                onPressed: () => _confirmToCustomer(a, customer),
                icon: const Icon(Icons.send_outlined),
                label: const Text('Termin dem Kunden bestätigen'),
              ),
          ],
        ),
      ),
    );
  }
}

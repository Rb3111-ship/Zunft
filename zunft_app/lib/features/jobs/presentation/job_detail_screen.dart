import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../appointments/presentation/job_appointments_section.dart';
import '../../time_tracking/application/time_providers.dart';
import '../../time_tracking/domain/time_billing.dart';
import '../../time_tracking/domain/time_models.dart';
import '../../time_tracking/presentation/job_time_section.dart';
import '../../time_tracking/presentation/time_billing_dialog.dart';
import '../../auth/application/auth_providers.dart';
import '../../capture/application/capture_providers.dart';
import '../../capture/presentation/captures_section.dart';
import '../../capture/presentation/receipt_flow.dart';
import '../../capture/presentation/record_flow.dart';
import '../../customers/presentation/customers_tab.dart';
import '../../data/data_providers.dart';
import '../../data/data_repository.dart';
import '../../review/models/draft_models.dart';
import '../../review/presentation/review_draft_screen.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/team_models.dart';
import '../../team/presentation/assignees_card.dart';
import '../application/job_notes_providers.dart';
import '../data/job_notes_remote.dart';
import '../domain/job_notes.dart';
import 'job_edit_screen.dart';
import 'note_replay.dart';
import 'jobs_tab.dart' show jobStatusColor;

/// One job: its customer, every note recorded for it (by any worker), and the button that turns
/// all open notes into ONE quote or invoice.
class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(jobsProvider).valueOrNull ?? const <Job>[];
    final job = jobs.where((j) => j.id == jobId).firstOrNull;
    if (job == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Auftrag'.tr)),
        body: Center(child: Text('Dieser Auftrag existiert nicht mehr.'.tr)),
      );
    }

    final customers = ref.watch(customersProvider).valueOrNull ?? const <Customer>[];
    final customer = customers.where((c) => c.id == job.customerId).firstOrNull;
    final notes = ref.watch(jobNotesProvider(jobId));
    final waiting =
        (ref.watch(capturesProvider).valueOrNull ?? const <PendingCapture>[]).where((c) => c.jobId == jobId).length;
    // Boss and office bill and assign; employees only record notes.
    final manager = ref.watch(profileProvider).valueOrNull?.isManager ?? false;
    final closed = JobStatus.isClosed(job.status);
    final canCreateRecords = ref.watch(canCreateRecordsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(job.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Auftrag bearbeiten'.tr,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobEditScreen(job: job))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header(job, customer),
          if (manager) AssigneesCard(jobId: jobId),
          const SizedBox(height: 14),
          if (closed)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  job.status == JobStatus.invoiced
                      ? 'Dieser Auftrag ist abgerechnet. Es können keine Notizen mehr aufgenommen werden.'.tr
                      : 'Dieser Auftrag ist abgeschlossen. Es können keine Notizen mehr aufgenommen werden.'.tr,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
            )
          else
            FilledButton.icon(
              onPressed: () => startRecordingFlow(context, ref, job: job),
              icon: const Icon(Icons.mic),
              label: Text('Notiz zu diesem Auftrag aufnehmen'.tr),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          if (!closed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: () => startReceiptFlow(context, ref, job: job),
                icon: const Icon(Icons.receipt_long),
                label: Text('Beleg fotografieren oder hochladen'.tr),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
          if (manager)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: () => _setStatus(context, ref, job.id, closed ? JobStatus.inProgress : JobStatus.completed),
                icon: Icon(closed ? Icons.lock_open : Icons.check_circle_outline),
                label: Text(closed ? 'Auftrag wieder öffnen'.tr : 'Auftrag abschließen'.tr),
              ),
            ),
          JobAppointmentsSection(job: job, canCreate: canCreateRecords && !closed),
          JobTimeSection(job: job),
          const SizedBox(height: 20),
          CapturesSection(jobId: jobId),
          Text('NOTIZEN DIESES AUFTRAGS'.tr,
            style:
                TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          notes.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: AppTheme.accentAmber)),
            ),
            error: (e, _) => _loadError(ref, e),
            data: (list) => _notesBody(context, ref, job, customer, list, waiting, manager),
          ),
        ],
      ),
    );
  }

  Widget _header(Job job, Customer? customer) {
    final color = jobStatusColor(job.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppTheme.primaryDark, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.person, color: AppTheme.accentAmber),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('KUNDE'.tr,
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 0.5)),
                  Text(
                    customer == null ? 'Kein Kunde zugeordnet'.tr : customerDisplayName(customer),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (customer == null)
                    Text('Über das Stift-Symbol oben einen Kunden wählen - oder beim Erstellen eintragen.'.tr,
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
              child: Text(JobStatus.label(job.status),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadError(WidgetRef ref, Object e) => Card(
        child: ListTile(
          leading: const Icon(Icons.cloud_off, color: AppTheme.accentAmber),
          title: Text(e is JobNotesException ? e.message : 'Die Notizen konnten nicht geladen werden.'.tr),
          subtitle: Text('Tippen zum erneuten Laden'.tr),
          onTap: () => ref.invalidate(jobNotesProvider(jobId)),
        ),
      );

  Widget _notesBody(BuildContext context, WidgetRef ref, Job job, Customer? customer, List<JobNote> notes, int waiting,
      bool manager) {
    final items = [for (final n in notes) ...n.draft.lineItems];
    final net = FinancialSummary.calculate(items: items).totalNetCents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notes.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Noch keine Notizen. Nimm eine Notiz auf (oder tippe sie ein): Arbeitszeit, Material, Besonderheiten. Du kannst beliebig viele Notizen machen, auch an mehreren Tagen.'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        for (final n in notes) _NoteCard(note: n, onDiscard: () => _discard(context, ref, n)),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            (items.length == 1
                    ? (notes.length == 1 ? '1 Position aus 1 Notiz - zusammen {0} netto' : '1 Position aus {1} Notizen - zusammen {0} netto')
                    : (notes.length == 1 ? '{2} Positionen aus 1 Notiz - zusammen {0} netto' : '{2} Positionen aus {1} Notizen - zusammen {0} netto'))
                .trf([CurrencyFormatter.formatCents(net), notes.length, items.length]),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          if (waiting > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                (waiting == 1
                        ? '1 weitere Notiz wartet noch auf die Verarbeitung und ist hier noch nicht enthalten.'
                        : '{0} weitere Notizen warten noch auf die Verarbeitung und sind hier noch nicht enthalten.')
                    .trf([waiting]),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.accentAmber, fontSize: 12.5),
              ),
            ),
          if (manager) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _review(context, ref, job, customer, notes),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text('Alle Notizen prüfen und abrechnen'.tr),
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: AppTheme.accentGreen),
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _setStatus(BuildContext context, WidgetRef ref, String id, String status) async {
    final repo = await ref.read(dataRepositoryProvider.future);
    await repo.setJobStatus(id, status);
  }

  Future<void> _review(BuildContext context, WidgetRef ref, Job job, Customer? customer, List<JobNote> notes) async {
    final business = ref.read(businessProvider).valueOrNull;
    final markup = business?.materialMarkupPercent ?? 0;

    // Tracked working time: the boss decides whether it is billed, and how it goes with the working
    // time that was said in the notes.
    final allTime = ref.read(timeEntriesProvider).valueOrNull ?? const <TimeEntry>[];
    final now = ref.read(timeClockProvider)();
    final billable = billableEntries(allTime, job.id);
    final minutes = billable.fold<int>(0, (s, t) => s + t.minutes(now));
    var choice = TimeBilling.skip;
    var lines = const <TimeBillingLine>[];
    if (minutes > 0) {
      final noteLabor = notes
          .expand((n) => n.draft.lineItems)
          .where((i) => i.type == 'labor' && i.unit == 'Std')
          .fold<double>(0, (s, i) => s + i.quantity);
      // Each person may have their own hourly rate (set by the owner); the others use the business's.
      Map<String, int> rates = const {};
      try {
        rates = await ref.read(memberRatesProvider.future);
      } catch (_) {}
      final members = ref.read(teamOverviewProvider).valueOrNull?.members ?? const <TeamMember>[];
      lines = timeBillingLines(
        entries: billable,
        rates: rates,
        roles: {for (final m in members) m.id: m.role},
        defaultRateCents: business?.defaultHourlyRateCents ?? 0,
        now: now,
      );
      if (!context.mounted) return;
      final picked = await askTimeBilling(
        context,
        minutes: minutes,
        byPerson: minutesByPerson(billable, now),
        lines: lines,
        noteLaborHours: noteLabor,
        timerStillRunning: allTime.any((t) => t.jobId == job.id && t.isRunning),
      );
      if (picked == null) return;
      choice = picked;
    }
    final billTime = choice != TimeBilling.skip && minutes > 0;
    final draft = buildJobDraft(
      job: job,
      customer: customer,
      notes: notes,
      materialMarkupPercent: markup,
      timeLines: billTime ? lines : const [],
      replaceNoteLabor: billTime && choice == TimeBilling.replace,
    );
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewDraftScreen(
          draft: draft,
          noteIds: [for (final n in notes) n.id],
          timeEntryIds: billTime ? [for (final t in billable) t.id] : const [],
        ),
      ),
    );
    ref.invalidate(jobNotesProvider(jobId));
  }

  Future<void> _discard(BuildContext context, WidgetRef ref, JobNote note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Notiz entfernen?'.tr),
        content: Text('Die Positionen dieser Notiz werden nicht abgerechnet. Der Auftrag bleibt erhalten.'.tr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Abbrechen'.tr)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Entfernen'.tr, style: TextStyle(color: AppTheme.accentRed))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(jobNotesRemoteProvider).discard(note.id);
    } on JobNotesException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    ref.invalidate(jobNotesProvider(jobId));
  }
}

class _NoteCard extends StatefulWidget {
  const _NoteCard({required this.note, required this.onDiscard});

  final JobNote note;
  final VoidCallback onDiscard;

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    final items = n.draft.lineItems;
    final net = FinancialSummary.calculate(items: items).totalNetCents;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(n.isReceipt ? Icons.receipt_long : Icons.mic, size: 16, color: AppTheme.accentAmber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${n.isReceipt ? 'Beleg'.tr + ' - ' : ''}${n.author} - ${DateFormatter.formatDateTime(n.createdAt)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                IconButton(
                  tooltip: 'Notiz entfernen'.tr,
                  icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.accentRed),
                  onPressed: widget.onDiscard,
                ),
              ],
            ),
            for (final i in items)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: Row(
                  children: [
                    Expanded(child: Text('• ${i.description}', style: const TextStyle(fontSize: 13.5))),
                    Text(CurrencyFormatter.formatCents(i.totalNetCents), style: const TextStyle(fontSize: 13.5)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Row(
                children: [
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                    onPressed: () => setState(() => _open = !_open),
                    child:
                        Text(
                            _open
                                ? (n.isReceipt ? 'Beleg verbergen'.tr : 'Gesagt verbergen'.tr)
                                : (n.isReceipt ? 'Beleg ansehen'.tr : 'Was wurde gesagt?'.tr),
                            style: const TextStyle(fontSize: 12.5)),
                  ),
                  const Spacer(),
                  Text('{0} netto'.trf([CurrencyFormatter.formatCents(net)]),
                      style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 6),
                child: NoteReplay(
                    transcript: n.transcript,
                    audioPath: n.audioPath,
                    imagePath: n.imagePath,
                    audioDeleted: n.audioDeleted),
              ),
            if (n.draft.warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 4),
                child: Text('Hinweis: {0}'.trf([n.draft.warnings.join('; ')]),
                    style: const TextStyle(color: AppTheme.accentAmber, fontSize: 12.5)),
              ),
          ],
        ),
      ),
    );
  }
}

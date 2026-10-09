import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
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
        appBar: AppBar(title: const Text('Auftrag')),
        body: const Center(child: Text('Dieser Auftrag existiert nicht mehr.')),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(job.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Auftrag bearbeiten',
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
                      ? 'Dieser Auftrag ist abgerechnet. Es können keine Notizen mehr aufgenommen werden.'
                      : 'Dieser Auftrag ist abgeschlossen. Es können keine Notizen mehr aufgenommen werden.',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
            )
          else
            FilledButton.icon(
              onPressed: () => startRecordingFlow(context, ref, job: job),
              icon: const Icon(Icons.mic),
              label: const Text('Notiz zu diesem Auftrag aufnehmen'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          if (!closed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: () => startReceiptFlow(context, ref, job: job),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Beleg fotografieren oder hochladen'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
          if (manager)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: () => _setStatus(context, ref, job.id, closed ? JobStatus.inProgress : JobStatus.completed),
                icon: Icon(closed ? Icons.lock_open : Icons.check_circle_outline),
                label: Text(closed ? 'Auftrag wieder öffnen' : 'Auftrag abschließen'),
              ),
            ),
          const SizedBox(height: 20),
          CapturesSection(jobId: jobId),
          const Text(
            'NOTIZEN DIESES AUFTRAGS',
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
                  const Text('KUNDE',
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 0.5)),
                  Text(
                    customer == null ? 'Kein Kunde zugeordnet' : customerDisplayName(customer),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (customer == null)
                    const Text(
                      'Über das Stift-Symbol oben einen Kunden wählen - oder beim Erstellen eintragen.',
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
          title: Text(e is JobNotesException ? e.message : 'Die Notizen konnten nicht geladen werden.'),
          subtitle: const Text('Tippen zum erneuten Laden'),
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Noch keine Notizen. Nimm eine Notiz auf (oder tippe sie ein): Arbeitszeit, Material, Besonderheiten. '
              'Du kannst beliebig viele Notizen machen, auch an mehreren Tagen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        for (final n in notes) _NoteCard(note: n, onDiscard: () => _discard(context, ref, n)),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '${items.length} Position${items.length == 1 ? '' : 'en'} aus ${notes.length} Notiz${notes.length == 1 ? '' : 'en'} '
            '- zusammen ${CurrencyFormatter.formatCents(net)} netto',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          if (waiting > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '$waiting weitere Notiz${waiting == 1 ? '' : 'en'} wart${waiting == 1 ? 'et' : 'en'} noch auf die Verarbeitung und '
                '${waiting == 1 ? 'ist' : 'sind'} hier noch nicht enthalten.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.accentAmber, fontSize: 12.5),
              ),
            ),
          if (manager) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _review(context, ref, job, customer, notes),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Alle Notizen prüfen und abrechnen'),
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
    final markup = ref.read(businessProvider).valueOrNull?.materialMarkupPercent ?? 0;
    final draft = buildJobDraft(job: job, customer: customer, notes: notes, materialMarkupPercent: markup);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReviewDraftScreen(draft: draft, noteIds: [for (final n in notes) n.id])),
    );
    ref.invalidate(jobNotesProvider(jobId));
  }

  Future<void> _discard(BuildContext context, WidgetRef ref, JobNote note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notiz entfernen?'),
        content: const Text('Die Positionen dieser Notiz werden nicht abgerechnet. Der Auftrag bleibt erhalten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Entfernen', style: TextStyle(color: AppTheme.accentRed))),
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
                    '${n.isReceipt ? 'Beleg - ' : ''}${n.author} - ${DateFormatter.formatDateTime(n.createdAt)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                IconButton(
                  tooltip: 'Notiz entfernen',
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
                                ? (n.isReceipt ? 'Beleg verbergen' : 'Gesagt verbergen')
                                : (n.isReceipt ? 'Beleg ansehen' : 'Was wurde gesagt?'),
                            style: const TextStyle(fontSize: 12.5)),
                  ),
                  const Spacer(),
                  Text('${CurrencyFormatter.formatCents(net)} netto',
                      style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 6),
                child: NoteReplay(transcript: n.transcript, audioPath: n.audioPath, imagePath: n.imagePath),
              ),
            if (n.draft.warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 4),
                child: Text('Hinweis: ${n.draft.warnings.join('; ')}',
                    style: const TextStyle(color: AppTheme.accentAmber, fontSize: 12.5)),
              ),
          ],
        ),
      ),
    );
  }
}

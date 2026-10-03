import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../review/models/draft_models.dart';
import '../../review/presentation/review_draft_screen.dart';
import '../application/capture_providers.dart';
import '../data/capture_processor.dart';

/// Notes that are still becoming drafts: waiting, processing, ready for review, or failed.
/// Shown at the top of the Aufträge tab; renders nothing when there are none.
class CapturesSection extends ConsumerWidget {
  const CapturesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captures = ref.watch(capturesProvider).valueOrNull ?? const <PendingCapture>[];
    if (captures.isEmpty) return const SizedBox.shrink();
    final problem = ref.watch(captureControllerProvider).problem;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'NEUE NOTIZEN',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5),
          ),
        ),
        for (final c in captures) CaptureTile(capture: c, problem: problem),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Draft title and customer from the server's stored answer; null if it cannot be read.
DraftDocument? draftFromCapture(PendingCapture c) {
  final raw = c.draftJson;
  if (raw == null) return null;
  try {
    return DraftDocument.fromJson(jsonDecode(raw) as Map<String, dynamic>, jobId: c.jobId);
  } catch (_) {
    return null;
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
  const CaptureTile({super.key, required this.capture, this.problem});

  final PendingCapture capture;
  final CaptureProblem? problem;

  Future<void> _open(BuildContext context) async {
    final draft = draftFromCapture(capture);
    if (draft == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Der Entwurf konnte nicht gelesen werden. Bitte die Notiz erneut senden.')),
      );
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewDraftScreen(draft: draft, captureId: capture.id)));
  }

  Future<void> _discardReady(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Entwurf entfernen?'),
        content: const Text('Der Auftrag bleibt erhalten, nur dieser Entwurf verschwindet aus der Liste.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entfernen', style: TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = await ref.read(captureRepositoryProvider.future);
    await repo.discard(capture.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = CaptureStatus.values.byName(capture.status);

    final (Widget leading, String subtitle, Color color) = switch (status) {
      CaptureStatus.queued => (
          Icon(
            problem == CaptureProblem.offline ? Icons.cloud_off : Icons.schedule,
            color: AppTheme.accentAmber,
          ),
          switch (problem) {
            CaptureProblem.offline => 'Wartet auf Internet - wird automatisch gesendet',
            CaptureProblem.authExpired => 'Bitte erneut anmelden',
            null => capture.errorMessage == null ? 'Wartet auf Verarbeitung' : 'Neuer Versuch folgt: ${capture.errorMessage}',
          },
          AppTheme.accentAmber,
        ),
      CaptureStatus.processing => (
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          'Wird verarbeitet...',
          AppTheme.accentBlue,
        ),
      CaptureStatus.ready => (
          const Icon(Icons.check_circle, color: AppTheme.accentGreen),
          _readySubtitle(),
          AppTheme.accentGreen,
        ),
      CaptureStatus.failed => (
          const Icon(Icons.error_outline, color: AppTheme.accentRed),
          capture.errorMessage ?? 'Die Verarbeitung ist fehlgeschlagen.',
          AppTheme.accentRed,
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        leading: SizedBox(width: 28, child: Center(child: leading)),
        title: Text(
          status == CaptureStatus.ready ? (draftFromCapture(capture)?.title ?? captureLabel(capture)) : captureLabel(capture),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle, style: TextStyle(color: color, fontSize: 12.5)),
        trailing: switch (status) {
          CaptureStatus.ready => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Entwurf entfernen',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => _discardReady(context, ref),
                ),
                const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary),
              ],
            ),
          CaptureStatus.failed => Row(
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
            ),
          _ => null,
        },
        onTap: status == CaptureStatus.ready ? () => _open(context) : null,
      ),
    );
  }

  String _readySubtitle() {
    final draft = draftFromCapture(capture);
    if (draft == null) return 'Entwurf bereit';
    final kind = draft.documentType == 'invoice' ? 'Rechnung' : 'Angebot';
    final warn = draft.warnings.isEmpty ? '' : ' - ${draft.warnings.length} Hinweis(e)';
    return '$kind für ${draft.customer.extractedName}: Entwurf prüfen$warn';
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatter.dart';
import '../../auth/application/auth_providers.dart';
import '../../capture/application/capture_providers.dart';
import '../../capture/data/receipt_picker.dart';
import '../../subscription/presentation/subscription_banner.dart';
import '../application/job_photos_providers.dart';
import '../data/job_photos_remote.dart';
import '../domain/job_photo.dart';

String _kindLabel(String kind) => switch (kind) {
      'before' => 'Vorher'.tr,
      'after' => 'Nachher'.tr,
      _ => 'Weitere'.tr,
    };

/// "FOTOS" on the job screen: the state of the work before and after, and other pictures. A photo
/// is saved on the phone at once and uploaded when there is a connection (like a note), so it also
/// works on a site without signal.
class JobPhotosSection extends ConsumerWidget {
  const JobPhotosSection({super.key, required this.job});

  final Job job;

  Future<void> _add(BuildContext context, WidgetRef ref, String kind) async {
    if (!await ensureWritable(context, ref) || !context.mounted) return;
    final source = await showModalBottomSheet<ReceiptSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Foto hinzufügen: {0}'.trf([_kindLabel(kind)]), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppTheme.accentAmber),
              title: Text('Foto aufnehmen'.tr),
              onTap: () => Navigator.pop(ctx, ReceiptSource.photo),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppTheme.accentAmber),
              title: Text('Foto vom Handy wählen'.tr),
              onTap: () => Navigator.pop(ctx, ReceiptSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final path = await ref.read(receiptPickerProvider).pick(source);
    if (path == null) return;
    try {
      final repo = await ref.read(captureRepositoryProvider.future);
      await repo.savePhoto(jobId: job.id, filePath: path, kind: kind);
      messenger.showSnackBar(SnackBar(content: Text('Foto gespeichert. Es wird hochgeladen, sobald Internet da ist.'.tr)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text('Das Foto konnte nicht gespeichert werden.'.tr)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(jobPhotosProvider(job.id)).valueOrNull ?? const <JobPhoto>[];
    final waiting = [
      for (final c in ref.watch(capturesProvider).valueOrNull ?? const <PendingCapture>[])
        if (c.kind == 'photo' && c.jobId == job.id) c,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('FOTOS'.tr,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final kind in JobPhoto.kinds)
              OutlinedButton.icon(
                key: ValueKey('add-photo-$kind'),
                onPressed: () => _add(context, ref, kind),
                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: Text(_kindLabel(kind)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final kind in JobPhoto.kinds)
          if (photos.any((p) => p.kind == kind) || waiting.any((c) => c.transcript == kind)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(_kindLabel(kind), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in photos.where((p) => p.kind == kind)) _Thumb(photo: p, onTap: () => _open(context, ref, p)),
                for (final c in waiting.where((c) => c.transcript == kind)) _WaitingThumb(capture: c),
              ],
            ),
          ],
        if (photos.isEmpty && waiting.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Noch keine Fotos. Halte den Zustand vor und nach der Arbeit fest.'.tr,
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          ),
      ],
    );
  }

  void _open(BuildContext context, WidgetRef ref, JobPhoto p) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PhotoViewerScreen(photo: p)));
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({required this.photo, required this.onTap});

  final JobPhoto photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(jobPhotoBytesProvider(photo.path));
    return InkWell(
      key: ValueKey('photo-${photo.id}'),
      onTap: onTap,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(color: AppTheme.primaryDark, borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: bytes.when(
          data: (b) => Image.memory(b, fit: BoxFit.cover, cacheWidth: 300, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
          loading: () => const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          error: (_, __) => const Icon(Icons.cloud_off, color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

/// A photo that is still on this phone, waiting for a connection.
class _WaitingThumb extends StatelessWidget {
  const _WaitingThumb({required this.capture});

  final PendingCapture capture;

  @override
  Widget build(BuildContext context) {
    final failed = capture.status == CaptureStatus.failed.name;
    return Container(
      key: ValueKey('waiting-${capture.id}'),
      width: 96,
      height: 96,
      decoration: BoxDecoration(color: AppTheme.primaryDark, borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (capture.localPath != null)
            Opacity(opacity: 0.5, child: Image.file(File(capture.localPath!), fit: BoxFit.cover, cacheWidth: 300, errorBuilder: (_, __, ___) => const SizedBox())),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(failed ? Icons.error_outline : Icons.schedule, color: failed ? AppTheme.accentRed : AppTheme.accentAmber),
                Text(failed ? 'Fehler'.tr : 'wartet'.tr, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One photo, full size, with who took it and when; zoom with two fingers. The boss, the office and
/// the person who took it can remove it.
class PhotoViewerScreen extends ConsumerStatefulWidget {
  const PhotoViewerScreen({super.key, required this.photo});

  final JobPhoto photo;

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  bool _busy = false;

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Foto entfernen?'.tr),
        content: Text('Das Foto wird für alle gelöscht.'.tr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Abbrechen'.tr)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Entfernen'.tr)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await ref.read(jobPhotosRemoteProvider).delete(widget.photo.id);
      ref.invalidate(jobPhotosProvider(widget.photo.jobId));
      nav.pop();
    } on JobPhotosException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photo;
    final me = ref.watch(profileProvider).valueOrNull;
    final canDelete = (me?.isManager ?? false) || (me != null && me.id == p.authorId);
    final bytes = ref.watch(jobPhotoBytesProvider(p.path));
    return Scaffold(
      appBar: AppBar(
        title: Text(_kindLabel(p.kind)),
        actions: [
          if (canDelete)
            IconButton(
              key: const ValueKey('delete-photo'),
              tooltip: 'Foto entfernen'.tr,
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: bytes.when(
              data: (b) => InteractiveViewer(child: Center(child: Image.memory(b, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 48)))),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(child: Text('Das Foto konnte nicht geladen werden.'.tr)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                [DateFormatter.formatDateTime(p.createdAt), if ((p.authorName ?? '').isNotEmpty) p.authorName!].join(' - '),
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

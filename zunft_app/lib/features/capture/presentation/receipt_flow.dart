import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../application/capture_providers.dart';
import '../data/receipt_picker.dart';

/// Photograph (or choose from the phone) a receipt for [job]. The photo is checked on screen first,
/// like a recording is listened to first: only when it is sharp and complete is it sent.
/// The server then reads it and adds the materials as positions of the job.
Future<void> startReceiptFlow(BuildContext context, WidgetRef ref, {required Job job}) async {
  var source = await _chooseSource(context);
  while (source != null) {
    if (!context.mounted) return;
    final path = await ref.read(receiptPickerProvider).pick(source);
    if (path == null || !context.mounted) return;

    final result = await Navigator.push<ReceiptDecision>(
      context,
      MaterialPageRoute(builder: (_) => ReceiptConfirmScreen(filePath: path, job: job)),
    );
    if (result == ReceiptDecision.sent) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Beleg gesendet. Er wird gelesen und erscheint gleich beim Auftrag.')),
        );
      }
      return;
    }
    // Not sent: the photo is not kept.
    await _deleteQuietly(ref, path);
    if (result != ReceiptDecision.retake) return;
  }
}

Future<void> _deleteQuietly(WidgetRef ref, String path) async {
  try {
    await ref.read(captureFilesProvider).delete(path);
  } catch (_) {}
}

Future<ReceiptSource?> _chooseSource(BuildContext context) {
  return showModalBottomSheet<ReceiptSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Beleg hinzufügen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera, color: AppTheme.accentAmber),
            title: const Text('Beleg fotografieren'),
            subtitle: const Text('Flach hinlegen, gutes Licht, alle Zeilen im Bild'),
            onTap: () => Navigator.pop(ctx, ReceiptSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppTheme.accentAmber),
            title: const Text('Foto vom Handy wählen'),
            onTap: () => Navigator.pop(ctx, ReceiptSource.gallery),
          ),
        ],
      ),
    ),
  );
}

enum ReceiptDecision { sent, retake, discarded }

/// Shows the photo and asks: readable? Then it is sent for reading.
class ReceiptConfirmScreen extends ConsumerStatefulWidget {
  const ReceiptConfirmScreen({super.key, required this.filePath, required this.job});

  final String filePath;
  final Job job;

  /// Tests replace the real photo (a file) with a placeholder.
  static Widget Function(String path)? debugImageBuilder;

  @override
  ConsumerState<ReceiptConfirmScreen> createState() => _ReceiptConfirmScreenState();
}

class _ReceiptConfirmScreenState extends ConsumerState<ReceiptConfirmScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(captureRepositoryProvider.future);
      await repo.saveReceipt(jobId: widget.job.id, filePath: widget.filePath);
      if (mounted) Navigator.pop(context, ReceiptDecision.sent);
    } catch (_) {
      if (mounted) setState(() => _error = 'Der Beleg konnte nicht gespeichert werden.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Beleg prüfen')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Für den Auftrag „${widget.job.title}“. Ist alles scharf und vollständig zu lesen, '
                'auch die Summe? Sonst lieber neu aufnehmen.',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: ReceiptConfirmScreen.debugImageBuilder?.call(widget.filePath) ??
                      Image.file(File(widget.filePath), fit: BoxFit.contain),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!, style: const TextStyle(color: AppTheme.accentRed)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context, ReceiptDecision.retake),
                      child: const Text('Neu aufnehmen'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Verwerfen',
                    onPressed: _busy ? null : () => Navigator.pop(context, ReceiptDecision.discarded),
                    icon: const Icon(Icons.delete_outline, color: AppTheme.accentRed),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _send,
                      child: const Text('Senden'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

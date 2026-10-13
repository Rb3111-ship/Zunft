import '../../../core/i18n/i18n.dart';
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
          SnackBar(content: Text('Beleg gesendet. Er wird gelesen und erscheint gleich beim Auftrag.'.tr)),
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
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Beleg hinzufügen'.tr, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera, color: AppTheme.accentAmber),
            title: Text('Beleg fotografieren'.tr),
            subtitle: Text('Der Scanner erkennt das Blatt. Flach hinlegen, gutes Licht.'.tr),
            onTap: () => Navigator.pop(ctx, ReceiptSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppTheme.accentAmber),
            title: Text('Foto vom Handy wählen'.tr),
            onTap: () => Navigator.pop(ctx, ReceiptSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.accentAmber),
            title: Text('PDF oder Datei wählen'.tr),
            subtitle: Text('z.B. eine Rechnung, die der Händler per E-Mail geschickt hat'.tr),
            onTap: () => Navigator.pop(ctx, ReceiptSource.file),
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
      if (mounted) setState(() => _error = 'Der Beleg konnte nicht gespeichert werden.'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Beleg prüfen'.tr)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Für den Auftrag „{0}“. {1}'.trf([widget.job.title, isPdfPath(widget.filePath) ? 'Dieses PDF wird gelesen und als Beleg gespeichert.'.tr : 'Ist alles scharf und vollständig zu lesen, auch die Summe? Sonst lieber neu aufnehmen.'.tr]),
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: ReceiptConfirmScreen.debugImageBuilder?.call(widget.filePath) ??
                      (isPdfPath(widget.filePath)
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.picture_as_pdf, size: 72, color: AppTheme.accentAmber),
                                const SizedBox(height: 8),
                                Text(widget.filePath.split(RegExp(r'[\\/]')).last),
                              ],
                            )
                          : Image.file(File(widget.filePath), fit: BoxFit.contain)),
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
                      child: Text('Neu aufnehmen'.tr),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Verwerfen'.tr,
                    onPressed: _busy ? null : () => Navigator.pop(context, ReceiptDecision.discarded),
                    icon: const Icon(Icons.delete_outline, color: AppTheme.accentRed),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _send,
                      child: Text('Senden'.tr),
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

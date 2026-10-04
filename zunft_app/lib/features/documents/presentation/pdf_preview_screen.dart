import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_theme.dart';

/// Shows a PDF with share and print actions.
///
/// [onShared] runs after the share sheet was opened (the app then marks the document "sent").
/// [showActions] is false for an unnumbered draft preview, which must not be sent out.
class PdfPreviewScreen extends StatelessWidget {
  final Uint8List pdfBytes;
  final String documentTitle;
  final VoidCallback? onShared;
  final bool showActions;

  /// Tests replace the real PDF viewer (it needs platform channels).
  static Widget Function(Uint8List bytes, String fileName)? debugBodyBuilder;

  const PdfPreviewScreen({
    super.key,
    required this.pdfBytes,
    required this.documentTitle,
    this.onShared,
    this.showActions = true,
  });

  String get _fileName => '${documentTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.pdf';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(documentTitle, style: const TextStyle(fontSize: 16)),
        actions: [
          if (showActions) ...[
            IconButton(
              icon: const Icon(Icons.share, color: AppTheme.accentAmber),
              tooltip: 'Per WhatsApp / E-Mail senden',
              onPressed: () async {
                await Printing.sharePdf(bytes: pdfBytes, filename: _fileName);
                onShared?.call();
              },
            ),
            IconButton(
              icon: const Icon(Icons.print, color: AppTheme.textPrimary),
              tooltip: 'Drucken',
              onPressed: () => Printing.layoutPdf(onLayout: (_) => pdfBytes, name: documentTitle),
            ),
          ],
        ],
      ),
      body: debugBodyBuilder?.call(pdfBytes, _fileName) ??
          PdfPreview(
            build: (_) => pdfBytes,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            useActions: false,
            maxPageWidth: 700,
            pdfFileName: _fileName,
          ),
    );
  }
}

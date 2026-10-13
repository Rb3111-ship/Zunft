import '../../../core/i18n/i18n.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/database/app_database.dart' show IssuedDocument;
import '../../../core/theme/app_theme.dart';
import '../../auth/data/business_models.dart' show Business;

/// Subject and text of the mail that carries the PDF.
String documentKindLabel(String docType) => switch (docType) {
      'quote' => 'Angebot',
      'cancellation' => 'Stornorechnung',
      _ => 'Rechnung',
    };

String shareSubject(IssuedDocument doc, Business business) =>
    '${documentKindLabel(doc.docType)} ${doc.docNumber} von ${business.name}';

String shareBody(IssuedDocument doc, Business business) =>
    'Guten Tag,\n\nanbei erhalten Sie ${doc.docType == 'quote' ? 'unser' : 'unsere'} ${documentKindLabel(doc.docType)} ${doc.docNumber}.\n\n'
    'Mit freundlichen Grüßen\n${business.name}';

/// Shows a PDF with share and print actions.
///
/// [onShared] runs after the share sheet was opened (the app then marks the document "sent").
/// [showActions] is false for an unnumbered draft preview, which must not be sent out.
class PdfPreviewScreen extends StatelessWidget {
  final Uint8List pdfBytes;
  final String documentTitle;
  final VoidCallback? onShared;
  final bool showActions;

  /// The customer's e-mail address, subject and text for the mail app (Android fills the address in;
  /// WhatsApp and others ignore these). Null when unknown.
  final String? customerEmail;
  final String? shareSubject;
  final String? shareBody;

  /// Tests replace the real PDF viewer (it needs platform channels).
  static Widget Function(Uint8List bytes, String fileName)? debugBodyBuilder;

  const PdfPreviewScreen({
    super.key,
    required this.pdfBytes,
    required this.documentTitle,
    this.onShared,
    this.showActions = true,
    this.customerEmail,
    this.shareSubject,
    this.shareBody,
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
              tooltip: (customerEmail ?? '').trim().isEmpty
                  ? 'Per WhatsApp / E-Mail senden'.tr
                  : 'Per E-Mail an {0} oder WhatsApp senden'.trf([customerEmail!.trim()]),
              onPressed: () async {
                final email = (customerEmail ?? '').trim();
                await Printing.sharePdf(
                  bytes: pdfBytes,
                  filename: _fileName,
                  subject: shareSubject,
                  body: shareBody,
                  emails: email.isEmpty ? null : [email],
                );
                onShared?.call();
              },
            ),
            IconButton(
              icon: const Icon(Icons.print, color: AppTheme.textPrimary),
              tooltip: 'Drucken'.tr,
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

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_mapping.dart';
import '../../../core/utils/address_parser.dart';
import '../../../core/utils/customer_duplicates.dart';
import '../../auth/data/business_models.dart';
import '../../data/data_repository.dart';
import '../../review/models/draft_models.dart';
import '../domain/document_data.dart';
import '../pdf_generator/din_5008_invoice_template.dart';
import 'documents_remote.dart';

/// Finalizing is not possible as things stand. [message] is German and tells the user what to fix.
class FinalizeBlocked implements Exception {
  const FinalizeBlocked(this.message);
  final String message;
  @override
  String toString() => message;
}

class FinalizeRequest {
  const FinalizeRequest({
    required this.documentId,
    required this.draft,
    required this.business,
    required this.issueDate,
    this.paymentDays = 14,
    this.deliveryPeriod,
    this.createCustomer = true,
    this.captureLogIds = const [],
  });

  /// Generated once per review screen. If the connection drops mid-request, the retry reuses it,
  /// so the server returns the same document instead of issuing a second number.
  final String documentId;
  final DraftDocument draft;
  final Business business;
  final DateTime issueDate;

  /// Invoice: days until payment is due. Quote: days the offer stays valid.
  final int paymentDays;
  final String? deliveryPeriod;

  /// Add a "new customer" from the draft to the customer list.
  final bool createCustomer;

  /// The job's notes that went into this document. The server marks them as used, in the same
  /// transaction as the number, so they cannot appear on a second document.
  final List<String> captureLogIds;
}

class FinalizeResult {
  const FinalizeResult({required this.document, required this.pdf, required this.pdfUploaded});
  final IssuedDocument document;
  final Uint8List pdf;

  /// False if the PDF copy could not be stored online (the document itself is saved either way).
  final bool pdfUploaded;
}

/// Turns a reviewed draft into an issued, numbered, locked document.
class DocumentService {
  DocumentService(
    this._db,
    this._remote, {
    required DataRepository data,
  }) : _data = data;

  final AppDatabase _db;
  final DocumentsRemote _remote;
  final DataRepository _data;

  /// Over this gross amount an invoice must show the recipient's address (§ 33 UStDV).
  static const smallInvoiceLimitCents = 25000;

  /// What is wrong with this draft or business for the given document type, or null. These are the
  /// same rules the database enforces; checking here gives a clear message without a round trip.
  static String? blockReason(DraftDocument draft, Business business) {
    final isInvoice = draft.documentType == 'invoice';

    if (draft.lineItems.isEmpty) return 'Bitte mindestens eine Position hinzufügen.';
    if (draft.customer.extractedName.trim().isEmpty) return 'Bitte den Namen des Kunden angeben.';
    for (final item in draft.lineItems) {
      if (item.description.trim().isEmpty) return 'Eine Position hat keine Bezeichnung.';
      if (item.quantity <= 0) return 'Eine Position hat eine ungültige Menge.';
    }

    if (isInvoice) {
      final missing = business.missingInvoiceFields.where((f) => f != 'IBAN').toList();
      if (missing.isNotEmpty) {
        return 'Für eine Rechnung fehlt noch in den Betriebsdaten: ${missing.join(', ')}.';
      }
      final gross = FinancialSummary.calculate(items: draft.lineItems, vatRate: business.defaultVatRate).totalGrossCents;
      if (gross > smallInvoiceLimitCents && (draft.customer.extractedAddress ?? '').trim().isEmpty) {
        return 'Bei Rechnungen über 250 € muss die Anschrift des Kunden angegeben werden.';
      }
    }
    return null;
  }

  /// Throws [FinalizeBlocked] (fixable by the user), or the [DocumentOfflineException],
  /// [DocumentAuthException], [DocumentRejectedException] from the server call.
  Future<FinalizeResult> finalize(FinalizeRequest req) async {
    final reason = blockReason(req.draft, req.business);
    if (reason != null) throw FinalizeBlocked(reason);

    final draft = req.draft;
    final isInvoice = draft.documentType == 'invoice';
    final address = draft.customer.extractedAddress?.trim();

    // A new customer who is clearly someone we already have (same name AND same address, phone or
    // e-mail) is not created a second time: the document and the job point to the existing one.
    var customerId = draft.customer.matchedCustomerId;
    if (customerId == null) {
      final a = parseGermanAddress(address);
      final matches = findDuplicateCustomers(await _db.allCustomers(), name: draft.customer.extractedName, street: a.street, zip: a.zip);
      final strong = matches.where((m) => m.strong).firstOrNull;
      if (strong != null) customerId = strong.customer.id;
    }

    // 1. One server call: validates, issues the number, stores the document (atomic).
    final row = await _remote.createDocument({
      'id': req.documentId,
      'doc_type': draft.documentType,
      'title': draft.title,
      'job_id': draft.jobId,
      if (req.captureLogIds.isNotEmpty) 'capture_log_ids': req.captureLogIds,
      'customer_id': customerId,
      'date_issued': _isoDate(req.issueDate),
      'date_due': _isoDate(_addDays(req.issueDate, req.paymentDays)),
      if (isInvoice) 'delivery_period': req.deliveryPeriod,
      'recipient_snapshot': {
        'name': draft.customer.extractedName.trim(),
        'address': (address == null || address.isEmpty) ? null : address,
      },
      'line_items': [
        for (final i in draft.lineItems)
          {
            'type': i.type,
            'description': i.description.trim(),
            'quantity': i.quantity,
            'unit': i.unit,
            'unit_price_net_cents': i.unitPriceNetCents,
          },
      ],
    });

    // 2. Keep the stored document locally right away so it shows up without waiting for a sync.
    await _db.upsertDocument(documentFromRemote(row));
    var document = (await _db.documentById(req.documentId))!;

    // 3. The PDF is made from the SERVER's numbers. Storing a copy online is best-effort: the
    //    document is valid without it and the PDF can always be recreated.
    final pdf = await Din5008PdfGenerator.generate(PdfDocumentData.fromIssued(document, req.business));
    var uploaded = false;
    try {
      final path = '${req.business.id}/${document.docNumber}.pdf';
      await _remote.uploadPdf(path, pdf);
      await _remote.setPdfPath(document.id, path);
      await _db.updateDocument(document.id, IssuedDocumentsCompanion(pdfPath: Value(path)));
      document = (await _db.documentById(document.id))!;
      uploaded = true;
    } catch (_) {}

    // 4. Housekeeping. None of this may undo or fail an issued document.
    await _bestEffort(() async {
      if (req.createCustomer && customerId == null) {
        final a = parseGermanAddress(address);
        final customerId = await _data.saveCustomer(name: draft.customer.extractedName, street: a.street, zip: a.zip, city: a.city);
        final jobId = draft.jobId;
        if (jobId != null) await _data.assignJobCustomer(jobId, customerId);
      }
    });
    await _bestEffort(() async {
      final jobId = draft.jobId;
      if (jobId != null && customerId != null) await _data.assignJobCustomer(jobId, customerId);
    });
    await _bestEffort(() async {
      final jobId = draft.jobId;
      if (jobId != null) await _data.advanceJobStatus(jobId, isInvoice ? JobStatus.invoiced : JobStatus.quoteSent);
    });

    return FinalizeResult(document: document, pdf: pdf, pdfUploaded: uploaded);
  }

  /// Moves a document to [status] (sent / paid). Needs a connection; the database enforces the rules.
  Future<void> markStatus(String documentId, String status) async {
    await _remote.updateStatus(documentId, status);
    await _db.updateDocument(documentId, IssuedDocumentsCompanion(status: Value(status)));
  }

  /// The original PDF from storage if available, otherwise recreated from the stored data.
  Future<Uint8List> pdfFor(IssuedDocument document, Business business) async {
    final path = document.pdfPath;
    if (path != null) {
      try {
        return await _remote.downloadPdf(path);
      } catch (_) {
        // offline or file gone: fall through to regenerate
      }
    }
    return Din5008PdfGenerator.generate(PdfDocumentData.fromIssued(document, business));
  }

  Future<void> _bestEffort(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  /// Calendar days, not 24-hour blocks: Duration(days: n) is off by one across a daylight-saving change.
  static DateTime _addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

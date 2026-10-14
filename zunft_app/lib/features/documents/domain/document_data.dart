import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../../auth/data/business_models.dart';
import '../../review/models/draft_models.dart';

/// One printed position. Amounts are whole cents.
class DocumentLine {
  const DocumentLine({
    required this.type,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPriceNetCents,
    required this.totalNetCents,
  });

  final String type; // labor | material | flat_fee
  final String description;
  final double quantity;
  final String unit;
  final int unitPriceNetCents;
  final int totalNetCents;

  /// § 35a EStG: labor and flat fees (Anfahrt etc.) are service costs; only material is excluded.
  bool get isService => type == 'labor' || type == 'flat_fee';

  factory DocumentLine.fromJson(Map<String, dynamic> j) {
    final price = (j['unit_price_net_cents'] as num).toInt();
    final qty = (j['quantity'] as num).toDouble();
    return DocumentLine(
      type: j['type'] as String,
      description: j['description'] as String,
      quantity: qty,
      unit: j['unit'] as String,
      unitPriceNetCents: price,
      totalNetCents: (j['total_net_cents'] as num?)?.toInt() ?? (qty * price).round(),
    );
  }

  factory DocumentLine.fromDraft(DraftLineItem i) => DocumentLine(
        type: i.type,
        description: i.description,
        quantity: i.quantity,
        unit: i.unit,
        unitPriceNetCents: i.unitPriceNetCents,
        totalNetCents: i.totalNetCents,
      );
}

/// The sender block of the letterhead, taken from the business settings.
class CompanyDetails {
  const CompanyDetails({
    required this.name,
    required this.ownerName,
    this.street = '',
    this.zip = '',
    this.city = '',
    this.phone = '',
    this.email = '',
    this.taxNumber = '',
    this.vatId = '',
    this.bankName = '',
    this.iban = '',
    this.bic = '',
  });

  final String name;
  final String ownerName;
  final String street;
  final String zip;
  final String city;
  final String phone;
  final String email;
  final String taxNumber;
  final String vatId;
  final String bankName;
  final String iban;
  final String bic;

  String get addressLine => [street, '$zip $city'.trim()].where((s) => s.isNotEmpty).join(', ');

  factory CompanyDetails.fromBusiness(Business b) => CompanyDetails(
        name: b.name,
        ownerName: b.ownerName,
        street: b.addressStreet ?? '',
        zip: b.addressZip ?? '',
        city: b.addressCity ?? '',
        phone: b.phone ?? '',
        email: b.email ?? '',
        taxNumber: b.taxNumber ?? '',
        vatId: b.vatId ?? '',
        bankName: b.bankName ?? '',
        iban: b.iban ?? '',
        bic: b.bic ?? '',
      );
}

/// Everything the PDF needs, independent of where it came from: a stored (issued) document, or
/// an unsaved draft for a preview. A preview has no number and is marked "Entwurf".
class PdfDocumentData {
  const PdfDocumentData({
    required this.docType,
    required this.docNumber,
    required this.title,
    required this.issueDate,
    required this.dueDate,
    required this.deliveryPeriod,
    required this.recipientName,
    required this.recipientAddress,
    required this.lines,
    required this.laborNetCents,
    required this.materialNetCents,
    required this.netCents,
    required this.vatRate,
    required this.vatCents,
    required this.grossCents,
    required this.company,
    this.buyerReference,
    this.buyerEmail,
  });

  final String docType; // quote | invoice | cancellation
  final String? docNumber; // null = preview
  final String? title;
  final DateTime issueDate;
  final DateTime? dueDate; // invoice: pay by, quote: valid until
  final String? deliveryPeriod;
  final String recipientName;
  final String? recipientAddress;
  final List<DocumentLine> lines;
  final int laborNetCents;
  final int materialNetCents;
  final int netCents;
  final double vatRate;
  final int vatCents;
  final int grossCents;
  final CompanyDetails company;

  /// Leitweg-ID of a public-sector customer (XRechnung buyer reference) and the buyer's e-mail address.
  final String? buyerReference;
  final String? buyerEmail;

  bool get isInvoice => docType == 'invoice';
  bool get isCancellation => docType == 'cancellation';
  bool get isPreview => docNumber == null;

  /// Kleinunternehmer (§ 19 UStG): no VAT is charged.
  bool get isSmallBusiness => vatRate == 0;

  /// § 35a EStG: the tax deduction is based on the labor amount INCLUDING VAT.
  int get laborGrossCents => laborNetCents + (laborNetCents * vatRate / 100).round();

  /// From the stored document. All amounts are the server's, never recalculated.
  factory PdfDocumentData.fromIssued(IssuedDocument d, Business business) {
    final raw = jsonDecode(d.lineItemsJson) as List<dynamic>;
    return PdfDocumentData(
      docType: d.docType,
      docNumber: d.docNumber,
      title: d.title,
      issueDate: DateTime.parse(d.dateIssued),
      dueDate: d.dateDue == null ? null : DateTime.parse(d.dateDue!),
      deliveryPeriod: d.deliveryPeriod,
      recipientName: d.recipientName,
      recipientAddress: d.recipientAddress,
      lines: raw.map((e) => DocumentLine.fromJson((e as Map).cast<String, dynamic>())).toList(),
      laborNetCents: d.subtotalLaborCents,
      materialNetCents: d.subtotalMaterialCents,
      netCents: d.totalNetCents,
      vatRate: d.vatRate,
      vatCents: d.vatAmountCents,
      grossCents: d.totalGrossCents,
      company: CompanyDetails.fromBusiness(business),
      buyerReference: d.buyerReference,
      buyerEmail: d.buyerEmail,
    );
  }

  /// Unsaved draft: totals are calculated here with the same rules as the server.
  factory PdfDocumentData.preview({
    required DraftDocument draft,
    required Business business,
    required DateTime issueDate,
    DateTime? dueDate,
    String? deliveryPeriod,
  }) {
    final summary = FinancialSummary.calculate(items: draft.lineItems, vatRate: business.defaultVatRate);
    return PdfDocumentData(
      docType: draft.documentType,
      docNumber: null,
      title: draft.title,
      issueDate: issueDate,
      dueDate: dueDate,
      deliveryPeriod: deliveryPeriod,
      recipientName: draft.customer.extractedName,
      recipientAddress: draft.customer.extractedAddress,
      lines: draft.lineItems.map(DocumentLine.fromDraft).toList(),
      laborNetCents: summary.subtotalLaborCents,
      materialNetCents: summary.subtotalMaterialCents,
      netCents: summary.totalNetCents,
      vatRate: summary.vatRate,
      vatCents: summary.vatAmountCents,
      grossCents: summary.totalGrossCents,
      company: CompanyDetails.fromBusiness(business),
    );
  }
}

import 'package:uuid/uuid.dart';

/// Models representing AI-parsed draft documents with § 35a EStG tax calculations
class DraftLineItem {
  final String id;
  String type; // 'labor', 'material', 'flat_fee'
  String description;
  double quantity;
  String unit; // 'Std', 'Stk', 'm', 'Pauschal'
  int unitPriceNetCents;
  bool requiresConfirmation;

  DraftLineItem({
    required this.id,
    required this.type,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPriceNetCents,
    this.requiresConfirmation = false,
  });

  int get totalNetCents => (quantity * unitPriceNetCents).round();

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'description': description,
        'quantity': quantity,
        'unit': unit,
        'unit_price_net_cents': unitPriceNetCents,
        'requires_confirmation': requiresConfirmation,
      };

  factory DraftLineItem.fromJson(Map<String, dynamic> json) => DraftLineItem(
        // Server drafts carry no ids. Each item needs its own (edit/delete work by id), and
        // DateTime.now() would give items parsed in the same millisecond the same id.
        id: json['id'] ?? const Uuid().v4(),
        type: json['type'] ?? 'material',
        description: json['description'] ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
        unit: json['unit'] ?? 'Stk',
        unitPriceNetCents: (json['unit_price_net_cents'] as num?)?.toInt() ?? 0,
        requiresConfirmation: json['requires_confirmation'] ?? false,
      );
}

class CustomerMatch {
  String? matchedCustomerId;
  String extractedName;
  String? extractedAddress;
  String confidence; // 'exact', 'fuzzy', 'new'

  CustomerMatch({
    this.matchedCustomerId,
    required this.extractedName,
    this.extractedAddress,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'matched_customer_id': matchedCustomerId,
        'extracted_name': extractedName,
        'extracted_address': extractedAddress,
        'confidence': confidence,
      };

  factory CustomerMatch.fromJson(Map<String, dynamic> json) => CustomerMatch(
        matchedCustomerId: json['matched_customer_id'],
        extractedName: json['extracted_name'] ?? 'Unbekannter Kunde',
        extractedAddress: json['extracted_address'],
        confidence: json['confidence'] ?? 'new',
      );
}

class FinancialSummary {
  final int subtotalLaborCents;
  final int subtotalMaterialCents;
  final int totalNetCents;
  final double vatRate;
  final int vatAmountCents;
  final int totalGrossCents;

  FinancialSummary({
    required this.subtotalLaborCents,
    required this.subtotalMaterialCents,
    required this.totalNetCents,
    required this.vatRate,
    required this.vatAmountCents,
    required this.totalGrossCents,
  });

  factory FinancialSummary.calculate({
    required List<DraftLineItem> items,
    double vatRate = 19.0,
  }) {
    int labor = 0;
    int material = 0;
    int net = 0;

    for (final item in items) {
      final total = item.totalNetCents;
      // § 35a EStG: Anfahrts-/Pauschalen are service costs (labor); only material is excluded.
      if (item.type == 'labor' || item.type == 'flat_fee') {
        labor += total;
      } else {
        material += total;
      }
      net += total;
    }

    final vat = (net * vatRate / 100.0).round();
    final gross = net + vat;

    return FinancialSummary(
      subtotalLaborCents: labor,
      subtotalMaterialCents: material,
      totalNetCents: net,
      vatRate: vatRate,
      vatAmountCents: vat,
      totalGrossCents: gross,
    );
  }
}

class DraftDocument {
  String? jobId;
  String title;
  String documentType; // 'quote' or 'invoice'
  CustomerMatch customer;
  List<DraftLineItem> lineItems;
  List<String> warnings;
  String? rawTranscript;

  /// A name/address the speaker mentioned. Only a suggestion for a job without a customer:
  /// the customer is chosen by the user, never by the AI.
  String? customerHintName;
  String? customerHintAddress;

  /// VAT rate in percent, taken from the business settings by the review screen.
  double vatRate;

  DraftDocument({
    this.jobId,
    required this.title,
    required this.documentType,
    required this.customer,
    required this.lineItems,
    this.warnings = const [],
    this.rawTranscript,
    this.customerHintName,
    this.customerHintAddress,
    this.vatRate = 19.0,
  });

  FinancialSummary get financialSummary => FinancialSummary.calculate(items: lineItems, vatRate: vatRate);

  factory DraftDocument.fromJson(Map<String, dynamic> json, {String? transcript, String? jobId}) {
    final parsed = json['parsedData'] ?? json;
    final itemsList = (parsed['line_items'] as List<dynamic>?)
            ?.map((e) => DraftLineItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final warningsList = (parsed['warnings'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final hint = parsed['customer_hint'] is Map ? parsed['customer_hint'] as Map : const {};
    String? clean(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

    return DraftDocument(
      jobId: jobId ?? json['jobId'],
      title: parsed['title'] ?? 'Neuer Auftrag',
      documentType: parsed['document_type'] ?? 'quote',
      customer: CustomerMatch(extractedName: '', confidence: 'new'),
      lineItems: itemsList,
      warnings: warningsList,
      rawTranscript: transcript ?? json['transcript'],
      customerHintName: clean(hint['name']),
      customerHintAddress: clean(hint['address']),
    );
  }
}

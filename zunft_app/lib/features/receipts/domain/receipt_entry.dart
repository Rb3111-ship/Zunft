/// Where a receipt (Beleg) stands: still waiting to be billed to the customer, already on an
/// invoice, or taken off the job (not billed, but the purchase document is kept).
enum ReceiptStatus { open, billed, removed }

class ReceiptLine {
  const ReceiptLine({required this.description, required this.quantity, required this.unit, required this.unitNetCents});

  final String description;
  final double quantity;
  final String unit;
  final int unitNetCents;

  int get totalNetCents => (quantity * unitNetCents).round();
}

/// One photographed receipt as stored by the server (a `capture_logs` row with an image).
class ReceiptEntry {
  const ReceiptEntry({
    required this.id,
    required this.createdAt,
    required this.imagePath,
    required this.status,
    this.receiptDate,
    this.supplier,
    this.receiptNumber,
    this.totalPrintedCents,
    this.netCents = 0,
    this.vatCents = 0,
    this.grossFromPositionsCents = 0,
    this.jobId,
    this.jobTitle,
    this.documentNumber,
    this.authorName,
    this.lines = const [],
    this.warnings = const [],
  });

  final String id;
  final DateTime createdAt;
  final String imagePath;
  final ReceiptStatus status;

  /// The date printed on the receipt (null if it could not be read).
  final DateTime? receiptDate;
  final String? supplier;
  final String? receiptNumber;

  /// The total as printed on the receipt, in cents (usually gross).
  final int? totalPrintedCents;

  /// Sum of the positions as read (net), their VAT and gross at the business's rate.
  final int netCents;
  final int vatCents;
  final int grossFromPositionsCents;

  final String? jobId;
  final String? jobTitle;

  /// The invoice number this receipt was billed in.
  final String? documentNumber;
  final String? authorName;
  final List<ReceiptLine> lines;
  final List<String> warnings;

  /// The date that counts for sorting and for the month: the printed one, else the day it was added.
  DateTime get date => receiptDate ?? DateTime(createdAt.year, createdAt.month, createdAt.day);

  /// "2026-10", used for the month filter and the folders of the export.
  String get monthKey => '${date.year}-${date.month.toString().padLeft(2, '0')}';

  /// The amount to show: what the receipt says if known, otherwise the positions' gross.
  int get grossCents => totalPrintedCents ?? grossFromPositionsCents;

  String get supplierLabel => (supplier ?? '').isEmpty ? 'Unbekannter Lieferant' : supplier!;

  String get statusLabel => switch (status) {
        ReceiptStatus.open => 'Noch nicht abgerechnet',
        ReceiptStatus.billed => documentNumber == null ? 'Abgerechnet' : 'Abgerechnet in $documentNumber',
        ReceiptStatus.removed => 'Vom Auftrag entfernt',
      };

  factory ReceiptEntry.fromRow(Map<String, dynamic> row) {
    final parsed = row['ai_parsed_json'] is Map ? Map<String, dynamic>.from(row['ai_parsed_json'] as Map) : <String, dynamic>{};
    final meta = parsed['receipt'] is Map ? Map<String, dynamic>.from(parsed['receipt'] as Map) : <String, dynamic>{};
    final sum =
        parsed['financial_summary'] is Map ? Map<String, dynamic>.from(parsed['financial_summary'] as Map) : <String, dynamic>{};

    int? intOf(Object? v) => v is num ? v.round() : null;
    String? text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

    final paths = row['photo_storage_paths'];
    final image = paths is List && paths.isNotEmpty ? paths.first as String : '';

    final job = row['jobs'];
    final doc = row['documents'];
    final status = row['discarded_at'] != null
        ? ReceiptStatus.removed
        : (row['document_id'] != null ? ReceiptStatus.billed : ReceiptStatus.open);

    final profile = row['profiles'];

    return ReceiptEntry(
      id: row['id'] as String,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      imagePath: image,
      status: status,
      receiptDate: DateTime.tryParse(text(meta['receipt_date']) ?? ''),
      supplier: text(meta['supplier']),
      receiptNumber: text(meta['receipt_number']),
      totalPrintedCents: intOf(meta['total_printed_cents']),
      netCents: intOf(sum['total_net_cents']) ?? 0,
      vatCents: intOf(sum['vat_amount_cents']) ?? 0,
      grossFromPositionsCents: intOf(sum['total_gross_cents']) ?? 0,
      jobId: row['job_id'] as String?,
      jobTitle: job is Map ? text(job['title']) : null,
      documentNumber: doc is Map ? text(doc['doc_number']) : null,
      authorName: (profile is Map ? text(profile['full_name']) : null) ?? text(row['created_by_name']),
      lines: [
        for (final l in (parsed['line_items'] as List? ?? const []))
          if (l is Map)
            ReceiptLine(
              description: text(l['description']) ?? '',
              quantity: (l['quantity'] as num?)?.toDouble() ?? 1,
              unit: text(l['unit']) ?? 'Stk',
              unitNetCents: intOf(l['unit_price_net_cents']) ?? 0,
            ),
      ],
      warnings: [for (final w in (parsed['warnings'] as List? ?? const [])) if (w is String) w],
    );
  }
}

const _monthNames = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember'
];

/// "2026-10" -> "Oktober 2026".
String monthLabel(String monthKey) {
  final parts = monthKey.split('-');
  return '${_monthNames[int.parse(parts[1]) - 1]} ${parts[0]}';
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Does [r] match what the user typed? Every typed word must appear somewhere: supplier, receipt
/// number, job, who added it, date, amount, status or the name of a position.
bool receiptMatches(ReceiptEntry r, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final euros = (r.grossCents / 100).toStringAsFixed(2).replaceAll('.', ',');
  final haystack = [
    r.supplier ?? '',
    r.receiptNumber ?? '',
    r.jobTitle ?? '',
    r.authorName ?? '',
    _fmtDate(r.date),
    euros,
    r.statusLabel,
    for (final l in r.lines) l.description,
  ].join(' ').toLowerCase();
  return words.every(haystack.contains);
}

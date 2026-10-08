import 'dart:typed_data';

import 'package:zunft_app/features/documents/data/documents_remote.dart';

/// Stand-in for the server side of documents. Mimics create_document(): it validates, computes the
/// totals itself, issues gapless numbers per type and year, and is idempotent per document id.
class FakeDocumentsRemote implements DocumentsRemote {
  /// Business VAT rate used for new documents (the server reads it from the business).
  double vatRate = 19;

  /// Thrown by [createDocument] while non-null.
  Exception? createError;

  /// Thrown by [uploadPdf] while non-null.
  Exception? uploadError;

  /// Thrown by [updateStatus] while non-null.
  Exception? statusError;

  /// Thrown by [downloadPdf] while non-null.
  Exception? downloadError;

  /// Called once for every NEW document (not for idempotent retries), like the server marking used notes.
  void Function(Map<String, dynamic> payload)? onCreated;

  final Map<String, Map<String, dynamic>> documents = {};
  final Map<String, int> _counters = {};
  final List<Map<String, dynamic>> createCalls = [];
  final Map<String, Uint8List> storedPdfs = {};
  final List<String> statusChanges = [];
  int serverClock = 0;

  @override
  Future<Map<String, dynamic>> createDocument(Map<String, dynamic> payload) async {
    createCalls.add(payload);
    if (createError != null) throw createError!;

    final id = payload['id'] as String;
    if (documents.containsKey(id)) return documents[id]!; // idempotent retry

    final lines = <Map<String, dynamic>>[];
    var labor = 0, material = 0;
    for (final raw in payload['line_items'] as List) {
      final item = Map<String, dynamic>.from(raw as Map);
      final total = ((item['quantity'] as num) * (item['unit_price_net_cents'] as num)).round();
      if (item['type'] == 'labor' || item['type'] == 'flat_fee') {
        labor += total;
      } else {
        material += total;
      }
      lines.add({...item, 'total_net_cents': total});
    }
    final net = labor + material;
    final vat = (net * vatRate / 100).round();

    final issued = payload['date_issued'] as String;
    final type = payload['doc_type'] as String;
    final year = int.parse(issued.substring(0, 4));
    final key = '$type-$year';
    final n = _counters[key] = (_counters[key] ?? 0) + 1;
    final number = '${type == 'invoice' ? 'RE' : 'ANG'}-$year-${n.toString().padLeft(4, '0')}';

    onCreated?.call(payload);
    return documents[id] = {
      'id': id,
      'business_id': 'b1',
      'job_id': payload['job_id'],
      'customer_id': payload['customer_id'],
      'doc_type': type,
      'doc_number': number,
      'status': 'issued',
      'title': payload['title'],
      'date_issued': issued,
      'date_due': payload['date_due'],
      'delivery_period': payload['delivery_period'],
      'subtotal_labor_cents': labor,
      'subtotal_material_cents': material,
      'total_net_cents': net,
      'vat_rate': vatRate,
      'vat_amount_cents': vat,
      'total_gross_cents': net + vat,
      'line_items': lines,
      'recipient_snapshot': payload['recipient_snapshot'],
      'pdf_url': null,
      'is_gobd_locked': true,
      'updated_at': DateTime.utc(2026, 10, 3, 12, 0, ++serverClock).toIso8601String(),
    };
  }

  /// Called when a cancellation is issued, like the server releasing the notes.
  void Function(Map<String, dynamic> cancellation, Map<String, dynamic> original)? onCancelled;
  final List<String> cancelCalls = [];

  @override
  Future<Map<String, dynamic>> cancelDocument(String id, String originalId) async {
    cancelCalls.add('$id:$originalId');
    if (createError != null) throw createError!;
    final orig = documents[originalId];
    if (orig == null) throw const DocumentRejectedException('document not found');
    if (documents.containsKey(id)) {
      return {'cancellation': documents[id], 'original': orig}; // idempotent retry
    }
    if (orig['status'] == 'paid') throw const DocumentRejectedException('Die Rechnung ist schon als bezahlt markiert.');
    if (orig['status'] == 'canceled') throw const DocumentRejectedException('Diese Rechnung wurde schon storniert.');
    final n = _counters['cancellation-2026'] = (_counters['cancellation-2026'] ?? 0) + 1;
    orig['status'] = 'canceled';
    orig['updated_at'] = DateTime.utc(2026, 10, 3, 12, 0, ++serverClock).toIso8601String();
    final lines = [
      for (final l in orig['line_items'] as List)
        {
          ...Map<String, dynamic>.from(l as Map),
          'unit_price_net_cents': -(l['unit_price_net_cents'] as num).toInt(),
          'total_net_cents': -(l['total_net_cents'] as num).toInt(),
        }
    ];
    final row = documents[id] = {
      ...orig,
      'id': id,
      'doc_type': 'cancellation',
      'doc_number': 'ST-2026-${n.toString().padLeft(4, '0')}',
      'status': 'issued',
      'title': 'Stornierung der Rechnung ${orig['doc_number']}',
      'subtotal_labor_cents': -(orig['subtotal_labor_cents'] as num).toInt(),
      'subtotal_material_cents': -(orig['subtotal_material_cents'] as num).toInt(),
      'total_net_cents': -(orig['total_net_cents'] as num).toInt(),
      'vat_amount_cents': -(orig['vat_amount_cents'] as num).toInt(),
      'total_gross_cents': -(orig['total_gross_cents'] as num).toInt(),
      'line_items': lines,
      'pdf_url': null,
      'updated_at': DateTime.utc(2026, 10, 3, 12, 0, ++serverClock).toIso8601String(),
    };
    onCancelled?.call(row, orig);
    return {'cancellation': row, 'original': orig};
  }

  @override
  Future<void> updateStatus(String id, String status) async {
    if (statusError != null) throw statusError!;
    statusChanges.add('$id:$status');
    documents[id]?['status'] = status;
  }

  @override
  Future<void> uploadPdf(String path, Uint8List bytes) async {
    if (uploadError != null) throw uploadError!;
    storedPdfs[path] = bytes;
  }

  @override
  Future<void> setPdfPath(String id, String path) async {
    documents[id]?['pdf_url'] = path;
  }

  @override
  Future<Uint8List> downloadPdf(String path) async {
    if (downloadError != null) throw downloadError!;
    final bytes = storedPdfs[path];
    if (bytes == null) throw const DocumentRejectedException('not found');
    return bytes;
  }
}

/// A server-side document row as the sync pull would deliver it.
Map<String, dynamic> remoteDocument(
  String id, {
  String number = 'RE-2026-0001',
  String type = 'invoice',
  String status = 'issued',
  String recipient = 'Thomas Müller',
  int gross = 20944,
  String business = 'b1',
  String date = '2026-10-01',
  String? customerId,
}) =>
    {
      'id': id,
      'business_id': business,
      'job_id': null,
      'customer_id': customerId,
      'doc_type': type,
      'doc_number': number,
      'status': status,
      'title': 'Steckdose Keller',
      'date_issued': date,
      'date_due': '2026-10-15',
      'delivery_period': '01.10.2026',
      'subtotal_labor_cents': 13600,
      'subtotal_material_cents': 4000,
      'total_net_cents': 17600,
      'vat_rate': '19.00', // NUMERIC arrives as a string through some transports
      'vat_amount_cents': 3344,
      'total_gross_cents': gross,
      'line_items': [
        {
          'type': 'labor',
          'description': 'Steckdose montiert',
          'quantity': 2,
          'unit': 'Std',
          'unit_price_net_cents': 6800,
          'total_net_cents': 13600
        },
        {
          'type': 'material',
          'description': 'Doppelsteckdose',
          'quantity': 1,
          'unit': 'Stk',
          'unit_price_net_cents': 4000,
          'total_net_cents': 4000
        },
      ],
      'recipient_snapshot': {'name': recipient, 'address': 'Elbchaussee 118, 22763 Hamburg'},
      'pdf_url': null,
      'is_gobd_locked': true,
    };

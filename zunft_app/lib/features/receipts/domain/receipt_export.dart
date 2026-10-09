import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../../core/database/app_database.dart' show IssuedDocument;
import 'receipt_entry.dart';

String _euro(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  return '${negative ? '-' : ''}${abs ~/ 100},${(abs % 100).toString().padLeft(2, '0')}';
}

String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _field(String v) {
  // A cell that starts with = + - @ is read as a formula by spreadsheet programs: neutralise it.
  final safe = RegExp(r'^[=+@]').hasMatch(v) ? "'$v" : v;
  return safe.contains(RegExp(r'[;"\n\r]')) ? '"${safe.replaceAll('"', '""')}"' : safe;
}

/// Semicolon separated with German number format and a byte order mark: opens correctly in
/// Excel and in the programs of a Steuerberater.
String _csv(List<List<String>> rows) => '﻿${rows.map((r) => r.map(_field).join(';')).join('\r\n')}\r\n';

String _slug(String s) {
  final t = s
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('Ä', 'Ae')
      .replaceAll('Ö', 'Oe')
      .replaceAll('Ü', 'Ue')
      .replaceAll('ß', 'ss')
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return t.length > 40 ? t.substring(0, 40) : t;
}

String _isoDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// File name of a receipt inside the export, e.g. `2026-10/2026-10-07_Baumarkt-Hansen_20457-0093.jpg`.
String receiptFileName(ReceiptEntry r) {
  final parts = [_isoDay(r.date), _slug(r.supplierLabel), if ((r.receiptNumber ?? '').isNotEmpty) _slug(r.receiptNumber!)]
      .where((s) => s.isNotEmpty)
      .join('_');
  return '${r.monthKey}/$parts.jpg';
}

String receiptsCsv(List<ReceiptEntry> receipts, Map<String, String> fileNames) => _csv([
      [
        'Belegdatum',
        'Lieferant',
        'Belegnummer',
        'Auftrag',
        'Erfasst von',
        'Status',
        'Summe Positionen netto',
        'MwSt. auf Positionen',
        'Gesamtbetrag laut Beleg',
        'Datei'
      ],
      for (final r in receipts)
        [
          _date(r.date),
          r.supplier ?? '',
          r.receiptNumber ?? '',
          r.jobTitle ?? '',
          r.authorName ?? '',
          r.statusLabel,
          _euro(r.netCents),
          _euro(r.vatCents),
          r.totalPrintedCents == null ? '' : _euro(r.totalPrintedCents!),
          fileNames[r.id] ?? '',
        ],
    ]);

String documentsCsv(List<IssuedDocument> docs) {
  String kind(String t) => switch (t) {
        'quote' => 'Angebot',
        'cancellation' => 'Stornorechnung',
        _ => 'Rechnung',
      };
  String status(String s) => switch (s) {
        'issued' => 'Erstellt',
        'sent' => 'Versendet',
        'paid' => 'Bezahlt',
        'canceled' => 'Storniert',
        _ => s,
      };
  return _csv([
    ['Nummer', 'Art', 'Datum', 'Kunde', 'Status', 'Netto', 'MwSt.', 'Brutto'],
    for (final d in docs)
      [
        d.docNumber,
        kind(d.docType),
        _date(DateTime.parse(d.dateIssued)),
        d.recipientName,
        status(d.status),
        _euro(d.totalNetCents),
        _euro(d.vatAmountCents),
        _euro(d.totalGrossCents),
      ],
  ]);
}

class ReceiptExport {
  const ReceiptExport({required this.zip, required this.receipts, required this.missingPhotos});

  final Uint8List zip;
  final int receipts;

  /// Photos that could not be fetched (listed in the ZIP's note file).
  final int missingPhotos;
}

/// A ZIP for the tax advisor: the receipt photos in one folder per month, a list of the receipts
/// (CSV) and, if given, a list of the issued documents. [fetchPhoto] downloads one photo.
Future<ReceiptExport> buildReceiptExport({
  required List<ReceiptEntry> receipts,
  required List<IssuedDocument> documents,
  required Future<Uint8List> Function(String imagePath) fetchPhoto,
  required String periodLabel,
}) async {
  final archive = Archive();
  final names = <String, String>{};
  final used = <String>{};
  final missing = <String>[];

  for (final r in receipts) {
    var name = receiptFileName(r);
    if (!used.add(name)) {
      name = name.replaceFirst(RegExp(r'\.jpg$'), '_${r.id.substring(0, 6)}.jpg');
      used.add(name);
    }
    try {
      final bytes = await fetchPhoto(r.imagePath);
      archive.addFile(ArchiveFile('belege/$name', bytes.length, bytes));
      names[r.id] = 'belege/$name';
    } catch (_) {
      missing.add('${_date(r.date)} ${r.supplierLabel}');
    }
  }

  void addText(String path, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  addText('belege.csv', receiptsCsv(receipts, names));
  if (documents.isNotEmpty) addText('ausgangsrechnungen.csv', documentsCsv(documents));
  addText(
    'LIESMICH.txt',
    'Zunft - Export $periodLabel\r\n\r\n'
    '${receipts.length} Einkaufsbelege (Fotos im Ordner "belege", Liste in belege.csv).\r\n'
    '${documents.length} ausgestellte Dokumente (ausgangsrechnungen.csv).\r\n\r\n'
    'Die Beträge der Einkaufsbelege wurden automatisch aus den Fotos gelesen. Maßgeblich ist immer das Foto.\r\n'
    '${missing.isEmpty ? '' : '\r\nDiese Fotos konnten nicht geladen werden:\r\n${missing.map((m) => '- $m').join('\r\n')}\r\n'}',
  );

  final encoded = ZipEncoder().encode(archive);
  return ReceiptExport(zip: Uint8List.fromList(encoded), receipts: receipts.length, missingPhotos: missing.length);
}

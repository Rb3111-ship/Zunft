import 'dart:typed_data';

import 'package:zunft_app/features/receipts/data/receipts_remote.dart';
import 'package:zunft_app/features/receipts/domain/receipt_entry.dart';

/// The receipt archive of the cloud, and the share sheet of the phone.
class FakeReceiptsRemote implements ReceiptsRemote {
  final List<ReceiptEntry> entries = [];

  /// Thrown by [fetchAll] while non-null.
  ReceiptsException? error;

  /// Paths whose photo cannot be downloaded.
  final Set<String> brokenPhotos = {};
  final List<String> downloads = [];

  @override
  Future<List<ReceiptEntry>> fetchAll() async {
    if (error != null) throw error!;
    return List.of(entries);
  }

  @override
  Future<Uint8List> downloadPhoto(String imagePath) async {
    downloads.add(imagePath);
    if (brokenPhotos.contains(imagePath)) throw StateError('gone');
    return Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]);
  }
}

class FakeFileSharer implements FileSharer {
  final List<({String name, Uint8List bytes, String? subject, String mimeType})> shared = [];
  Object? error;

  @override
  Future<void> share(Uint8List bytes, String fileName, {String? subject, String mimeType = 'application/zip'}) async {
    if (error != null) throw error!;
    shared.add((name: fileName, bytes: bytes, subject: subject, mimeType: mimeType));
  }
}

ReceiptEntry aReceipt({
  String id = 'r1-abcdef',
  String supplier = 'Baumarkt Hansen',
  DateTime? date,
  String? number = '20457-0093',
  int total = 10600,
  String job = 'Steckdose Keller',
  ReceiptStatus status = ReceiptStatus.open,
  String? docNumber,
  String author = 'Thorsten',
  String line = 'Mantelleitung NYM-J 3x1,5',
}) =>
    ReceiptEntry(
      id: id,
      createdAt: DateTime(2026, 10, 8, 9),
      imagePath: 'b1/u1/$id.jpg',
      status: status,
      receiptDate: date ?? DateTime(2026, 10, 7),
      supplier: supplier,
      receiptNumber: number,
      totalPrintedCents: total,
      netCents: 8908,
      vatCents: 1693,
      grossFromPositionsCents: 10601,
      jobId: 'j1',
      jobTitle: job,
      documentNumber: docNumber,
      authorName: author,
      lines: [ReceiptLine(description: line, quantity: 50, unit: 'm', unitNetCents: 100)],
    );

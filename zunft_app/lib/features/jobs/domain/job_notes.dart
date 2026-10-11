import '../../../core/database/app_database.dart';
import '../../customers/presentation/customers_tab.dart' show customerDisplayName;
import '../../review/models/draft_models.dart';

/// One voice (or typed) note on a job, as stored by the server after the AI structured it.
/// A job collects notes from all workers; they are combined into one document at the end.
class JobNote {
  const JobNote({
    required this.id,
    required this.createdAt,
    required this.transcript,
    required this.draft,
    this.authorId,
    this.authorName,
    this.audioPath,
    this.imagePath,
    this.audioDeleted = false,
  });

  /// The server's capture_logs id. Sent to create_document so the note is used up exactly once.
  final String id;
  final DateTime createdAt;
  final String? authorId;
  final String? authorName;
  final String transcript;

  /// Where the recording is stored in the private "captures" bucket; null for typed notes.
  final String? audioPath;

  /// Where the photo of a receipt (Beleg) is stored; null for voice and typed notes.
  final String? imagePath;

  /// The recording was deleted after the retention period; the text of the note is all that is left.
  final bool audioDeleted;

  bool get isReceipt => imagePath != null;

  /// What the AI extracted from this one note (positions, warnings, document type, name hint).
  final DraftDocument draft;

  static String? _firstPath(Object? v) {
    if (v is List && v.isNotEmpty && v.first is String && (v.first as String).isNotEmpty) return v.first as String;
    return null;
  }

  String get author => (authorName ?? '').isEmpty ? 'Mitarbeiter' : authorName!;

  /// From one `capture_logs` row (with the author's profile embedded).
  factory JobNote.fromRow(Map<String, dynamic> row) {
    final parsed = row['ai_parsed_json'];
    final profile = row['profiles'];
    return JobNote(
      id: row['id'] as String,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      authorId: row['created_by'] as String?,
      // The live profile if there is one; otherwise the name stored with the note (the person may have left).
      authorName: (profile is Map ? profile['full_name'] as String? : null) ?? row['created_by_name'] as String?,
      transcript: (row['raw_transcript'] as String?) ?? '',
      audioPath: row['audio_deleted_at'] != null ? null : row['audio_storage_path'] as String?,
      audioDeleted: row['audio_deleted_at'] != null,
      imagePath: _firstPath(row['photo_storage_paths']),
      draft: DraftDocument.fromJson(
        parsed is Map ? Map<String, dynamic>.from(parsed) : <String, dynamic>{},
      ),
    );
  }
}

/// The document for a whole job: the job's customer plus every open note's positions.
///
/// The customer comes from the job (chosen by the user), never from what the AI heard. A spoken
/// name is only offered as a suggestion when the job has no customer yet.
DraftDocument buildJobDraft({
  required Job job,
  Customer? customer,
  required List<JobNote> notes,
  double materialMarkupPercent = 0,
  int trackedMinutes = 0,
  int hourlyRateCents = 0,
  bool replaceNoteLabor = false,
}) {
  // Material from receipts is invoiced with the business's markup (the cost price stays on the receipt).
  final markup = 1 + materialMarkupPercent / 100;
  final items = <DraftLineItem>[
    for (final n in notes)
      for (final i in n.draft.lineItems)
        if (n.isReceipt && materialMarkupPercent > 0)
          DraftLineItem(
            id: i.id,
            type: i.type,
            description: i.description,
            quantity: i.quantity,
            unit: i.unit,
            unitPriceNetCents: (i.unitPriceNetCents * markup).round(),
            requiresConfirmation: i.requiresConfirmation,
          )
        else
          i,
  ];

  final warnings = <String>[];

  // Tracked working time: one position for all of it. If the boss chose "instead of the notes",
  // the spoken working time is taken out so that time is not billed twice.
  if (replaceNoteLabor) {
    final spoken = items.where((i) => i.type == 'labor');
    final hours = spoken.where((i) => i.unit == 'Std').fold<double>(0, (s, i) => s + i.quantity);
    if (spoken.isNotEmpty) {
      final text = hours.toStringAsFixed(hours % 1 == 0 ? 0 : 2).replaceAll('.', ',');
      warnings.add('Die Arbeitszeit aus den Notizen${hours > 0 ? ' ($text Std)' : ''} wurde durch die erfasste Zeit ersetzt.');
    }
    items.removeWhere((i) => i.type == 'labor');
  }
  if (trackedMinutes > 0) {
    final hours = (trackedMinutes / 60 * 100).round() / 100;
    final clock = '${trackedMinutes ~/ 60}:${(trackedMinutes % 60).toString().padLeft(2, '0')}';
    items.add(DraftLineItem(
      id: 'time-tracking',
      type: 'labor',
      description: 'Arbeitszeit (Zeiterfassung)',
      quantity: hours,
      unit: 'Std',
      unitPriceNetCents: hourlyRateCents,
      requiresConfirmation: true,
    ));
    warnings.add('Arbeitszeit aus der Zeiterfassung: $clock Std (${hours.toStringAsFixed(2).replaceAll('.', ',')}). Bitte den Stundensatz prüfen.');
  }
  if (materialMarkupPercent > 0 && notes.any((n) => n.isReceipt)) {
    final p = materialMarkupPercent.toStringAsFixed(materialMarkupPercent % 1 == 0 ? 0 : 1).replaceAll('.', ',');
    warnings.add('Material aus Belegen ist mit $p % Aufschlag berechnet.');
  }
  for (final n in notes) {
    for (final w in n.draft.warnings) {
      if (!warnings.contains(w)) warnings.add(w);
    }
  }

  // One invoice note makes the whole job an invoice; only if every note is a quote it stays a quote.
  final isQuote = notes.isNotEmpty && notes.every((n) => n.draft.documentType == 'quote');

  String? hintName;
  String? hintAddress;
  for (final n in notes) {
    final h = n.draft.customerHintName;
    if (h != null && h.isNotEmpty) {
      hintName = h;
      hintAddress = n.draft.customerHintAddress;
      break;
    }
  }

  final CustomerMatch match;
  if (customer != null) {
    final address = [
      if ((customer.street ?? '').isNotEmpty) customer.street!,
      [customer.zip, customer.city].where((s) => (s ?? '').isNotEmpty).join(' '),
    ].where((s) => s.isNotEmpty).join(', ');
    match = CustomerMatch(
      matchedCustomerId: customer.id,
      extractedName: customerDisplayName(customer),
      extractedAddress: address.isEmpty ? null : address,
      confidence: 'exact',
    );
  } else {
    match = CustomerMatch(extractedName: '', confidence: 'new');
  }

  return DraftDocument(
    jobId: job.id,
    title: job.title,
    documentType: isQuote ? 'quote' : 'invoice',
    customer: match,
    lineItems: items,
    warnings: warnings,
    sources: [for (final n in notes) NoteSource(author: n.author, transcript: n.transcript, audioPath: n.audioPath, imagePath: n.imagePath)],
    rawTranscript: notes.isEmpty ? null : notes.map((n) => '${n.author}: "${n.transcript}"').join('\n\n'),
    customerHintName: customer == null ? hintName : null,
    customerHintAddress: customer == null ? hintAddress : null,
  );
}

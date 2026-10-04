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
  });

  /// The server's capture_logs id. Sent to create_document so the note is used up exactly once.
  final String id;
  final DateTime createdAt;
  final String? authorId;
  final String? authorName;
  final String transcript;

  /// What the AI extracted from this one note (positions, warnings, document type, name hint).
  final DraftDocument draft;

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
DraftDocument buildJobDraft({required Job job, Customer? customer, required List<JobNote> notes}) {
  final items = <DraftLineItem>[for (final n in notes) ...n.draft.lineItems];

  final warnings = <String>[];
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
    rawTranscript: notes.isEmpty ? null : notes.map((n) => '${n.author}: "${n.transcript}"').join('\n\n'),
    customerHintName: customer == null ? hintName : null,
    customerHintAddress: customer == null ? hintAddress : null,
  );
}

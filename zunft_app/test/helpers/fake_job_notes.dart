import 'package:zunft_app/features/jobs/data/job_notes_remote.dart';
import 'package:zunft_app/features/jobs/domain/job_notes.dart';
import 'package:zunft_app/features/review/models/draft_models.dart';

/// Stand-in for the notes the server stores on jobs. Tests add notes directly, or wire it to a
/// [FakeCaptureRemote] so processing a queued note stores one here.
class FakeJobNotesRemote implements JobNotesRemote {
  final Map<String, List<JobNote>> _byJob = {};
  final List<String> discarded = [];

  /// Thrown by [fetchOpenNotes] / [discard] while non-null.
  JobNotesException? error;

  void add(String jobId, JobNote note) => _byJob.putIfAbsent(jobId, () => []).add(note);

  /// A note with the given positions: (type, description, quantity, unit, price in cents).
  static JobNote note({
    required String id,
    String author = 'Thorsten',
    String transcript = 'Steckdose im Keller gesetzt',
    String documentType = 'invoice',
    DateTime? at,
    String? hintName,
    String? audioPath,
    String? imagePath,
    List<String> warnings = const [],
    bool checkFirstItem = false, // first position is flagged "Preis prüfen"
    List<({String type, String text, double qty, String unit, int cents})> items = const [
      (type: 'labor', text: 'Steckdose montiert', qty: 2, unit: 'Std', cents: 6800),
      (type: 'material', text: 'Doppelsteckdose', qty: 1, unit: 'Stk', cents: 4000),
    ],
  }) =>
      JobNote(
        id: id,
        createdAt: at ?? DateTime(2026, 10, 5, 9, 30),
        authorId: 'user-$author',
        authorName: author,
        transcript: transcript,
        audioPath: audioPath,
        imagePath: imagePath,
        draft: DraftDocument(
          title: 'Notiz',
          documentType: documentType,
          customer: CustomerMatch(extractedName: '', confidence: 'new'),
          customerHintName: hintName,
          warnings: warnings,
          lineItems: [
            for (final (i, it) in items.indexed)
              DraftLineItem(
                id: '$id-$i',
                type: it.type,
                description: it.text,
                quantity: it.qty,
                unit: it.unit,
                unitPriceNetCents: it.cents,
                requiresConfirmation: checkFirstItem && i == 0,
              ),
          ],
        ),
      );

  @override
  Future<List<JobNote>> fetchOpenNotes(String jobId) async {
    if (error != null) throw error!;
    return List.of(_byJob[jobId] ?? const []);
  }

  @override
  Future<String> audioUrl(String audioPath) async {
    if (error != null) throw error!;
    return 'https://audio.test/$audioPath';
  }

  @override
  Future<void> discard(String noteId) async {
    if (error != null) throw error!;
    discarded.add(noteId);
    for (final list in _byJob.values) {
      list.removeWhere((n) => n.id == noteId);
    }
  }

  /// What the server does when create_document is called with these note ids.
  void markUsed(Iterable<String> ids) {
    for (final list in _byJob.values) {
      list.removeWhere((n) => ids.contains(n.id));
    }
  }
}

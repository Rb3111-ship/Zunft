import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../data/data_repository.dart' show ValidationFailure;
import 'capture_files.dart';

/// Creates and manages captures in the local queue. Processing happens in the background
/// ([CaptureProcessor]); [onChanged] tells the scheduler there is something to do.
class CaptureRepository {
  CaptureRepository(
    this._db, {
    required this.onChanged,
    String Function()? newId,
    DateTime Function()? now,
    CaptureFiles files = const DiskCaptureFiles(),
  })  : _newId = newId ?? (() => const Uuid().v4()),
        _now = now ?? DateTime.now,
        _files = files;

  /// Same limit as the server (process-capture rejects longer text).
  static const maxTypedChars = 4000;

  /// A recording that short is a mis-tap, not a job note.
  static const minRecordingSeconds = 1;

  final AppDatabase _db;
  final void Function() onChanged;
  final String Function() _newId;
  final DateTime Function() _now;
  final CaptureFiles _files;

  /// [jobId] is the job the note belongs to. The user chooses it before recording; it is never guessed.
  Future<String> saveRecording({required String jobId, required String filePath, required int seconds}) async {
    if (seconds < minRecordingSeconds) {
      await _safeDelete(filePath);
      throw const ValidationFailure('Die Aufnahme war zu kurz.');
    }
    final id = _newId();
    await _db.insertCapture(PendingCapturesCompanion.insert(
      id: id,
      kind: 'audio',
      createdAt: _now(),
      localPath: Value(filePath),
      durationSeconds: Value(seconds),
      jobId: Value(jobId),
    ));
    onChanged();
    return id;
  }

  Future<String> saveTypedNote(String text, {required String jobId}) async {
    final clean = text.trim();
    if (clean.isEmpty) throw const ValidationFailure('Bitte eine Notiz eingeben.');
    if (clean.length > maxTypedChars) {
      throw const ValidationFailure('Die Notiz ist zu lang (höchstens $maxTypedChars Zeichen).');
    }
    final id = _newId();
    await _db.insertCapture(PendingCapturesCompanion.insert(
      id: id,
      kind: 'text',
      createdAt: _now(),
      transcript: Value(clean),
      jobId: Value(jobId),
    ));
    onChanged();
    return id;
  }

  /// Puts a failed capture back in the queue. Keeps `uploaded` so audio is not sent twice.
  Future<void> retry(String id) async {
    await _db.updateCapture(
      id,
      PendingCapturesCompanion(
        status: Value(CaptureStatus.queued.name),
        attempts: const Value(0),
        errorMessage: const Value(null),
      ),
    );
    onChanged();
  }

  /// Removes the capture and its local audio. (A note the server already stored stays on the job.)
  Future<void> discard(String id) async {
    final capture = await _db.captureById(id);
    await _db.deleteCapture(id);
    if (capture?.localPath != null) await _safeDelete(capture!.localPath!);
  }

  Future<void> _safeDelete(String path) async {
    try {
      await _files.delete(path);
    } catch (_) {}
  }
}

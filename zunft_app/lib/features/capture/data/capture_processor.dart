import 'dart:io' show FileSystemException;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;

import '../../../core/database/app_database.dart';
import 'capture_files.dart';
import 'capture_remote.dart';

enum CaptureProblem { offline, authExpired }

class CaptureRunResult {
  const CaptureRunResult({this.ready = 0, this.failed = 0, this.problem});
  final int ready;
  final int failed;
  final CaptureProblem? problem;
}

/// Moves queued notes through: upload audio -> Edge Function. The server stores the result as a
/// note on the job; the local row and audio are then removed (the server is the source of truth).
///
/// Designed to be interrupted at any point (app killed, signal lost) and resumed:
/// - the upload is skipped if it already happened (`uploaded`),
/// - the server call is idempotent (same capture id -> same stored note),
/// - local audio is deleted only after the server confirmed the note.
class CaptureProcessor {
  CaptureProcessor(
    this._db,
    this._remote, {
    required this.businessId,
    required this.userId,
    this.maxAutoRetries = 3,
    CaptureFiles files = const DiskCaptureFiles(),
    this.syncJobs,
  }) : _files = files;

  /// Pushes unsynced local changes. A note can only be stored on a job the server already knows,
  /// so a job created offline is synced first.
  final Future<void> Function()? syncJobs;

  final AppDatabase _db;
  final CaptureRemote _remote;
  final String businessId;

  /// The person recording. Part of the storage path so that colleagues cannot fetch each other's recordings.
  final String userId;
  final int maxAutoRetries;
  final CaptureFiles _files;

  String storagePathFor(String captureId) => '$businessId/$userId/$captureId.m4a';

  /// Receipts keep their kind of file (photo or PDF) so the server reads and shows them correctly.
  String imagePathFor(String captureId, [String? localPath]) {
    final ext = (localPath ?? '').toLowerCase().split('.').last;
    return '$businessId/$userId/$captureId.${const ['pdf', 'png', 'jpeg'].contains(ext) ? ext : 'jpg'}';
  }

  Future<CaptureRunResult> run() async {
    var ready = 0;
    var failed = 0;

    for (final capture in await _db.queuedCaptures()) {
      await _db.updateCapture(capture.id, PendingCapturesCompanion(status: Value(CaptureStatus.processing.name)));
      try {
        await _process(capture);
        ready++;
      } on CaptureOfflineException {
        await _requeue(capture.id);
        return CaptureRunResult(ready: ready, failed: failed, problem: CaptureProblem.offline);
      } on CaptureAuthException {
        await _requeue(capture.id);
        return CaptureRunResult(ready: ready, failed: failed, problem: CaptureProblem.authExpired);
      } on CaptureTransientException catch (e) {
        final attempts = capture.attempts + 1;
        if (attempts >= maxAutoRetries) {
          await _fail(capture.id, '${e.message} Bitte später erneut versuchen.', attempts);
          failed++;
        } else {
          await _db.updateCapture(
            capture.id,
            PendingCapturesCompanion(
              status: Value(CaptureStatus.queued.name),
              attempts: Value(attempts),
              errorMessage: Value(e.message),
            ),
          );
        }
      } on CaptureRejectedException catch (e) {
        await _fail(capture.id, e.message, capture.attempts + 1);
        failed++;
      } on _JobNotSynced {
        // The job is not on the server yet. Keep the note; it goes out on the next run.
        await _db.updateCapture(
          capture.id,
          PendingCapturesCompanion(
            status: Value(CaptureStatus.queued.name),
            errorMessage: const Value('Der Auftrag wird noch synchronisiert.'),
          ),
        );
      } on _MissingAudio {
        await _fail(capture.id, 'Die Datei (Aufnahme oder Foto) wurde nicht gefunden.', capture.attempts + 1);
        failed++;
      }
    }
    return CaptureRunResult(ready: ready, failed: failed);
  }

  Future<void> _process(PendingCapture capture) async {
    final jobId = capture.jobId;
    if (jobId == null) {
      throw const CaptureRejectedException('Diese Notiz gehört zu keinem Auftrag. Bitte verwerfen und neu aufnehmen.');
    }
    if (await _db.jobById(jobId) == null) {
      throw const CaptureRejectedException('Der Auftrag dieser Notiz existiert nicht mehr.');
    }
    if (await _jobUnsynced(jobId)) {
      try {
        await syncJobs?.call();
      } catch (_) {}
      if (await _jobUnsynced(jobId)) throw _JobNotSynced();
    }

    String? audioPath;
    String? imagePath;
    if (capture.kind == 'audio' || capture.kind == 'image') {
      final isImage = capture.kind == 'image';
      final path = isImage ? imagePathFor(capture.id, capture.localPath) : storagePathFor(capture.id);
      if (isImage) {
        imagePath = path;
      } else {
        audioPath = path;
      }
      if (!capture.uploaded) {
        final local = capture.localPath;
        if (local == null) throw _MissingAudio();
        final Uint8List bytes;
        try {
          bytes = await _files.read(local);
        } on FileSystemException {
          throw _MissingAudio();
        }
        if (isImage) {
          await _remote.uploadImage(path, bytes);
        } else {
          await _remote.uploadAudio(path, bytes);
        }
        await _db.updateCapture(capture.id, const PendingCapturesCompanion(uploaded: Value(true)));
      }
    }

    await _remote.process(
      captureId: capture.id,
      jobId: jobId,
      audioStoragePath: audioPath,
      imageStoragePath: imagePath,
      transcript: capture.kind == 'text' ? capture.transcript : null,
    );

    // The server has the note now. Remove the local copy; the job screen shows the stored one.
    await _db.deleteCapture(capture.id);
    if (capture.localPath != null) {
      try {
        await _files.delete(capture.localPath!);
      } catch (_) {
        // A leftover file is harmless; the note is safe on the server.
      }
    }
  }

  Future<bool> _jobUnsynced(String jobId) async => (await _db.pendingIds(SyncEntity.job)).contains(jobId);

  Future<void> _requeue(String id) =>
      _db.updateCapture(id, PendingCapturesCompanion(status: Value(CaptureStatus.queued.name)));

  Future<void> _fail(String id, String message, int attempts) => _db.updateCapture(
        id,
        PendingCapturesCompanion(
          status: Value(CaptureStatus.failed.name),
          errorMessage: Value(message),
          attempts: Value(attempts),
        ),
      );
}

class _MissingAudio implements Exception {}

class _JobNotSynced implements Exception {}

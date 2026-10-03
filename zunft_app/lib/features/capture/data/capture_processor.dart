import 'dart:convert';
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

/// Moves queued captures through: upload audio -> Edge Function -> ready draft.
///
/// Designed to be interrupted at any point (app killed, signal lost) and resumed:
/// - the upload is skipped if it already happened (`uploaded`),
/// - the server call is idempotent (same capture id -> same job and draft),
/// - local audio is deleted only after a draft was stored.
class CaptureProcessor {
  CaptureProcessor(
    this._db,
    this._remote, {
    required this.businessId,
    this.maxAutoRetries = 3,
    CaptureFiles files = const DiskCaptureFiles(),
  }) : _files = files;

  final AppDatabase _db;
  final CaptureRemote _remote;
  final String businessId;
  final int maxAutoRetries;
  final CaptureFiles _files;

  String storagePathFor(String captureId) => '$businessId/$captureId.m4a';

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
      } on _MissingAudio {
        await _fail(capture.id, 'Die Aufnahme-Datei wurde nicht gefunden.', capture.attempts + 1);
        failed++;
      }
    }
    return CaptureRunResult(ready: ready, failed: failed);
  }

  Future<void> _process(PendingCapture capture) async {
    String? audioPath;
    if (capture.kind == 'audio') {
      audioPath = storagePathFor(capture.id);
      if (!capture.uploaded) {
        final local = capture.localPath;
        if (local == null) throw _MissingAudio();
        final Uint8List bytes;
        try {
          bytes = await _files.read(local);
        } on FileSystemException {
          throw _MissingAudio();
        }
        await _remote.uploadAudio(audioPath, bytes);
        await _db.updateCapture(capture.id, const PendingCapturesCompanion(uploaded: Value(true)));
      }
    }

    final response = await _remote.process(
      captureId: capture.id,
      audioStoragePath: audioPath,
      transcript: capture.kind == 'text' ? capture.transcript : null,
    );

    await _db.updateCapture(
      capture.id,
      PendingCapturesCompanion(
        status: Value(CaptureStatus.ready.name),
        draftJson: Value(jsonEncode(response.json)),
        jobId: Value(response.jobId),
        errorMessage: const Value(null),
      ),
    );
    if (capture.localPath != null) {
      try {
        await _files.delete(capture.localPath!);
      } catch (_) {
        // A leftover file is harmless; the draft is safe in the database.
      }
    }
  }

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

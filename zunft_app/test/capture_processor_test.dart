import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/features/capture/data/capture_processor.dart';
import 'package:zunft_app/features/capture/data/capture_remote.dart';
import 'package:zunft_app/features/capture/data/capture_repository.dart';
import 'package:zunft_app/features/data/data_repository.dart' show ValidationFailure;
import 'package:zunft_app/features/review/models/draft_models.dart';

import 'helpers/fake_capture.dart';

void main() {
  late AppDatabase db;
  late FakeCaptureRemote remote;
  late CaptureProcessor processor;
  late CaptureRepository repo;
  late FakeCaptureFiles files;
  late List<String> deletedFiles;
  var changes = 0;
  var ids = 0;
  const job = 'job-1';

  JobsCompanion jobRow(String id) => JobsCompanion(
        id: Value(id),
        businessId: const Value('biz'),
        title: const Value('Schiller Bad'),
        status: const Value('draft'),
        updatedAt: Value(DateTime(2026, 10, 1)),
      );

  /// A job the server already knows (as if it came in through sync).
  Future<void> syncedJob([String id = job]) => db.applyRemoteJobs([jobRow(id)]);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    remote = FakeCaptureRemote();
    files = FakeCaptureFiles();
    deletedFiles = files.deleted;
    changes = 0;
    ids = 0;
    processor = CaptureProcessor(db, remote, businessId: 'biz', files: files);
    repo = CaptureRepository(db, onChanged: () => changes++, newId: () => 'cap-${++ids}', files: files);
    await syncedJob();
  });

  tearDown(() => db.close());

  Future<PendingCapture?> get(String id) => db.captureById(id);
  Future<String?> status(String id) async => (await get(id))?.status;

  group('happy paths', () {
    test('a recording is uploaded and stored on its job; the local row and audio are then removed', () async {
      final id = await repo.saveRecording(jobId: job, filePath: '/rec/a.m4a', seconds: 42);
      expect((await get(id))!.jobId, job);

      final result = await processor.run();

      expect(result.ready, 1);
      expect(remote.uploads, ['biz/cap-1.m4a']);
      expect(remote.processCalls.single, {'captureId': id, 'job': job, 'audio': 'biz/cap-1.m4a', 'transcript': null});
      expect(await get(id), isNull); // the server holds the note now
      expect(deletedFiles, ['/rec/a.m4a']);
    });

    test('a typed note skips the upload and sends the text', () async {
      final id = await repo.saveTypedNote('  Sicherung getauscht  ', jobId: job);
      await processor.run();

      expect(remote.uploads, isEmpty);
      expect(remote.processCalls.single, {'captureId': id, 'job': job, 'audio': null, 'transcript': 'Sicherung getauscht'});
      expect(await get(id), isNull);
    });

    test('notes are processed oldest first and each goes to ITS job', () async {
      await syncedJob('job-2');
      await repo.saveTypedNote('erste', jobId: job);
      await repo.saveTypedNote('zweite', jobId: 'job-2');
      await processor.run();
      expect(remote.processCalls.map((c) => (c['transcript'], c['job'])), [('erste', job), ('zweite', 'job-2')]);
    });
  });

  group('a job created offline', () {
    setUp(() async {
      // A job made on this phone that the server has not seen yet (it waits in the outbox).
      await db.saveJobLocal(jobRow('new-job'), now: DateTime(2026, 10, 1));
    });

    test('is synced first, then the note is processed', () async {
      var syncCalls = 0;
      processor = CaptureProcessor(db, remote, businessId: 'biz', files: files, syncJobs: () async {
        syncCalls++;
        for (final o in await db.pendingOutbox()) {
          await db.removeOutbox(o.id, o.rev); // the sync pushed it
        }
      });
      final id = await repo.saveTypedNote('Notiz', jobId: 'new-job');

      final result = await processor.run();

      expect(syncCalls, 1);
      expect(result.ready, 1);
      expect(remote.processCalls.single['job'], 'new-job');
      expect(await get(id), isNull);
    });

    test('if the job cannot be synced, the note stays queued and other notes still go out', () async {
      final waiting = await repo.saveTypedNote('wartet', jobId: 'new-job');
      final other = await repo.saveTypedNote('geht raus', jobId: job);

      final result = await processor.run(); // no way to sync

      expect(result.problem, isNull); // not a connectivity problem: do not stop the run
      expect(await status(waiting), 'queued');
      expect((await get(waiting))!.errorMessage, contains('synchronisiert'));
      expect(await get(other), isNull); // processed
      expect(remote.processCalls.map((c) => c['job']), [job]);
    });

    test('the note is sent once the job has reached the server', () async {
      final waiting = await repo.saveTypedNote('wartet', jobId: 'new-job');
      await processor.run();
      expect(await status(waiting), 'queued');

      for (final o in await db.pendingOutbox()) {
        await db.removeOutbox(o.id, o.rev);
      }
      await processor.run();
      expect(await get(waiting), isNull);
    });
  });

  group('notes without a usable job', () {
    test('a note whose job was deleted fails with a clear message and is never sent', () async {
      await syncedJob('gone');
      final id = await repo.saveTypedNote('x', jobId: 'gone');
      await db.deleteJobLocal('gone', now: DateTime(2026, 10, 2));
      await db.removeOutbox((await db.pendingOutbox()).single.id, (await db.pendingOutbox()).single.rev);

      await processor.run();

      expect(await status(id), 'failed');
      expect((await get(id))!.errorMessage, contains('Auftrag'));
      expect(remote.processCalls, isEmpty);
    });

    test('a leftover note from before jobs were required (no job) fails instead of guessing', () async {
      await db.insertCapture(PendingCapturesCompanion.insert(id: 'old', kind: 'text', createdAt: DateTime(2026, 10, 1), transcript: const Value('alt')));
      await processor.run();
      expect(await status('old'), 'failed');
      expect(remote.processCalls, isEmpty);
    });
  });

  group('interruptions (the whole point of the queue)', () {
    test('offline during upload: nothing lost, audio kept, retry succeeds', () async {
      final id = await repo.saveRecording(jobId: job, filePath: '/rec/a.m4a', seconds: 10);
      remote.uploadError = const CaptureOfflineException();

      final first = await processor.run();
      expect(first.problem, CaptureProblem.offline);
      expect(await status(id), 'queued');
      expect((await get(id))!.uploaded, isFalse);
      expect(deletedFiles, isEmpty);

      remote.uploadError = null;
      final second = await processor.run();
      expect(second.ready, 1);
      expect(await get(id), isNull);
    });

    test('offline AFTER the upload: the retry does not upload again and reuses the same capture id', () async {
      final id = await repo.saveRecording(jobId: job, filePath: '/rec/a.m4a', seconds: 10);
      remote.processError = const CaptureOfflineException();

      await processor.run();
      expect((await get(id))!.uploaded, isTrue);
      expect(await status(id), 'queued');

      remote.processError = null;
      await processor.run();

      expect(remote.uploads, hasLength(1)); // not re-sent
      expect(remote.processCalls.map((c) => c['captureId']), [id, id]); // same idempotency key
      expect(await get(id), isNull);
    });

    test('going offline stops the run; later notes stay untouched', () async {
      final a = await repo.saveTypedNote('a', jobId: job);
      final b = await repo.saveTypedNote('b', jobId: job);
      remote.processError = const CaptureOfflineException();

      await processor.run();

      expect(remote.processCalls, hasLength(1)); // gave up after the first, did not hammer the network
      expect(await status(a), 'queued');
      expect(await status(b), 'queued');
    });

    test('an expired login pauses everything and loses nothing', () async {
      final id = await repo.saveTypedNote('a', jobId: job);
      remote.processError = const CaptureAuthException();
      final result = await processor.run();
      expect(result.problem, CaptureProblem.authExpired);
      expect(await status(id), 'queued');
    });

    test('notes stuck in "processing" after an app kill are queued again', () async {
      final id = await repo.saveTypedNote('a', jobId: job);
      await db.updateCapture(id, PendingCapturesCompanion(status: Value(CaptureStatus.processing.name)));
      expect(await db.queuedCaptures(), isEmpty);

      await db.requeueInterruptedCaptures();

      expect((await db.queuedCaptures()).single.id, id);
    });
  });

  group('server problems', () {
    test('temporary errors are retried automatically, then give up with a clear message', () async {
      final id = await repo.saveTypedNote('a', jobId: job);
      remote.processError = const CaptureTransientException('Der Server ist gerade nicht erreichbar.');

      await processor.run();
      expect(await status(id), 'queued');
      expect((await get(id))!.attempts, 1);

      await processor.run();
      expect((await get(id))!.attempts, 2);
      expect(await status(id), 'queued');

      final third = await processor.run();
      final c = (await get(id))!;
      expect(c.status, 'failed');
      expect(third.failed, 1);
      expect(c.errorMessage, contains('Server'));
      expect(c.errorMessage, contains('später'));
    });

    test('a rejection fails immediately with the server message and is not retried by itself', () async {
      final id = await repo.saveTypedNote('a', jobId: job);
      remote.processError = const CaptureRejectedException('Aus der Notiz konnte kein Entwurf erstellt werden.');

      await processor.run();
      final c = (await get(id))!;
      expect(c.status, 'failed');
      expect(c.errorMessage, 'Aus der Notiz konnte kein Entwurf erstellt werden.');

      remote.processError = null;
      await processor.run(); // nothing queued, so nothing happens
      expect(remote.processCalls, hasLength(1));
    });

    test('a failed note can be retried by the user and then succeeds', () async {
      final id = await repo.saveTypedNote('a', jobId: job);
      remote.processError = const CaptureRejectedException('kaputt');
      await processor.run();
      expect(await status(id), 'failed');

      remote.processError = null;
      await repo.retry(id);
      expect((await get(id))!.errorMessage, isNull);
      expect((await get(id))!.attempts, 0);
      await processor.run();
      expect(await get(id), isNull);
    });

    test('a recording whose file vanished fails with a clear message', () async {
      final id = await repo.saveRecording(jobId: job, filePath: '/rec/missing.m4a', seconds: 5);
      await processor.run();
      final c = (await get(id))!;
      expect(c.status, 'failed');
      expect(c.errorMessage, contains('nicht gefunden'));
      expect(remote.uploads, isEmpty);
    });
  });

  group('CaptureRepository', () {
    test('a too-short recording is rejected and its file removed', () async {
      await expectLater(repo.saveRecording(jobId: job, filePath: '/rec/short.m4a', seconds: 0), throwsA(isA<ValidationFailure>()));
      expect(deletedFiles, ['/rec/short.m4a']);
      expect(await db.queuedCaptures(), isEmpty);
      expect(changes, 0);
    });

    test('typed notes: empty and over-long are rejected', () async {
      await expectLater(repo.saveTypedNote('   ', jobId: job), throwsA(isA<ValidationFailure>()));
      await expectLater(repo.saveTypedNote('x' * 4001, jobId: job), throwsA(isA<ValidationFailure>()));
      await repo.saveTypedNote('x' * 4000, jobId: job); // exactly at the server limit is fine
      expect(changes, 1);
    });

    test('saving nudges the processor; discarding deletes the row and the audio', () async {
      final id = await repo.saveRecording(jobId: job, filePath: '/rec/a.m4a', seconds: 3);
      expect(changes, 1);
      await repo.discard(id);
      expect(await db.captureById(id), isNull);
      expect(deletedFiles, ['/rec/a.m4a']);
    });
  });

  group('DraftLineItem ids', () {
    test('items from a server draft (no ids) each get their own id', () {
      final draft = DraftDocument.fromJson(FakeCaptureRemote().defaultResponse('x', null));
      final ids = draft.lineItems.map((i) => i.id).toSet();
      expect(ids, hasLength(draft.lineItems.length));
    });

    test('a spoken name only becomes a hint; the draft never picks a customer by itself', () {
      final draft = DraftDocument.fromJson(FakeCaptureRemote().defaultResponse('x', null));
      expect(draft.customerHintName, 'Thomas Müller');
      expect(draft.customer.extractedName, isEmpty);
      expect(draft.customer.matchedCustomerId, isNull);
    });
  });
}

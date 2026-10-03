import 'dart:convert';

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

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    remote = FakeCaptureRemote();
    files = FakeCaptureFiles();
    deletedFiles = files.deleted;
    changes = 0;
    ids = 0;
    processor = CaptureProcessor(db, remote, businessId: 'biz', files: files);
    repo = CaptureRepository(db, onChanged: () => changes++, newId: () => 'cap-${++ids}', files: files);
  });

  tearDown(() => db.close());

  Future<PendingCapture> get(String id) async => (await db.captureById(id))!;

  group('happy paths', () {
    test('a recording is uploaded, processed, stored as a ready draft, and its audio deleted', () async {
      final id = await repo.saveRecording(filePath: '/rec/a.m4a', seconds: 42);

      final result = await processor.run();

      expect(result.ready, 1);
      expect(remote.uploads, ['biz/cap-1.m4a']);
      expect(remote.processCalls.single, {'captureId': id, 'audio': 'biz/cap-1.m4a', 'transcript': null});
      final c = await get(id);
      expect(c.status, 'ready');
      expect(c.uploaded, isTrue);
      expect(c.jobId, 'job-1');
      expect(deletedFiles, ['/rec/a.m4a']);

      // The stored answer can be turned back into a draft for the review screen.
      final draft = DraftDocument.fromJson(jsonDecode(c.draftJson!) as Map<String, dynamic>, jobId: c.jobId);
      expect(draft.title, 'Steckdose Keller');
      expect(draft.lineItems, hasLength(2));
      expect(draft.customer.extractedName, 'Thomas Müller');
    });

    test('a typed note skips the upload and sends the text', () async {
      final id = await repo.saveTypedNote('  Kunde Schmidt, Sicherung getauscht  ');
      await processor.run();

      expect(remote.uploads, isEmpty);
      expect(remote.processCalls.single, {'captureId': id, 'audio': null, 'transcript': 'Kunde Schmidt, Sicherung getauscht'});
      expect((await get(id)).status, 'ready');
    });

    test('captures are processed oldest first', () async {
      await repo.saveTypedNote('erste');
      await repo.saveTypedNote('zweite');
      await processor.run();
      expect(remote.processCalls.map((c) => c['transcript']), ['erste', 'zweite']);
    });
  });

  group('interruptions (the whole point of the queue)', () {
    test('offline during upload: nothing lost, audio kept, retry succeeds', () async {
      final id = await repo.saveRecording(filePath: '/rec/a.m4a', seconds: 10);
      remote.uploadError = const CaptureOfflineException();

      final first = await processor.run();
      expect(first.problem, CaptureProblem.offline);
      expect((await get(id)).status, 'queued');
      expect((await get(id)).uploaded, isFalse);
      expect(deletedFiles, isEmpty);

      remote.uploadError = null;
      final second = await processor.run();
      expect(second.ready, 1);
      expect((await get(id)).status, 'ready');
    });

    test('offline AFTER the upload: the retry does not upload again and reuses the same capture id', () async {
      final id = await repo.saveRecording(filePath: '/rec/a.m4a', seconds: 10);
      remote.processError = const CaptureOfflineException();

      await processor.run();
      expect((await get(id)).uploaded, isTrue);
      expect((await get(id)).status, 'queued');

      remote.processError = null;
      await processor.run();

      expect(remote.uploads, hasLength(1)); // not re-sent
      expect(remote.processCalls.map((c) => c['captureId']), [id, id]); // same idempotency key
      expect((await get(id)).status, 'ready');
    });

    test('going offline stops the run; later captures stay untouched', () async {
      final a = await repo.saveTypedNote('a');
      final b = await repo.saveTypedNote('b');
      remote.processError = const CaptureOfflineException();

      await processor.run();

      expect(remote.processCalls, hasLength(1)); // gave up after the first, did not hammer the network
      expect((await get(a)).status, 'queued');
      expect((await get(b)).status, 'queued');
    });

    test('an expired login pauses everything and loses nothing', () async {
      final id = await repo.saveTypedNote('a');
      remote.processError = const CaptureAuthException();
      final result = await processor.run();
      expect(result.problem, CaptureProblem.authExpired);
      expect((await get(id)).status, 'queued');
    });

    test('captures stuck in "processing" after an app kill are queued again', () async {
      final id = await repo.saveTypedNote('a');
      await db.updateCapture(id, PendingCapturesCompanion(status: Value(CaptureStatus.processing.name)));
      expect(await db.queuedCaptures(), isEmpty);

      await db.requeueInterruptedCaptures();

      expect((await db.queuedCaptures()).single.id, id);
    });
  });

  group('server problems', () {
    test('temporary errors are retried automatically, then give up with a clear message', () async {
      final id = await repo.saveTypedNote('a');
      remote.processError = const CaptureTransientException('Der Server ist gerade nicht erreichbar.');

      await processor.run();
      expect((await get(id)).status, 'queued');
      expect((await get(id)).attempts, 1);

      await processor.run();
      expect((await get(id)).attempts, 2);
      expect((await get(id)).status, 'queued');

      final third = await processor.run();
      final c = await get(id);
      expect(c.status, 'failed');
      expect(third.failed, 1);
      expect(c.errorMessage, contains('Server'));
      expect(c.errorMessage, contains('später'));
    });

    test('a rejection fails immediately with the server message and is not retried by itself', () async {
      final id = await repo.saveTypedNote('a');
      remote.processError = const CaptureRejectedException('Aus der Notiz konnte kein Entwurf erstellt werden.');

      await processor.run();
      final c = await get(id);
      expect(c.status, 'failed');
      expect(c.errorMessage, 'Aus der Notiz konnte kein Entwurf erstellt werden.');

      remote.processError = null;
      await processor.run(); // nothing queued, so nothing happens
      expect(remote.processCalls, hasLength(1));
    });

    test('a failed capture can be retried by the user and then succeeds', () async {
      final id = await repo.saveTypedNote('a');
      remote.processError = const CaptureRejectedException('kaputt');
      await processor.run();
      expect((await get(id)).status, 'failed');

      remote.processError = null;
      await repo.retry(id);
      expect((await get(id)).errorMessage, isNull);
      expect((await get(id)).attempts, 0);
      await processor.run();
      expect((await get(id)).status, 'ready');
    });

    test('a recording whose file vanished fails with a clear message', () async {
      final id = await repo.saveRecording(filePath: '/rec/missing.m4a', seconds: 5);
      await processor.run();
      final c = await get(id);
      expect(c.status, 'failed');
      expect(c.errorMessage, contains('nicht gefunden'));
      expect(remote.uploads, isEmpty);
    });
  });

  group('CaptureRepository', () {
    test('a too-short recording is rejected and its file removed', () async {
      await expectLater(repo.saveRecording(filePath: '/rec/short.m4a', seconds: 0), throwsA(isA<ValidationFailure>()));
      expect(deletedFiles, ['/rec/short.m4a']);
      expect(await db.queuedCaptures(), isEmpty);
      expect(changes, 0);
    });

    test('typed notes: empty and over-long are rejected', () async {
      await expectLater(repo.saveTypedNote('   '), throwsA(isA<ValidationFailure>()));
      await expectLater(repo.saveTypedNote('x' * 4001), throwsA(isA<ValidationFailure>()));
      await repo.saveTypedNote('x' * 4000); // exactly at the server limit is fine
      expect(changes, 1);
    });

    test('saving nudges the processor; discarding deletes the row and the audio', () async {
      final id = await repo.saveRecording(filePath: '/rec/a.m4a', seconds: 3);
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
  });
}

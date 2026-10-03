import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/core/sync/sync_engine.dart';
import 'package:zunft_app/features/data/data_repository.dart';

import 'helpers/fake_sync_remote.dart';

void main() {
  late AppDatabase db;
  late FakeSyncRemote remote;
  late SyncEngine engine;
  late DataRepository repo;
  var changes = 0;
  var idCounter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    remote = FakeSyncRemote();
    engine = SyncEngine(db, remote, pageSize: 2);
    changes = 0;
    idCounter = 0;
    repo = DataRepository(
      db,
      businessId: 'b1',
      onChanged: () => changes++,
      newId: () => 'id-${++idCounter}',
    );
  });

  tearDown(() => db.close());

  group('push', () {
    test('local edits reach the server, customers before the jobs that reference them', () async {
      // Job is saved first on purpose: order of creation must not matter.
      final customerId = await repo.saveCustomer(name: 'Müller');
      await repo.saveJob(title: 'Steckdose', customerId: customerId);

      final result = await engine.run();

      expect(result.ok, isTrue);
      expect(result.pushed, 2);
      expect(remote.log.take(2), ['upsert customer id-1', 'upsert job id-2']);
      expect(remote.row(SyncEntity.job, 'id-2')!['customer_id'], 'id-1');
      expect(await db.pendingOutbox(), isEmpty);
    });

    test('payload never carries updated_at (the server sets it)', () async {
      await repo.saveCustomer(name: 'Müller');
      await engine.run();
      // The fake stamps its own value; the local copy then adopts the server value on pull.
      final local = await db.customerById('id-1');
      expect(local!.updatedAt.toUtc().year, 2026);
    });

    test('deletes go out jobs first, then customers, and the server nulls dependent jobs', () async {
      remote.seed(SyncEntity.customer, remoteCustomer('c1'));
      remote.seed(SyncEntity.job, remoteJob('j1', customerId: 'c1'));
      await engine.run();

      await repo.deleteJob('j1');
      await repo.deleteCustomer('c1');
      final result = await engine.run();

      expect(result.ok, isTrue);
      expect(remote.log.where((l) => l.startsWith('delete')).toList(), ['delete job j1', 'delete customer c1']);
      expect(await db.select(db.customers).get(), isEmpty);
      expect(await db.select(db.jobs).get(), isEmpty);
    });

    test('repeated edits collapse into one outbox entry with a higher rev', () async {
      final id = await repo.saveCustomer(name: 'Müller');
      await repo.saveCustomer(id: id, name: 'Müller-Lüdenscheidt');
      final pending = await db.pendingOutbox();
      expect(pending, hasLength(1));
      expect(pending.single.rev, 2);

      await engine.run();
      expect(remote.row(SyncEntity.customer, id)!['name'], 'Müller-Lüdenscheidt');
    });

    test('an edit made while a push is in flight is not lost', () async {
      final id = await repo.saveCustomer(name: 'Alt');
      remote.duringUpsert = (entity, row) async {
        remote.duringUpsert = null;
        await repo.saveCustomer(id: id, name: 'Neu'); // user edits mid-push
      };

      await engine.run();

      // The in-flight push sent "Alt"; the newer edit must still be queued...
      final pending = await db.pendingOutbox();
      expect(pending, hasLength(1));
      // ...and goes out on the next run.
      await engine.run();
      expect(remote.row(SyncEntity.customer, id)!['name'], 'Neu');
      expect(await db.pendingOutbox(), isEmpty);
    });
  });

  group('failures', () {
    test('offline keeps everything queued and reports the problem; retry succeeds', () async {
      await repo.saveCustomer(name: 'Müller');
      remote.offline = true;

      final first = await engine.run();
      expect(first.problem, SyncProblem.offline);
      expect(await db.pendingOutbox(), hasLength(1));
      expect(await db.customerById('id-1'), isNotNull);

      remote.offline = false;
      final second = await engine.run();
      expect(second.ok, isTrue);
      expect(await db.pendingOutbox(), isEmpty);
      expect(remote.row(SyncEntity.customer, 'id-1'), isNotNull);
    });

    test('an expired session stops the run without losing changes', () async {
      await repo.saveCustomer(name: 'Müller');
      remote.authExpired = true;
      final result = await engine.run();
      expect(result.problem, SyncProblem.authExpired);
      expect(await db.pendingOutbox(), hasLength(1));
    });

    test('a rejected change stays queued with its error while other changes still sync', () async {
      final bad = await repo.saveCustomer(name: 'Kaputt');
      final good = await repo.saveCustomer(name: 'Gut');
      remote.rejectIds.add(bad);

      final result = await engine.run();

      expect(result.rejected, 1);
      expect(result.pushed, 1);
      expect(remote.row(SyncEntity.customer, good), isNotNull);
      final stuck = await db.pendingOutbox();
      expect(stuck.single.entityId, bad);
      expect(stuck.single.lastError, 'rejected by server');
      expect(stuck.single.attempts, 1);
      expect(await db.customerById(bad), isNotNull); // never silently dropped locally
    });

    test('a job whose customer was rejected is rejected too (FK), and recovers later', () async {
      final customer = await repo.saveCustomer(name: 'Kunde');
      await repo.saveJob(title: 'Auftrag', customerId: customer);
      remote.rejectIds.add(customer);

      final first = await engine.run();
      expect(first.rejected, 2);

      remote.rejectIds.clear();
      final second = await engine.run();
      expect(second.ok, isTrue);
      expect(await db.pendingOutbox(), isEmpty);
    });
  });

  group('pull', () {
    test('imports server rows and paginates', () async {
      for (var i = 1; i <= 5; i++) {
        remote.seed(SyncEntity.customer, remoteCustomer('c$i', name: 'Kunde $i'));
      }
      final result = await engine.run();
      expect(result.pulled, greaterThanOrEqualTo(5));
      expect((await db.select(db.customers).get()).map((c) => c.name).toSet(),
          {'Kunde 1', 'Kunde 2', 'Kunde 3', 'Kunde 4', 'Kunde 5'});
    });

    test('picks up later server changes using the watermark', () async {
      remote.seed(SyncEntity.customer, remoteCustomer('c1', name: 'Alt'));
      await engine.run();
      remote.seed(SyncEntity.customer, remoteCustomer('c1', name: 'Neu'));
      await engine.run();
      expect((await db.customerById('c1'))!.name, 'Neu');
    });

    test('a pending local edit is not overwritten by a pull', () async {
      remote.seed(SyncEntity.customer, remoteCustomer('c1', name: 'Server'));
      await engine.run();

      await repo.saveCustomer(id: 'c1', name: 'Lokal');
      remote.seed(SyncEntity.customer, remoteCustomer('c1', name: 'Server-Neu'));
      remote.offline = false;

      // While offline the pull cannot run; simulate a pull-only moment by blocking the push.
      remote.rejectIds.add('c1');
      await engine.run();
      expect((await db.customerById('c1'))!.name, 'Lokal');

      remote.rejectIds.clear();
      await engine.run(); // local edit pushed, last write wins
      expect(remote.row(SyncEntity.customer, 'c1')!['name'], 'Lokal');
      expect((await db.customerById('c1'))!.name, 'Lokal');
    });

    test('rows deleted on the server disappear locally, unsynced local rows stay', () async {
      remote.seed(SyncEntity.customer, remoteCustomer('c1'));
      remote.seed(SyncEntity.customer, remoteCustomer('c2'));
      await engine.run();

      remote.tables[SyncEntity.customer]!.remove('c1'); // deleted from another device
      remote.offline = true;
      await repo.saveCustomer(name: 'Neu offline'); // id-1, not on the server yet
      remote.offline = false;
      remote.rejectIds.add('id-1'); // keep it pending through this run

      await engine.run();

      final names = (await db.select(db.customers).get()).map((c) => c.id).toSet();
      expect(names, {'c2', 'id-1'});
    });
  });

  group('local cache', () {
    test('deleting a customer detaches its jobs locally, like ON DELETE SET NULL', () async {
      final c = await repo.saveCustomer(name: 'Kunde');
      final j = await repo.saveJob(title: 'Auftrag', customerId: c);
      await repo.deleteCustomer(c);
      expect((await db.jobById(j))!.customerId, isNull);
    });

    test('ensureBusiness keeps data for the same business and wipes it for another', () async {
      await db.ensureBusiness('b1');
      await repo.saveCustomer(name: 'Kunde');
      await db.ensureBusiness('b1');
      expect(await db.select(db.customers).get(), hasLength(1));

      await db.ensureBusiness('b2');
      expect(await db.select(db.customers).get(), isEmpty);
      expect(await db.pendingOutbox(), isEmpty);
    });

    test('stores last sync time after a successful run only', () async {
      remote.offline = true;
      await engine.run();
      expect(await db.getMeta(SyncEngine.lastSyncKey), isNull);
      remote.offline = false;
      await engine.run();
      expect(await db.getMeta(SyncEngine.lastSyncKey), isNotNull);
    });
  });

  group('DataRepository', () {
    test('rejects empty names, empty titles, bad status and unknown customers', () async {
      await expectLater(repo.saveCustomer(name: '   '), throwsA(isA<ValidationFailure>()));
      await expectLater(repo.saveJob(title: ''), throwsA(isA<ValidationFailure>()));
      await expectLater(repo.saveJob(title: 'x', status: 'bogus'), throwsA(isA<ValidationFailure>()));
      await expectLater(repo.saveJob(title: 'x', customerId: 'nope'), throwsA(isA<ValidationFailure>()));
      expect(await db.pendingOutbox(), isEmpty);
      expect(changes, 0);
    });

    test('trims input, turns blanks into null and nudges the sync', () async {
      final id = await repo.saveCustomer(name: '  Müller ', phone: '   ', city: ' Hamburg ');
      final c = (await db.customerById(id))!;
      expect(c.name, 'Müller');
      expect(c.phone, isNull);
      expect(c.city, 'Hamburg');
      expect(c.businessId, 'b1');
      expect(changes, 1);
    });
  });
}

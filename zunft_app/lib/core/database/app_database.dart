import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Local copy of `customers` (Supabase is the source of truth, this is the offline cache).
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get salutation => text().nullable()();
  TextColumn get name => text()();
  TextColumn get firstName => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get street => text().nullable()();
  TextColumn get zip => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local copy of `jobs`.
class Jobs extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get customerId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local changes not yet sent to the server. One row per entity: later edits
/// replace the earlier entry, and a delete replaces a pending upsert.
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text()(); // 'customer' | 'job'
  TextColumn get entityId => text()();
  TextColumn get op => text()(); // 'upsert' | 'delete'
  DateTimeColumn get createdAt => dateTime()();

  /// Bumped on every re-queue. A push only clears the entry if the rev it started with is
  /// still current, so an edit made during an in-flight push is never lost.
  IntColumn get rev => integer().withDefault(const Constant(1))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {entity, entityId},
      ];
}

/// Small key/value store: owning business, per-table pull watermarks, last sync time.
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// A voice note (or typed note) on its way to the server. Always belongs to a job ([jobId], chosen
/// by the user). Lives only on this device until the server has stored it as a note on the job;
/// the row is then removed.
///
/// status: queued -> processing -> (row removed) | failed (needs the user)
class PendingCaptures extends Table {
  TextColumn get id => text()(); // also sent to the server as the idempotency key
  TextColumn get kind => text()(); // 'audio' | 'text'
  TextColumn get localPath => text().nullable()();
  TextColumn get transcript => text().nullable()(); // typed note
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('queued'))();
  BoolColumn get uploaded => boolean().withDefault(const Constant(false))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get draftJson => text().nullable()(); // unused since the job-notes redesign (kept to avoid a migration)
  TextColumn get jobId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local copy of `documents` (issued quotes and invoices). Created on the server only, by
/// create_document(); pulled here read-only. Dates are ISO strings (yyyy-MM-dd).
@DataClassName('IssuedDocument')
class IssuedDocuments extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get jobId => text().nullable()();
  TextColumn get customerId => text().nullable()();
  TextColumn get docType => text()(); // 'quote' | 'invoice'
  TextColumn get docNumber => text()();
  TextColumn get status => text()(); // issued | sent | paid | canceled
  TextColumn get title => text().nullable()();
  TextColumn get dateIssued => text()();
  TextColumn get dateDue => text().nullable()();
  TextColumn get deliveryPeriod => text().nullable()();
  IntColumn get subtotalLaborCents => integer()();
  IntColumn get subtotalMaterialCents => integer()();
  IntColumn get totalNetCents => integer()();
  RealColumn get vatRate => real()();
  IntColumn get vatAmountCents => integer()();
  IntColumn get totalGrossCents => integer()();
  TextColumn get lineItemsJson => text()();
  TextColumn get recipientName => text()();
  TextColumn get recipientAddress => text().nullable()();
  TextColumn get pdfPath => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

enum CaptureStatus { queued, processing, failed }

enum SyncEntity { customer, job, document }

enum OutboxOp { upsert, delete }

@DriftDatabase(tables: [Customers, Jobs, Outbox, SyncMeta, PendingCaptures, IssuedDocuments])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(pendingCaptures);
          if (from < 3) await m.createTable(issuedDocuments);
        },
      );

  // --- Issued documents (read-only cache of the server) ---------------------------------

  Stream<List<IssuedDocument>> watchDocuments() => (select(issuedDocuments)
        ..orderBy([(d) => OrderingTerm.desc(d.dateIssued), (d) => OrderingTerm.desc(d.docNumber)]))
      .watch();

  Future<IssuedDocument?> documentById(String id) =>
      (select(issuedDocuments)..where((d) => d.id.equals(id))).getSingleOrNull();

  Future<void> upsertDocument(IssuedDocumentsCompanion row) => into(issuedDocuments).insertOnConflictUpdate(row);

  Future<void> updateDocument(String id, IssuedDocumentsCompanion changes) =>
      (update(issuedDocuments)..where((d) => d.id.equals(id))).write(changes);

  /// Documents are never edited locally, so a pull simply overwrites.
  Future<void> applyRemoteDocuments(List<IssuedDocumentsCompanion> rows) => transaction(() async {
        for (final r in rows) {
          await into(issuedDocuments).insertOnConflictUpdate(r);
        }
      });

  /// Removes documents the server no longer has. [knownUpTo] is the newest server timestamp this sync
  /// has pulled: a document NEWER than that was created after the server id list was fetched (for example
  /// issued from this very phone while the sync was running), so its absence from the list means nothing.
  /// Without a known timestamp nothing is pruned.
  Future<void> pruneDocuments(Set<String> serverIds, {required DateTime? knownUpTo}) => transaction(() async {
        if (knownUpTo == null) return;
        final local = await select(issuedDocuments).get();
        for (final d in local) {
          if (!serverIds.contains(d.id) && !d.updatedAt.isAfter(knownUpTo)) {
            await (delete(issuedDocuments)..where((x) => x.id.equals(d.id))).go();
          }
        }
      });

  // --- Captures -------------------------------------------------------------------

  Stream<List<PendingCapture>> watchCaptures() =>
      (select(pendingCaptures)..orderBy([(c) => OrderingTerm.desc(c.createdAt)])).watch();

  Future<PendingCapture?> captureById(String id) =>
      (select(pendingCaptures)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<List<PendingCapture>> queuedCaptures() => (select(pendingCaptures)
        ..where((c) => c.status.equals(CaptureStatus.queued.name))
        ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]))
      .get();

  Future<void> insertCapture(PendingCapturesCompanion row) => into(pendingCaptures).insert(row);

  Future<void> updateCapture(String id, PendingCapturesCompanion changes) =>
      (update(pendingCaptures)..where((c) => c.id.equals(id))).write(changes);

  Future<void> deleteCapture(String id) => (delete(pendingCaptures)..where((c) => c.id.equals(id))).go();

  /// After an app kill mid-processing: those captures must be tried again.
  Future<void> requeueInterruptedCaptures() =>
      (update(pendingCaptures)..where((c) => c.status.equals(CaptureStatus.processing.name)))
          .write(PendingCapturesCompanion(status: Value(CaptureStatus.queued.name)));

  // --- Reads (streams drive the UI) -------------------------------------------

  Stream<List<Customer>> watchCustomers() =>
      (select(customers)..orderBy([(c) => OrderingTerm.asc(c.name), (c) => OrderingTerm.asc(c.firstName)])).watch();

  Stream<List<Job>> watchJobs() =>
      (select(jobs)..orderBy([(j) => OrderingTerm.desc(j.updatedAt)])).watch();

  Stream<int> watchPendingCount() =>
      (selectOnly(outbox)..addColumns([outbox.id.count()])).map((r) => r.read(outbox.id.count()) ?? 0).watchSingle();

  Future<Customer?> customerById(String id) =>
      (select(customers)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<Job?> jobById(String id) => (select(jobs)..where((j) => j.id.equals(id))).getSingleOrNull();

  // --- Local writes (always paired with an outbox entry, atomically) -----------

  Future<void> saveCustomerLocal(CustomersCompanion row, {required DateTime now}) => transaction(() async {
        await into(customers).insertOnConflictUpdate(row.copyWith(updatedAt: Value(now)));
        await _enqueue(SyncEntity.customer, row.id.value, OutboxOp.upsert, now);
      });

  Future<void> saveJobLocal(JobsCompanion row, {required DateTime now}) => transaction(() async {
        await into(jobs).insertOnConflictUpdate(row.copyWith(updatedAt: Value(now)));
        await _enqueue(SyncEntity.job, row.id.value, OutboxOp.upsert, now);
      });

  Future<void> deleteCustomerLocal(String id, {required DateTime now}) => transaction(() async {
        await (delete(customers)..where((c) => c.id.equals(id))).go();
        // The server nulls jobs.customer_id on delete (ON DELETE SET NULL); mirror it locally.
        await (update(jobs)..where((j) => j.customerId.equals(id))).write(const JobsCompanion(customerId: Value(null)));
        await _enqueue(SyncEntity.customer, id, OutboxOp.delete, now);
      });

  Future<void> deleteJobLocal(String id, {required DateTime now}) => transaction(() async {
        await (delete(jobs)..where((j) => j.id.equals(id))).go();
        await _enqueue(SyncEntity.job, id, OutboxOp.delete, now);
      });

  Future<void> _enqueue(SyncEntity entity, String entityId, OutboxOp op, DateTime now) async {
    // A later change replaces the pending one. A delete is kept even if the row was only ever
    // created offline: deleting a row the server never saw is a harmless no-op there.
    await into(outbox).insert(
      OutboxCompanion.insert(entity: entity.name, entityId: entityId, op: op.name, createdAt: now),
      onConflict: DoUpdate(
        (old) => RawValuesInsertable({
          'op': Variable<String>(op.name),
          'created_at': Variable<DateTime>(now),
          'rev': old.rev + const Constant(1),
          'attempts': const Constant(0),
          'last_error': const Constant<String>(null),
        }),
        target: [outbox.entity, outbox.entityId],
      ),
    );
  }

  // --- Sync support -------------------------------------------------------------

  Future<List<OutboxData>> pendingOutbox() => (select(outbox)..orderBy([(o) => OrderingTerm.asc(o.id)])).get();

  /// Removes the entry only if it was not re-queued since [rev] was read.
  Future<void> removeOutbox(int id, int rev) =>
      (delete(outbox)..where((o) => o.id.equals(id) & o.rev.equals(rev))).go();

  Future<void> markOutboxFailed(int id, String error) async {
    await customStatement(
      'UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }

  Future<Set<String>> pendingIds(SyncEntity entity) async {
    final rows = await (select(outbox)..where((o) => o.entity.equals(entity.name))).get();
    return rows.map((r) => r.entityId).toSet();
  }

  /// Applies rows pulled from the server, except for ids with a pending local change
  /// (the local edit wins and will be pushed on the next run).
  Future<void> applyRemoteCustomers(List<CustomersCompanion> rows) => transaction(() async {
        final pending = await pendingIds(SyncEntity.customer);
        for (final r in rows) {
          if (!pending.contains(r.id.value)) await into(customers).insertOnConflictUpdate(r);
        }
      });

  Future<void> applyRemoteJobs(List<JobsCompanion> rows) => transaction(() async {
        final pending = await pendingIds(SyncEntity.job);
        for (final r in rows) {
          if (!pending.contains(r.id.value)) await into(jobs).insertOnConflictUpdate(r);
        }
      });

  /// Removes local rows the server no longer has (deleted elsewhere), keeping unsynced ones.
  Future<void> pruneCustomers(Set<String> serverIds) => transaction(() async {
        final pending = await pendingIds(SyncEntity.customer);
        final local = await select(customers).get();
        for (final c in local) {
          if (!serverIds.contains(c.id) && !pending.contains(c.id)) {
            await (delete(customers)..where((x) => x.id.equals(c.id))).go();
          }
        }
      });

  Future<void> pruneJobs(Set<String> serverIds) => transaction(() async {
        final pending = await pendingIds(SyncEntity.job);
        final local = await select(jobs).get();
        for (final j in local) {
          if (!serverIds.contains(j.id) && !pending.contains(j.id)) {
            await (delete(jobs)..where((x) => x.id.equals(j.id))).go();
          }
        }
      });

  Future<String?> getMeta(String key) async =>
      (await (select(syncMeta)..where((m) => m.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setMeta(String key, String value) =>
      into(syncMeta).insertOnConflictUpdate(SyncMetaData(key: key, value: value));

  /// Makes sure the local cache belongs to [businessId]; wipes it if another business used this device.
  Future<void> ensureBusiness(String businessId) async {
    final current = await getMeta('business_id');
    if (current == businessId) return;
    await wipeAll();
    await setMeta('business_id', businessId);
  }

  Future<void> wipeAll() => transaction(() async {
        await delete(customers).go();
        await delete(jobs).go();
        await delete(outbox).go();
        await delete(pendingCaptures).go();
        await delete(issuedDocuments).go();
        await delete(syncMeta).go();
      });
}

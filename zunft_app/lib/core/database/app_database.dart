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

  /// Set when this customer was merged into another one: hidden from lists and pickers, but kept,
  /// because issued documents still point at it (they are frozen by law).
  TextColumn get mergedInto => text().nullable()();
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

  /// The PDF carries an embedded ZUGFeRD / Factur-X XML (frozen with the document).
  BoolColumn get eInvoice => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

enum CaptureStatus { queued, processing, failed }

/// Local copy of `appointments` (the calendar). Times are stored in UTC and shown in local time.
class Appointments extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get jobId => text().nullable()();
  TextColumn get customerId => text().nullable()();
  TextColumn get kind => text().withDefault(const Constant('job'))(); // job | absence | other
  TextColumn get title => text()();
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  TextColumn get status => text().withDefault(const Constant('planned'))(); // planned | done | canceled

  /// The people on it: a JSON list of user ids.
  TextColumn get assigneeIds => text().withDefault(const Constant('[]'))();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local copy of the working time entries. An entry without an end is a running timer.
class TimeEntries extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get userName => text().nullable()();
  TextColumn get jobId => text().nullable()();
  TextColumn get appointmentId => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get breakMinutes => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();

  /// Set by the server when the entry was billed on an invoice: from then on it is frozen.
  TextColumn get documentId => text().nullable()();

  /// Who created the entry (set by the server). Differs from the person when the boss added it.
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

enum SyncEntity { customer, job, document, appointment, timeEntry }

enum OutboxOp { upsert, delete }

@DriftDatabase(tables: [Customers, Jobs, Outbox, SyncMeta, PendingCaptures, IssuedDocuments, Appointments, TimeEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(pendingCaptures);
          if (from < 3) await m.createTable(issuedDocuments);
          if (from < 4) await m.addColumn(customers, customers.mergedInto);
          if (from < 5) await m.addColumn(issuedDocuments, issuedDocuments.eInvoice);
          if (from < 6) await m.createTable(appointments);
          if (from < 7) await m.createTable(timeEntries);
          if (from < 8) await m.addColumn(timeEntries, timeEntries.createdBy);
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

  /// Merged customers are hidden: only the one they were merged into is shown.
  Stream<List<Customer>> watchCustomers() => (select(customers)
        ..where((c) => c.mergedInto.isNull())
        ..orderBy([(c) => OrderingTerm.asc(c.name), (c) => OrderingTerm.asc(c.firstName)]))
      .watch();

  Stream<List<Job>> watchJobs() => (select(jobs)..orderBy([(j) => OrderingTerm.desc(j.updatedAt)])).watch();

  Stream<int> watchPendingCount() =>
      (selectOnly(outbox)..addColumns([outbox.id.count()])).map((r) => r.read(outbox.id.count()) ?? 0).watchSingle();

  Future<List<Customer>> allCustomers() => (select(customers)..where((c) => c.mergedInto.isNull())).get();

  Future<Customer?> customerById(String id) => (select(customers)..where((c) => c.id.equals(id))).getSingleOrNull();

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
        await (update(appointments)..where((a) => a.customerId.equals(id)))
            .write(const AppointmentsCompanion(customerId: Value(null)));
        await _enqueue(SyncEntity.customer, id, OutboxOp.delete, now);
      });

  Future<void> deleteJobLocal(String id, {required DateTime now}) => transaction(() async {
        await (delete(jobs)..where((j) => j.id.equals(id))).go();
        await (update(appointments)..where((x) => x.jobId.equals(id)))
            .write(const AppointmentsCompanion(jobId: Value(null)));
        await (update(timeEntries)..where((x) => x.jobId.equals(id))).write(const TimeEntriesCompanion(jobId: Value(null)));
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

  // --- Appointments --------------------------------------------------------------------

  Stream<List<Appointment>> watchAppointments() =>
      (select(appointments)..orderBy([(a) => OrderingTerm.asc(a.startsAt)])).watch();

  Future<Appointment?> appointmentById(String id) =>
      (select(appointments)..where((a) => a.id.equals(id))).getSingleOrNull();

  Future<void> saveAppointmentLocal(AppointmentsCompanion row, {required DateTime now}) => transaction(() async {
        await into(appointments).insertOnConflictUpdate(row.copyWith(updatedAt: Value(now)));
        await _enqueue(SyncEntity.appointment, row.id.value, OutboxOp.upsert, now);
      });

  Future<void> deleteAppointmentLocal(String id, {required DateTime now}) => transaction(() async {
        await (delete(appointments)..where((a) => a.id.equals(id))).go();
        await (update(timeEntries)..where((t) => t.appointmentId.equals(id)))
            .write(const TimeEntriesCompanion(appointmentId: Value(null)));
        await _enqueue(SyncEntity.appointment, id, OutboxOp.delete, now);
      });

  Future<void> applyRemoteAppointments(List<AppointmentsCompanion> rows) => transaction(() async {
        final pending = await pendingIds(SyncEntity.appointment);
        for (final r in rows) {
          if (!pending.contains(r.id.value)) await into(appointments).insertOnConflictUpdate(r);
        }
      });

  Future<void> pruneAppointments(Set<String> serverIds) => transaction(() async {
        final pending = await pendingIds(SyncEntity.appointment);
        final local = await select(appointments).get();
        for (final a in local) {
          if (!serverIds.contains(a.id) && !pending.contains(a.id)) {
            await (delete(appointments)..where((x) => x.id.equals(a.id))).go();
          }
        }
      });

  // --- Working time ---------------------------------------------------------------------

  Stream<List<TimeEntry>> watchTimeEntries() =>
      (select(timeEntries)..orderBy([(t) => OrderingTerm.desc(t.startedAt)])).watch();

  Future<TimeEntry?> timeEntryById(String id) =>
      (select(timeEntries)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// The running timer of a person (an entry without an end), if there is one.
  Future<TimeEntry?> runningTimerOf(String userId) => (select(timeEntries)
        ..where((t) => t.userId.equals(userId) & t.endedAt.isNull())
        ..limit(1))
      .getSingleOrNull();

  Future<void> saveTimeEntryLocal(TimeEntriesCompanion row, {required DateTime now}) => transaction(() async {
        await into(timeEntries).insertOnConflictUpdate(row.copyWith(updatedAt: Value(now)));
        await _enqueue(SyncEntity.timeEntry, row.id.value, OutboxOp.upsert, now);
      });

  Future<void> deleteTimeEntryLocal(String id, {required DateTime now}) => transaction(() async {
        await (delete(timeEntries)..where((t) => t.id.equals(id))).go();
        await _enqueue(SyncEntity.timeEntry, id, OutboxOp.delete, now);
      });

  Future<void> applyRemoteTimeEntries(List<TimeEntriesCompanion> rows) => transaction(() async {
        final pending = await pendingIds(SyncEntity.timeEntry);
        for (final r in rows) {
          if (!pending.contains(r.id.value)) await into(timeEntries).insertOnConflictUpdate(r);
        }
      });

  Future<void> pruneTimeEntries(Set<String> serverIds) => transaction(() async {
        final pending = await pendingIds(SyncEntity.timeEntry);
        final local = await select(timeEntries).get();
        for (final t in local) {
          if (!serverIds.contains(t.id) && !pending.contains(t.id)) {
            await (delete(timeEntries)..where((x) => x.id.equals(t.id))).go();
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
        await delete(timeEntries).go();
        await delete(appointments).go();
        await delete(customers).go();
        await delete(jobs).go();
        await delete(outbox).go();
        await delete(pendingCaptures).go();
        await delete(issuedDocuments).go();
        await delete(syncMeta).go();
      });
}

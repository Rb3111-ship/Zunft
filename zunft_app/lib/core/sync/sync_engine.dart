import '../database/app_database.dart';
import 'sync_mapping.dart';
import 'sync_remote.dart';

enum SyncProblem { offline, authExpired }

class SyncResult {
  const SyncResult({this.pushed = 0, this.rejected = 0, this.pulled = 0, this.problem});

  final int pushed;
  final int rejected; // changes the server refused (stay in the outbox, shown to the user)
  final int pulled;
  final SyncProblem? problem;

  bool get ok => problem == null && rejected == 0;
}

/// One sync pass: push the local outbox, then pull server changes.
///
/// Conflict policy (Phase 1): last write wins. A local edit that is still in the outbox is
/// never overwritten by a pull; once pushed, the server value (with its own `updated_at`)
/// replaces the local copy on the next pull.
class SyncEngine {
  SyncEngine(this._db, this._remote, {DateTime Function()? now, this.pageSize = 500}) : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final SyncRemote _remote;
  final DateTime Function() _now;
  final int pageSize;

  static const lastSyncKey = 'last_sync_at';

  Future<SyncResult> run() async {
    var pushed = 0;
    var rejected = 0;
    var pulled = 0;
    try {
      final push = await _push();
      pushed = push.$1;
      rejected = push.$2;
      pulled += await _pull(SyncEntity.customer);
      pulled += await _pull(SyncEntity.job);
      pulled += await _pull(SyncEntity.appointment); // after jobs and customers (it points at both)
      pulled += await _pull(SyncEntity.document); // read-only: only create_document() makes documents
      await _db.setMeta(lastSyncKey, _now().toUtc().toIso8601String());
    } on SyncOfflineException {
      return SyncResult(pushed: pushed, rejected: rejected, pulled: pulled, problem: SyncProblem.offline);
    } on SyncAuthException {
      return SyncResult(pushed: pushed, rejected: rejected, pulled: pulled, problem: SyncProblem.authExpired);
    }
    return SyncResult(pushed: pushed, rejected: rejected, pulled: pulled);
  }

  /// Returns (pushed, rejected). Order respects foreign keys: customers exist before the jobs
  /// that point at them, and jobs are deleted before their customers.
  Future<(int, int)> _push() async {
    final all = await _db.pendingOutbox();
    // Upserts: customers, then jobs, then appointments (which point at both). Deletes in reverse.
    int rank(OutboxData o) {
      final upsert = o.op == OutboxOp.upsert.name;
      final level = switch (o.entity) {
        'customer' => 0,
        'job' => 1,
        _ => 2, // appointment
      };
      return upsert ? level : 5 - level;
    }

    final ordered = [...all]..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.id.compareTo(b.id);
      });

    var pushed = 0;
    var rejected = 0;
    for (final entry in ordered) {
      final entity = SyncEntity.values.byName(entry.entity);
      try {
        if (entry.op == OutboxOp.delete.name) {
          await _remote.delete(entity, entry.entityId);
        } else {
          final payload = await _localPayload(entity, entry.entityId);
          if (payload != null) await _remote.upsert(entity, payload);
          // payload == null: the row was deleted locally meanwhile; a delete entry replaced this one.
        }
        // Only drop the entry if it was not edited while we were pushing (rev unchanged).
        await _db.removeOutbox(entry.id, entry.rev);
        pushed++;
      } on SyncRejectedException catch (e) {
        await _db.markOutboxFailed(entry.id, e.message);
        rejected++;
      }
    }
    return (pushed, rejected);
  }

  Future<Map<String, dynamic>?> _localPayload(SyncEntity entity, String id) async {
    switch (entity) {
      case SyncEntity.customer:
        final c = await _db.customerById(id);
        return c == null ? null : customerToRemote(c);
      case SyncEntity.appointment:
        final a = await _db.appointmentById(id);
        return a == null ? null : appointmentToRemote(a);
      default:
        final j = await _db.jobById(id);
        return j == null ? null : jobToRemote(j);
    }
  }

  Future<int> _pull(SyncEntity entity) async {
    final metaKey = 'pull_${entity.name}';
    var since = await _db.getMeta(metaKey);
    var total = 0;

    while (true) {
      final rows = await _remote.fetchChanged(entity, since: since, limit: pageSize);
      if (rows.isEmpty) break;

      switch (entity) {
        case SyncEntity.customer:
          await _db.applyRemoteCustomers(rows.map(customerFromRemote).toList());
        case SyncEntity.job:
          await _db.applyRemoteJobs(rows.map(jobFromRemote).toList());
        case SyncEntity.document:
          await _db.applyRemoteDocuments(rows.map(documentFromRemote).toList());
        case SyncEntity.appointment:
          await _db.applyRemoteAppointments(rows.map(appointmentFromRemote).toList());
      }
      total += rows.length;

      final newest = rows.last['updated_at'] as String;
      final progressed = newest != since;
      since = newest;
      await _db.setMeta(metaKey, newest);

      // Short page = caught up. A full page that did not advance the watermark would loop forever.
      if (rows.length < pageSize || !progressed) break;
    }

    final serverIds = await _remote.fetchIds(entity);
    switch (entity) {
      case SyncEntity.customer:
        await _db.pruneCustomers(serverIds);
      case SyncEntity.job:
        await _db.pruneJobs(serverIds);
      case SyncEntity.appointment:
        await _db.pruneAppointments(serverIds);
      case SyncEntity.document:
        final watermark = await _db.getMeta('pull_document');
        await _db.pruneDocuments(serverIds, knownUpTo: watermark == null ? null : DateTime.tryParse(watermark));
    }
    return total;
  }
}

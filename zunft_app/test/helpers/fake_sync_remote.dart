import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/core/sync/sync_remote.dart';

/// In-memory stand-in for the Supabase tables. Mimics what matters for sync:
/// server-assigned `updated_at`, the jobs -> customers foreign key, and ON DELETE SET NULL.
class FakeSyncRemote implements SyncRemote {
  final Map<SyncEntity, Map<String, Map<String, dynamic>>> tables = {
    SyncEntity.customer: {},
    SyncEntity.job: {},
    SyncEntity.document: {},
    SyncEntity.appointment: {},
    SyncEntity.timeEntry: {},
  };

  int _clock = 0;
  bool offline = false;
  bool authExpired = false;
  final Set<String> rejectIds = {};

  /// Who is pushing (the person logged in on this phone): the server stamps new rows with it.
  String? actingUser;

  /// Names of the people of the business, for entries that the server labels with the name.
  final Map<String, String> userNames = {'u1': 'Erika', 'u2': 'Hans'};
  final List<String> log = [];

  /// Runs inside upsert (before it is stored); lets a test edit data "while a push is in flight".
  Future<void> Function(SyncEntity entity, Map<String, dynamic> row)? duringUpsert;

  String _stamp() => DateTime.utc(2026, 1, 1).add(Duration(seconds: ++_clock)).toIso8601String();

  void _guard() {
    if (offline) throw const SyncOfflineException('fake offline');
    if (authExpired) throw const SyncAuthException();
  }

  /// A row that already exists on the server (e.g. created from another device).
  void seed(SyncEntity entity, Map<String, dynamic> row) {
    tables[entity]![row['id'] as String] = {...row, 'updated_at': _stamp()};
  }

  /// What create_document does on the server: finished entries named in the order are billed.
  void markTimeEntriesBilled(List<String> ids, String documentId) {
    for (final id in ids) {
      final e = tables[SyncEntity.timeEntry]![id];
      if (e != null && e['ended_at'] != null && e['document_id'] == null) {
        e['document_id'] = documentId;
        e['updated_at'] = _stamp();
      }
    }
  }

  Map<String, dynamic>? row(SyncEntity entity, String id) => tables[entity]![id];

  @override
  Future<List<Map<String, dynamic>>> fetchChanged(SyncEntity entity, {String? since, required int limit}) async {
    _guard();
    final rows =
        tables[entity]!.values.where((r) => since == null || (r['updated_at'] as String).compareTo(since) >= 0).toList()
          ..sort((a, b) {
            final c = (a['updated_at'] as String).compareTo(b['updated_at'] as String);
            return c != 0 ? c : (a['id'] as String).compareTo(b['id'] as String);
          });
    return rows.take(limit).map((r) => {...r}).toList();
  }

  @override
  Future<Set<String>> fetchIds(SyncEntity entity) async {
    _guard();
    return tables[entity]!.keys.toSet();
  }

  @override
  Future<void> upsert(SyncEntity entity, Map<String, dynamic> row) async {
    _guard();
    final id = row['id'] as String;
    if (rejectIds.contains(id)) throw const SyncRejectedException('rejected by server', code: '23514');
    if (entity == SyncEntity.job) {
      final cid = row['customer_id'] as String?;
      if (cid != null && !tables[SyncEntity.customer]!.containsKey(cid)) {
        throw const SyncRejectedException('violates foreign key', code: '23503');
      }
    }
    await duringUpsert?.call(entity, row);
    // the server stores the person's name with a time entry (a trigger does that)
    if (entity == SyncEntity.timeEntry) {
      row = {
        ...row,
        'user_name': userNames[row['user_id']] ?? row['user_name'],
        'created_by': tables[SyncEntity.timeEntry]![id]?['created_by'] ?? actingUser ?? row['user_id'],
      };
    }
    log.add('upsert ${entity.name} $id');
    tables[entity]![id] = {...?tables[entity]![id], ...row, 'updated_at': _stamp()};
  }

  @override
  Future<void> delete(SyncEntity entity, String id) async {
    _guard();
    log.add('delete ${entity.name} $id');
    tables[entity]!.remove(id);
    if (entity == SyncEntity.customer) {
      for (final j in tables[SyncEntity.job]!.values) {
        if (j['customer_id'] == id) {
          j['customer_id'] = null;
          j['updated_at'] = _stamp(); // the UPDATE from SET NULL fires the updated_at trigger
        }
      }
    }
  }
}

Map<String, dynamic> remoteCustomer(String id, {String name = 'Müller', String business = 'b1', String? email}) => {
      'id': id,
      'business_id': business,
      'salutation': 'Herr',
      'name': name,
      'first_name': null,
      'email': email,
      'phone': null,
      'street': null,
      'zip': null,
      'city': null,
      'notes': null,
    };

Map<String, dynamic> remoteJob(String id, {String title = 'Steckdose', String? customerId, String business = 'b1'}) => {
      'id': id,
      'business_id': business,
      'customer_id': customerId,
      'title': title,
      'description': null,
      'status': 'draft',
    };

/// An appointment as the server stores it. Times are local wall-clock times of the test.
Map<String, dynamic> remoteAppointment(
  String id, {
  String title = 'Steckdose Keller',
  required DateTime start,
  DateTime? end,
  List<String> assignees = const ['u1'],
  String? jobId,
  String? customerId,
  String kind = 'job',
  String status = 'planned',
  String? location,
  String? notes,
  String business = 'b1',
  String? createdBy,
}) =>
    {
      'id': id,
      'business_id': business,
      'job_id': jobId,
      'customer_id': customerId,
      'kind': kind,
      'title': title,
      'location': location,
      'notes': notes,
      'starts_at': start.toUtc().toIso8601String(),
      'ends_at': (end ?? start.add(const Duration(hours: 1))).toUtc().toIso8601String(),
      'status': status,
      'assignee_ids': assignees,
      'created_by': createdBy,
    };

/// A time entry as the server stores it (times are the local wall-clock times of the test).
Map<String, dynamic> remoteTimeEntry(
  String id, {
  String userId = 'u1',
  String userName = 'Erika',
  String? jobId = 'j1',
  String? appointmentId,
  required DateTime start,
  DateTime? end,
  int breakMinutes = 0,
  String? note,
  String? documentId,
  String? createdBy,
  String business = 'b1',
}) =>
    {
      'id': id,
      'business_id': business,
      'created_by': createdBy ?? userId,
      'user_id': userId,
      'user_name': userName,
      'job_id': jobId,
      'appointment_id': appointmentId,
      'started_at': start.toUtc().toIso8601String(),
      'ended_at': end?.toUtc().toIso8601String(),
      'break_minutes': breakMinutes,
      'note': note,
      'document_id': documentId,
    };

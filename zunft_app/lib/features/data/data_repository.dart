import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

/// Job states the UI offers. The database also knows `overflow_ready` (Phase 3).
class JobStatus {
  static const draft = 'draft';
  static const quoteSent = 'quote_sent';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const invoiced = 'invoiced';

  static const all = [draft, quoteSent, inProgress, completed, invoiced];

  static const labels = {
    draft: 'Entwurf',
    quoteSent: 'Angebot versendet',
    inProgress: 'In Arbeit',
    completed: 'Abgeschlossen',
    invoiced: 'Abgerechnet',
  };

  static String label(String status) => labels[status] ?? status;
}

class ValidationFailure implements Exception {
  const ValidationFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// All local writes. Every change lands in the local database and the outbox in one
/// transaction, so it survives app kills and works offline; [onChanged] nudges the sync.
class DataRepository {
  DataRepository(
    this._db, {
    required this.businessId,
    required this.onChanged,
    String Function()? newId,
    DateTime Function()? now,
  })  : _newId = newId ?? (() => const Uuid().v4()),
        _now = now ?? DateTime.now;

  final AppDatabase _db;
  final String businessId;
  final void Function() onChanged;
  final String Function() _newId;
  final DateTime Function() _now;

  String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// Creates (id == null) or updates a customer; returns its id.
  Future<String> saveCustomer({
    String? id,
    String? salutation,
    required String name,
    String? firstName,
    String? email,
    String? phone,
    String? street,
    String? zip,
    String? city,
    String? notes,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw const ValidationFailure('Name darf nicht leer sein');
    final customerId = id ?? _newId();

    await _db.saveCustomerLocal(
      CustomersCompanion(
        id: Value(customerId),
        businessId: Value(businessId),
        salutation: Value(_clean(salutation)),
        name: Value(cleanName),
        firstName: Value(_clean(firstName)),
        email: Value(_clean(email)),
        phone: Value(_clean(phone)),
        street: Value(_clean(street)),
        zip: Value(_clean(zip)),
        city: Value(_clean(city)),
        notes: Value(_clean(notes)),
      ),
      now: _now(),
    );
    onChanged();
    return customerId;
  }

  Future<void> deleteCustomer(String id) async {
    await _db.deleteCustomerLocal(id, now: _now());
    onChanged();
  }

  /// Creates (id == null) or updates a job; returns its id.
  Future<String> saveJob({
    String? id,
    String? customerId,
    required String title,
    String? description,
    String status = JobStatus.draft,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) throw const ValidationFailure('Titel darf nicht leer sein');
    if (!JobStatus.all.contains(status)) throw ValidationFailure('Unbekannter Status: $status');
    if (customerId != null && await _db.customerById(customerId) == null) {
      throw const ValidationFailure('Der Kunde existiert nicht mehr');
    }
    final jobId = id ?? _newId();

    await _db.saveJobLocal(
      JobsCompanion(
        id: Value(jobId),
        businessId: Value(businessId),
        customerId: Value(customerId),
        title: Value(cleanTitle),
        description: Value(_clean(description)),
        status: Value(status),
      ),
      now: _now(),
    );
    onChanged();
    return jobId;
  }

  Future<void> deleteJob(String id) async {
    await _db.deleteJobLocal(id, now: _now());
    onChanged();
  }

  /// Moves a job forward (e.g. to "invoiced" once an invoice was issued). Never moves it back,
  /// and does nothing if the job is not in the local cache (yet).
  Future<void> advanceJobStatus(String id, String status) async {
    final job = await _db.jobById(id);
    if (job == null) return;
    final current = JobStatus.all.indexOf(job.status);
    final target = JobStatus.all.indexOf(status);
    if (target < 0 || target <= current) return;

    await _db.saveJobLocal(
      JobsCompanion(
        id: Value(job.id),
        businessId: Value(job.businessId),
        customerId: Value(job.customerId),
        title: Value(job.title),
        description: Value(job.description),
        status: Value(status),
      ),
      now: _now(),
    );
    onChanged();
  }
}

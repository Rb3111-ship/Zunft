import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/utils/validators.dart';

/// Job states the UI offers. The database also knows `overflow_ready` (Phase 3).
class JobStatus {
  static const draft = 'draft';
  static const quoteSent = 'quote_sent';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const invoiced = 'invoiced';

  static const all = [draft, quoteSent, inProgress, completed, invoiced];

  /// No more notes can be recorded on such a job (it is finished or already billed).
  static bool isClosed(String status) => status == completed || status == invoiced;

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
    // An issued document is frozen by law and points at its customer: such a customer must stay.
    final used = await (_db.select(_db.issuedDocuments)..where((d) => d.customerId.equals(id))).get();
    if (used.isNotEmpty) {
      throw const ValidationFailure(
          'Dieser Kunde hat Angebote oder Rechnungen und kann nicht gelöscht werden (gesetzliche Aufbewahrung).');
    }
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
    final cleanTitle = Validators.tidy(title);
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

  /// Merges [removeId] into [keepId]: the jobs move to the customer that is kept, missing details
  /// are filled in from the other one, and details that differ are written into the notes so
  /// nothing is lost. The merged customer is not deleted but hidden (issued documents still point
  /// at it, and they are frozen by law).
  Future<void> mergeCustomers({required String keepId, required String removeId}) async {
    if (keepId == removeId) throw const ValidationFailure('Das ist derselbe Kunde.');
    final keep = await _db.customerById(keepId);
    final gone = await _db.customerById(removeId);
    if (keep == null || gone == null) throw const ValidationFailure('Der Kunde existiert nicht mehr.');
    if (keep.mergedInto != null || gone.mergedInto != null) {
      throw const ValidationFailure('Einer der Kunden wurde schon zusammengeführt.');
    }

    String? firstNonEmpty(String? a, String? b) => (a ?? '').trim().isNotEmpty ? a : b;
    bool differs(String? a, String? b) =>
        (a ?? '').trim().isNotEmpty && (b ?? '').trim().isNotEmpty && a!.trim().toLowerCase() != b!.trim().toLowerCase();

    final extra = <String>[
      if (differs(keep.phone, gone.phone)) 'Telefon ${gone.phone}',
      if (differs(keep.email, gone.email)) 'E-Mail ${gone.email}',
      if (differs(keep.street, gone.street) || differs(keep.zip, gone.zip))
        'Adresse ${[gone.street, '${gone.zip ?? ''} ${gone.city ?? ''}'.trim()].where((p) => (p ?? '').isNotEmpty).join(', ')}',
      if ((gone.notes ?? '').trim().isNotEmpty && gone.notes!.trim() != (keep.notes ?? '').trim()) 'Notiz: ${gone.notes!.trim()}',
    ];
    final goneName = [gone.firstName, gone.name].where((p) => (p ?? '').isNotEmpty).join(' ');
    final notes = [
      if ((keep.notes ?? '').trim().isNotEmpty) keep.notes!.trim(),
      if (extra.isNotEmpty) 'Zusammengeführt mit „$goneName“ (${extra.join('; ')})',
    ].join('\n');

    await _db.transaction(() async {
      final merged = keep.toCompanion(true).copyWith(
            salutation: Value(firstNonEmpty(keep.salutation, gone.salutation)),
            firstName: Value(firstNonEmpty(keep.firstName, gone.firstName)),
            email: Value(firstNonEmpty(keep.email, gone.email)),
            phone: Value(firstNonEmpty(keep.phone, gone.phone)),
            street: Value(firstNonEmpty(keep.street, gone.street)),
            zip: Value(firstNonEmpty(keep.zip, gone.zip)),
            city: Value(firstNonEmpty(keep.city, gone.city)),
            notes: Value(_clean(notes)),
          );
      await _db.saveCustomerLocal(merged, now: _now());
      final jobs = await (_db.select(_db.jobs)..where((j) => j.customerId.equals(removeId))).get();
      for (final j in jobs) {
        await _db.saveJobLocal(j.toCompanion(true).copyWith(customerId: Value(keepId)), now: _now());
      }
      final appts = await (_db.select(_db.appointments)..where((a) => a.customerId.equals(removeId))).get();
      for (final a in appts) {
        await _db.saveAppointmentLocal(a.toCompanion(true).copyWith(customerId: Value(keepId)), now: _now());
      }
      await _db.saveCustomerLocal(gone.toCompanion(true).copyWith(mergedInto: Value(keepId)), now: _now());
    });
    onChanged();
  }

  // --- Appointments --------------------------------------------------------------------

  /// Creates (id == null) or changes an appointment; returns its id. Saved locally first, then synced.
  Future<String> saveAppointment({
    String? id,
    String kind = 'job',
    required String title,
    String? location,
    String? notes,
    required DateTime start,
    required DateTime end,
    String? jobId,
    String? customerId,
    String status = 'planned',
    Set<String> assignees = const {},
  }) async {
    final cleanTitle = Validators.tidy(title);
    if (cleanTitle.isEmpty) throw const ValidationFailure('Titel darf nicht leer sein');
    if (!end.isAfter(start)) throw const ValidationFailure('Das Ende muss nach dem Beginn liegen.');
    if (end.difference(start) > const Duration(days: 31)) {
      throw const ValidationFailure('Ein Termin darf höchstens 31 Tage dauern.');
    }
    if (!const ['job', 'absence', 'other'].contains(kind)) throw ValidationFailure('Unbekannte Art: $kind');
    if (jobId != null && await _db.jobById(jobId) == null) throw const ValidationFailure('Der Auftrag existiert nicht mehr');
    if (customerId != null && await _db.customerById(customerId) == null) {
      throw const ValidationFailure('Der Kunde existiert nicht mehr');
    }
    final appointmentId = id ?? _newId();
    await _db.saveAppointmentLocal(
      AppointmentsCompanion(
        id: Value(appointmentId),
        businessId: Value(businessId),
        jobId: Value(jobId),
        customerId: Value(customerId),
        kind: Value(kind),
        title: Value(cleanTitle),
        location: Value(_clean(location)),
        notes: Value(_clean(notes)),
        startsAt: Value(start.toUtc()),
        endsAt: Value(end.toUtc()),
        status: Value(status),
        assigneeIds: Value(jsonEncode(assignees.toList()..sort())),
      ),
      now: _now(),
    );
    onChanged();
    return appointmentId;
  }

  Future<void> deleteAppointment(String id) async {
    await _db.deleteAppointmentLocal(id, now: _now());
    onChanged();
  }

  /// Boss and office: the change is saved here and synced like any other edit.
  Future<void> setAppointmentStatus(String id, String status) async {
    final a = await _db.appointmentById(id);
    if (a == null) return;
    await _db.saveAppointmentLocal(a.toCompanion(true).copyWith(status: Value(status)), now: _now());
    onChanged();
  }

  /// An employee marked it through the server (an employee may not edit appointments directly):
  /// only the local copy is updated, nothing is queued.
  Future<void> applyServerAppointmentStatus(String id, String status) async {
    await (_db.update(_db.appointments)..where((a) => a.id.equals(id))).write(AppointmentsCompanion(status: Value(status)));
  }

  Future<void> deleteJob(String id) async {
    await _db.deleteJobLocal(id, now: _now());
    onChanged();
  }

  /// Links a job to a customer (e.g. after a new customer was created while issuing its invoice).
  Future<void> assignJobCustomer(String jobId, String customerId) async {
    final job = await _db.jobById(jobId);
    if (job == null || job.customerId != null) return;
    await _db.saveJobLocal(
      JobsCompanion(
        id: Value(job.id),
        businessId: Value(job.businessId),
        customerId: Value(customerId),
        title: Value(job.title),
        description: Value(job.description),
        status: Value(job.status),
      ),
      now: _now(),
    );
    onChanged();
  }

  /// Sets the status in either direction (finish a job, or reopen it for more work).
  Future<void> setJobStatus(String id, String status) async {
    final job = await _db.jobById(id);
    if (job == null || !JobStatus.all.contains(status) || job.status == status) return;
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

import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Server JSON <-> local rows. `updated_at` is only ever read from the server
/// (a database trigger sets it), so it is never part of a push payload.

CustomersCompanion customerFromRemote(Map<String, dynamic> j) => CustomersCompanion(
      id: Value(j['id'] as String),
      businessId: Value(j['business_id'] as String),
      salutation: Value(j['salutation'] as String?),
      name: Value(j['name'] as String),
      firstName: Value(j['first_name'] as String?),
      email: Value(j['email'] as String?),
      phone: Value(j['phone'] as String?),
      street: Value(j['street'] as String?),
      zip: Value(j['zip'] as String?),
      city: Value(j['city'] as String?),
      notes: Value(j['notes'] as String?),
      mergedInto: Value(j['merged_into'] as String?),
      updatedAt: Value(DateTime.parse(j['updated_at'] as String)),
    );

Map<String, dynamic> customerToRemote(Customer c) => {
      'id': c.id,
      'business_id': c.businessId,
      'salutation': c.salutation,
      'name': c.name,
      'first_name': c.firstName,
      'email': c.email,
      'phone': c.phone,
      'street': c.street,
      'zip': c.zip,
      'city': c.city,
      'notes': c.notes,
      'merged_into': c.mergedInto,
    };

JobsCompanion jobFromRemote(Map<String, dynamic> j) => JobsCompanion(
      id: Value(j['id'] as String),
      businessId: Value(j['business_id'] as String),
      customerId: Value(j['customer_id'] as String?),
      title: Value(j['title'] as String),
      description: Value(j['description'] as String?),
      status: Value(j['status'] as String),
      updatedAt: Value(DateTime.parse(j['updated_at'] as String)),
    );

Map<String, dynamic> jobToRemote(Job j) => {
      'id': j.id,
      'business_id': j.businessId,
      'customer_id': j.customerId,
      'title': j.title,
      'description': j.description,
      'status': j.status,
    };

/// documents.line_items / recipient_snapshot arrive as JSON (or, depending on the transport, strings).
IssuedDocumentsCompanion documentFromRemote(Map<String, dynamic> j) {
  final lines = j['line_items'];
  final recipient = j['recipient_snapshot'];
  final recipientMap =
      recipient is String ? jsonDecode(recipient) as Map<String, dynamic> : (recipient as Map).cast<String, dynamic>();
  return IssuedDocumentsCompanion(
    id: Value(j['id'] as String),
    businessId: Value(j['business_id'] as String),
    jobId: Value(j['job_id'] as String?),
    customerId: Value(j['customer_id'] as String?),
    docType: Value(j['doc_type'] as String),
    docNumber: Value(j['doc_number'] as String),
    status: Value(j['status'] as String),
    title: Value(j['title'] as String?),
    dateIssued: Value(j['date_issued'] as String),
    dateDue: Value(j['date_due'] as String?),
    deliveryPeriod: Value(j['delivery_period'] as String?),
    subtotalLaborCents: Value((j['subtotal_labor_cents'] as num).toInt()),
    subtotalMaterialCents: Value((j['subtotal_material_cents'] as num).toInt()),
    totalNetCents: Value((j['total_net_cents'] as num).toInt()),
    // NUMERIC can arrive as int, double or String.
    vatRate: Value(double.parse(j['vat_rate'].toString())),
    vatAmountCents: Value((j['vat_amount_cents'] as num).toInt()),
    totalGrossCents: Value((j['total_gross_cents'] as num).toInt()),
    lineItemsJson: Value(lines is String ? lines : jsonEncode(lines)),
    recipientName: Value((recipientMap['name'] ?? '') as String),
    recipientAddress: Value(recipientMap['address'] as String?),
    pdfPath: Value(j['pdf_url'] as String?),
    eInvoice: Value((j['e_invoice'] as bool?) ?? false),
    updatedAt: Value(DateTime.parse(j['updated_at'] as String)),
  );
}

/// assignee_ids is a Postgres uuid[] on the server (a JSON array in the payload) and a JSON text
/// column locally.
AppointmentsCompanion appointmentFromRemote(Map<String, dynamic> j) {
  final ids = j['assignee_ids'];
  return AppointmentsCompanion(
    id: Value(j['id'] as String),
    businessId: Value(j['business_id'] as String),
    jobId: Value(j['job_id'] as String?),
    customerId: Value(j['customer_id'] as String?),
    kind: Value((j['kind'] as String?) ?? 'job'),
    title: Value(j['title'] as String),
    location: Value(j['location'] as String?),
    notes: Value(j['notes'] as String?),
    startsAt: Value(DateTime.parse(j['starts_at'] as String).toUtc()),
    endsAt: Value(DateTime.parse(j['ends_at'] as String).toUtc()),
    status: Value((j['status'] as String?) ?? 'planned'),
    assigneeIds: Value(jsonEncode(ids is List ? ids.cast<String>() : <String>[])),
    createdBy: Value(j['created_by'] as String?),
    updatedAt: Value(DateTime.parse(j['updated_at'] as String)),
  );
}

Map<String, dynamic> appointmentToRemote(Appointment a) => {
      'id': a.id,
      'business_id': a.businessId,
      'job_id': a.jobId,
      'customer_id': a.customerId,
      'kind': a.kind,
      'title': a.title,
      'location': a.location,
      'notes': a.notes,
      'starts_at': a.startsAt.toUtc().toIso8601String(),
      'ends_at': a.endsAt.toUtc().toIso8601String(),
      'status': a.status,
      'assignee_ids': (jsonDecode(a.assigneeIds) as List).cast<String>(),
    };

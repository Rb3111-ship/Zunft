import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../../core/database/app_database.dart';
import '../../jobs/domain/job_photo.dart';
import '../../receipts/domain/receipt_entry.dart';
import '../../receipts/domain/receipt_export.dart';

/// A voice or typed note of a job, for the export (the text only; the recording is not part of it).
class ExportNote {
  const ExportNote({
    required this.createdAt,
    required this.jobTitle,
    required this.author,
    required this.status,
    required this.text,
  });

  final DateTime createdAt;
  final String jobTitle;
  final String author;

  /// Offen | Abgerechnet | Entfernt
  final String status;
  final String text;
}

/// Everything the export is made of. The lists come from the phone's copy (customers, jobs,
/// documents, appointments, time entries) and from the server (receipts, notes).
class FullExportData {
  const FullExportData({
    required this.businessName,
    required this.now,
    required this.customers,
    required this.jobs,
    required this.documents,
    required this.appointments,
    required this.timeEntries,
    required this.notes,
    required this.receipts,
    required this.memberNames,
    this.jobPhotos = const [],
  });

  final String businessName;
  final DateTime now;
  final List<Customer> customers;
  final List<Job> jobs;
  final List<IssuedDocument> documents;
  final List<Appointment> appointments;
  final List<TimeEntry> timeEntries;
  final List<ExportNote> notes;
  final List<ReceiptEntry> receipts;

  /// User id -> full name, to name the people of an appointment.
  final Map<String, String> memberNames;

  /// The photos of the jobs (before, after, other).
  final List<JobPhoto> jobPhotos;
}

class FullExport {
  const FullExport({required this.zip, required this.counts, required this.missingFiles});

  final Uint8List zip;

  /// What is inside, by name (Kunden, Aufträge, ...), for the summary shown to the user.
  final Map<String, int> counts;

  /// PDFs and photos that could not be fetched (also listed in the ZIP's README).
  final List<String> missingFiles;
}

String _stamp(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _day(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _kind(String t) => switch (t) {
      'quote' => 'Angebot',
      'cancellation' => 'Stornorechnung',
      _ => 'Rechnung',
    };

String _status(String s) => switch (s) {
      'issued' => 'Erstellt',
      'sent' => 'Versendet',
      'paid' => 'Bezahlt',
      'canceled' => 'Storniert',
      _ => s,
    };

String customersCsv(List<Customer> customers) {
  final byId = {for (final c in customers) c.id: c};
  String name(Customer c) => [c.firstName, c.name].where((s) => (s ?? '').isNotEmpty).join(' ');
  return csvOf([
    ['Anrede', 'Vorname', 'Nachname / Firma', 'E-Mail', 'Telefon', 'Straße', 'PLZ', 'Ort', 'Leitweg-ID', 'Notizen', 'Zusammengeführt mit'],
    for (final c in customers)
      [
        c.salutation ?? '',
        c.firstName ?? '',
        c.name,
        c.email ?? '',
        c.phone ?? '',
        c.street ?? '',
        c.zip ?? '',
        c.city ?? '',
        c.leitwegId ?? '',
        c.notes ?? '',
        c.mergedInto == null ? '' : (byId[c.mergedInto] == null ? c.mergedInto! : name(byId[c.mergedInto]!)),
      ],
  ]);
}

String jobsCsv(List<Job> jobs, List<Customer> customers) {
  final byId = {for (final c in customers) c.id: c};
  String status(String s) => switch (s) {
        'draft' => 'Entwurf',
        'in_progress' => 'In Arbeit',
        'completed' => 'Abgeschlossen',
        'invoiced' => 'Abgerechnet',
        _ => s,
      };
  return csvOf([
    ['Titel', 'Kunde', 'Status', 'Beschreibung', 'Zuletzt geändert'],
    for (final j in jobs)
      [
        j.title,
        byId[j.customerId] == null ? '' : [byId[j.customerId]!.firstName, byId[j.customerId]!.name].where((s) => (s ?? '').isNotEmpty).join(' '),
        status(j.status),
        j.description ?? '',
        _stamp(j.updatedAt),
      ],
  ]);
}

String documentsFullCsv(List<IssuedDocument> docs, Map<String, String> pdfNames) => csvOf([
      [
        'Nummer', 'Art', 'Datum', 'Fällig', 'Kunde', 'Anschrift', 'Leitweg-ID', 'Titel', 'Leistungszeitraum', 'Status',
        'Lohn netto', 'Material netto', 'Netto', 'MwSt.-Satz', 'MwSt.', 'Brutto', 'E-Rechnung', 'PDF'
      ],
      for (final d in docs)
        [
          d.docNumber,
          _kind(d.docType),
          _day(DateTime.parse(d.dateIssued)),
          d.dateDue == null ? '' : _day(DateTime.parse(d.dateDue!)),
          d.recipientName,
          d.recipientAddress ?? '',
          d.buyerReference ?? '',
          d.title ?? '',
          d.deliveryPeriod ?? '',
          _status(d.status),
          euroCsv(d.subtotalLaborCents),
          euroCsv(d.subtotalMaterialCents),
          euroCsv(d.totalNetCents),
          '${d.vatRate.toStringAsFixed(d.vatRate % 1 == 0 ? 0 : 1).replaceAll('.', ',')} %',
          euroCsv(d.vatAmountCents),
          euroCsv(d.totalGrossCents),
          d.eInvoice ? 'ja' : 'nein',
          pdfNames[d.id] ?? '',
        ],
    ]);

String positionsCsv(List<IssuedDocument> docs) {
  final rows = <List<String>>[
    ['Dokument', 'Position', 'Art', 'Beschreibung', 'Menge', 'Einheit', 'Einzelpreis netto', 'Summe netto'],
  ];
  for (final d in docs) {
    try {
      final items = jsonDecode(d.lineItemsJson) as List<dynamic>;
      for (final (i, raw) in items.indexed) {
        final m = (raw as Map).cast<String, dynamic>();
        final qty = (m['quantity'] as num?)?.toDouble() ?? 0;
        final unit = (m['unit_price_net_cents'] as num?)?.toInt() ?? 0;
        final total = (m['total_net_cents'] as num?)?.toInt() ?? (qty * unit).round();
        rows.add([
          d.docNumber,
          '${i + 1}',
          switch (m['type']) { 'labor' => 'Arbeit', 'flat_fee' => 'Pauschale', _ => 'Material' },
          (m['description'] as String?) ?? '',
          qty.toString().replaceAll(RegExp(r'\.0$'), '').replaceAll('.', ','),
          (m['unit'] as String?) ?? '',
          euroCsv(unit),
          euroCsv(total),
        ]);
      }
    } catch (_) {
      // an unreadable positions list is skipped; the document itself is in the other list
    }
  }
  return csvOf(rows);
}

String appointmentsCsv(List<Appointment> appts, List<Job> jobs, List<Customer> customers, Map<String, String> memberNames) {
  final jobById = {for (final j in jobs) j.id: j};
  final customerById = {for (final c in customers) c.id: c};
  String kind(String k) => switch (k) { 'absence' => 'Abwesenheit', 'other' => 'Sonstiges', _ => 'Termin' };
  String status(String s) => switch (s) { 'done' => 'Erledigt', 'canceled' => 'Abgesagt', _ => 'Geplant' };
  List<String> people(String json) {
    try {
      return [for (final id in jsonDecode(json) as List<dynamic>) memberNames['$id'] ?? '$id'];
    } catch (_) {
      return const [];
    }
  }

  return csvOf([
    ['Titel', 'Art', 'Beginn', 'Ende', 'Ort', 'Auftrag', 'Kunde', 'Personen', 'Status', 'Notiz'],
    for (final a in appts)
      [
        a.title,
        kind(a.kind),
        _stamp(a.startsAt.toLocal()),
        _stamp(a.endsAt.toLocal()),
        a.location ?? '',
        jobById[a.jobId]?.title ?? '',
        customerById[a.customerId] == null
            ? ''
            : [customerById[a.customerId]!.firstName, customerById[a.customerId]!.name].where((s) => (s ?? '').isNotEmpty).join(' '),
        people(a.assigneeIds).join(', '),
        status(a.status),
        a.notes ?? '',
      ],
  ]);
}

String timeEntriesCsv(List<TimeEntry> entries, List<Job> jobs, DateTime now) {
  final jobById = {for (final j in jobs) j.id: j};
  String hours(int minutes) => '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
  return csvOf([
    ['Person', 'Auftrag', 'Beginn', 'Ende', 'Pause (Min.)', 'Arbeitszeit (Std.)', 'Notiz', 'Abgerechnet', 'Vom Betrieb eingetragen'],
    for (final t in entries)
      [
        t.userName ?? '',
        jobById[t.jobId]?.title ?? '',
        _stamp(t.startedAt.toLocal()),
        t.endedAt == null ? 'läuft' : _stamp(t.endedAt!.toLocal()),
        '${t.breakMinutes}',
        hours(((t.endedAt ?? now).difference(t.startedAt).inMinutes - t.breakMinutes).clamp(0, 1 << 30)),
        t.note ?? '',
        t.documentId == null ? 'nein' : 'ja',
        (t.createdBy != null && t.createdBy != t.userId) ? 'ja' : 'nein',
      ],
  ]);
}

String photosCsv(List<JobPhoto> photos, List<Job> jobs, Map<String, String> fileNames) {
  final jobById = {for (final j in jobs) j.id: j};
  return csvOf([
    ['Datum', 'Auftrag', 'Art', 'Erfasst von', 'Datei'],
    for (final p in photos)
      [_stamp(p.createdAt), jobById[p.jobId]?.title ?? '', photoKindLabelDe(p.kind), p.authorName ?? '', fileNames[p.id] ?? ''],
  ]);
}

String notesCsv(List<ExportNote> notes) => csvOf([
      ['Datum', 'Auftrag', 'Erfasst von', 'Status', 'Text'],
      for (final n in notes) [_stamp(n.createdAt), n.jobTitle, n.author, n.status, n.text],
    ]);

String _readme(FullExportData d, Map<String, int> counts, List<String> missing) => [
      'Datenexport von ${d.businessName}',
      'Erstellt am ${_stamp(d.now)} mit Zunft.',
      '',
      'Inhalt:',
      '- kunden.csv: alle Kunden (auch zusammengeführte, mit Hinweis)',
      '- auftraege.csv: alle Aufträge',
      '- notizen.csv: der Text aller Sprach- und getippten Notizen (die Tonaufnahmen sind nicht enthalten)',
      '- rechnungen.csv und positionen.csv: alle Angebote, Rechnungen und Stornorechnungen mit ihren Positionen',
      '- rechnungen/: die PDF jedes Dokuments (Dateiname = Nummer)',
      '- belege.csv und belege/: die Einkaufsbelege mit Fotos, nach Monat sortiert',
      '- fotos.csv und fotos/: die Fotos der Aufträge (vorher, nachher, weitere), nach Auftrag sortiert',
      '- termine.csv: alle Termine',
      '- zeiten.csv: die erfasste Arbeitszeit',
      '',
      'Anzahl: ${counts.entries.map((e) => '${e.key} ${e.value}').join(', ')}.',
      'Die CSV-Dateien sind mit Semikolon getrennt und im deutschen Zahlenformat; sie öffnen sich in Excel.',
      'Ausgestellte Rechnungen müssen gesetzlich aufbewahrt werden: bewahre diese Datei sicher auf.',
      if (missing.isNotEmpty) ...[
        '',
        'Diese Dateien konnten nicht geladen werden (bitte später erneut exportieren):',
        for (final m in missing) '- $m',
      ],
    ].join('\r\n');

/// A ZIP of everything the business has in Zunft, for the owner's own records, the tax advisor or a
/// change of tool. [fetchPdf] gives the PDF of one document, [fetchPhoto] one receipt photo; a file
/// that cannot be fetched is listed in the README and the rest is still delivered.
/// [onProgress] is called after each file with (done, total).
Future<FullExport> buildFullExport(
  FullExportData d, {
  required Future<Uint8List> Function(IssuedDocument doc) fetchPdf,
  required Future<Uint8List> Function(String imagePath) fetchPhoto,
  Future<Uint8List> Function(JobPhoto photo)? fetchJobPhoto,
  void Function(int done, int total)? onProgress,
}) async {
  final archive = Archive();
  void add(String name, List<int> bytes) => archive.addFile(ArchiveFile(name, bytes.length, bytes));
  List<int> text(String s) => utf8.encode(s);

  final missing = <String>[];
  final total = d.documents.length + d.receipts.length + (fetchJobPhoto == null ? 0 : d.jobPhotos.length);
  var done = 0;

  // documents: the CSV needs the PDF names, so the PDFs are fetched first
  final pdfNames = <String, String>{};
  final usedPdf = <String>{};
  for (final doc in d.documents) {
    var name = 'rechnungen/${doc.docNumber.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')}.pdf';
    if (!usedPdf.add(name)) name = name.replaceFirst('.pdf', '_${doc.id.substring(0, doc.id.length < 6 ? doc.id.length : 6)}.pdf');
    try {
      add(name, await fetchPdf(doc));
      pdfNames[doc.id] = name;
    } catch (_) {
      missing.add('${doc.docNumber} (PDF)');
    }
    onProgress?.call(++done, total);
  }

  final photoNames = <String, String>{};
  final usedPhoto = <String>{};
  for (final r in d.receipts) {
    var name = receiptFileName(r);
    if (!usedPhoto.add(name)) {
      name = name.replaceFirstMapped(RegExp(r'\.(jpg|png|pdf)$'), (m) => '_${r.id.substring(0, r.id.length < 6 ? r.id.length : 6)}.${m[1]}');
      usedPhoto.add(name);
    }
    try {
      add('belege/$name', await fetchPhoto(r.imagePath));
      photoNames[r.id] = 'belege/$name';
    } catch (_) {
      missing.add('Beleg ${_day(r.date)} ${r.supplierLabel}');
    }
    onProgress?.call(++done, total);
  }

  final jobPhotoNames = <String, String>{};
  if (fetchJobPhoto != null) {
    final jobTitle = {for (final j in d.jobs) j.id: j.title};
    for (final p in d.jobPhotos) {
      final folder = slugOf(jobTitle[p.jobId] ?? 'Auftrag');
      final name = 'fotos/${folder.isEmpty ? 'Auftrag' : folder}/${_iso(p.createdAt)}_${photoKindLabelDe(p.kind)}_${p.id.substring(0, p.id.length < 6 ? p.id.length : 6)}.jpg';
      try {
        add(name, await fetchJobPhoto(p));
        jobPhotoNames[p.id] = name;
      } catch (_) {
        missing.add('Foto ${_day(p.createdAt)} ${jobTitle[p.jobId] ?? ''}');
      }
      onProgress?.call(++done, total);
    }
  }

  add('kunden.csv', text(customersCsv(d.customers)));
  add('auftraege.csv', text(jobsCsv(d.jobs, d.customers)));
  add('notizen.csv', text(notesCsv(d.notes)));
  add('rechnungen.csv', text(documentsFullCsv(d.documents, pdfNames)));
  add('positionen.csv', text(positionsCsv(d.documents)));
  add('belege.csv', text(receiptsCsv(d.receipts, photoNames)));
  add('termine.csv', text(appointmentsCsv(d.appointments, d.jobs, d.customers, d.memberNames)));
  add('zeiten.csv', text(timeEntriesCsv(d.timeEntries, d.jobs, d.now)));
  add('fotos.csv', text(photosCsv(d.jobPhotos, d.jobs, jobPhotoNames)));

  final counts = {
    'Kunden': d.customers.length,
    'Aufträge': d.jobs.length,
    'Notizen': d.notes.length,
    'Dokumente': d.documents.length,
    'Belege': d.receipts.length,
    'Termine': d.appointments.length,
    'Zeiteinträge': d.timeEntries.length,
    'Fotos': d.jobPhotos.length,
  };
  add('LIESMICH.txt', text(_readme(d, counts, missing)));

  return FullExport(zip: Uint8List.fromList(ZipEncoder().encode(archive)), counts: counts, missingFiles: missing);
}

/// The file name of the export, e.g. `Zunft_Datenexport_2026-10-14.zip`.
String fullExportFileName(DateTime now) => 'Zunft_Datenexport_${_iso(now)}.zip';

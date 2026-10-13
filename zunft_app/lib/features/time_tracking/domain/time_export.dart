import 'dart:convert';
import 'dart:typed_data';

import '../../../core/database/app_database.dart';
import '../../appointments/domain/appointment_models.dart' show monthNames;
import '../../receipts/domain/receipt_export.dart';
import 'time_models.dart';

String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _time(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _decimal(int minutes) => hoursText(minutes);

String timesheetPeriodLabel(DateTime start, bool month) {
  if (month) return '${monthNames[start.month - 1]} ${start.year}';
  final end = start.add(const Duration(days: 6));
  return '${_date(start).substring(0, 6)} - ${_date(end)}';
}

String timesheetFileStem(DateTime start, bool month) => month
    ? 'arbeitszeiten-${start.year}-${start.month.toString().padLeft(2, '0')}'
    : 'arbeitszeiten-woche-${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';

/// The working times of a period as a CSV file (German format, opens in Excel): one line per
/// entry, then the total of each person. [jobTitle] looks a job up by id.
Uint8List timesheetCsv({
  required List<TimeEntry> entries,
  required String Function(String? jobId) jobTitle,
  required DateTime now,
  required String periodLabel,
}) {
  final sorted = [...entries]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final rows = <List<String>>[
    ['Zeitraum', periodLabel],
    [''],
    [
      'Datum',
      'Mitarbeiter',
      'Auftrag',
      'Beginn',
      'Ende',
      'Pause (Min.)',
      'Arbeitszeit (Std:Min)',
      'Arbeitszeit (dezimal)',
      'Notiz',
      'Vom Betrieb eingetragen',
      'Abgerechnet',
    ],
    for (final t in sorted)
      [
        _date(t.start),
        (t.userName ?? '').isEmpty ? 'Mitarbeiter' : t.userName!,
        jobTitle(t.jobId),
        _time(t.start),
        t.isRunning ? 'läuft' : _time(t.end!),
        '${t.breakMinutes}',
        clockLabel(t.worked(now)),
        _decimal(t.minutes(now)),
        t.note ?? '',
        t.enteredByOthers ? 'ja' : 'nein',
        t.isBilled ? 'ja' : 'nein',
      ],
    [''],
    ['Summe je Person'],
    for (final e in minutesByPerson(sorted, now).entries) [e.key, clockLabel(Duration(minutes: e.value)), _decimal(e.value)],
    ['Zusammen', clockLabel(Duration(minutes: sorted.fold<int>(0, (s, t) => s + t.minutes(now)))), _decimal(sorted.fold<int>(0, (s, t) => s + t.minutes(now)))],
    [''],
    ['Zusammenstellung der erfassten Zeiten. Kein Arbeitszeitnachweis im rechtlichen Sinn; Einträge können bis zur Abrechnung geändert werden.'],
  ];
  return Uint8List.fromList(utf8.encode(csvText(rows)));
}

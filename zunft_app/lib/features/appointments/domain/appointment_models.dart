import 'dart:convert';

import '../../../core/database/app_database.dart';

class AppointmentKind {
  static const job = 'job';
  static const absence = 'absence';
  static const other = 'other';

  static const all = [job, absence, other];

  static const labels = {job: 'Termin', absence: 'Abwesenheit', other: 'Sonstiges'};

  static String label(String kind) => labels[kind] ?? kind;
}

class AppointmentStatus {
  static const planned = 'planned';
  static const done = 'done';
  static const canceled = 'canceled';

  static const labels = {planned: 'Geplant', done: 'Erledigt', canceled: 'Abgesagt'};

  static String label(String status) => labels[status] ?? status;
}

extension AppointmentX on Appointment {
  /// The people on it (user ids).
  List<String> get assignees {
    try {
      return (jsonDecode(assigneeIds) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  DateTime get start => startsAt.toLocal();
  DateTime get end => endsAt.toLocal();

  bool get isAbsence => kind == AppointmentKind.absence;
  bool get isDone => status == AppointmentStatus.done;
  bool get isCanceled => status == AppointmentStatus.canceled;
}

String encodeAssignees(Iterable<String> ids) => jsonEncode(ids.toSet().toList()..sort());

bool _overlaps(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) =>
    aStart.isBefore(bEnd) && bStart.isBefore(aEnd);

/// The existing appointments that collide with a new one: they overlap in time AND share a person.
/// Cancelled ones do not count; an absence (holiday, sick) does, because the person is not there.
List<Appointment> findConflicts(
  Iterable<Appointment> existing, {
  required DateTime start,
  required DateTime end,
  required Set<String> assignees,
  String? excludeId,
}) {
  if (assignees.isEmpty) return const [];
  return [
    for (final a in existing)
      if (a.id != excludeId &&
          !a.isCanceled &&
          _overlaps(a.startsAt, a.endsAt, start.toUtc(), end.toUtc()) &&
          a.assignees.any(assignees.contains))
        a,
  ]..sort((x, y) => x.startsAt.compareTo(y.startsAt));
}

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// The Monday of the week that contains [d] (local time).
DateTime mondayOf(DateTime d) => startOfDay(d).subtract(Duration(days: d.weekday - DateTime.monday));

/// Appointments that touch the local day [day], earliest first. A multi-day absence appears on each day.
List<Appointment> appointmentsOnDay(Iterable<Appointment> all, DateTime day) {
  final from = startOfDay(day);
  final to = DateTime(from.year, from.month, from.day + 1); // not +24h: a day can be 23 or 25 hours long
  return [
    for (final a in all)
      if (_overlaps(a.startsAt, a.endsAt, from.toUtc(), to.toUtc())) a,
  ]..sort((x, y) => x.startsAt.compareTo(y.startsAt));
}

const weekdayNames = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
const weekdayShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const monthNames = [
  'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
];

String two(int n) => n.toString().padLeft(2, '0');

String timeLabel(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String dateLabel(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';

/// "Dienstag, 14.10.2026"
String longDateLabel(DateTime d) => '${weekdayNames[d.weekday - 1]}, ${dateLabel(d)}';

/// "08:00 - 10:30", or with dates when the appointment spans days.
String rangeLabel(Appointment a) {
  final s = a.start;
  final e = a.end;
  final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
  return sameDay
      ? '${timeLabel(s)} - ${timeLabel(e)}'
      : '${two(s.day)}.${two(s.month)}. ${timeLabel(s)} - ${two(e.day)}.${two(e.month)}. ${timeLabel(e)}';
}

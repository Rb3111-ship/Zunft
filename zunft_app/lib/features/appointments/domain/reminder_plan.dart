import '../../../core/database/app_database.dart';
import '../data/reminder_scheduler.dart';
import 'appointment_models.dart';

/// Which reminders to plan for [userId]: their own planned appointments (not absences, not done,
/// not cancelled) that start in the future, each [lead] before it starts. At most [limit] of the
/// next [horizon] (phones cap the number of pending alarms), earliest first.
List<Reminder> planReminders({
  required List<Appointment> appointments,
  required String userId,
  required DateTime now,
  required Duration lead,
  Duration horizon = const Duration(days: 14),
  int limit = 50,
}) {
  final result = <Reminder>[];
  final sorted = [...appointments]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  for (final a in sorted) {
    if (a.isAbsence || a.isDone || a.isCanceled || !a.assignees.contains(userId)) continue;
    final at = a.start.subtract(lead);
    if (!at.isAfter(now)) continue; // already past: a reminder now would only be noise
    if (a.start.isAfter(now.add(horizon))) break;
    final place = (a.location ?? '').trim();
    result.add(Reminder(
      id: a.id.hashCode & 0x7fffffff,
      title: lead.inMinutes == 0 ? 'Termin jetzt' : 'Termin in ${_leadLabel(lead)}',
      body: '${timeLabel(a.start)} · ${a.title}${place.isEmpty ? '' : ', $place'}',
      at: at,
    ));
    if (result.length >= limit) break;
  }
  return result;
}

String _leadLabel(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes} Minuten';
  final h = d.inMinutes ~/ 60;
  return h == 1 ? '1 Stunde' : '$h Stunden';
}

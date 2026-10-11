import '../../../core/database/app_database.dart';

extension TimeEntryX on TimeEntry {
  DateTime get start => startedAt.toLocal();
  DateTime? get end => endedAt?.toLocal();

  /// A timer that has not been stopped yet.
  bool get isRunning => endedAt == null;

  /// Billed on an invoice: frozen.
  bool get isBilled => documentId != null;

  /// How long was worked: start to end (or to [now] while running) minus the break; never negative.
  Duration worked(DateTime now) {
    final end = endedAt ?? now.toUtc();
    final d = end.difference(startedAt) - Duration(minutes: breakMinutes);
    return d.isNegative ? Duration.zero : d;
  }

  /// Whole minutes worked (a finished entry has a fixed value).
  int minutes(DateTime now) => worked(now).inMinutes;
}

/// "7:45" (hours and minutes), the way people read a working time.
String clockLabel(Duration d) => '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';

/// "01:23:45" for a running timer.
String elapsedLabel(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

/// Hours as a decimal number rounded to hundredths, for the invoice (7:45 is 7.75).
double decimalHours(int minutes) => (minutes / 60 * 100).round() / 100;

/// "7,75" with a German comma.
String hoursText(int minutes) => decimalHours(minutes).toStringAsFixed(2).replaceAll('.', ',');

/// The finished, not yet billed entries of [jobId]: what an invoice for the job may bill.
List<TimeEntry> billableEntries(Iterable<TimeEntry> all, String jobId) => [
      for (final t in all)
        if (t.jobId == jobId && !t.isRunning && !t.isBilled) t,
    ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));

/// Minutes per person, most first. A person who left is still counted under the name stored with
/// the entry.
Map<String, int> minutesByPerson(Iterable<TimeEntry> entries, DateTime now) {
  final result = <String, int>{};
  for (final t in entries) {
    final who = (t.userName ?? '').isEmpty ? 'Mitarbeiter' : t.userName!;
    result[who] = (result[who] ?? 0) + t.minutes(now);
  }
  final sorted = result.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return {for (final e in sorted) e.key: e.value};
}

/// A timer that has been running for more than this is probably a forgotten one.
const forgottenTimerAfter = Duration(hours: 12);

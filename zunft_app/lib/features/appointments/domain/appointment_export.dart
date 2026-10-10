import 'dart:convert';

import '../../../core/database/app_database.dart';
import 'appointment_models.dart';

String _icsDate(DateTime d) {
  final u = d.toUtc();
  return '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

String _escape(String s) =>
    s.replaceAll('\\', '\\\\').replaceAll(';', '\\;').replaceAll(',', '\\,').replaceAll('\r\n', '\\n').replaceAll('\n', '\\n');

/// RFC 5545: lines are at most 75 octets; longer ones continue on the next line after a space.
/// Folding counts bytes (umlauts are two) and never cuts a character in half.
String _fold(String line) {
  if (utf8.encode(line).length <= 75) return line;
  final out = StringBuffer();
  var bytes = 0;
  var limit = 75;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final n = utf8.encode(ch).length;
    if (bytes + n > limit) {
      out.write('\r\n ');
      bytes = 0;
      limit = 74; // the leading space counts
    }
    out.write(ch);
    bytes += n;
  }
  return out.toString();
}

/// A calendar file (.ics) with the given appointments: opens in the calendar app of any phone.
/// [names] maps a user id to a name; [now] is the time stamp (a parameter so tests are exact).
String buildIcs(List<Appointment> appointments, {Map<String, String> names = const {}, required DateTime now}) {
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Zunft//Termine//DE',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
  ];
  for (final a in appointments) {
    final who = [for (final id in a.assignees) if (names[id] != null) names[id]!];
    final description = [
      if (who.isNotEmpty) 'Wer: ${who.join(', ')}',
      if ((a.notes ?? '').trim().isNotEmpty) a.notes!.trim(),
    ].join('\n');
    lines.addAll([
      'BEGIN:VEVENT',
      'UID:${a.id}@zunft.app',
      'DTSTAMP:${_icsDate(now)}',
      'DTSTART:${_icsDate(a.startsAt)}',
      'DTEND:${_icsDate(a.endsAt)}',
      'SUMMARY:${_escape(a.title)}',
      if ((a.location ?? '').trim().isNotEmpty) 'LOCATION:${_escape(a.location!.trim())}',
      if (description.isNotEmpty) 'DESCRIPTION:${_escape(description)}',
      'STATUS:${a.isCanceled ? 'CANCELLED' : 'CONFIRMED'}',
      'END:VEVENT',
    ]);
  }
  lines.add('END:VCALENDAR');
  return '${lines.map(_fold).join('\r\n')}\r\n';
}

/// A friendly message for the customer to confirm the appointment, to send by WhatsApp, SMS or
/// e-mail. [salutation] is the customer's Anrede (Herr / Frau / Firma) and [name] the last name.
String confirmationText(
  Appointment a, {
  required String businessName,
  String? salutation,
  String? customerName,
  String? phone,
}) {
  final greeting = switch (salutation) {
    'Herr' when (customerName ?? '').isNotEmpty => 'Sehr geehrter Herr $customerName',
    'Frau' when (customerName ?? '').isNotEmpty => 'Sehr geehrte Frau $customerName',
    _ => 'Guten Tag',
  };
  final s = a.start;
  final where = (a.location ?? '').trim().isEmpty ? '' : ' (${a.location!.trim()})';
  return [
    '$greeting,',
    '',
    'wir bestätigen unseren Termin: ${longDateLabel(s)} um ${timeLabel(s)} Uhr$where.',
    a.title,
    '',
    'Falls der Termin nicht passt, melden Sie sich bitte kurz${(phone ?? '').isEmpty ? '' : ' unter $phone'}.',
    '',
    'Mit freundlichen Grüßen',
    businessName,
  ].join('\n');
}

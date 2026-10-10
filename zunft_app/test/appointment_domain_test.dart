import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/features/appointments/domain/appointment_export.dart';
import 'package:zunft_app/features/appointments/domain/appointment_models.dart';

Appointment appt(
  String id,
  DateTime start,
  DateTime end, {
  List<String> who = const ['u1'],
  String title = 'Termin',
  String kind = 'job',
  String status = 'planned',
  String? location,
  String? notes,
}) =>
    Appointment(
      id: id,
      businessId: 'b1',
      kind: kind,
      title: title,
      location: location,
      notes: notes,
      startsAt: start.toUtc(),
      endsAt: end.toUtc(),
      status: status,
      assigneeIds: jsonEncode(who),
      updatedAt: DateTime(2026),
    );

void main() {
  final d = DateTime(2026, 10, 14); // a Wednesday

  group('double booking', () {
    final existing = [appt('a', DateTime(2026, 10, 14, 8), DateTime(2026, 10, 14, 10), who: ['u1', 'u2'])];

    test('overlapping in time AND sharing a person is a conflict', () {
      final c = findConflicts(existing,
          start: DateTime(2026, 10, 14, 9), end: DateTime(2026, 10, 14, 11), assignees: {'u2'});
      expect(c.map((x) => x.id), ['a']);
    });

    test('touching ends do not collide (10:00 end, 10:00 start)', () {
      expect(
          findConflicts(existing, start: DateTime(2026, 10, 14, 10), end: DateTime(2026, 10, 14, 11), assignees: {'u1'}),
          isEmpty);
      expect(
          findConflicts(existing, start: DateTime(2026, 10, 14, 7), end: DateTime(2026, 10, 14, 8), assignees: {'u1'}),
          isEmpty);
    });

    test('another person, or nobody assigned: no conflict', () {
      expect(
          findConflicts(existing, start: DateTime(2026, 10, 14, 9), end: DateTime(2026, 10, 14, 11), assignees: {'u3'}),
          isEmpty);
      expect(
          findConflicts(existing, start: DateTime(2026, 10, 14, 9), end: DateTime(2026, 10, 14, 11), assignees: {}),
          isEmpty);
    });

    test('a cancelled appointment does not block; the appointment being edited does not collide with itself', () {
      final cancelled = [appt('x', DateTime(2026, 10, 14, 8), DateTime(2026, 10, 14, 10), status: 'canceled')];
      expect(
          findConflicts(cancelled, start: DateTime(2026, 10, 14, 8), end: DateTime(2026, 10, 14, 9), assignees: {'u1'}),
          isEmpty);
      expect(
          findConflicts(existing,
              start: DateTime(2026, 10, 14, 8), end: DateTime(2026, 10, 14, 9), assignees: {'u1'}, excludeId: 'a'),
          isEmpty);
    });

    test('an absence collides: the person is not there', () {
      final holiday = [appt('h', DateTime(2026, 10, 12), DateTime(2026, 10, 17), kind: 'absence', title: 'Urlaub')];
      expect(
          findConflicts(holiday, start: DateTime(2026, 10, 14, 9), end: DateTime(2026, 10, 14, 10), assignees: {'u1'}),
          hasLength(1));
    });
  });

  group('the calendar days', () {
    test('mondayOf: any day of the week gives its Monday', () {
      expect(mondayOf(DateTime(2026, 10, 14)), DateTime(2026, 10, 12));
      expect(mondayOf(DateTime(2026, 10, 12, 23, 59)), DateTime(2026, 10, 12));
      expect(mondayOf(DateTime(2026, 10, 18)), DateTime(2026, 10, 12)); // Sunday belongs to the week before
    });

    test('a day shows what touches it, earliest first; a multi-day absence shows on each day', () {
      final all = [
        appt('late', DateTime(2026, 10, 14, 15), DateTime(2026, 10, 14, 16)),
        appt('early', DateTime(2026, 10, 14, 8), DateTime(2026, 10, 14, 9)),
        appt('other', DateTime(2026, 10, 15, 8), DateTime(2026, 10, 15, 9)),
        appt('hol', DateTime(2026, 10, 13), DateTime(2026, 10, 16), kind: 'absence'), // Tue 00:00 - Fri 00:00
      ];
      expect(appointmentsOnDay(all, d).map((a) => a.id), ['hol', 'early', 'late']);
      expect(appointmentsOnDay(all, DateTime(2026, 10, 13)).map((a) => a.id), ['hol']);
      expect(appointmentsOnDay(all, DateTime(2026, 10, 15)).map((a) => a.id), ['hol', 'other']);
      expect(appointmentsOnDay(all, DateTime(2026, 10, 16)), isEmpty); // ends at midnight: Friday is free
    });

    test('an appointment that ends at midnight is not on the next day', () {
      final a = appt('n', DateTime(2026, 10, 14, 22), DateTime(2026, 10, 15));
      expect(appointmentsOnDay([a], DateTime(2026, 10, 15)), isEmpty);
      expect(appointmentsOnDay([a], DateTime(2026, 10, 14)), hasLength(1));
    });

    test('the German labels', () {
      expect(longDateLabel(d), 'Mittwoch, 14.10.2026');
      expect(rangeLabel(appt('r', DateTime(2026, 10, 14, 8), DateTime(2026, 10, 14, 10, 30))), '08:00 - 10:30');
      expect(rangeLabel(appt('r', DateTime(2026, 10, 14, 8), DateTime(2026, 10, 15, 12))), '14.10. 08:00 - 15.10. 12:00');
    });
  });

  group('the calendar file (.ics)', () {
    final now = DateTime.utc(2026, 10, 11, 8, 30);

    test('one event: UTC times, CRLF lines, escaped text, the people and notes in the description', () {
      final ics = buildIcs(
        [
          appt('id-1', DateTime.utc(2026, 10, 14, 6), DateTime.utc(2026, 10, 14, 8),
              title: 'Steckdose; Keller, 2. OG',
              location: 'Weg 1, 20095 Hamburg',
              notes: 'Zeile 1\nZeile 2',
              who: ['u1', 'u2'])
        ],
        names: {'u1': 'Roy', 'u2': 'Aydin'},
        now: now,
      );
      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics, endsWith('END:VCALENDAR\r\n'));
      expect(ics, contains('UID:id-1@zunft.app\r\n'));
      expect(ics, contains('DTSTAMP:20261011T083000Z\r\n'));
      expect(ics, contains('DTSTART:20261014T060000Z\r\n'));
      expect(ics, contains('DTEND:20261014T080000Z\r\n'));
      expect(ics, contains(r'SUMMARY:Steckdose\; Keller\, 2. OG'));
      expect(ics, contains(r'LOCATION:Weg 1\, 20095 Hamburg'));
      expect(ics, contains(r'DESCRIPTION:Wer: Roy\, Aydin\nZeile 1\nZeile 2'));
      expect(ics, contains('STATUS:CONFIRMED'));
      expect(ics.replaceAll('\r\n', '').contains('\n'), isFalse); // only CRLF line ends
    });

    test('a cancelled appointment is marked cancelled; several appointments make several events', () {
      final ics = buildIcs([
        appt('a', DateTime.utc(2026, 10, 14, 6), DateTime.utc(2026, 10, 14, 7)),
        appt('b', DateTime.utc(2026, 10, 15, 6), DateTime.utc(2026, 10, 15, 7), status: 'canceled'),
      ], now: now);
      expect('BEGIN:VEVENT'.allMatches(ics).length, 2);
      expect(ics, contains('STATUS:CANCELLED'));
    });

    test('long lines are folded at 75 bytes, never inside an umlaut', () {
      final title = 'Ä' * 80;
      final ics = buildIcs([appt('a', DateTime.utc(2026, 10, 14, 6), DateTime.utc(2026, 10, 14, 7), title: title)], now: now);
      for (final line in ics.split('\r\n')) {
        expect(utf8.encode(line).length, lessThanOrEqualTo(75), reason: line);
      }
      expect(ics.replaceAll('\r\n ', ''), contains('SUMMARY:$title'));
    });
  });

  group('the confirmation text for the customer', () {
    final a = appt('a', DateTime(2026, 10, 14, 8), DateTime(2026, 10, 14, 10),
        title: 'Steckdose im Keller', location: 'Elbchaussee 118, 22763 Hamburg');

    test('Herr, Frau, and a company or unknown each get the right greeting', () {
      String text(String? s) =>
          confirmationText(a, businessName: 'Elektro Test GmbH', salutation: s, customerName: 'Müller', phone: '040 123');
      expect(text('Herr'), startsWith('Sehr geehrter Herr Müller,'));
      expect(text('Frau'), startsWith('Sehr geehrte Frau Müller,'));
      expect(text('Firma'), startsWith('Guten Tag,'));
      expect(text(null), startsWith('Guten Tag,'));
    });

    test('the date, the time, the place, the job, a way to reach us, and the sender', () {
      final t = confirmationText(a, businessName: 'Elektro Test GmbH', salutation: 'Herr', customerName: 'Müller', phone: '040 123');
      expect(t, contains('Mittwoch, 14.10.2026 um 08:00 Uhr (Elbchaussee 118, 22763 Hamburg)'));
      expect(t, contains('Steckdose im Keller'));
      expect(t, contains('unter 040 123'));
      expect(t, endsWith('Elektro Test GmbH'));
    });

    test('without place and phone nothing odd is printed', () {
      final t = confirmationText(appt('b', DateTime(2026, 10, 14, 8), DateTime(2026, 10, 14, 9)), businessName: 'X');
      expect(t, isNot(contains('()')));
      expect(t, isNot(contains('unter')));
    });
  });
}

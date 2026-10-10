import 'dart:convert';

import 'package:flutter/widgets.dart' show AppLifecycleState, Scrollable;
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/features/appointments/application/reminder_providers.dart';
import 'package:zunft_app/features/appointments/domain/reminder_plan.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';

import 'helpers/fake_appointments.dart';
import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/job_app.dart';
import 'helpers/test_app.dart';

Appointment appt(
  String id,
  DateTime start, {
  List<String> who = const ['u1'],
  String status = 'planned',
  String kind = 'job',
  String title = 'Steckdose Keller',
  String? location,
}) =>
    Appointment(
      id: id,
      businessId: 'b1',
      kind: kind,
      title: title,
      location: location,
      startsAt: start.toUtc(),
      endsAt: start.add(const Duration(hours: 1)).toUtc(),
      status: status,
      assigneeIds: jsonEncode(who),
      updatedAt: DateTime(2026),
    );

void main() {
  final now = DateTime(2026, 10, 14, 7, 0);

  group('which reminders are planned', () {
    List<String> ids(List<Appointment> a, {String user = 'u1', Duration lead = const Duration(minutes: 30)}) =>
        planReminders(appointments: a, userId: user, now: now, lead: lead).map((r) => r.body).toList();

    test('my planned appointments, a lead time before the start, earliest first', () {
      final r = planReminders(
        appointments: [
          appt('b', DateTime(2026, 10, 14, 13), location: 'Elbchaussee 118'),
          appt('a', DateTime(2026, 10, 14, 9), title: 'Zähler'),
        ],
        userId: 'u1',
        now: now,
        lead: const Duration(minutes: 30),
      );
      expect(r.map((x) => x.at), [DateTime(2026, 10, 14, 8, 30), DateTime(2026, 10, 14, 12, 30)]);
      expect(r.first.title, 'Termin in 30 Minuten');
      expect(r.first.body, '09:00 · Zähler');
      expect(r.last.body, '13:00 · Steckdose Keller, Elbchaussee 118');
    });

    test('not for other people, absences, done or cancelled appointments', () {
      expect(
          ids([
            appt('other', DateTime(2026, 10, 14, 9), who: ['u2']),
            appt('abs', DateTime(2026, 10, 14, 9), kind: 'absence'),
            appt('done', DateTime(2026, 10, 14, 9), status: 'done'),
            appt('canc', DateTime(2026, 10, 14, 9), status: 'canceled'),
          ]),
          isEmpty);
    });

    test('a reminder whose time has passed is not planned (no noise); the one 31 minutes ahead is', () {
      expect(ids([appt('soon', DateTime(2026, 10, 14, 7, 20))]), isEmpty); // 20 min away, lead 30
      expect(ids([appt('ok', DateTime(2026, 10, 14, 7, 31))]), hasLength(1));
      expect(ids([appt('past', DateTime(2026, 10, 14, 6))]), isEmpty);
    });

    test('only the next 14 days, and at most 50', () {
      expect(ids([appt('far', DateTime(2026, 11, 20, 9))]), isEmpty);
      final many = [for (var i = 0; i < 80; i++) appt('x$i', DateTime(2026, 10, 14, 9).add(Duration(minutes: i * 5)))];
      expect(planReminders(appointments: many, userId: 'u1', now: now, lead: const Duration(minutes: 15)), hasLength(50));
    });

    test('the lead time shows in the title, and each reminder keeps its own id', () {
      final r = planReminders(
        appointments: [appt('a', DateTime(2026, 10, 14, 12)), appt('b', DateTime(2026, 10, 14, 14))],
        userId: 'u1',
        now: now,
        lead: const Duration(hours: 2),
      );
      expect(r.first.title, 'Termin in 2 Stunden');
      expect(r.first.id, isNot(r.last.id));
      expect(r.first.id, appt('a', DateTime(2026, 10, 14, 12)).id.hashCode & 0x7fffffff);
    });
  });

  group('on the phone', () {
    FakeAuthRepository owner() => FakeAuthRepository(
          userId: 'u1',
          profile: const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: 'owner'),
        );
    final base = DateTime.now().add(const Duration(days: 1));
    final tomorrow9 = DateTime(base.year, base.month, base.day, 9);

    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Terminerinnerungen'), 200, scrollable: find.byType(Scrollable).first);
    }

    testApp('off by default: nothing is planned, and no permission is asked', (tester) async {
      final reminders = FakeReminderScheduler();
      await pumpApp(tester, owner(),
          remote: remoteWithJob()..seed(SyncEntity.appointment, remoteAppointment('a1', start: tomorrow9)), reminders: reminders);
      expect(reminders.planned, isEmpty);
      expect(reminders.permissionRequests, 0);
    });

    testApp('switching on asks for permission, then plans my appointments; the lead time can be changed', (tester) async {
      final reminders = FakeReminderScheduler();
      final store = FakeReminderPrefsStore();
      await pumpApp(tester, owner(),
          remote: remoteWithJob()
            ..seed(SyncEntity.appointment, remoteAppointment('a1', title: 'Meiner', start: tomorrow9))
            ..seed(SyncEntity.appointment, remoteAppointment('a2', title: 'Fremder', start: tomorrow9, assignees: ['u2'])),
          reminders: reminders,
          reminderPrefs: store);
      await openSettings(tester);
      await tester.tap(find.text('Terminerinnerungen'));
      await tester.pumpAndSettle();

      expect(reminders.permissionRequests, 1);
      expect(store.prefs.enabled, isTrue);
      expect(reminders.planned.map((r) => r.body), ['09:00 · Meiner']);
      expect(reminders.planned.single.at, tomorrow9.subtract(const Duration(minutes: 30)));

      await tester.tap(find.text('30 Minuten vorher'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 Stunde vorher').last);
      await tester.pumpAndSettle();
      expect(store.prefs.leadMinutes, 60);
      expect(reminders.planned.single.at, tomorrow9.subtract(const Duration(hours: 1)));
    });

    testApp('without the permission of the phone it stays off and says why', (tester) async {
      final reminders = FakeReminderScheduler()..allow = false;
      final store = FakeReminderPrefsStore();
      await pumpApp(tester, owner(), remote: remoteWithJob(), reminders: reminders, reminderPrefs: store);
      await openSettings(tester);
      await tester.tap(find.text('Terminerinnerungen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Erlaubnis für Benachrichtigungen fehlt'), findsOneWidget);
      expect(store.prefs.enabled, isFalse);
    });

    testApp('a new appointment is planned at once; switching off cancels everything', (tester) async {
      final reminders = FakeReminderScheduler();
      final store = FakeReminderPrefsStore(const ReminderPrefs(enabled: true, leadMinutes: 30));
      final app = await pumpApp(tester, owner(), remote: remoteWithJob(), reminders: reminders, reminderPrefs: store);
      expect(reminders.planned, isEmpty);

      app.remote.seed(SyncEntity.appointment, remoteAppointment('n1', title: 'Neu', start: tomorrow9));
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pumpAndSettle();
      expect(reminders.planned.map((r) => r.body), ['09:00 · Neu']);

      await openSettings(tester);
      await tester.tap(find.text('Terminerinnerungen'));
      await tester.pumpAndSettle();
      expect(store.prefs.enabled, isFalse);
      expect(reminders.planned, isEmpty);
    });
  });
}

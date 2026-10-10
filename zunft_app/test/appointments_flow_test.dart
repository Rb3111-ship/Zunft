import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/core/sync/sync_engine.dart';
import 'package:zunft_app/core/sync/sync_mapping.dart';
import 'package:zunft_app/features/appointments/data/appointments_remote.dart';
import 'package:zunft_app/features/appointments/domain/appointment_models.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/data/data_repository.dart';
import 'package:zunft_app/features/team/domain/team_models.dart';

import 'helpers/fake_appointments.dart';
import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/fake_team.dart';
import 'helpers/job_app.dart';
import 'helpers/test_app.dart';

final _now = DateTime.now();
DateTime at(int hour, [int minute = 0, int addDays = 0]) =>
    DateTime(_now.year, _now.month, _now.day + addDays, hour, minute);

FakeAuthRepository owner() => FakeAuthRepository(
      userId: 'u1',
      profile: const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: 'owner'),
      business: FakeAuthRepository.completeBusiness(),
    );

FakeAuthRepository geselle({Business? business}) => FakeAuthRepository(
      userId: 'u2',
      profile: const UserProfile(id: 'u2', businessId: 'b1', fullName: 'Hans', role: 'geselle'),
      business: business ?? FakeAuthRepository.completeBusiness(),
    );

FakeTeamRemote team() => FakeTeamRemote(members: const [
      TeamMember(id: 'u1', fullName: 'Erika', role: Roles.owner, active: true),
      TeamMember(id: 'u2', fullName: 'Hans', role: Roles.geselle, active: true),
    ]);

FakeSyncRemote remoteWith(List<Map<String, dynamic>> appointments) {
  final r = remoteWithJob();
  for (final a in appointments) {
    r.seed(SyncEntity.appointment, a);
  }
  return r;
}

Future<void> openCalendar(WidgetTester tester) async {
  await tester.tap(find.text('Termine'));
  await tester.pumpAndSettle();
}

Future<List<Appointment>> localAppointments(WidgetTester tester, TestApp app) async =>
    (await tester.runAsync(() => app.db.select(app.db.appointments).get()))!;

void main() {
  group('the calendar tab', () {
    testApp('shows today with the time, the title, the customer and the place', (tester) async {
      await pumpApp(
        tester,
        owner(),
        remote: remoteWith([
          remoteAppointment('a1',
              title: 'Steckdose Keller', start: at(10), end: at(11, 30), customerId: 'c1', location: 'Elbchaussee 118'),
        ]),
        team: team(),
      );
      await openCalendar(tester);
      expect(find.text('10:00 - 11:30'), findsOneWidget);
      expect(find.text('Steckdose Keller'), findsOneWidget);
      expect(find.text('Thomas Müller · Elbchaussee 118'), findsOneWidget);
      expect(find.text('Erika'), findsWidgets); // who goes
    });

    testApp('another day is empty and says so; Heute brings today back; the week lists every day', (tester) async {
      await pumpApp(tester, owner(), remote: remoteWith([remoteAppointment('a1', title: 'Heute-Termin', start: at(10))]), team: team());
      await openCalendar(tester);

      await tester.tap(find.byTooltip('Nächster Tag'));
      await tester.pumpAndSettle();
      expect(find.text('Heute-Termin'), findsNothing);
      expect(find.text('Keine Termine an diesem Tag.'), findsOneWidget);

      await tester.tap(find.text('Heute'));
      await tester.pumpAndSettle();
      expect(find.text('Heute-Termin'), findsOneWidget);

      await tester.tap(find.text('Woche'));
      await tester.pumpAndSettle();
      expect(find.text('Heute-Termin'), findsOneWidget);
      expect(find.textContaining('HEUTE'), findsOneWidget);
      expect(find.text('–'), findsWidgets); // the free days
    });

    testApp('the boss can look at one person only', (tester) async {
      await pumpApp(
        tester,
        owner(),
        remote: remoteWith([
          remoteAppointment('a1', title: 'Chef-Termin', start: at(9), assignees: ['u1']),
          remoteAppointment('a2', title: 'Hans-Termin', start: at(13), assignees: ['u2']),
        ]),
        team: team(),
      );
      await openCalendar(tester);
      expect(find.text('Chef-Termin'), findsOneWidget);
      expect(find.text('Hans-Termin'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Hans'));
      await tester.pumpAndSettle();
      expect(find.text('Chef-Termin'), findsNothing);
      expect(find.text('Hans-Termin'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Ich'));
      await tester.pumpAndSettle();
      expect(find.text('Chef-Termin'), findsOneWidget);
      expect(find.text('Hans-Termin'), findsNothing);
    });

    testApp('a solo craftsman sees no person filter', (tester) async {
      await pumpApp(tester, owner(), remote: remoteWith([]));
      await openCalendar(tester);
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testApp('an all-day absence is labelled ganztägig, a cancelled appointment is struck through', (tester) async {
      await pumpApp(
        tester,
        owner(),
        remote: remoteWith([
          remoteAppointment('h', title: 'Urlaub', kind: 'absence', start: at(0), end: at(0, 0, 1)),
          remoteAppointment('c', title: 'Abgesagt', start: at(14), status: 'canceled'),
        ]),
        team: team(),
      );
      await openCalendar(tester);
      expect(find.text('ganztägig'), findsOneWidget);
      final cancelled = tester.widget<Text>(find.text('Abgesagt'));
      expect(cancelled.style?.decoration, TextDecoration.lineThrough);
    });
  });

  group('creating, changing and deleting', () {
    testApp('a new appointment is saved here, shown at once, and synced with the people on it', (tester) async {
      final app = await pumpApp(tester, owner(), remote: remoteWith([]), team: team());
      await openCalendar(tester);
      await tester.tap(find.text('Neuer Termin'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Titel'), 'Zählerschrank prüfen');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      expect(find.text('Zählerschrank prüfen'), findsOneWidget);
      expect(find.text('08:00 - 09:00'), findsOneWidget);
      final local = await localAppointments(tester, app);
      expect(local.single.assignees, ['u1']);
      await tester.pump(const Duration(seconds: 2));
      final onServer = app.remote.tables[SyncEntity.appointment]!.values.single;
      expect(onServer['title'], 'Zählerschrank prüfen');
      expect(onServer['assignee_ids'], ['u1']);
      expect(onServer['kind'], 'job');
    });

    testApp('a title is required', (tester) async {
      final app = await pumpApp(tester, owner(), remote: remoteWith([]));
      await openCalendar(tester);
      await tester.tap(find.text('Neuer Termin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Titel darf nicht leer sein'), findsOneWidget);
      expect(await localAppointments(tester, app), isEmpty);
    });

    testApp('the boss chooses who goes; an appointment for two people has both', (tester) async {
      final app = await pumpApp(tester, owner(), remote: remoteWith([]), team: team());
      await openCalendar(tester);
      await tester.tap(find.text('Neuer Termin'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Titel'), 'Zu zweit');
      await tester.scrollUntilVisible(find.text('Hans'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Hans'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Speichern'), -200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect((await localAppointments(tester, app)).single.assignees, ['u1', 'u2']);
    });

    testApp('a person who is already busy: the boss is asked; Zurück saves nothing, Trotzdem speichern saves', (tester) async {
      final app = await pumpApp(
        tester,
        owner(),
        remote: remoteWith([remoteAppointment('a1', title: 'Schon belegt', start: at(8), end: at(9, 30))]),
        team: team(),
      );
      await openCalendar(tester);
      await tester.tap(find.text('Neuer Termin'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Titel'), 'Kollision');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Doppelt eingeplant?'), findsOneWidget);
      expect(find.textContaining('Schon belegt'), findsWidgets);
      await tester.tap(find.text('Zurück'));
      await tester.pumpAndSettle();
      expect(await localAppointments(tester, app), hasLength(1));

      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trotzdem speichern'));
      await tester.pumpAndSettle();
      expect(await localAppointments(tester, app), hasLength(2));
    });

    testApp('an all-day absence runs from midnight to midnight and is saved as an absence', (tester) async {
      final app = await pumpApp(tester, owner(), remote: remoteWith([]));
      await openCalendar(tester);
      await tester.tap(find.text('Neuer Termin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abwesenheit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Grund (z. B. Urlaub, krank)'), 'Urlaub');
      await tester.tap(find.widgetWithText(SwitchListTile, 'Ganztägig'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      final a = (await localAppointments(tester, app)).single;
      expect(a.kind, 'absence');
      expect(a.start, at(0));
      expect(a.end, at(0, 0, 1));
      expect(find.text('ganztägig'), findsOneWidget);
    });

    testApp('changing an appointment saves the change and keeps who created it', (tester) async {
      final app = await pumpApp(
        tester,
        owner(),
        remote: remoteWith([remoteAppointment('a1', title: 'Alt', start: at(10), createdBy: 'u1')]),
        team: team(),
      );
      await openCalendar(tester);
      await tester.tap(find.text('Alt'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bearbeiten'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Titel'), 'Neu');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      final a = (await localAppointments(tester, app)).single;
      expect(a.title, 'Neu');
      expect(a.createdBy, 'u1');
      expect(a.start, at(10));
    });

    testApp('deleting asks first and removes it here and on the server', (tester) async {
      final app = await pumpApp(tester, owner(), remote: remoteWith([remoteAppointment('a1', title: 'Weg damit', start: at(10))]), team: team());
      await openCalendar(tester);
      await tester.tap(find.text('Weg damit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bearbeiten'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(await localAppointments(tester, app), hasLength(1));

      await tester.tap(find.byTooltip('Löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Löschen'));
      await tester.pumpAndSettle();
      expect(find.text('Weg damit'), findsNothing);
      expect(await localAppointments(tester, app), isEmpty);
      await tester.pump(const Duration(seconds: 2));
      expect(app.remote.tables[SyncEntity.appointment], isEmpty);
    });

    testApp('from a job: the job, the customer and the address are filled in; the job lists its appointments',
        (tester) async {
      final app = await pumpApp(tester, owner(), remote: remoteWith([]), team: team());
      await openJob(tester);
      await tester.scrollUntilVisible(find.text('Termin anlegen'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Termin anlegen'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Titel')).controller!.text, 'Steckdose Keller');
      expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Ort / Adresse')).controller!.text,
          'Elbchaussee 118, 22763 Hamburg');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      final a = (await localAppointments(tester, app)).single;
      expect(a.jobId, 'j1');
      expect(a.customerId, 'c1');
      // back on the job screen the appointment is listed
      expect(find.text('TERMINE'), findsOneWidget);
      expect(find.text('08:00 - 09:00'), findsOneWidget);
    });
  });

  group('the appointment screen', () {
    testApp('calling, the route, the calendar file and the confirmation text go to the other apps', (tester) async {
      final actions = FakeExternalActions();
      final remote = remoteWith([
        remoteAppointment('a1',
            title: 'Steckdose Keller', start: at(10), customerId: 'c1', location: 'Elbchaussee 118, 22763 Hamburg', notes: 'Hund im Haus'),
      ]);
      remote.tables[SyncEntity.customer]!['c1']!['phone'] = '040 123 456';
      await pumpApp(tester, owner(), remote: remote, team: team(), actions: actions);
      await openCalendar(tester);
      await tester.tap(find.text('Steckdose Keller'));
      await tester.pumpAndSettle();
      expect(find.text('Hund im Haus'), findsOneWidget);

      await tester.tap(find.byTooltip('Anrufen'));
      await tester.pumpAndSettle();
      expect(actions.opened.last.toString(), 'tel:040123456');

      await tester.tap(find.byTooltip('Route'));
      await tester.pumpAndSettle();
      expect(actions.opened.last.host, 'www.google.com');
      expect(actions.opened.last.queryParameters['query'], 'Elbchaussee 118, 22763 Hamburg');

      await tester.scrollUntilVisible(find.text('In Kalender übernehmen'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('In Kalender übernehmen'));
      await tester.pumpAndSettle();
      expect(actions.calendarFiles.single.name, 'Termin-Steckdose-Keller.ics');
      expect(String.fromCharCodes(actions.calendarFiles.single.bytes), contains('BEGIN:VEVENT'));

      await tester.tap(find.text('Termin dem Kunden bestätigen'));
      await tester.pumpAndSettle();
      expect(actions.texts.single.text, startsWith('Sehr geehrter Herr Müller,'));
      expect(actions.texts.single.text, contains('Uhr (Elbchaussee 118, 22763 Hamburg)'));
    });

    testApp('when the phone cannot open the dialer the user is told', (tester) async {
      final actions = FakeExternalActions()..canOpen = false;
      final remote = remoteWith([remoteAppointment('a1', start: at(10), customerId: 'c1')]);
      remote.tables[SyncEntity.customer]!['c1']!['phone'] = '040 1';
      await pumpApp(tester, owner(), remote: remote, team: team(), actions: actions);
      await openCalendar(tester);
      await tester.tap(find.text('Steckdose Keller'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Anrufen'));
      await tester.pumpAndSettle();
      expect(find.text('Der Anruf konnte nicht gestartet werden.'), findsOneWidget);
    });

    testApp('the boss marks it done, cancels it and plans it again; each change is synced', (tester) async {
      final app = await pumpApp(tester, owner(), remote: remoteWith([remoteAppointment('a1', title: 'Termin', start: at(10))]), team: team());
      await openCalendar(tester);
      await tester.tap(find.text('Termin'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Als erledigt markieren'));
      await tester.pumpAndSettle();
      expect(find.text('Erledigt'), findsOneWidget);
      expect((await localAppointments(tester, app)).single.status, 'done');
      await tester.pump(const Duration(seconds: 2));
      expect(app.remote.tables[SyncEntity.appointment]!['a1']!['status'], 'done');

      await tester.tap(find.text('Wieder öffnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Absagen'));
      await tester.pumpAndSettle();
      expect(find.text('Abgesagt'), findsOneWidget);
      expect(find.text('Als erledigt markieren'), findsNothing); // nothing to finish on a cancelled one
      await tester.tap(find.text('Wieder planen'));
      await tester.pumpAndSettle();
      expect((await localAppointments(tester, app)).single.status, 'planned');
    });

    testApp('the job of the appointment opens from it', (tester) async {
      await pumpApp(tester, owner(), remote: remoteWith([remoteAppointment('a1', title: 'Termin', start: at(10), jobId: 'j1')]), team: team());
      await openCalendar(tester);
      await tester.tap(find.text('Termin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();
      expect(find.text('Notiz zu diesem Auftrag aufnehmen'), findsOneWidget);
    });
  });

  group('an employee', () {
    testApp('sees their appointments but cannot plan or edit (switch off)', (tester) async {
      await pumpApp(tester, geselle(), remote: remoteWith([remoteAppointment('a1', title: 'Mein Termin', start: at(10), assignees: ['u2'])]), team: team());
      await openCalendar(tester);
      expect(find.text('Mein Termin'), findsOneWidget);
      expect(find.text('Neuer Termin'), findsNothing);
      await tester.tap(find.text('Mein Termin'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Bearbeiten'), findsNothing);
      expect(find.text('Absagen'), findsNothing);
    });

    testApp('may plan their own when the owner allowed creating (and only for themselves)', (tester) async {
      final business = Business.fromJson({...FakeAuthRepository.completeBusiness().toUpdateJson(), 'id': 'b1', 'employees_can_create': true});
      final app = await pumpApp(tester, geselle(business: business), remote: remoteWith([]), team: team());
      await openCalendar(tester);
      await tester.tap(find.text('Neuer Termin'));
      await tester.pumpAndSettle();
      expect(find.text('WER?'), findsNothing); // no choice of other people
      await tester.enterText(find.widgetWithText(TextFormField, 'Titel'), 'Eigener Termin');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect((await localAppointments(tester, app)).single.assignees, ['u2']);
    });

    testApp('marks it done through the server; the local copy follows and nothing is queued', (tester) async {
      final server = FakeAppointmentsRemote();
      final app = await pumpApp(
        tester,
        geselle(),
        remote: remoteWith([remoteAppointment('a1', title: 'Mein Termin', start: at(10), assignees: ['u2'])]),
        team: team(),
        appointmentsRemote: server,
      );
      await openCalendar(tester);
      await tester.tap(find.text('Mein Termin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Als erledigt markieren'));
      await tester.pumpAndSettle();

      expect(server.calls.single, (id: 'a1', status: 'done'));
      expect((await localAppointments(tester, app)).single.status, 'done');
      expect(await tester.runAsync(() => app.db.pendingOutbox()), isEmpty);
      expect(find.text('Erledigt'), findsOneWidget);
    });

    testApp('offline: told so, and nothing changes', (tester) async {
      final server = FakeAppointmentsRemote()..error = const AppointmentException('Keine Verbindung. Zum Abhaken wird Internet gebraucht.');
      final app = await pumpApp(
        tester,
        geselle(),
        remote: remoteWith([remoteAppointment('a1', title: 'Mein Termin', start: at(10), assignees: ['u2'])]),
        team: team(),
        appointmentsRemote: server,
      );
      await openCalendar(tester);
      await tester.tap(find.text('Mein Termin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Als erledigt markieren'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Internet gebraucht'), findsOneWidget);
      expect((await localAppointments(tester, app)).single.status, 'planned');
    });

    testApp('an appointment taken away on the server disappears from the phone', (tester) async {
      final app = await pumpApp(tester, geselle(), remote: remoteWith([remoteAppointment('a1', title: 'Verschwindet', start: at(10), assignees: ['u2'])]), team: team());
      await openCalendar(tester);
      expect(find.text('Verschwindet'), findsOneWidget);
      app.remote.tables[SyncEntity.appointment]!.remove('a1'); // the boss gave it to someone else
      // the app comes back to the front: it fetches what changed meanwhile
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pumpAndSettle();
      expect(find.text('Verschwindet'), findsNothing);
    });
  });

  group('behind the screens', () {
    late AppDatabase db;
    late DataRepository repo;
    var ids = 0;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      ids = 0;
      repo = DataRepository(db, businessId: 'b1', onChanged: () {}, newId: () => 'id-${++ids}');
    });
    tearDown(() => db.close());

    test('a title, a later end, at most 31 days, a known job: each is checked', () async {
      final s = DateTime(2026, 10, 14, 8);
      await expectLater(repo.saveAppointment(title: '  ', start: s, end: s.add(const Duration(hours: 1))), throwsA(isA<ValidationFailure>()));
      await expectLater(repo.saveAppointment(title: 'x', start: s, end: s), throwsA(isA<ValidationFailure>()));
      await expectLater(repo.saveAppointment(title: 'x', start: s, end: s.add(const Duration(days: 32))), throwsA(isA<ValidationFailure>()));
      await expectLater(repo.saveAppointment(title: 'x', start: s, end: s.add(const Duration(hours: 1)), jobId: 'gone'), throwsA(isA<ValidationFailure>()));
      await expectLater(repo.saveAppointment(title: 'x', kind: 'party', start: s, end: s.add(const Duration(hours: 1))), throwsA(isA<ValidationFailure>()));
      expect(await db.select(db.appointments).get(), isEmpty);
    });

    test('times are stored in UTC and come back as the same moment; a change is queued for the server', () async {
      final s = DateTime(2026, 10, 14, 8);
      final id = await repo.saveAppointment(title: 'Test', start: s, end: s.add(const Duration(hours: 2)), assignees: {'u2', 'u1'});
      final a = (await db.appointmentById(id))!;
      expect(a.start, s);
      expect(a.assignees, ['u1', 'u2']);
      expect((await db.pendingOutbox()).single.entity, 'appointment');
    });

    test('deleting the job or the customer keeps the appointment, without the link', () async {
      final c = await repo.saveCustomer(name: 'Müller');
      final j = await repo.saveJob(title: 'Job', customerId: c);
      final s = DateTime(2026, 10, 14, 8);
      final a = await repo.saveAppointment(title: 'T', start: s, end: s.add(const Duration(hours: 1)), jobId: j, customerId: c);
      await repo.deleteJob(j);
      expect((await db.appointmentById(a))!.jobId, isNull);
      expect((await db.appointmentById(a))!.customerId, c);
      await repo.deleteCustomer(c);
      expect((await db.appointmentById(a))!.customerId, isNull);
    });

    test('merging two customers moves their appointments too', () async {
      final keep = await repo.saveCustomer(name: 'Müller', firstName: 'Thomas');
      final gone = await repo.saveCustomer(name: 'Mueller', firstName: 'Thomas');
      final s = DateTime(2026, 10, 14, 8);
      final a = await repo.saveAppointment(title: 'T', start: s, end: s.add(const Duration(hours: 1)), customerId: gone);
      await repo.mergeCustomers(keepId: keep, removeId: gone);
      expect((await db.appointmentById(a))!.customerId, keep);
    });

    test('sync pushes customer, then job, then appointment; deletes go the other way round', () async {
      final remote = FakeSyncRemote();
      final c = await repo.saveCustomer(name: 'Müller');
      final j = await repo.saveJob(title: 'Job', customerId: c);
      final s = DateTime(2026, 10, 14, 8);
      // the appointment was created FIRST in time order of ids on purpose: ranks decide, not ids
      final a = await repo.saveAppointment(title: 'T', start: s, end: s.add(const Duration(hours: 1)), jobId: j, customerId: c);
      final result = await SyncEngine(db, remote).run();
      expect(result.ok, isTrue);
      expect(remote.log.where((l) => l.startsWith('upsert')).toList(), ['upsert customer $c', 'upsert job $j', 'upsert appointment $a']);
      expect(remote.tables[SyncEntity.appointment]![a]!['assignee_ids'], isEmpty);

      remote.log.clear();
      await repo.deleteAppointment(a);
      await repo.deleteJob(j);
      await repo.deleteCustomer(c);
      await SyncEngine(db, remote).run();
      expect(remote.log.where((l) => l.startsWith('delete')).toList(), ['delete appointment $a', 'delete job $j', 'delete customer $c']);
    });

    test('the server row of an appointment becomes a local row and back (people as a list)', () async {
      final remote = remoteAppointment('r1', start: DateTime(2026, 10, 14, 8), assignees: ['u1', 'u2'], notes: 'n');
      final row = {...remote, 'updated_at': '2026-10-11T08:00:00Z'};
      await db.applyRemoteAppointments([appointmentFromRemote(row)]);
      final a = (await db.appointmentById('r1'))!;
      expect(a.assignees, ['u1', 'u2']);
      expect(a.start, DateTime(2026, 10, 14, 8));
    });
  });
}

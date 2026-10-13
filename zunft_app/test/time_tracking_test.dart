import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/features/time_tracking/domain/time_billing.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/core/sync/sync_engine.dart';
import 'package:zunft_app/core/sync/sync_mapping.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/data/data_repository.dart';
import 'package:zunft_app/features/jobs/domain/job_notes.dart';
import 'package:zunft_app/features/team/domain/team_models.dart';
import 'package:zunft_app/features/time_tracking/domain/time_export.dart';
import 'package:zunft_app/features/time_tracking/domain/time_models.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_job_notes.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/fake_team.dart';
import 'helpers/job_app.dart';
import 'helpers/test_app.dart';

final _now = DateTime.now();
DateTime at(int hour, [int minute = 0, int addDays = 0]) =>
    DateTime(_now.year, _now.month, _now.day + addDays, hour, minute);

TimeEntry entry(String id, DateTime start, DateTime? end,
        {int breakMinutes = 0, String? user = 'u1', String? name = 'Erika', String? job = 'j1', String? doc}) =>
    TimeEntry(
      id: id,
      businessId: 'b1',
      userId: user,
      userName: name,
      jobId: job,
      startedAt: start.toUtc(),
      endedAt: end?.toUtc(),
      breakMinutes: breakMinutes,
      documentId: doc,
      updatedAt: DateTime(2026),
    );

FakeAuthRepository owner() => FakeAuthRepository(
      userId: 'u1',
      profile: const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: 'owner'),
      business: FakeAuthRepository.completeBusiness(),
    );

FakeAuthRepository geselle() => FakeAuthRepository(
      userId: 'u2',
      profile: const UserProfile(id: 'u2', businessId: 'b1', fullName: 'Hans', role: 'geselle'),
      business: FakeAuthRepository.completeBusiness(),
    );

FakeTeamRemote team() => FakeTeamRemote(members: const [
      TeamMember(id: 'u1', fullName: 'Erika', role: Roles.owner, active: true),
      TeamMember(id: 'u2', fullName: 'Hans', role: Roles.geselle, active: true),
    ]);

FakeSyncRemote remoteWith(List<Map<String, dynamic>> entries, {List<Map<String, dynamic>> extraJobs = const []}) {
  final r = remoteWithJob();
  for (final j in extraJobs) {
    r.seed(SyncEntity.job, j);
  }
  for (final e in entries) {
    r.seed(SyncEntity.timeEntry, e);
  }
  return r;
}

Future<List<TimeEntry>> localEntries(WidgetTester tester, TestApp app) async =>
    (await tester.runAsync(() => app.db.select(app.db.timeEntries).get()))!;

void main() {
  group('how long was worked', () {
    final nine = DateTime(2026, 10, 14, 9);

    test('start to end minus the break; a running timer counts up to now; never negative', () {
      expect(entry('a', nine, nine.add(const Duration(hours: 8)), breakMinutes: 30).worked(nine).inMinutes, 450);
      expect(entry('b', nine, null).worked(nine.add(const Duration(minutes: 95))).inMinutes, 95);
      expect(entry('c', nine, nine.add(const Duration(minutes: 20)), breakMinutes: 60).worked(nine), Duration.zero);
    });

    test('labels: 7:45 for people, 7,75 for the invoice, 01:02:03 for a running timer', () {
      expect(clockLabel(const Duration(minutes: 465)), '7:45');
      expect(clockLabel(const Duration(minutes: 5)), '0:05');
      expect(decimalHours(465), 7.75);
      expect(decimalHours(100), 1.67); // rounded to hundredths
      expect(hoursText(465), '7,75');
      expect(elapsedLabel(const Duration(hours: 1, minutes: 2, seconds: 3)), '01:02:03');
    });

    test('only finished, not yet billed entries of the job are billable, oldest first', () {
      final all = [
        entry('late', DateTime(2026, 10, 15, 8), DateTime(2026, 10, 15, 9)),
        entry('early', DateTime(2026, 10, 14, 8), DateTime(2026, 10, 14, 9)),
        entry('running', DateTime(2026, 10, 16, 8), null),
        entry('billed', DateTime(2026, 10, 13, 8), DateTime(2026, 10, 13, 9), doc: 'd1'),
        entry('other job', DateTime(2026, 10, 14, 8), DateTime(2026, 10, 14, 9), job: 'j2'),
      ];
      expect(billableEntries(all, 'j1').map((t) => t.id), ['early', 'late']);
    });

    test('minutes per person, most first; a person without a name is "Mitarbeiter"', () {
      final all = [
        entry('1', nine, nine.add(const Duration(hours: 2))),
        entry('2', nine, nine.add(const Duration(hours: 3)), user: 'u2', name: 'Hans'),
        entry('3', nine, nine.add(const Duration(hours: 1)), name: 'Erika'),
        entry('4', nine, nine.add(const Duration(minutes: 30)), user: null, name: null),
      ];
      expect(minutesByPerson(all, nine), {'Hans': 180, 'Erika': 180, 'Mitarbeiter': 30});
    });
  });

  group('hourly rates per person', () {
    final d = DateTime(2026, 10, 14);
    final t = [
      entry('a', DateTime(2026, 10, 14, 8), DateTime(2026, 10, 14, 10), user: 'm'),
      entry('b', DateTime(2026, 10, 14, 8), DateTime(2026, 10, 14, 12), user: 'g'),
      entry('c', DateTime(2026, 10, 15, 8), DateTime(2026, 10, 15, 9), user: 'g'),
    ];

    test('without own rates everything is one position at the business rate', () {
      final l = timeBillingLines(entries: t, rates: const {}, roles: const {}, defaultRateCents: 6000, now: d);
      expect(l.length, 1);
      expect(l.single.minutes, 420);
      expect(l.single.rateCents, 6000);
      expect(l.single.description, 'Arbeitszeit (Zeiterfassung)');
    });

    test('two rates: one position each, named after the role, highest rate first', () {
      final l = timeBillingLines(
          entries: t, rates: const {'m': 9000}, roles: const {'m': 'owner', 'g': 'employee'}, defaultRateCents: 6000, now: d);
      expect(l.map((x) => (x.minutes, x.rateCents)), [(120, 9000), (300, 6000)]);
      expect(l.first.description, contains(Roles.label('owner')));
      expect(l.last.description, contains(Roles.label('employee')));
    });

    test('same role at two rates: the rate tells the positions apart', () {
      final l = timeBillingLines(
          entries: t, rates: const {'m': 9000}, roles: const {'m': 'employee', 'g': 'employee'}, defaultRateCents: 6000, now: d);
      expect(l.first.description, isNot(l.last.description));
      expect(l.first.description, contains('90,00'));
    });

    test('a rate equal to the default does not split the position', () {
      final l = timeBillingLines(entries: t, rates: const {'m': 6000}, roles: const {}, defaultRateCents: 6000, now: d);
      expect(l.length, 1);
    });

    test('the draft gets one flagged position per line', () {
      final job = Job(id: 'j1', businessId: 'b1', title: 'X', status: 'in_progress', updatedAt: DateTime(2026));
      final lines = timeBillingLines(entries: t, rates: const {'m': 9000}, roles: const {}, defaultRateCents: 6000, now: d);
      final dr = buildJobDraft(job: job, notes: const [], timeLines: lines);
      expect(dr.lineItems.length, 2);
      expect(dr.lineItems.every((i) => i.requiresConfirmation && i.type == 'labor'), isTrue);
      expect(dr.lineItems.first.unitPriceNetCents, 9000);
      expect(dr.lineItems.first.quantity, 2);
    });
  });

  group('the invoice suggestion', () {
    final job = Job(id: 'j1', businessId: 'b1', title: 'Steckdose Keller', status: 'in_progress', updatedAt: DateTime(2026));
    final note = FakeJobNotesRemote.note(id: 'n1'); // 2 Std Arbeit à 68 € + 1 Doppelsteckdose

    test('without tracked time nothing changes', () {
      final d = buildJobDraft(job: job, notes: [note]);
      expect(d.lineItems.map((i) => i.type), ['labor', 'material']);
    });

    test('added: one position for all tracked time, flagged for a price check, notes untouched', () {
      final d = buildJobDraft(job: job, notes: [note], timeLines: const [TimeBillingLine(description: 'Arbeitszeit (Zeiterfassung)', minutes: 465, rateCents: 7000)]);
      final time = d.lineItems.last;
      expect(d.lineItems.length, 3);
      expect(time.description, 'Arbeitszeit (Zeiterfassung)');
      expect(time.quantity, 7.75);
      expect(time.unit, 'Std');
      expect(time.unitPriceNetCents, 7000);
      expect(time.requiresConfirmation, isTrue);
      expect(d.warnings.any((w) => w.contains('7:45 Std') && w.contains('Stundensatz')), isTrue);
    });

    test('replacing: the spoken working time is removed so it is not billed twice; material stays', () {
      final d = buildJobDraft(job: job, notes: [note], timeLines: const [TimeBillingLine(description: 'Arbeitszeit (Zeiterfassung)', minutes: 120, rateCents: 6800)], replaceNoteLabor: true);
      expect(d.lineItems.map((i) => '${i.type}:${i.description}'), ['material:Doppelsteckdose', 'labor:Arbeitszeit (Zeiterfassung)']);
      expect(d.warnings.any((w) => w.contains('2 Std') && w.contains('ersetzt')), isTrue);
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

    test('starting a timer opens an entry without an end; starting another stops the first', () async {
      final j1 = await repo.saveJob(title: 'Eins');
      final j2 = await repo.saveJob(title: 'Zwei');
      final a = await repo.startTimer(userId: 'u1', userName: 'Erika', jobId: j1);
      expect(a.stopped, isNull);
      expect((await db.timeEntryById(a.id))!.endedAt, isNull);

      final b = await repo.startTimer(userId: 'u1', userName: 'Erika', jobId: j2);
      expect(b.stopped!.id, a.id);
      expect((await db.timeEntryById(a.id))!.endedAt, isNotNull);
      expect((await db.runningTimerOf('u1'))!.id, b.id);
      expect(await db.runningTimerOf('u2'), isNull); // another person's timer is separate
    });

    test('stopping gives the entry an end; stopping again changes nothing', () async {
      final t = await repo.startTimer(userId: 'u1', userName: 'E');
      await repo.stopTimer(t.id);
      final end = (await db.timeEntryById(t.id))!.endedAt;
      expect(end, isNotNull);
      await repo.stopTimer(t.id);
      expect((await db.timeEntryById(t.id))!.endedAt, end);
    });

    test('a timer for a job that does not exist is refused', () async {
      await expectLater(repo.startTimer(userId: 'u1', userName: 'E', jobId: 'gone'), throwsA(isA<ValidationFailure>()));
      expect(await db.select(db.timeEntries).get(), isEmpty);
    });

    test('by hand: the end must follow the start, at most 24 h, the break shorter than the work, minutes sane', () async {
      final s = DateTime(2026, 10, 14, 8);
      Future<void> save({DateTime? end, int brk = 0}) =>
          repo.saveTimeEntry(userId: 'u1', userName: 'E', start: s, end: end, breakMinutes: brk);
      await expectLater(save(end: s), throwsA(isA<ValidationFailure>()));
      await expectLater(save(end: s.subtract(const Duration(hours: 1))), throwsA(isA<ValidationFailure>()));
      await expectLater(save(end: s.add(const Duration(hours: 25))), throwsA(isA<ValidationFailure>()));
      await expectLater(save(end: s.add(const Duration(hours: 1)), brk: 60), throwsA(isA<ValidationFailure>()));
      await expectLater(save(end: s.add(const Duration(hours: 9)), brk: -5), throwsA(isA<ValidationFailure>()));
      expect(await db.select(db.timeEntries).get(), isEmpty);
      await save(end: s.add(const Duration(hours: 8)), brk: 30);
      expect((await db.select(db.timeEntries).get()).single.breakMinutes, 30);
    });

    test('a billed entry cannot be changed or deleted here', () async {
      final id = await repo.saveTimeEntry(userId: 'u1', userName: 'E', start: DateTime(2026, 10, 14, 8), end: DateTime(2026, 10, 14, 9));
      // the server billed it (this is what the next sync brings)
      await (db.update(db.timeEntries)..where((t) => t.id.equals(id))).write(const TimeEntriesCompanion(documentId: Value('doc-1')));
      await expectLater(
          repo.saveTimeEntry(id: id, userId: 'u1', userName: 'E', start: DateTime(2026, 10, 14, 8), end: DateTime(2026, 10, 14, 10)),
          throwsA(isA<ValidationFailure>()));
      await expectLater(repo.deleteTimeEntry(id), throwsA(isA<ValidationFailure>()));
      expect(await db.timeEntryById(id), isNotNull);
    });

    test('sync: a time entry is pushed after its job, deleted before it; the server fills in billing', () async {
      final remote = FakeSyncRemote();
      final j = await repo.saveJob(title: 'Job');
      final t = await repo.saveTimeEntry(userId: 'u1', userName: 'E', jobId: j, start: DateTime(2026, 10, 14, 8), end: DateTime(2026, 10, 14, 9));
      expect((await SyncEngine(db, remote).run()).ok, isTrue);
      expect(remote.log.where((l) => l.startsWith('upsert')).toList(), ['upsert job $j', 'upsert timeEntry $t']);
      expect(remote.tables[SyncEntity.timeEntry]![t]!.containsKey('document_id'), isFalse); // never sent by the app

      remote.markTimeEntriesBilled([t], 'doc-9');
      await SyncEngine(db, remote).run();
      expect((await db.timeEntryById(t))!.documentId, 'doc-9');
      expect((await db.timeEntryById(t))!.isBilled, isTrue);

      remote.log.clear();
      final u = await repo.saveTimeEntry(userId: 'u1', userName: 'E', jobId: j, start: DateTime(2026, 10, 15, 8), end: DateTime(2026, 10, 15, 9));
      await SyncEngine(db, remote).run();
      remote.log.clear();
      await repo.deleteTimeEntry(u);
      await repo.deleteJob(j);
      await SyncEngine(db, remote).run();
      expect(remote.log.where((l) => l.startsWith('delete')).toList(), ['delete timeEntry $u', 'delete job $j']);
    });
  });

  group('timer on the phone', () {
    testApp('start on a job: the bar shows it everywhere; stop ends it and syncs it', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
      await openJob(tester);
      await tester.scrollUntilVisible(find.text('Zeit starten'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Zeit starten'));
      await tester.pumpAndSettle();

      expect(find.text('Zeit stoppen'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Stopp'), findsOneWidget); // still there on the job list
      expect(find.textContaining('00:00:0'), findsOneWidget);

      await tester.tap(find.text('Stopp'));
      await tester.pumpAndSettle();
      expect(find.text('Stopp'), findsNothing);
      final e = (await localEntries(tester, app)).single;
      expect(e.endedAt, isNotNull);
      expect(e.userId, 'u1');
      expect(e.jobId, 'j1');
      await tester.pump(const Duration(seconds: 2));
      expect(app.remote.tables[SyncEntity.timeEntry]!.values.single['job_id'], 'j1');
    });

    testApp('starting on another job stops the running one and says so', (tester) async {
      final app = await pumpApp(
        tester,
        owner(),
        remote: remoteWith([remoteTimeEntry('t1', start: at(8), end: null)], extraJobs: [remoteJob('j2', title: 'Zweiter Auftrag')]),
        team: team(),
      );
      expect(find.text('Stopp'), findsOneWidget);
      await tester.tap(find.text('Zweiter Auftrag'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Zeit starten'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Zeit starten'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Der laufende Timer für „Steckdose Keller“ wurde beendet'), findsOneWidget);
      final all = await localEntries(tester, app);
      expect(all.where((t) => t.endedAt == null).single.jobId, 'j2');
      expect(all.firstWhere((t) => t.id == 't1').endedAt, isNotNull);
    });

    testApp('a closed job cannot be timed', (tester) async {
      final remote = remoteWithJob();
      remote.tables[SyncEntity.job]!['j1']!['status'] = 'completed';
      await pumpApp(tester, owner(), remote: remote, team: team());
      await tester.tap(find.text('Erledigt (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Steckdose Keller'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Zeit nachtragen'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Zeit starten'), findsNothing);
    });

    testApp('a timer that runs for more than 12 hours is flagged as forgotten', (tester) async {
      await pumpApp(tester, owner(), remote: remoteWith([remoteTimeEntry('t1', start: DateTime.now().subtract(const Duration(hours: 13)), end: null)]), team: team());
      expect(find.textContaining('Vergessen zu stoppen'), findsOneWidget);
    });

    testApp('from an appointment: the timer starts for its job and remembers the appointment', (tester) async {
      final remote = remoteWithJob()
        ..seed(SyncEntity.appointment, remoteAppointment('a1', title: 'Termin Keller', start: at(10), jobId: 'j1'));
      final app = await pumpApp(tester, owner(), remote: remote, team: team());
      await tester.tap(find.text('Termine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Termin Keller'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Zeit starten'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Zeit starten'));
      await tester.pumpAndSettle();
      final e = (await localEntries(tester, app)).single;
      expect(e.jobId, 'j1');
      expect(e.appointmentId, 'a1');
    });
  });

  group('adding and correcting time', () {
    Future<void> openJobTime(WidgetTester tester) async {
      await openJob(tester);
      await tester.scrollUntilVisible(find.text('Zeit nachtragen'), 200, scrollable: find.byType(Scrollable).first);
    }

    testApp('by hand: 8:00 to 16:00 is the suggestion; a break is subtracted; it shows on the job', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
      await openJobTime(tester);
      await tester.tap(find.text('Zeit nachtragen'));
      await tester.pumpAndSettle();
      expect(find.text('Arbeitszeit: 8:00 Std (8,00)'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Pause (Minuten)'), '30');
      await tester.pumpAndSettle();
      expect(find.text('Arbeitszeit: 7:30 Std (7,50)'), findsOneWidget);
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      final e = (await localEntries(tester, app)).single;
      expect(e.breakMinutes, 30);
      expect(e.minutes(DateTime.now()), 450);
      expect(find.textContaining('7:30 Std'), findsWidgets);
      expect(find.textContaining('Noch nicht abgerechnet: 7:30 Std (7,50)'), findsOneWidget);
    });

    testApp('a break as long as the work is refused with an explanation', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
      await openJobTime(tester);
      await tester.tap(find.text('Zeit nachtragen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Pause (Minuten)'), '480');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Die Pause muss kürzer sein als die Arbeitszeit.'), findsOneWidget);
      expect(await localEntries(tester, app), isEmpty);
    });

    testApp('an entry can be corrected and deleted (asks first)', (tester) async {
      final app = await pumpApp(tester, owner(), remote: remoteWith([remoteTimeEntry('t1', start: at(8), end: at(12), note: 'Altbau')]), team: team());
      await openJobTime(tester);
      await tester.tap(find.textContaining('08:00 - 12:00'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Pause (Minuten)'), '45');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect((await localEntries(tester, app)).single.breakMinutes, 45);

      await tester.tap(find.textContaining('08:00 - 12:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(await localEntries(tester, app), hasLength(1));
      await tester.tap(find.byTooltip('Löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Löschen'));
      await tester.pumpAndSettle();
      expect(await localEntries(tester, app), isEmpty);
    });

    testApp('a billed entry is locked: marked, no way to edit it', (tester) async {
      await pumpApp(tester, owner(), remote: remoteWith([remoteTimeEntry('t1', start: at(8), end: at(12), documentId: 'doc-1')]), team: team());
      await openJobTime(tester);
      expect(find.textContaining('abgerechnet'), findsWidgets);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      await tester.tap(find.textContaining('08:00 - 12:00'));
      await tester.pumpAndSettle();
      expect(find.text('Zeit bearbeiten'), findsNothing); // nothing opened
    });

    testApp('time the boss added is marked for the worker: "vom Betrieb eingetragen"', (tester) async {
      // Hans sees an entry that Erika (u1) created for him
      await pumpApp(
        tester,
        geselle(),
        remote: remoteWith([remoteTimeEntry('t1', userId: 'u2', userName: 'Hans', createdBy: 'u1', start: at(8), end: at(12))]),
        team: team(),
      );
      await openJobTime(tester);
      expect(find.textContaining('vom Betrieb eingetragen'), findsOneWidget);
      await tester.tap(find.textContaining('08:00 - 12:00'));
      await tester.pumpAndSettle();
      expect(find.text('Diese Zeit wurde vom Betrieb eingetragen.'), findsOneWidget);
    });

    testApp('time a worker recorded themselves carries no such mark', (tester) async {
      await pumpApp(tester, geselle(), remote: remoteWith([remoteTimeEntry('t1', userId: 'u2', userName: 'Hans', start: at(8), end: at(12))]), team: team());
      await openJobTime(tester);
      expect(find.textContaining('vom Betrieb eingetragen'), findsNothing);
    });

    testApp('the boss can add time for a worker', (tester) async {
      final app = await pumpApp(tester, owner(), remote: remoteWith([]), team: team());
      await openJobTime(tester);
      await tester.tap(find.text('Zeit nachtragen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hans').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      final e = (await localEntries(tester, app)).single;
      expect(e.userId, 'u2');
      expect(e.userName, 'Hans');
      await tester.pump(const Duration(seconds: 2)); // synced: the server stamps who created it
      final synced = (await localEntries(tester, app)).single;
      expect(synced.createdBy, 'u1');
      expect(synced.enteredByOthers, isTrue);
    });
  });

  group('the weekly list', () {
    Future<void> openTimesheet(WidgetTester tester, String title) async {
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(title), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }

    testApp('the boss sees every person with their hours and the total of the week', (tester) async {
      await pumpApp(
        tester,
        owner(),
        remote: remoteWith([
          remoteTimeEntry('t1', start: at(8), end: at(12)),
          remoteTimeEntry('t2', userId: 'u2', userName: 'Hans', start: at(8), end: at(13)),
        ]),
        team: team(),
      );
      // the entries are "today": show them in the current week even on a Sunday
      await openTimesheet(tester, 'Arbeitszeiten');
      expect(find.textContaining('HANS'), findsOneWidget);
      expect(find.textContaining('ERIKA'), findsOneWidget);
      expect(find.text('Zusammen: 9:00 Std'), findsOneWidget);
      expect(find.textContaining('5:00 STD'), findsOneWidget);
      await tester.tap(find.byTooltip('Nächste Woche'));
      await tester.pumpAndSettle();
      expect(find.text('In dieser Woche ist keine Zeit erfasst.'), findsOneWidget);
    });

    testApp('a worker sees only "Meine Zeiten", their own', (tester) async {
      await pumpApp(tester, geselle(), remote: remoteWith([remoteTimeEntry('t2', userId: 'u2', userName: 'Hans', start: at(8), end: at(13))]), team: team());
      await openTimesheet(tester, 'Meine Zeiten');
      expect(find.text('Zusammen: 5:00 Std'), findsOneWidget);
      expect(find.text('Arbeitszeiten'), findsNothing);
    });
  });

  group('the times as a file', () {
    final nine = DateTime(2026, 10, 14, 9);

    test('one line per entry with the working time as 7:45 and 7,75, and the total of each person', () {
      final bytes = timesheetCsv(
        entries: [
          entry('a', nine, nine.add(const Duration(hours: 8, minutes: 15)), breakMinutes: 30),
          entry('b', nine, nine.add(const Duration(hours: 2)), user: 'u2', name: 'Hans', doc: 'd1'),
          entry('c', nine, null, name: 'Erika'),
        ].map((t) => t).toList(),
        jobTitle: (id) => id == 'j1' ? 'Steckdose Keller' : 'Ohne Auftrag',
        now: nine.add(const Duration(minutes: 90)),
        periodLabel: 'Oktober 2026',
      );
      final text = utf8.decode(bytes);
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]); // opens correctly in Excel
      expect(text, contains('Zeitraum;Oktober 2026'));
      expect(text, contains('Datum;Mitarbeiter;Auftrag;Beginn;Ende;Pause (Min.);Arbeitszeit (Std:Min);Arbeitszeit (dezimal);Notiz;Vom Betrieb eingetragen;Abgerechnet'));
      expect(text, contains('14.10.2026;Erika;Steckdose Keller;09:00;17:15;30;7:45;7,75;;nein;nein'));
      expect(text, contains('14.10.2026;Hans;Steckdose Keller;09:00;11:00;0;2:00;2,00;;nein;ja')); // billed
      expect(text, contains('läuft;0;1:30;1,50')); // a running timer counts up to now
      expect(text, contains('Summe je Person'));
      expect(text, contains('Erika;9:15;9,25')); // 7:45 + the running 1:30
      expect(text, contains('Hans;2:00;2,00'));
      expect(text, contains('Zusammen;11:15;11,25'));
      expect(text, contains('Kein Arbeitszeitnachweis im rechtlichen Sinn'));
    });

    test('entries the boss added are marked; names with ; or quotes stay one cell', () {
      final text = utf8.decode(timesheetCsv(
        entries: [TimeEntry(id: 'x', businessId: 'b1', userId: 'u2', userName: 'Hans "Hansi"; Meister', jobId: null, createdBy: 'u1', startedAt: nine.toUtc(), endedAt: nine.add(const Duration(hours: 1)).toUtc(), breakMinutes: 0, updatedAt: DateTime(2026))],
        jobTitle: (_) => 'Ohne Auftrag',
        now: nine,
        periodLabel: 'x',
      ));
      expect(text, contains('"Hans ""Hansi""; Meister";Ohne Auftrag;09:00;10:00;0;1:00;1,00;;ja;nein'));
    });

    test('names and file names of the period', () {
      expect(timesheetPeriodLabel(DateTime(2026, 10), true), 'Oktober 2026');
      expect(timesheetPeriodLabel(DateTime(2026, 10, 12), false), '12.10. - 18.10.2026');
      expect(timesheetFileStem(DateTime(2026, 10), true), 'arbeitszeiten-2026-10');
      expect(timesheetFileStem(DateTime(2026, 10, 12), false), 'arbeitszeiten-woche-2026-10-12');
    });
  });

  group('the month view and the file on the screen', () {
    Future<void> openTimesheet(WidgetTester tester, [String title = 'Arbeitszeiten']) async {
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(title), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }

    testApp('the month adds up everything of the month; the arrows move by month; the file goes to the share sheet', (tester) async {
      final app = await pumpApp(
        tester,
        owner(),
        remote: remoteWith([
          remoteTimeEntry('t1', start: at(8), end: at(12)),
          remoteTimeEntry('t2', userId: 'u2', userName: 'Hans', start: at(8), end: at(13)),
        ]),
        team: team(),
      );
      await openTimesheet(tester);
      await tester.tap(find.text('Monat'));
      await tester.pumpAndSettle();
      expect(find.text('Zusammen: 9:00 Std'), findsOneWidget);
      expect(find.text(timesheetPeriodLabel(DateTime(DateTime.now().year, DateTime.now().month), true)), findsOneWidget);

      await tester.tap(find.text('Als Datei teilen (CSV)'));
      await tester.pumpAndSettle();
      final f = app.sharer.shared.single;
      expect(f.mimeType, 'text/csv');
      expect(f.name, timesheetFileStem(DateTime(DateTime.now().year, DateTime.now().month), true) + '.csv');
      expect(utf8.decode(f.bytes), contains('Zusammen;9:00;9,00'));

      await tester.tap(find.byTooltip('Voriger Monat'));
      await tester.pumpAndSettle();
      expect(find.text('In diesem Monat ist keine Zeit erfasst.'), findsOneWidget);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Als Datei teilen (CSV)')).onPressed, isNull); // nothing to share
    });

    testApp('a worker can share his own times too (only his own are in the file)', (tester) async {
      final app = await pumpApp(
        tester,
        geselle(),
        remote: remoteWith([remoteTimeEntry('t2', userId: 'u2', userName: 'Hans', start: at(8), end: at(13))]),
        team: team(),
      );
      await openTimesheet(tester, 'Meine Zeiten');
      await tester.tap(find.text('Als Datei teilen (CSV)'));
      await tester.pumpAndSettle();
      final text = utf8.decode(app.sharer.shared.single.bytes);
      expect(text, contains('Hans'));
      expect(text, isNot(contains('Erika')));
    });
  });

  group('billing the tracked time on an invoice', () {
    // 7:45 in two entries: Erika 4:30, Hans 3:15
    List<Map<String, dynamic>> twoEntries() => [
          remoteTimeEntry('t1', start: at(8, 0, -2), end: at(12, 30, -2)),
          remoteTimeEntry('t2', userId: 'u2', userName: 'Hans', start: at(8, 0, -1), end: at(11, 15, -1)),
        ];

    testApp('no tracked time: no question, the review opens as before', (tester) async {
      await pumpJobApp(tester);
      await openReviewFromJob(tester);
      expect(find.text('Erfasste Arbeitszeit'), findsNothing);
      expect(find.text('Rechnung prüfen'), findsOneWidget);
    });

    testApp('with spoken working time too: the boss chooses; the default replaces it', (tester) async {
      await pumpJobApp(tester, remote: remoteWith(twoEntries()));
      await openJob(tester);
      await tester.tap(find.text('Alle Notizen prüfen und abrechnen'));
      await tester.pumpAndSettle();
      expect(find.text('Erfasste Arbeitszeit'), findsOneWidget);
      expect(find.textContaining('Für diesen Auftrag ist Zeit erfasst: 7:45 Std (7,75)'), findsOneWidget);
      expect(find.textContaining('Erika 4:30'), findsWidgets); // in the question and on the job screen
      expect(find.textContaining('Hans 3:15'), findsWidgets);
      expect(find.textContaining('Arbeitszeit: 2 Std'), findsOneWidget);
      expect(find.text('Erfasste Zeit statt der Arbeitszeit aus den Notizen'), findsOneWidget);
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();

      expect(find.text('Rechnung prüfen'), findsOneWidget);
      expect(find.textContaining('Arbeitszeit (Zeiterfassung)'), findsOneWidget);
      expect(find.textContaining('Steckdose montiert'), findsNothing); // the spoken working time is gone
      expect(find.textContaining('Doppelsteckdose'), findsOneWidget); // material stays
    });

    testApp('"both" keeps the spoken time and adds the tracked time', (tester) async {
      await pumpJobApp(tester, remote: remoteWith(twoEntries()));
      await openJob(tester);
      await tester.tap(find.text('Alle Notizen prüfen und abrechnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beides berechnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Arbeitszeit (Zeiterfassung)'), findsOneWidget);
      expect(find.textContaining('Steckdose montiert'), findsOneWidget);
    });

    testApp('"not now" leaves the tracked time out of the invoice and open for later', (tester) async {
      final app = await pumpJobApp(tester, remote: remoteWith(twoEntries()));
      await openJob(tester);
      await tester.tap(find.text('Alle Notizen prüfen und abrechnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erfasste Zeit jetzt nicht abrechnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Arbeitszeit (Zeiterfassung)'), findsNothing);
      expect(find.textContaining('Steckdose montiert'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Rechnung fertigstellen'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Rechnung fertigstellen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fertigstellen'));
      await tester.pumpAndSettle();
      expect(app.documents.createCalls.single.containsKey('time_entry_ids'), isFalse);
      expect(app.remote.tables[SyncEntity.timeEntry]!.values.every((e) => e['document_id'] == null), isTrue);
    });

    testApp('cancelling the question opens nothing', (tester) async {
      await pumpJobApp(tester, remote: remoteWith(twoEntries()));
      await openJob(tester);
      await tester.tap(find.text('Alle Notizen prüfen und abrechnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.text('Rechnung prüfen'), findsNothing);
    });

    testApp('issued: the entries go to the server with the order and are billed afterwards; the price must be checked', (tester) async {
      final app = await pumpJobApp(tester, remote: remoteWith(twoEntries()));
      await openJob(tester);
      await tester.tap(find.text('Alle Notizen prüfen und abrechnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Rechnung fertigstellen'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Rechnung fertigstellen'));
      await tester.pumpAndSettle();
      // the time position carries a price check: it has to be confirmed first
      final confirm = find.widgetWithText(FilledButton, 'Fertigstellen');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile).last);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      final sent = app.documents.createCalls.single;
      expect((sent['time_entry_ids'] as List).toSet(), {'t1', 't2'});
      final labor = (sent['line_items'] as List).cast<Map>().where((l) => l['description'] == 'Arbeitszeit (Zeiterfassung)').single;
      expect(labor['quantity'], 7.75);
      expect(labor['unit'], 'Std');
      expect(labor['unit_price_net_cents'], 6800); // the hourly rate of the business, to be checked
      // the server billed them; after the next sync both are frozen on the phone
      expect(app.remote.tables[SyncEntity.timeEntry]!.values.every((e) => e['document_id'] != null), isTrue);
    });
  });
}

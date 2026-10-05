import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/features/auth/data/auth_repository.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/auth/domain/privacy_notice.dart';
import 'package:zunft_app/features/jobs/domain/job_notes.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_job_notes.dart';
import 'helpers/fake_team.dart';
import 'helpers/job_app.dart';
import 'helpers/test_app.dart';

Future<void> openBetrieb(WidgetTester tester) async {
  await tester.tap(find.text('Betrieb'));
  await tester.pumpAndSettle();
}

Future<void> tapScrolled(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('the owner removes a person', () {
    testApp('asks first, explains what happens, then ends the link and frees the seat', (tester) async {
      final app = await pumpJobApp(tester, team: FakeTeamRemote(members: sampleTeam(), seatLimit: 5));
      await openBetrieb(tester);
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      expect(find.text('3 von 5 Plätzen belegt'), findsOneWidget);

      await tester.tap(find.byTooltip('Aus dem Betrieb entfernen').first); // Gesa Geselle
      await tester.pumpAndSettle();
      expect(find.text('Gesa Geselle entfernen?'), findsOneWidget);
      expect(find.textContaining('Ihr Konto gehört ihr'), findsOneWidget); // the account stays theirs
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(app.team.log, isEmpty);

      await tester.tap(find.byTooltip('Aus dem Betrieb entfernen').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Entfernen'));
      await tester.pumpAndSettle();

      expect(app.team.log, ['remove:u2']);
      expect(find.text('Gesa Geselle'), findsNothing);
      expect(find.text('2 von 5 Plätzen belegt'), findsOneWidget);
    });

    testApp('there is no remove button for yourself or the owner', (tester) async {
      await pumpJobApp(tester, team: FakeTeamRemote(members: sampleTeam()));
      await openBetrieb(tester);
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      // 3 other people (Gesa, Bernd, Max), none for Erika
      expect(find.byTooltip('Aus dem Betrieb entfernen'), findsNWidgets(3));
    });

    testApp('a removed person is also taken off their jobs', (tester) async {
      final team = FakeTeamRemote(members: sampleTeam())..assignees['j1'] = {'u2', 'u3'};
      await pumpJobApp(tester, team: team);
      await openBetrieb(tester);
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Aus dem Betrieb entfernen').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Entfernen'));
      await tester.pumpAndSettle();
      expect(team.assignees['j1'], {'u3'});
    });
  });

  group('the person leaves on their own', () {
    testApp('an employee can leave: the link and the phone data are gone, the account stays', (tester) async {
      final repo = signedInOwner(role: 'geselle');
      final app = await pumpApp(tester, repo, remote: remoteWithJob(), jobNotes: FakeJobNotesRemote());
      expect((await tester.runAsync(() => app.db.select(app.db.jobs).get()))!, isNotEmpty); // synced to the phone
      await openBetrieb(tester);

      await tapScrolled(tester, find.text('Betrieb verlassen'));
      expect(find.text('Betrieb verlassen?'), findsOneWidget);
      expect(find.textContaining('Dein Konto bleibt bestehen'), findsWidgets);
      await tester.tap(find.text('Verlassen'));
      await tester.pumpAndSettle();

      expect(repo.leaves, 1);
      expect(repo.signOuts, 0); // still signed in: the account is theirs
      // back at the start screen, free to start a business of their own or join another
      expect(find.text('Betrieb einrichten'), findsOneWidget);
      expect(find.text('Mit Einladungscode beitreten'), findsOneWidget);
      // nothing of the old business is left on the phone
      expect(await tester.runAsync(() => app.db.select(app.db.jobs).get()), isEmpty);
      expect(await tester.runAsync(() => app.db.select(app.db.customers).get()), isEmpty);
    });

    testApp('the owner has no "Betrieb verlassen"', (tester) async {
      await pumpJobApp(tester);
      await openBetrieb(tester);
      await tester.scrollUntilVisible(find.text('Datenschutz'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Betrieb verlassen'), findsNothing);
    });

    testApp('a refusal from the server is shown', (tester) async {
      final repo = signedInOwner(role: 'geselle')
        ..leaveError = const AuthFailure('Das ist für den Inhaber eines Betriebs nicht möglich.');
      await pumpApp(tester, repo, remote: remoteWithJob());
      await openBetrieb(tester);
      await tapScrolled(tester, find.text('Betrieb verlassen'));
      await tester.tap(find.text('Verlassen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('nicht möglich'), findsOneWidget);
      expect(find.text('Betrieb einrichten'), findsNothing);
    });
  });

  group('deleting the account', () {
    testApp('an employee can erase the account after confirming; the phone forgets everything', (tester) async {
      final repo = signedInOwner(role: 'geselle');
      final app = await pumpApp(tester, repo, remote: remoteWithJob());
      await openBetrieb(tester);

      await tapScrolled(tester, find.text('Konto löschen'));
      expect(find.text('Konto endgültig löschen?'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(repo.deletions, 0);

      await tapScrolled(tester, find.text('Konto löschen'));
      await tester.tap(find.text('Konto löschen').last);
      await tester.pumpAndSettle();

      expect(repo.deletions, 1);
      expect(find.text('Anmelden'), findsWidgets); // back at the login screen
      expect(await tester.runAsync(() => app.db.select(app.db.jobs).get()), isEmpty);
    });

    testApp('an owner is told why it is not possible here, and nothing is deleted', (tester) async {
      final repo = signedInOwner();
      await pumpApp(tester, repo, remote: remoteWithJob());
      await openBetrieb(tester);
      await tapScrolled(tester, find.text('Konto löschen'));

      expect(find.text('Konto des Inhabers'), findsOneWidget);
      expect(find.textContaining('GoBD'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(repo.deletions, 0);
    });

    testApp('someone who registered but never joined a business can delete the account too', (tester) async {
      final repo = FakeAuthRepository(userId: 'u1', profile: null);
      await pumpApp(tester, repo);
      await tapScrolled(tester, find.text('Konto löschen'));
      await tester.tap(find.text('Konto löschen').last);
      await tester.pumpAndSettle();
      expect(repo.deletions, 1);
    });
  });

  group('the app notices when access ends while it is open', () {
    testApp('removed by the owner: after the next sync the phone forgets the business and offers a fresh start',
        (tester) async {
      final repo = signedInOwner(role: 'geselle');
      final app = await pumpApp(tester, repo, remote: remoteWithJob());
      expect(find.text('Aufträge'), findsOneWidget);

      repo.profile = null; // the owner removed this person
      app.connectivity.add(true); // any sync run notices
      await tester.pumpAndSettle();

      expect(find.text('Betrieb einrichten'), findsOneWidget);
      expect(await tester.runAsync(() => app.db.select(app.db.jobs).get()), isEmpty);
    });

    testApp('switched off by the owner: the "Zugang abgeschaltet" screen appears and local data is wiped',
        (tester) async {
      final repo = signedInOwner(role: 'geselle');
      final app = await pumpApp(tester, repo, remote: remoteWithJob());
      repo.profile = const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: 'geselle', active: false);
      app.connectivity.add(true);
      await tester.pumpAndSettle();

      expect(find.text('Dein Zugang wurde abgeschaltet.'), findsOneWidget);
      expect(await tester.runAsync(() => app.db.select(app.db.jobs).get()), isEmpty);
    });

    testApp('a role change (Geselle becomes Büro) is picked up: the Belege tab appears', (tester) async {
      final repo = signedInOwner(role: 'geselle');
      final app = await pumpApp(tester, repo, remote: remoteWithJob());
      expect(find.text('Belege'), findsNothing);

      repo.profile = const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: 'buero');
      app.connectivity.add(true);
      await tester.pumpAndSettle();
      expect(find.text('Belege'), findsOneWidget);
    });

    testApp('nothing changes while the profile stays the same', (tester) async {
      final app = await pumpApp(tester, signedInOwner(role: 'geselle'), remote: remoteWithJob());
      app.connectivity.add(true);
      await tester.pumpAndSettle();
      expect(find.text('Aufträge'), findsOneWidget);
      expect((await tester.runAsync(() => app.db.select(app.db.jobs).get()))!, isNotEmpty);
    });
  });

  group('a shared phone', () {
    test('a different person in the same business does not inherit the previous person\'s cache', () async {
      final db = await _memoryDb();
      await db.ensureBusiness('b1:anna');
      await db.applyRemoteJobs([
        JobsCompanion(
            id: const Value('annas-job'),
            businessId: const Value('b1'),
            title: const Value('Annas Auftrag'),
            status: const Value('draft'),
            updatedAt: Value(DateTime(2026))),
      ]);
      await db.ensureBusiness('b1:anna'); // same person: nothing happens
      expect(await db.select(db.jobs).get(), hasLength(1));

      await db.ensureBusiness('b1:bernd'); // same business, other person
      expect(await db.select(db.jobs).get(), isEmpty);
      await db.close();
    });
  });

  group('author names', () {
    test('a note of a person who has left keeps their name', () {
      final n = JobNote.fromRow({
        'id': 'n',
        'created_at': '2026-10-05T07:30:00Z',
        'created_by': null, // the profile is gone
        'created_by_name': 'Gerd Neu',
        'raw_transcript': 'x',
        'profiles': null,
        'ai_parsed_json': null,
      });
      expect(n.author, 'Gerd Neu');
    });

    test('the live profile name wins while the person is still there', () {
      final n = JobNote.fromRow({
        'id': 'n',
        'created_at': '2026-10-05T07:30:00Z',
        'created_by': 'u2',
        'created_by_name': 'Alter Name',
        'raw_transcript': 'x',
        'profiles': {'full_name': 'Neuer Name'},
        'ai_parsed_json': null,
      });
      expect(n.author, 'Neuer Name');
    });
  });

  group('privacy notice for employees', () {
    testApp('joining needs the notice to be ticked, and the notice can be read', (tester) async {
      await pumpApp(tester, FakeAuthRepository(userId: 'u1', profile: null));
      await tapScrolled(tester, find.text('Mit Einladungscode beitreten'));

      final join = find.widgetWithText(FilledButton, 'Beitreten');
      await tester.ensureVisible(join);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(join).onPressed, isNull); // not before ticking

      await tester.tap(find.text('Hinweis lesen'));
      await tester.pumpAndSettle();
      expect(find.text(PrivacyNotice.title), findsOneWidget);
      expect(find.text('Dein Konto gehört dir'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(join).onPressed, isNotNull);
    });

    testApp('it is also available later under Betrieb -> Datenschutz', (tester) async {
      await pumpJobApp(tester);
      await openBetrieb(tester);
      await tapScrolled(tester, find.text('Datenschutz'));
      expect(find.text(PrivacyNotice.title), findsOneWidget);
    });

    test('it states the facts about what the app stores: no location, no time tracking, the account stays theirs', () {
      final t = PrivacyNotice.fullText;
      expect(t, contains('keinen Standort'));
      expect(t, contains('keine Arbeitszeit'));
      expect(t, contains('Konto gehört dir'));
      expect(t, contains('Deepgram'));
      expect(t, contains('Google'));
      expect(t, contains('Supabase'));
    });
  });
}

Future<AppDatabase> _memoryDb() async => AppDatabase(NativeDatabase.memory());

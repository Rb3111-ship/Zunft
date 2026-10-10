import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/features/auth/data/auth_repository.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/team/data/team_remote.dart';
import 'package:zunft_app/features/team/domain/team_models.dart';
import 'package:zunft_app/features/team/presentation/scan_code_screen.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_job_notes.dart';
import 'helpers/fake_team.dart';
import 'helpers/job_app.dart';
import 'helpers/test_app.dart';

Future<void> openTeam(WidgetTester tester) async {
  await tester.tap(find.text('Betrieb'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
}

/// Ticks "Datenschutzhinweis gelesen" and taps Beitreten (both may be below the fold).
Future<void> acceptNoticeAndJoin(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(CheckboxListTile));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Checkbox)); // the box itself: the tile also holds the "Hinweis lesen" button
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Beitreten'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Beitreten'));
  await tester.pumpAndSettle();
}

/// Someone who registered with their own e-mail but has no business yet.
FakeAuthRepository newcomer() => FakeAuthRepository(userId: 'u1', profile: null);

void main() {
  group('invitation codes', () {
    test('the QR payload, the bare code and sloppy typing are all understood', () {
      expect(parseInviteCode('zunft-invite:ABCD2345'), 'ABCD2345');
      expect(parseInviteCode('ABCD2345'), 'ABCD2345');
      expect(parseInviteCode('  abcd-2345 '), 'ABCD2345');
      expect(parseInviteCode('abcd 2345'), 'ABCD2345');
    });

    test('anything else is not a code', () {
      expect(parseInviteCode(null), isNull);
      expect(parseInviteCode(''), isNull);
      expect(parseInviteCode('ABC'), isNull);
      expect(parseInviteCode('https://example.com'), isNull);
      expect(parseInviteCode('ABCD234I'), isNull); // I, O, 0 and 1 never appear in our codes
      expect(parseInviteCode('ABCD23450'), isNull); // too long
    });

    test('seats: active people plus open invitations, never below zero', () {
      final o = TeamOverview(
          members: sampleTeam(),
          invites: [TeamInvite(id: 'i', code: 'ABCD2345', role: 'geselle', expiresAt: DateTime(2030))],
          seatLimit: 5);
      expect(o.activeMembers, 3); // the switched-off person does not count
      expect(o.seatsInUse, 4);
      expect(o.freeSeats, 1);
      expect(TeamOverview(members: sampleTeam(), invites: const [], seatLimit: 2).freeSeats, 0);
    });
  });

  group('the owner manages the team', () {
    testApp('the Team card is only for the owner', (tester) async {
      await pumpJobApp(tester);
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      expect(find.text('Team'), findsOneWidget);
    });

    testApp('the owner switches on whether employees may create customers and jobs', (tester) async {
      final app = await pumpJobApp(tester, team: FakeTeamRemote(members: sampleTeam()));
      await openTeam(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.textContaining('Meister und Gesellen können eigene'), findsOneWidget);
    });

    testApp('shows seats, people and who is switched off', (tester) async {
      await pumpJobApp(tester, team: FakeTeamRemote(members: sampleTeam(), seatLimit: 5));
      await openTeam(tester);

      expect(find.text('3 von 5 Plätzen belegt'), findsOneWidget);
      expect(find.text('Erika (du)'), findsOneWidget);
      expect(find.text('Gesa Geselle'), findsOneWidget);
      expect(find.text('Bernd Büro'), findsOneWidget);
      expect(find.textContaining('Zugang abgeschaltet'), findsOneWidget);
      // no switch for yourself or the owner
      expect(find.text('Abschalten'), findsNWidgets(2));
      expect(find.text('Einschalten'), findsOneWidget);
    });

    testApp('invite: choose a role, get a QR code and a short code, and the seat is reserved', (tester) async {
      final app = await pumpJobApp(tester, team: FakeTeamRemote(seatLimit: 3));
      await openTeam(tester);
      expect(find.text('1 von 3 Plätzen belegt'), findsOneWidget);

      await tester.tap(find.text('Mitarbeiter einladen'));
      await tester.pumpAndSettle();
      expect(find.text('Geselle'), findsOneWidget);
      await tester.tap(find.text('Büro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Einladung erstellen'));
      await tester.pumpAndSettle();

      expect(app.team.log, ['invite:buero']);
      expect(find.text('Einladung: Büro'), findsOneWidget);
      expect(find.text('ABCD2341'), findsOneWidget);
      expect(find.byKey(const ValueKey('invite-qr')), findsOneWidget);
      expect(app.team.invites.single.qrData, 'zunft-invite:ABCD2341'); // what the QR code carries

      await tester.tap(find.text('Fertig'));
      await tester.pumpAndSettle();
      expect(find.text('2 von 3 Plätzen belegt'), findsOneWidget);
      expect(find.text('OFFENE EINLADUNGEN'), findsOneWidget);
    });

    testApp('an open invitation can be shown again and withdrawn', (tester) async {
      final app = await pumpJobApp(tester, team: FakeTeamRemote(seatLimit: 3));
      await openTeam(tester);
      await tester.tap(find.text('Mitarbeiter einladen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Einladung erstellen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fertig'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Geselle - ABCD2341'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('invite-qr')), findsOneWidget);
      await tester.tap(find.text('Fertig'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Einladung zurückziehen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(app.team.invites, hasLength(1)); // cancelled: still there

      await tester.tap(find.byTooltip('Einladung zurückziehen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zurückziehen'));
      await tester.pumpAndSettle();
      expect(app.team.invites, isEmpty);
      expect(find.text('OFFENE EINLADUNGEN'), findsNothing);
      expect(find.text('1 von 3 Plätzen belegt'), findsOneWidget);
    });

    testApp('with all seats taken the button is off and says why', (tester) async {
      await pumpJobApp(tester, team: FakeTeamRemote(members: sampleTeam(), seatLimit: 3));
      await openTeam(tester);

      expect(find.textContaining('Alle Plätze sind belegt'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Mitarbeiter einladen'));
      expect(button.onPressed, isNull);
    });

    testApp('switching a person off asks first, frees the seat, and can be undone', (tester) async {
      final app = await pumpJobApp(tester, team: FakeTeamRemote(members: sampleTeam(), seatLimit: 3));
      await openTeam(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Abschalten').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Notizen bleiben erhalten'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(app.team.log, isEmpty);

      await tester.tap(find.widgetWithText(TextButton, 'Abschalten').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Abschalten').last);
      await tester.pumpAndSettle();
      expect(app.team.log, ['active:u2:false']);
      expect(find.text('2 von 3 Plätzen belegt'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Einschalten').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Einschalten').last);
      await tester.pumpAndSettle();
      expect(app.team.log.last, 'active:u2:true');
    });

    testApp('switching a person on without a free seat is explained', (tester) async {
      final team = FakeTeamRemote(members: sampleTeam(), seatLimit: 3); // full: 3 active
      await pumpJobApp(tester, team: team);
      await openTeam(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Einschalten'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Einschalten').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Alle Plätze deines Pakets sind belegt'), findsOneWidget);
    });

    testApp('a failed load can be retried', (tester) async {
      final team = FakeTeamRemote()
        ..error = const TeamException('Keine Verbindung. Bitte Internet prüfen und erneut versuchen.');
      await pumpJobApp(tester, team: team);
      await openTeam(tester);
      expect(find.textContaining('Keine Verbindung'), findsOneWidget);

      team.error = null;
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();
      expect(find.text('1 von 5 Plätzen belegt'), findsOneWidget);
    });
  });

  group('assigning jobs', () {
    testApp('boss: assign a job to people; the choice is saved and shown', (tester) async {
      final app = await pumpJobApp(tester, team: FakeTeamRemote(members: sampleTeam()));
      await openJob(tester);

      expect(find.text('ZUGEWIESEN AN'), findsOneWidget);
      expect(find.textContaining('Niemand'), findsOneWidget);
      await tester.tap(find.text('Zuweisen'));
      await tester.pumpAndSettle();
      expect(find.text('Max Ausgeschieden'), findsNothing); // switched-off people cannot be assigned
      await tester.tap(find.text('Gesa Geselle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      expect(app.team.log, ['assign:j1:u2']);
      expect(find.text('Gesa Geselle'), findsOneWidget);
      expect(find.textContaining('Niemand'), findsNothing);
    });

    testApp('boss: taking a person off a job', (tester) async {
      final team = FakeTeamRemote(members: sampleTeam())..assignees['j1'] = {'u2', 'u3'};
      await pumpJobApp(tester, team: team);
      await openJob(tester);
      expect(find.text('Gesa Geselle'), findsOneWidget); // the office is not listed: it sees every job
      expect(find.widgetWithText(CheckboxListTile, 'Bernd Büro'), findsNothing);

      await tester.tap(find.text('Zuweisen'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(CheckboxListTile, 'Bernd Büro'), findsNothing);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gesa Geselle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(team.assignees['j1'], {'u3'});
    });

    testApp('a self-employed person (alone in the business) sees no assignment at all', (tester) async {
      await pumpJobApp(tester, team: FakeTeamRemote()); // only the owner
      await openJob(tester);
      expect(find.text('ZUGEWIESEN AN'), findsNothing);
      expect(find.text('Alle Notizen prüfen und abrechnen'), findsOneWidget); // but billing, of course
    });

    testApp('the office may assign and bill too', (tester) async {
      await pumpJobApp(tester, role: 'buero', team: FakeTeamRemote(members: sampleTeam()));
      await openJob(tester);
      expect(find.text('ZUGEWIESEN AN'), findsOneWidget);
      expect(find.text('Alle Notizen prüfen und abrechnen'), findsOneWidget);
    });

    testApp('assigning offline is explained', (tester) async {
      final team = FakeTeamRemote(members: sampleTeam());
      await pumpJobApp(tester, team: team);
      await openJob(tester);
      await tester.tap(find.text('Zuweisen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gesa Geselle'));
      team.error = const TeamException('Keine Verbindung. Bitte Internet prüfen und erneut versuchen.');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Keine Verbindung'), findsOneWidget);
    });
  });

  group('an employee', () {
    testApp('has no documents tab, no billing, no assignment and no team card', (tester) async {
      await pumpJobApp(tester, role: 'geselle', team: FakeTeamRemote(members: sampleTeam()));

      expect(find.text('Belege'), findsNothing);
      expect(find.text('Aufträge'), findsOneWidget);
      expect(find.text('Kunden'), findsOneWidget);

      await openJob(tester);
      expect(find.textContaining('Steckdose montiert'), findsOneWidget); // can read the notes of the job
      expect(find.text('Notiz zu diesem Auftrag aufnehmen'), findsOneWidget); // and add to them
      expect(find.text('Alle Notizen prüfen und abrechnen'), findsNothing);
      expect(find.text('ZUGEWIESEN AN'), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      expect(find.text('Team'), findsNothing);
      expect(find.text('Erika (Geselle)'), findsOneWidget); // who am I
    });

    testApp('may not create customers or jobs unless the owner allows it', (tester) async {
      await pumpJobApp(tester, role: 'geselle');
      expect(find.text('Neuer Auftrag'), findsNothing);
      await tester.tap(find.text('ERFASSEN')); // the job picker offers only existing jobs
      await tester.pumpAndSettle();
      expect(find.text('Für welchen Auftrag?'), findsOneWidget);
      expect(find.text('Neuer Auftrag'), findsNothing);
      expect(find.text('Steckdose Keller'), findsWidgets);
      await tester.tapAt(const Offset(10, 10)); // close the sheet
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kunden'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Kunde anlegen'), findsNothing);
    });

    testApp('may create customers and jobs once the owner allows it', (tester) async {
      await pumpJobApp(tester,
          role: 'geselle', business: FakeAuthRepository.completeBusiness().withEmployeesCanCreate(true));
      expect(find.text('Neuer Auftrag'), findsOneWidget);
      await tester.tap(find.text('Kunden'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Kunde anlegen'), findsOneWidget);
    });

    testApp('boss and office can always create them', (tester) async {
      await pumpJobApp(tester, role: 'buero');
      expect(find.text('Neuer Auftrag'), findsOneWidget);
    });

    testApp('a Meister is an employee too', (tester) async {
      await pumpJobApp(tester, role: 'meister');
      expect(find.text('Belege'), findsNothing);
    });

    testApp('the office is not an employee: documents yes, team management no', (tester) async {
      await pumpJobApp(tester, role: 'buero');
      expect(find.text('Belege'), findsOneWidget);
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      expect(find.text('Team'), findsNothing);
    });

    testApp('can still record notes, which go to the assigned job', (tester) async {
      final app = await pumpJobApp(tester, role: 'geselle', withNote: false);
      await tester.tap(find.text('ERFASSEN'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(ListView), matching: find.text('Steckdose Keller')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lieber tippen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sicherung getauscht');
      await tester.tap(find.text('Notiz senden'));
      await tester.pumpAndSettle();
      expect(app.captureRemote.processCalls.single['job'], 'j1');
    });
  });

  group('switched-off access', () {
    testApp('shows a clear message instead of the business, and signing out works', (tester) async {
      final repo = signedInOwner(role: 'geselle', active: false);
      await pumpApp(tester, repo);

      expect(find.text('Dein Zugang wurde abgeschaltet.'), findsOneWidget);
      expect(find.text('Aufträge'), findsNothing);
      await tester.tap(find.text('Abmelden'));
      await tester.pumpAndSettle();
      expect(repo.signOuts, 1);
    });
  });

  group('joining with a code', () {
    Future<void> openJoin(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Ich wurde eingeladen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ich wurde eingeladen'));
      await tester.pumpAndSettle();
    }

    testApp('the new person types the code and lands in the app as an employee', (tester) async {
      final repo = newcomer();
      await pumpApp(tester, repo);
      expect(find.text('Ich wurde eingeladen'), findsOneWidget);
      await openJoin(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Dein Name'), 'Gerd Neu');
      await tester.enterText(find.widgetWithText(TextFormField, 'Einladungscode'), 'abcd-2345');
      await acceptNoticeAndJoin(tester);
      await tester.pumpAndSettle();

      expect(repo.joined, {'code': 'ABCD2345', 'name': 'Gerd Neu'});
      expect(find.text('Betrieb beitreten'), findsNothing); // the join screen is gone
      expect(find.text('Aufträge'), findsOneWidget);
      expect(find.text('Belege'), findsNothing); // an employee
    });

    testApp('a malformed code is refused before anything is sent', (tester) async {
      final repo = newcomer();
      await pumpApp(tester, repo);
      await openJoin(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Dein Name'), 'Gerd');
      await tester.enterText(find.widgetWithText(TextFormField, 'Einladungscode'), 'ABC');
      await acceptNoticeAndJoin(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Buchstaben und Ziffern'), findsOneWidget);
      expect(repo.joined, isNull);
    });

    testApp('a name is required', (tester) async {
      final repo = newcomer();
      await pumpApp(tester, repo);
      await openJoin(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Einladungscode'), 'ABCD2345');
      await acceptNoticeAndJoin(tester);
      await tester.pumpAndSettle();
      expect(repo.joined, isNull);
    });

    testApp('a rejected code (used, expired, no seat) is explained and nothing changes', (tester) async {
      final repo = newcomer()
        ..joinError = const AuthFailure(
            'Der Code ist ungültig, abgelaufen oder schon benutzt. Bitte beim Chef einen neuen Code holen.');
      await pumpApp(tester, repo);
      await openJoin(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Dein Name'), 'Gerd');
      await tester.enterText(find.widgetWithText(TextFormField, 'Einladungscode'), 'ABCD2345');
      await acceptNoticeAndJoin(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('ungültig, abgelaufen'), findsOneWidget);
      expect(find.text('Betrieb beitreten'), findsOneWidget); // still here, can correct the code
    });

    testApp('scanning the QR code fills in the code', (tester) async {
      ScanCodeScreen.debugBodyBuilder = (onScan) => Center(
            child: FilledButton(
                onPressed: () => onScan('zunft-invite:ABCD2345'), child: const Text('Kamera erkennt Code')),
          );
      final repo = newcomer();
      await pumpApp(tester, repo);
      await openJoin(tester);

      await tester.tap(find.byTooltip('QR-Code scannen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kamera erkennt Code'));
      await tester.pumpAndSettle();

      expect(find.text('ABCD2345'), findsOneWidget); // in the field
      await tester.enterText(find.widgetWithText(TextFormField, 'Dein Name'), 'Gerd');
      await acceptNoticeAndJoin(tester);
      await tester.pumpAndSettle();
      expect(repo.joined!['code'], 'ABCD2345');
    });

    testApp('scanning some other QR code is refused politely', (tester) async {
      ScanCodeScreen.debugBodyBuilder = (onScan) => Center(
            child: FilledButton(
                onPressed: () => onScan('https://example.com/menu'), child: const Text('Kamera erkennt Code')),
          );
      await pumpApp(tester, newcomer());
      await openJoin(tester);
      await tester.tap(find.byTooltip('QR-Code scannen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kamera erkennt Code'));
      await tester.pumpAndSettle();
      expect(find.text('Das ist kein Einladungscode von Zunft.'), findsOneWidget);
    });

    testApp('someone who is not invited can still start their own business', (tester) async {
      final repo = newcomer();
      await pumpApp(tester, repo);
      expect(find.text('Ich bin Inhaber'), findsOneWidget);
      await tester.tap(find.text('Ich bin Inhaber'));
      await tester.pumpAndSettle();
      expect(find.text('Betrieb einrichten'), findsOneWidget);
      expect(find.text('Los geht\'s'), findsOneWidget);
    });
  });

  group('roles', () {
    test('who is a manager and who may run the team', () {
      UserProfile p(String role) => UserProfile(id: 'x', businessId: 'b', fullName: 'n', role: role);
      expect([
        for (final r in ['owner', 'buero', 'meister', 'geselle']) p(r).isManager
      ], [
        true,
        true,
        false,
        false
      ]);
      expect([
        for (final r in ['owner', 'buero', 'meister', 'geselle']) p(r).isOwner
      ], [
        true,
        false,
        false,
        false
      ]);
    });

    test('a profile without the active flag counts as active', () {
      expect(UserProfile.fromJson({'id': 'x', 'business_id': 'b', 'full_name': 'n', 'role': 'geselle'}).active, isTrue);
      expect(
          UserProfile.fromJson({'id': 'x', 'business_id': 'b', 'full_name': 'n', 'role': 'geselle', 'active': false})
              .active,
          isFalse);
    });

    test('every invitable role has a label and a description', () {
      for (final r in Roles.invitable) {
        expect(Roles.label(r), isNot(r));
        expect(Roles.descriptions[r], isNotEmpty);
      }
      expect(Roles.invitable, isNot(contains(Roles.owner))); // nobody is invited as a second owner
    });
  });

  // keep the unused-import lint quiet for helpers used only in some groups
  test('helpers are wired', () => expect(FakeJobNotesRemote.note(id: 'x').id, 'x'));
}

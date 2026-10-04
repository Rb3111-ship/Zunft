import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/features/auth/data/auth_repository.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/test_app.dart';

Future<void> pumpGate(WidgetTester tester, FakeAuthRepository repo) => pumpApp(tester, repo);

UserProfile owner() => const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika Test', role: 'owner');

void main() {
  group('AuthGate', () {
    testApp('signed out shows the login screen', (tester) async {
      await pumpGate(tester, FakeAuthRepository());
      expect(find.text('Anmelden'), findsWidgets);
      expect(find.text('Noch kein Konto? Registrieren'), findsOneWidget);
    });

    testApp('signed in without profile shows onboarding', (tester) async {
      await pumpGate(tester, FakeAuthRepository(userId: 'u1'));
      expect(find.text('Betrieb einrichten'), findsOneWidget);
    });

    testApp('signed in with profile shows the app with the business name', (tester) async {
      await pumpGate(tester, FakeAuthRepository(userId: 'u1', profile: owner()));
      expect(find.text('Elektro Test GmbH'), findsOneWidget);
      expect(find.text('SPRECHEN'), findsOneWidget);
    });

    testApp('signing out returns to the login screen', (tester) async {
      final repo = FakeAuthRepository(userId: 'u1', profile: owner());
      await pumpGate(tester, repo);

      await tester.tap(find.text('Betrieb')); // bottom nav tab
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abmelden'));
      await tester.pumpAndSettle();

      expect(repo.signOuts, 1);
      expect(find.text('Noch kein Konto? Registrieren'), findsOneWidget);
    });
  });

  group('LoginScreen', () {
    testApp('validates input before calling the backend', (tester) async {
      final repo = FakeAuthRepository();
      await pumpGate(tester, repo);

      await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
      await tester.pumpAndSettle();

      expect(find.text('Bitte E-Mail-Adresse eingeben'), findsOneWidget);
      expect(find.text('Bitte Passwort eingeben'), findsOneWidget);
      expect(repo.signIns, isEmpty);
    });

    testApp('successful sign in moves on to onboarding', (tester) async {
      final repo = FakeAuthRepository();
      await pumpGate(tester, repo);

      await tester.enterText(find.widgetWithText(TextFormField, 'E-Mail'), 'erika@test.de');
      await tester.enterText(find.widgetWithText(TextFormField, 'Passwort'), 'geheim123');
      await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
      await tester.pumpAndSettle();

      expect(repo.signIns, ['erika@test.de']);
      expect(find.text('Betrieb einrichten'), findsOneWidget);
    });

    testApp('shows the German error message on failure and stays on login', (tester) async {
      final repo = FakeAuthRepository()..signInError = const AuthFailure('E-Mail oder Passwort ist falsch.');
      await pumpGate(tester, repo);

      await tester.enterText(find.widgetWithText(TextFormField, 'E-Mail'), 'erika@test.de');
      await tester.enterText(find.widgetWithText(TextFormField, 'Passwort'), 'falsch');
      await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
      await tester.pumpAndSettle();

      expect(find.text('E-Mail oder Passwort ist falsch.'), findsOneWidget);
      expect(find.text('Noch kein Konto? Registrieren'), findsOneWidget);
    });

    testApp('registration enforces the password length', (tester) async {
      final repo = FakeAuthRepository();
      await pumpGate(tester, repo);

      await tester.tap(find.text('Noch kein Konto? Registrieren'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'E-Mail'), 'erika@test.de');
      await tester.enterText(find.widgetWithText(TextFormField, 'Passwort'), 'kurz');
      await tester.tap(find.widgetWithText(FilledButton, 'Konto erstellen'));
      await tester.pumpAndSettle();

      expect(find.text('Mindestens 8 Zeichen'), findsOneWidget);
      expect(repo.signUps, isEmpty);
    });

    testApp('registration with e-mail confirmation tells the user to check mail', (tester) async {
      final repo = FakeAuthRepository()..signUpResult = SignUpResult.confirmationRequired;
      await pumpGate(tester, repo);

      await tester.tap(find.text('Noch kein Konto? Registrieren'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'E-Mail'), 'erika@test.de');
      await tester.enterText(find.widgetWithText(TextFormField, 'Passwort'), 'geheim1234');
      await tester.tap(find.widgetWithText(FilledButton, 'Konto erstellen'));
      await tester.pumpAndSettle();

      expect(repo.signUps, ['erika@test.de']);
      expect(find.textContaining('E-Mail geschickt'), findsOneWidget);
      expect(find.text('Noch kein Konto? Registrieren'), findsOneWidget); // back in login mode
    });
  });

  group('OnboardingScreen', () {
    testApp('creates the business and opens the app', (tester) async {
      final repo = FakeAuthRepository(userId: 'u1');
      await pumpGate(tester, repo);

      await tester.enterText(find.widgetWithText(TextFormField, 'Betriebsname'), '  Elektro Hansa ');
      await tester.enterText(find.widgetWithText(TextFormField, 'Dein Name (Inhaber)'), 'Thorsten Krause');
      await tester.tap(find.widgetWithText(FilledButton, 'Los geht\'s'));
      await tester.pumpAndSettle();

      expect(repo.createdBusiness, {'name': 'Elektro Hansa', 'owner': 'Thorsten Krause', 'trade': 'elektro'});
      expect(find.text('SPRECHEN'), findsOneWidget);
    });

    testApp('"Sonstiges" lets the person type their own kind of business', (tester) async {
      final repo = FakeAuthRepository(userId: 'u1');
      await pumpGate(tester, repo);

      await tester.enterText(find.widgetWithText(TextFormField, 'Betriebsname'), 'Glanz GmbH');
      await tester.enterText(find.widgetWithText(TextFormField, 'Dein Name (Inhaber)'), 'Mia Klein');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sonstiges (selbst eingeben)').last);
      await tester.pumpAndSettle();

      // Left empty: refused.
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Los geht\'s'));
      await tester.tap(find.widgetWithText(FilledButton, 'Los geht\'s'));
      await tester.pumpAndSettle();
      expect(find.text('Art des Betriebs darf nicht leer sein'), findsOneWidget);
      expect(repo.createdBusiness, isNull);

      await tester.enterText(find.widgetWithText(TextFormField, 'Art des Betriebs'), ' Gebäudereinigung ');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Los geht\'s'));
      await tester.tap(find.widgetWithText(FilledButton, 'Los geht\'s'));
      await tester.pumpAndSettle();

      expect(repo.createdBusiness, {'name': 'Glanz GmbH', 'owner': 'Mia Klein', 'trade': 'Gebäudereinigung'});
    });

    testApp('requires both names', (tester) async {
      final repo = FakeAuthRepository(userId: 'u1');
      await pumpGate(tester, repo);

      await tester.tap(find.widgetWithText(FilledButton, 'Los geht\'s'));
      await tester.pumpAndSettle();

      expect(find.text('Betriebsname darf nicht leer sein'), findsOneWidget);
      expect(find.text('Name darf nicht leer sein'), findsOneWidget);
      expect(repo.createdBusiness, isNull);
    });

    testApp('shows backend errors', (tester) async {
      final repo = FakeAuthRepository(userId: 'u1')
        ..createBusinessError = const AuthFailure('Für dieses Konto existiert bereits ein Betrieb.');
      await pumpGate(tester, repo);

      await tester.enterText(find.widgetWithText(TextFormField, 'Betriebsname'), 'X GmbH');
      await tester.enterText(find.widgetWithText(TextFormField, 'Dein Name (Inhaber)'), 'Y');
      await tester.tap(find.widgetWithText(FilledButton, 'Los geht\'s'));
      await tester.pumpAndSettle();

      expect(find.text('Für dieses Konto existiert bereits ein Betrieb.'), findsOneWidget);
    });
  });

  group('Business settings', () {
    Future<void> openSettings(WidgetTester tester, FakeAuthRepository repo) async {
      await pumpGate(tester, repo);
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bearbeiten'));
      await tester.pumpAndSettle();
    }

    testApp('Betrieb tab warns about missing invoice fields', (tester) async {
      await pumpGate(tester, FakeAuthRepository(userId: 'u1', profile: owner()));
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Für Rechnungen fehlt noch'), findsOneWidget);
    });

    testApp('saves normalized values', (tester) async {
      final repo = FakeAuthRepository(userId: 'u1', profile: owner());
      await openSettings(tester, repo);

      await tester.enterText(find.widgetWithText(TextFormField, 'IBAN'), 'de89 3704 0044 0532 0130 00');
      await tester.enterText(find.widgetWithText(TextFormField, 'Stundensatz netto (€ / Std)'), '72,50');
      await tester.enterText(find.widgetWithText(TextFormField, 'Straße und Hausnummer'), 'Elbchaussee 1');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      final saved = repo.updatedBusiness!;
      expect(saved.id, 'b1');
      expect(saved.iban, 'DE89370400440532013000');
      expect(saved.defaultHourlyRateCents, 7250);
      expect(saved.addressStreet, 'Elbchaussee 1');
      expect(saved.taxNumber, isNull); // empty optional field stored as null
      expect(find.text('Betriebsdaten'), findsNothing); // popped back
    });

    testApp('blocks saving an invalid IBAN', (tester) async {
      final repo = FakeAuthRepository(userId: 'u1', profile: owner());
      await openSettings(tester, repo);

      await tester.enterText(find.widgetWithText(TextFormField, 'IBAN'), 'DE00 1234');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      expect(repo.updatedBusiness, isNull);
      expect(find.text('Betriebsdaten'), findsOneWidget); // still on the form
    });

    testApp('non-owner roles get a read-only form', (tester) async {
      final repo = FakeAuthRepository(
        userId: 'u1',
        profile: const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Gesa', role: 'geselle'),
      );
      await pumpGate(tester, repo);
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ansehen'));
      await tester.pumpAndSettle();

      expect(find.text('Speichern'), findsNothing);
      expect(find.textContaining('Nur Inhaber und Büro'), findsOneWidget);
    });
  });
}

import 'package:zunft_app/core/i18n/i18n.dart';
import 'package:flutter/widgets.dart' show Scrollable;
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/push/application/push_providers.dart';
import 'package:zunft_app/features/push/data/push_service.dart';

import 'helpers/fake_appointments.dart';
import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/job_app.dart';
import 'helpers/test_app.dart';

FakeAuthRepository worker() => FakeAuthRepository(
      userId: 'u2',
      profile: const UserProfile(id: 'u2', businessId: 'b1', fullName: 'Hans', role: 'geselle'),
      business: FakeAuthRepository.completeBusiness(),
    );

Future<void> openBetrieb(WidgetTester tester) async {
  await tester.tap(find.text('Betrieb'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Meldungen bei Terminen'), 200, scrollable: find.byType(Scrollable).first);
}

void main() {
  group('switching push on and off', () {
    testApp('off by default: no permission asked, nothing sent to the server', (tester) async {
      final service = FakePushService();
      final remote = FakePushRemote();
      await pumpApp(tester, worker(), push: service, pushRemote: remote);
      expect(service.permissionRequests, 0);
      expect(remote.calls, isEmpty);
    });

    testApp('on: the phone is asked for permission, its address goes to the server and is remembered', (tester) async {
      final service = FakePushService();
      final remote = FakePushRemote();
      final prefs = FakePushPrefsStore();
      await pumpApp(tester, worker(), push: service, pushRemote: remote, pushPrefs: prefs);
      await openBetrieb(tester);
      await tester.tap(find.text('Meldungen bei Terminen'));
      await tester.pumpAndSettle();

      expect(service.permissionRequests, 1);
      expect(remote.calls, ['register:fcm-token-1']);
      expect(prefs.prefs.enabled, isTrue);
      expect(prefs.prefs.registeredToken, 'fcm-token-1');
    });

    testApp('the server is told the app language, and told again when the language changes', (tester) async {
      addTearDown(() => I18n.current = 'de');
      final service = FakePushService();
      final remote = FakePushRemote();
      final prefs = FakePushPrefsStore();
      await pumpApp(tester, worker(), push: service, pushRemote: remote, pushPrefs: prefs);
      await openBetrieb(tester);
      await tester.tap(find.text('Meldungen bei Terminen'));
      await tester.pumpAndSettle();
      expect(remote.languages, ['de']);
      expect(prefs.prefs.registeredLanguage, 'de');

      await tester.scrollUntilVisible(find.text('Sprache'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Sprache'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Türkçe'));
      await tester.pumpAndSettle();
      expect(remote.languages, ['de', 'tr']);
      expect(remote.calls, ['register:fcm-token-1', 'register:fcm-token-1']);
      expect(prefs.prefs.registeredLanguage, 'tr');
    });

    testApp('a start with push on and the language unchanged tells the server nothing new', (tester) async {
      final remote = FakePushRemote();
      final prefs = FakePushPrefsStore(const PushPrefs(enabled: true, registeredToken: 'fcm-token-1'));
      await pumpApp(tester, worker(), push: FakePushService(), pushRemote: remote, pushPrefs: prefs);
      expect(remote.calls, isEmpty);
    });

    testApp('without the permission of the phone it stays off and says why; the server hears nothing', (tester) async {
      final service = FakePushService()..allow = false;
      final remote = FakePushRemote();
      final prefs = FakePushPrefsStore();
      await pumpApp(tester, worker(), push: service, pushRemote: remote, pushPrefs: prefs);
      await openBetrieb(tester);
      await tester.tap(find.text('Meldungen bei Terminen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Erlaubnis für Benachrichtigungen fehlt'), findsOneWidget);
      expect(prefs.prefs.enabled, isFalse);
      expect(remote.calls, isEmpty);
    });

    testApp('no address from the push service, or no connection to the server: stays off and says so', (tester) async {
      final service = FakePushService()..currentToken = null;
      final remote = FakePushRemote();
      final prefs = FakePushPrefsStore();
      await pumpApp(tester, worker(), push: service, pushRemote: remote, pushPrefs: prefs);
      await openBetrieb(tester);
      await tester.tap(find.text('Meldungen bei Terminen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('keine Adresse für Meldungen'), findsOneWidget);
      expect(prefs.prefs.enabled, isFalse);

      await tester.pumpAndSettle(const Duration(seconds: 5)); // the message goes away
      service.currentToken = 'fcm-token-1';
      remote.error = Exception('offline');
      await tester.tap(find.text('Meldungen bei Terminen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Zum Einschalten wird Internet gebraucht'), findsOneWidget);
      expect(prefs.prefs.enabled, isFalse);
    });

    testApp('off again: the phone is taken off the server and its address is deleted at Google', (tester) async {
      final service = FakePushService();
      final remote = FakePushRemote();
      final prefs = FakePushPrefsStore(const PushPrefs(enabled: true, registeredToken: 'fcm-token-1'));
      await pumpApp(tester, worker(), push: service, pushRemote: remote, pushPrefs: prefs);
      remote.calls.clear();
      await openBetrieb(tester);
      await tester.tap(find.text('Meldungen bei Terminen'));
      await tester.pumpAndSettle();
      expect(remote.calls, ['unregister:fcm-token-1']);
      expect(service.tokenDeleted, isTrue);
      expect(prefs.prefs.enabled, isFalse);
      expect(prefs.prefs.registeredToken, isNull);
    });
  });

  group('while it is on', () {
    testApp('a start with the same address registers nothing again; a new address is registered', (tester) async {
      final remote = FakePushRemote();
      await pumpApp(tester, worker(),
          push: FakePushService()..currentToken = 'same', pushRemote: remote, pushPrefs: FakePushPrefsStore(const PushPrefs(enabled: true, registeredToken: 'same')));
      expect(remote.calls, isEmpty);

      final remote2 = FakePushRemote();
      final prefs2 = FakePushPrefsStore(const PushPrefs(enabled: true, registeredToken: 'old'));
      await pumpApp(tester, worker(), push: FakePushService()..currentToken = 'new', pushRemote: remote2, pushPrefs: prefs2);
      expect(remote2.calls, ['register:new']);
      expect(prefs2.prefs.registeredToken, 'new');
    });

    testApp('the push service gives a fresh address: the server gets it', (tester) async {
      final service = FakePushService()..currentToken = 'a';
      final remote = FakePushRemote();
      final prefs = FakePushPrefsStore(const PushPrefs(enabled: true, registeredToken: 'a'));
      await pumpApp(tester, worker(), push: service, pushRemote: remote, pushPrefs: prefs);
      service.currentToken = 'b'; // what the push service reports from now on
      service.tokenController.add('b');
      await tester.pumpAndSettle();
      expect(remote.calls, ['register:b']);
      expect(prefs.prefs.registeredToken, 'b');
    });

    testApp('a message arrives: the app fetches the news at once (the new appointment shows up)', (tester) async {
      final service = FakePushService()..currentToken = 'a';
      final server = remoteWithJob();
      await pumpApp(tester, worker(), remote: server, push: service,
          pushPrefs: FakePushPrefsStore(const PushPrefs(enabled: true, registeredToken: 'a')));
      await tester.tap(find.text('Termine'));
      await tester.pumpAndSettle();
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(find.text('Neu vom Chef'), findsNothing);

      server.seed(SyncEntity.appointment,
          remoteAppointment('n1', title: 'Neu vom Chef', start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9), assignees: ['u2']));
      service.messageController.add(const PushMessage(appointmentId: 'n1', event: 'new'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Nächster Tag'));
      await tester.pumpAndSettle();
      expect(find.text('Neu vom Chef'), findsOneWidget);
    });

    testApp('tapping the notification opens that appointment (after the news were fetched)', (tester) async {
      final service = FakePushService()..currentToken = 'a';
      final server = remoteWithJob();
      await pumpApp(tester, worker(), remote: server, push: service,
          pushPrefs: FakePushPrefsStore(const PushPrefs(enabled: true, registeredToken: 'a')));
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      server.seed(SyncEntity.appointment,
          remoteAppointment('n1', title: 'Genau dieser Termin', start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9), assignees: ['u2']));

      service.messageController.add(const PushMessage(appointmentId: 'n1', event: 'new', opened: true));
      await tester.pumpAndSettle();
      expect(find.text('Genau dieser Termin'), findsOneWidget);
      expect(find.text('Als erledigt markieren'), findsOneWidget); // the appointment screen
    });

    testApp('a message that arrives while the app is open, and one about a deleted appointment, open nothing', (tester) async {
      final service = FakePushService()..currentToken = 'a';
      final server = remoteWithJob();
      await pumpApp(tester, worker(), remote: server, push: service,
          pushPrefs: FakePushPrefsStore(const PushPrefs(enabled: true, registeredToken: 'a')));
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      server.seed(SyncEntity.appointment,
          remoteAppointment('n1', title: 'Nicht aufklappen', start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9), assignees: ['u2']));
      service.messageController.add(const PushMessage(appointmentId: 'n1', event: 'new')); // arrived in the open app
      service.messageController.add(const PushMessage(appointmentId: 'n1', event: 'deleted', opened: true));
      service.messageController.add(const PushMessage(event: 'new', opened: true)); // no appointment named
      await tester.pumpAndSettle();
      expect(find.text('Als erledigt markieren'), findsNothing);
      expect(find.text('ERFASSEN'), findsOneWidget);
    });

    testApp('with push off a message changes nothing (nobody listens)', (tester) async {
      final service = FakePushService();
      final server = remoteWithJob();
      await pumpApp(tester, worker(), remote: server, push: service);
      expect(service.messageController.hasListener, isFalse);
      expect(service.tokenController.hasListener, isFalse);
    });
  });

  group('signing out and sharing a phone', () {
    testApp('sign-out takes the phone off the server FIRST and switches push off', (tester) async {
      final remote = FakePushRemote();
      final prefs = FakePushPrefsStore(const PushPrefs(enabled: true, registeredToken: 'fcm-token-1'));
      final repo = worker();
      await pumpApp(tester, repo, push: FakePushService(), pushRemote: remote, pushPrefs: prefs);
      remote.calls.clear();
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Abmelden'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Abmelden'));
      await tester.pumpAndSettle();
      expect(remote.calls, ['unregister:fcm-token-1']);
      expect(prefs.prefs.enabled, isFalse);
      expect(prefs.prefs.registeredToken, isNull);
      expect(find.text('Anmelden'), findsWidgets); // back at the login screen
    });

    testApp('a person who signs out while offline is still signed out; the address is cleaned up later', (tester) async {
      final remote = FakePushRemote()..error = Exception('offline');
      final prefs = FakePushPrefsStore(const PushPrefs(enabled: true, registeredToken: 'fcm-token-1'));
      await pumpApp(tester, worker(), push: FakePushService(), pushRemote: remote, pushPrefs: prefs);
      await tester.tap(find.text('Betrieb'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Abmelden'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Abmelden'));
      await tester.pumpAndSettle();
      expect(find.text('Anmelden'), findsWidgets);
      expect(prefs.prefs.enabled, isFalse);
    });

    testApp('the next person starts with push off and an address left behind: it is removed', (tester) async {
      final remote = FakePushRemote();
      final prefs = FakePushPrefsStore(const PushPrefs(enabled: false, registeredToken: 'left-behind'));
      final service = FakePushService();
      await pumpApp(tester, worker(), push: service, pushRemote: remote, pushPrefs: prefs);
      expect(remote.calls, ['unregister:left-behind']);
      expect(service.tokenDeleted, isTrue);
      expect(prefs.prefs.registeredToken, isNull);
    });
  });
}

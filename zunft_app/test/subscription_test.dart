import 'helpers/fake_appointments.dart' show FakeExternalActions;
import 'helpers/fake_auth_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/features/subscription/domain/subscription.dart';

import 'helpers/fake_subscription.dart';
import 'helpers/job_app.dart';
import 'helpers/test_app.dart';

final banner = find.byKey(const ValueKey('subscription-banner'));

void main() {
  group('the subscription as the server reports it', () {
    test('read from the server answer', () {
      final s = Subscription.fromJson({
        'status': 'trialing',
        'access': 'full',
        'trial_ends_at': '2026-10-28T12:00:00+00:00',
        'paid_until': null,
        'grace_ends_at': null,
        'seat_limit': 1,
      });
      expect(s.isTrial, isTrue);
      expect(s.isReadOnly, isFalse);
      expect(s.paidUntil, isNull);
      expect(Subscription.fromJson(s.toJson()).trialEndsAt, s.trialEndsAt);
    });

    test('days left of the trial count calendar days; only a running trial has them', () {
      final now = DateTime(2026, 10, 14, 15);
      Subscription trial(DateTime end) => Subscription(status: 'trialing', access: 'full', trialEndsAt: end);
      expect(trial(DateTime(2026, 10, 14, 23)).trialDaysLeft(now), 0);
      expect(trial(DateTime(2026, 10, 15, 1)).trialDaysLeft(now), 1);
      expect(trial(DateTime(2026, 10, 21, 1)).trialDaysLeft(now), 7);
      expect(const Subscription(status: 'active', access: 'full').trialDaysLeft(now), isNull);
      expect(Subscription(status: 'trialing', access: 'readonly', trialEndsAt: DateTime(2026, 10, 1)).trialDaysLeft(now), isNull);
    });
  });

  group('the strip above the tabs', () {
    testApp('nothing is shown while everything is fine', (tester) async {
      await pumpJobApp(tester);
      expect(banner, findsNothing);
    });

    testApp('a trial far from its end shows nothing, the last days do', (tester) async {
      await pumpJobApp(tester, subscription: FakeSubscriptionRemote(FakeSubscriptionRemote.trial(10)));
      expect(banner, findsNothing);
    });

    testApp('the last days of the trial are announced', (tester) async {
      await pumpJobApp(tester, subscription: FakeSubscriptionRemote(FakeSubscriptionRemote.trial(3)));
      expect(find.descendant(of: banner, matching: find.textContaining('Testphase: noch 3 Tage')), findsOneWidget);
    });

    testApp('a late payment says until when everything still works', (tester) async {
      await pumpJobApp(tester, subscription: FakeSubscriptionRemote(FakeSubscriptionRemote.grace()));
      expect(find.descendant(of: banner, matching: find.textContaining('Zahlung überfällig: bis')), findsOneWidget);
    });

    testApp('an ended subscription says that nothing new is possible, but looking and exporting is', (tester) async {
      await pumpJobApp(tester, subscription: FakeSubscriptionRemote(FakeSubscriptionRemote.readOnly()));
      expect(find.descendant(of: banner, matching: find.textContaining('Dein Zugang ist abgelaufen')), findsOneWidget);
      expect(find.textContaining('Steckdose Keller'), findsWidgets); // the job list still shows
    });

    testApp('offline with nothing known: no strip and nothing blocked', (tester) async {
      await pumpJobApp(tester, subscription: FakeSubscriptionRemote()..offline = true);
      expect(banner, findsNothing);
      await tester.tap(find.text('ERFASSEN'));
      await tester.pumpAndSettle();
      expect(find.text('Für welchen Auftrag?'), findsOneWidget);
    });

    testApp('offline: the last answer is remembered, so an ended subscription is still announced', (tester) async {
      final cache = FakeAuthCache(cachedSubscription: FakeSubscriptionRemote.readOnly().toJson());
      await pumpApp(tester, signedInOwner(), remote: remoteWithJob(), authCache: cache, subscription: FakeSubscriptionRemote()..offline = true);
      expect(find.descendant(of: banner, matching: find.textContaining('Dein Zugang ist abgelaufen')), findsOneWidget);
    });

    testApp('every answer from the server is remembered for the next offline start', (tester) async {
      final cache = FakeAuthCache();
      await pumpApp(tester, signedInOwner(), remote: remoteWithJob(), authCache: cache, subscription: FakeSubscriptionRemote(FakeSubscriptionRemote.grace()));
      expect(cache.cachedSubscription?['access'], 'grace');
    });
  });

  group('the renew button', () {
    final renew = find.byKey(const ValueKey('renew-button'));

    testApp('the owner can open the payment page from the strip', (tester) async {
      final actions = FakeExternalActions();
      await pumpJobApp(tester,
          subscription: FakeSubscriptionRemote(FakeSubscriptionRemote.readOnly()), billingUrl: 'https://zunft.example/abo', actions: actions);
      expect(find.descendant(of: renew, matching: find.text('Abo verlängern')), findsOneWidget);
      await tester.tap(renew);
      await tester.pumpAndSettle();
      expect(actions.opened.map((u) => u.toString()), ['https://zunft.example/abo']);
    });

    testApp('in the last days of the trial it says "Abo abschließen"', (tester) async {
      await pumpJobApp(tester, subscription: FakeSubscriptionRemote(FakeSubscriptionRemote.trial(2)));
      expect(find.descendant(of: renew, matching: find.text('Abo abschließen')), findsOneWidget);
    });

    testApp('without a payment page the app says so instead of doing nothing', (tester) async {
      final actions = FakeExternalActions();
      await pumpJobApp(tester, subscription: FakeSubscriptionRemote(FakeSubscriptionRemote.readOnly()), billingUrl: '', actions: actions);
      await tester.tap(renew);
      await tester.pumpAndSettle();
      expect(find.textContaining('Die Bezahlseite ist noch nicht eingerichtet'), findsOneWidget);
      expect(actions.opened, isEmpty);
    });

    testApp('a page that cannot be opened is reported', (tester) async {
      final actions = FakeExternalActions()..canOpen = false;
      await pumpJobApp(tester,
          subscription: FakeSubscriptionRemote(FakeSubscriptionRemote.readOnly()), billingUrl: 'https://zunft.example/abo', actions: actions);
      await tester.tap(renew);
      await tester.pumpAndSettle();
      expect(find.textContaining('Die Seite konnte nicht geöffnet werden'), findsOneWidget);
    });

    testApp('an employee has no button (only the owner pays)', (tester) async {
      await pumpJobApp(tester, role: 'geselle', subscription: FakeSubscriptionRemote(FakeSubscriptionRemote.readOnly()));
      expect(banner, findsOneWidget);
      expect(renew, findsNothing);
    });

    testApp('the explanation dialog offers it to the owner too', (tester) async {
      final actions = FakeExternalActions();
      await pumpJobApp(tester,
          subscription: FakeSubscriptionRemote(FakeSubscriptionRemote.readOnly()), billingUrl: 'https://zunft.example/abo', actions: actions);
      await tester.tap(find.text('ERFASSEN'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Abo verlängern')));
      await tester.pumpAndSettle();
      expect(actions.opened.length, 1);
    });
  });

  group('creating something new when access has ended', () {
    testApp('ERFASSEN explains instead of opening the recorder', (tester) async {
      await pumpJobApp(tester, subscription: FakeSubscriptionRemote(FakeSubscriptionRemote.readOnly()));
      await tester.tap(find.text('ERFASSEN'));
      await tester.pumpAndSettle();
      expect(find.text('Zugang abgelaufen'), findsOneWidget);
      expect(find.textContaining('Alles Vorhandene bleibt les- und exportierbar'), findsOneWidget);
      expect(find.text('Für welchen Auftrag?'), findsNothing);
      expect(find.textContaining('Inhaber des Betriebs'), findsNothing); // the owner is the one who can renew
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Zugang abgelaufen'), findsNothing);
    });

    testApp('an employee is told to ask the owner', (tester) async {
      await pumpJobApp(tester, role: 'geselle', subscription: FakeSubscriptionRemote(FakeSubscriptionRemote.readOnly()));
      await tester.tap(find.text('ERFASSEN'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Bitte wende dich an den Inhaber des Betriebs'), findsOneWidget);
    });

    testApp('a new job is refused, an existing one still opens', (tester) async {
      await pumpJobApp(tester, subscription: FakeSubscriptionRemote(FakeSubscriptionRemote.readOnly()));
      await tester.tap(find.text('Neuer Auftrag'));
      await tester.pumpAndSettle();
      expect(find.text('Zugang abgelaufen'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await openJob(tester);
      expect(find.text('Alle Notizen prüfen und abrechnen'), findsOneWidget);
    });

    testApp('with a valid subscription ERFASSEN works as before', (tester) async {
      await pumpJobApp(tester);
      await tester.tap(find.text('ERFASSEN'));
      await tester.pumpAndSettle();
      expect(find.text('Für welchen Auftrag?'), findsOneWidget);
    });
  });
}

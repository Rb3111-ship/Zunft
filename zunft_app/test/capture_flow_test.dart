import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/capture/data/capture_remote.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_capture.dart';
import 'helpers/test_app.dart';

FakeAuthRepository signedIn() => FakeAuthRepository(
      userId: 'u1',
      profile: const UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: 'owner'),
    );

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.text('SPRECHEN'));
  await tester.pumpAndSettle();
}

Future<void> tapMic(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.mic).last);
  await tester.pump();
}

/// Types a note in the sheet and sends it.
Future<void> sendTyped(WidgetTester tester, String text) async {
  await openSheet(tester);
  await tester.tap(find.text('Lieber tippen'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.text('Notiz senden'));
  await tester.pumpAndSettle();
}

void main() {
  group('recording', () {
    testApp('record, stop, and the draft shows up ready for review', (tester) async {
      final app = await pumpApp(tester, signedIn());
      await openSheet(tester);

      await tapMic(tester);
      expect(app.recorder.recording, isTrue);
      expect(app.recorder.startedPath, startsWith('rec_dir'));
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('0:03'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.stop));
      await tester.pumpAndSettle();

      // Sheet closed with a confirmation; the note is processed in the background.
      expect(find.text('Sprachnotiz aufnehmen'), findsNothing);
      expect(find.textContaining('Aufnahme gespeichert'), findsOneWidget);
      expect(app.captureRemote.uploads.single, matches(RegExp(r'^b1/[0-9a-f-]{36}\.m4a$')));
      expect(find.text('NEUE NOTIZEN'), findsOneWidget);
      expect(find.text('Steckdose Keller'), findsOneWidget);
      expect(find.textContaining('Rechnung für Thomas Müller'), findsOneWidget);
      expect(find.textContaining('1 Hinweis'), findsOneWidget);
    });

    testApp('tapping a ready draft opens the review screen with the AI result', (tester) async {
      await pumpApp(tester, signedIn());
      await openSheet(tester);
      await tapMic(tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Steckdose Keller'));
      await tester.pumpAndSettle();

      expect(find.text('Rechnung prüfen'), findsOneWidget);
      expect(find.textContaining('Steckdose montiert'), findsOneWidget);
    });

    testApp('a mis-tap (under one second) is refused with a hint and nothing is queued', (tester) async {
      final app = await pumpApp(tester, signedIn());
      await openSheet(tester);
      await tapMic(tester);
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pumpAndSettle();

      expect(find.text('Die Aufnahme war zu kurz.'), findsOneWidget);
      expect(app.captureRemote.uploads, isEmpty);
      expect(find.text('NEUE NOTIZEN'), findsNothing);
    });

    testApp('without microphone permission the user is told what to do', (tester) async {
      final app = await pumpApp(tester, signedIn(), recorder: FakeAudioRecorder()..permissionGranted = false);
      await openSheet(tester);
      await tapMic(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('Mikrofon-Zugriff'), findsOneWidget);
      expect(app.recorder.recording, isFalse);
    });

    testApp('if the microphone cannot start, the user sees an error', (tester) async {
      await pumpApp(tester, signedIn(), recorder: FakeAudioRecorder()..failToStart = true);
      await openSheet(tester);
      await tapMic(tester);
      await tester.pumpAndSettle();
      expect(find.text('Die Aufnahme konnte nicht gestartet werden.'), findsOneWidget);
    });

    testApp('closing the sheet while recording cancels the recording', (tester) async {
      final app = await pumpApp(tester, signedIn());
      await openSheet(tester);
      await tapMic(tester);
      expect(app.recorder.recording, isTrue);

      await tester.tapAt(const Offset(450, 100)); // tap outside the sheet to dismiss it
      await tester.pumpAndSettle();

      expect(app.recorder.cancels, 1);
      expect(app.recorder.recording, isFalse);
      expect(app.captureRemote.uploads, isEmpty);
    });

    testApp('recording stops by itself at the 3 minute limit', (tester) async {
      final app = await pumpApp(tester, signedIn());
      await openSheet(tester);
      await tapMic(tester);

      await tester.pump(const Duration(seconds: 181));
      await tester.pumpAndSettle();

      expect(app.recorder.recording, isFalse);
      expect(app.captureRemote.uploads, hasLength(1));
    });
  });

  group('typed notes', () {
    testApp('type instead of speaking', (tester) async {
      final app = await pumpApp(tester, signedIn());
      await sendTyped(tester, 'Kunde Schmidt, Sicherung getauscht, eine Stunde');

      expect(app.captureRemote.uploads, isEmpty);
      expect(app.captureRemote.processCalls.single['transcript'], 'Kunde Schmidt, Sicherung getauscht, eine Stunde');
      expect(find.text('Steckdose Keller'), findsOneWidget);
    });

    testApp('an empty note is refused', (tester) async {
      final app = await pumpApp(tester, signedIn());
      await openSheet(tester);
      await tester.tap(find.text('Lieber tippen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notiz senden'));
      await tester.pumpAndSettle();

      expect(find.text('Bitte eine Notiz eingeben.'), findsOneWidget);
      expect(app.captureRemote.processCalls, isEmpty);
    });
  });

  group('no signal / problems', () {
    testApp('offline: the note waits, says so, and is sent when the network returns', (tester) async {
      final capture = FakeCaptureRemote()..processError = const CaptureOfflineException();
      final app = await pumpApp(tester, signedIn(), captureRemote: capture);
      await sendTyped(tester, 'Kunde Müller, Steckdose');

      expect(find.textContaining('Wartet auf Internet'), findsOneWidget);
      expect(find.text('Kunde Müller, Steckdose'), findsOneWidget);

      capture.processError = null;
      app.connectivity.add(true); // signal is back
      await tester.pumpAndSettle();

      expect(find.textContaining('Wartet auf Internet'), findsNothing);
      expect(find.text('Steckdose Keller'), findsOneWidget);
      // Same capture id both times, so the server can recognise the retry.
      expect(capture.processCalls.map((c) => c['captureId']).toSet(), hasLength(1));
    });

    testApp('a failed note shows the reason; Wiederholen retries it', (tester) async {
      final capture = FakeCaptureRemote()
        ..processError = const CaptureRejectedException('Aus der Notiz konnte kein Entwurf erstellt werden.');
      await pumpApp(tester, signedIn(), captureRemote: capture);
      await sendTyped(tester, 'Brummen im Keller');

      expect(find.text('Aus der Notiz konnte kein Entwurf erstellt werden.'), findsOneWidget);

      capture.processError = null;
      await tester.tap(find.text('Wiederholen'));
      await tester.pumpAndSettle();

      expect(find.text('Steckdose Keller'), findsOneWidget);
      expect(find.text('Aus der Notiz konnte kein Entwurf erstellt werden.'), findsNothing);
    });

    testApp('a failed note can be discarded', (tester) async {
      final capture = FakeCaptureRemote()..processError = const CaptureRejectedException('kaputt');
      await pumpApp(tester, signedIn(), captureRemote: capture);
      await sendTyped(tester, 'x');

      await tester.tap(find.byTooltip('Verwerfen'));
      await tester.pumpAndSettle();

      expect(find.text('NEUE NOTIZEN'), findsNothing);
    });

    testApp('removing a ready draft asks first', (tester) async {
      await pumpApp(tester, signedIn());
      await sendTyped(tester, 'x');

      await tester.tap(find.byTooltip('Entwurf entfernen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.text('Steckdose Keller'), findsOneWidget); // cancelled: still there

      await tester.tap(find.byTooltip('Entwurf entfernen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();
      expect(find.text('Steckdose Keller'), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/features/capture/data/capture_remote.dart';
import 'package:zunft_app/features/capture/presentation/record_capture_sheet.dart';
import 'package:zunft_app/features/capture/presentation/record_flow.dart';

import 'helpers/fake_capture.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/job_app.dart';
import 'helpers/test_app.dart';

/// A job in the open picker (the same title can also be visible on the screen behind it).
Finder inPicker(String title) => find.descendant(of: find.byType(JobPickerSheet), matching: find.text(title));

/// SPRECHEN -> the job picker -> the job "Steckdose Keller" -> the recording sheet.
Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.text('SPRECHEN'));
  await tester.pumpAndSettle();
  expect(find.text('Für welchen Auftrag?'), findsOneWidget);
  await tester.tap(inPicker('Steckdose Keller'));
  await tester.pumpAndSettle();
}

Future<void> tapMic(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.mic).last);
  await tester.pump();
}

/// Types a note for the job and sends it.
Future<void> sendTyped(WidgetTester tester, String text) async {
  await openSheet(tester);
  await tester.tap(find.text('Lieber tippen'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.text('Notiz senden'));
  await tester.pumpAndSettle();
}

void main() {
  group('choosing the job first', () {
    testApp('the recording sheet always shows which job and customer the note goes to', (tester) async {
      await pumpJobApp(tester, withNote: false);
      await openSheet(tester);

      expect(find.text('AUFNAHME FÜR'), findsOneWidget);
      expect(find.text('Thomas Müller'), findsWidgets);
      expect(find.descendant(of: find.byType(RecordCaptureSheet), matching: find.text('Steckdose Keller')), findsOneWidget);
    });

    testApp('a job without a customer says so in the banner', (tester) async {
      await pumpJobApp(tester, withCustomer: false, withNote: false);
      await openSheet(tester);
      expect(find.text('Kein Kunde im Auftrag'), findsOneWidget);
    });

    testApp('"Ändern" goes back to the picker; the other job gets the note', (tester) async {
      final remote = remoteWithJob()..seed(SyncEntity.job, remoteJob('j2', title: 'Frau Neumann Bad'));
      final app = await pumpJobApp(tester, withNote: false, remote: remote);
      await openSheet(tester);

      await tester.tap(find.text('Ändern'));
      await tester.pumpAndSettle();
      expect(find.text('Für welchen Auftrag?'), findsOneWidget);
      await tester.tap(inPicker('Frau Neumann Bad'));
      await tester.pumpAndSettle();
      expect(find.text('Frau Neumann Bad'), findsWidgets); // now in the banner

      await tester.tap(find.text('Lieber tippen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Waschtisch montiert');
      await tester.tap(find.text('Notiz senden'));
      await tester.pumpAndSettle();

      expect(app.captureRemote.processCalls.single['job'], 'j2');
    });

    testApp('finished (invoiced) jobs are not offered in the picker', (tester) async {
      final remote = remoteWithJob()..seed(SyncEntity.job, {...remoteJob('j2', title: 'Alter Auftrag'), 'status': 'invoiced'});
      await pumpJobApp(tester, withNote: false, remote: remote);
      await tester.tap(find.text('SPRECHEN'));
      await tester.pumpAndSettle();
      expect(inPicker('Steckdose Keller'), findsOneWidget);
      expect(inPicker('Alter Auftrag'), findsNothing);
    });

    testApp('with no job yet, the picker offers to create one and then records for it', (tester) async {
      final app = await pumpApp(tester, signedInOwner());
      await tester.tap(find.text('SPRECHEN'));
      await tester.pumpAndSettle();
      expect(find.text('Noch kein offener Auftrag.'), findsOneWidget);

      await tester.tap(find.text('Neuer Auftrag').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Titel'), 'Neubau Garage');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      // straight into the recording sheet, for the new job
      expect(find.text('AUFNAHME FÜR'), findsOneWidget);
      expect(find.descendant(of: find.byType(RecordCaptureSheet), matching: find.text('Neubau Garage')), findsOneWidget);

      await tester.tap(find.text('Lieber tippen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Leitung verlegt');
      await tester.tap(find.text('Notiz senden'));
      await tester.pumpAndSettle();

      final job = (await tester.runAsync(() => app.db.select(app.db.jobs).get()))!.single;
      expect(app.captureRemote.processCalls.single['job'], job.id);
      // the new job had to reach the server before the note could be stored on it
      expect(app.remote.tables[SyncEntity.job]!.keys, contains(job.id));
    });

    testApp('recording from inside a job needs no picker', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
      await openJob(tester);
      await tester.tap(find.text('Notiz zu diesem Auftrag aufnehmen'));
      await tester.pumpAndSettle();

      expect(find.text('Für welchen Auftrag?'), findsNothing);
      expect(find.text('AUFNAHME FÜR'), findsOneWidget);
      await tester.tap(find.text('Lieber tippen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sicherung getauscht');
      await tester.tap(find.text('Notiz senden'));
      await tester.pumpAndSettle();

      expect(app.captureRemote.processCalls.single['job'], 'j1');
      // and the stored note now shows on the job screen
      expect(find.textContaining('Steckdose montiert'), findsOneWidget);
    });
  });

  group('recording', () {
    testApp('record, stop, and the note ends up on the job', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
      await openSheet(tester);

      await tapMic(tester);
      expect(app.recorder.recording, isTrue);
      expect(app.recorder.startedPath, startsWith('rec_dir'));
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('0:03'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.stop));
      await tester.pumpAndSettle();

      expect(find.text('Sprachnotiz aufnehmen'), findsNothing); // sheet closed
      expect(find.textContaining('Aufnahme gespeichert'), findsOneWidget);
      expect(app.captureRemote.uploads.single, matches(RegExp(r'^b1/u1/[0-9a-f-]{36}\.m4a$')));
      expect(app.captureRemote.processCalls.single['job'], 'j1');
      // nothing is left waiting, the processed note lives on the job
      expect(find.text('WARTEN AUF VERARBEITUNG'), findsNothing);
      expect((await app.jobNotes.fetchOpenNotes('j1')), hasLength(1));
    });

    testApp('a mis-tap (under one second) is refused with a hint and nothing is queued', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
      await openSheet(tester);
      await tapMic(tester);
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pumpAndSettle();

      expect(find.text('Die Aufnahme war zu kurz.'), findsOneWidget);
      expect(app.captureRemote.uploads, isEmpty);
      expect(find.text('WARTEN AUF VERARBEITUNG'), findsNothing);
    });

    testApp('without microphone permission the user is told what to do', (tester) async {
      final app = await pumpJobApp(tester, withNote: false, recorder: FakeAudioRecorder()..permissionGranted = false);
      await openSheet(tester);
      await tapMic(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('Mikrofon-Zugriff'), findsOneWidget);
      expect(app.recorder.recording, isFalse);
    });

    testApp('if the microphone cannot start, the user sees an error', (tester) async {
      await pumpJobApp(tester, withNote: false, recorder: FakeAudioRecorder()..failToStart = true);
      await openSheet(tester);
      await tapMic(tester);
      await tester.pumpAndSettle();
      expect(find.text('Die Aufnahme konnte nicht gestartet werden.'), findsOneWidget);
    });

    testApp('closing the sheet while recording cancels the recording', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
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
      final app = await pumpJobApp(tester, withNote: false);
      await openSheet(tester);
      await tapMic(tester);

      await tester.pump(const Duration(seconds: 181));
      await tester.pumpAndSettle();

      expect(app.recorder.recording, isFalse);
      expect(app.captureRemote.uploads, hasLength(1));
    });

    testApp('"Ändern" is not possible while recording', (tester) async {
      await pumpJobApp(tester, withNote: false);
      await openSheet(tester);
      await tapMic(tester);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Ändern')).onPressed, isNull);
    });
  });

  group('typed notes', () {
    testApp('type instead of speaking', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
      await sendTyped(tester, 'Sicherung getauscht, eine Stunde');

      expect(app.captureRemote.uploads, isEmpty);
      expect(app.captureRemote.processCalls.single['transcript'], 'Sicherung getauscht, eine Stunde');
      expect(app.captureRemote.processCalls.single['job'], 'j1');
    });

    testApp('an empty note is refused', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
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
    testApp('offline: the note waits (labelled with its job) and is sent when the network returns', (tester) async {
      final capture = FakeCaptureRemote()..processError = const CaptureOfflineException();
      final app = await pumpJobApp(tester, withNote: false, captureRemote: capture);
      await sendTyped(tester, 'Steckdose gesetzt');

      expect(find.text('WARTEN AUF VERARBEITUNG'), findsOneWidget);
      expect(find.textContaining('Wartet auf Internet'), findsOneWidget);
      expect(find.text('Steckdose gesetzt'), findsOneWidget);
      expect(find.textContaining('Auftrag: Steckdose Keller'), findsOneWidget);

      capture.processError = null;
      app.connectivity.add(true); // signal is back
      await tester.pumpAndSettle();

      expect(find.text('WARTEN AUF VERARBEITUNG'), findsNothing);
      expect(await app.jobNotes.fetchOpenNotes('j1'), hasLength(1));
      // Same capture id both times, so the server can recognise the retry.
      expect(capture.processCalls.map((c) => c['captureId']).toSet(), hasLength(1));
    });

    testApp('several notes for different jobs recorded offline each reach their own job', (tester) async {
      final remote = remoteWithJob()..seed(SyncEntity.job, remoteJob('j2', title: 'Frau Neumann Bad'));
      final capture = FakeCaptureRemote()..processError = const CaptureOfflineException();
      final app = await pumpJobApp(tester, withNote: false, captureRemote: capture, remote: remote);

      await sendTyped(tester, 'Montag bei Müller');
      // second note, other job
      await tester.tap(find.text('SPRECHEN'));
      await tester.pumpAndSettle();
      await tester.tap(inPicker('Frau Neumann Bad'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lieber tippen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Dienstag bei Neumann');
      await tester.tap(find.text('Notiz senden'));
      await tester.pumpAndSettle();
      expect(find.text('WARTEN AUF VERARBEITUNG'), findsOneWidget);

      capture.processError = null;
      app.connectivity.add(true);
      await tester.pumpAndSettle();

      expect(find.text('WARTEN AUF VERARBEITUNG'), findsNothing);
      expect((await app.jobNotes.fetchOpenNotes('j1')).single.transcript, 'Montag bei Müller');
      expect((await app.jobNotes.fetchOpenNotes('j2')).single.transcript, 'Dienstag bei Neumann');
    });

    testApp('a failed note shows the reason; Wiederholen retries it', (tester) async {
      final capture = FakeCaptureRemote()
        ..processError = const CaptureRejectedException('Aus der Notiz konnte kein Entwurf erstellt werden.');
      final app = await pumpJobApp(tester, withNote: false, captureRemote: capture);
      await sendTyped(tester, 'Brummen im Keller');

      expect(find.textContaining('Aus der Notiz konnte kein Entwurf erstellt werden.'), findsOneWidget);

      capture.processError = null;
      await tester.tap(find.text('Wiederholen'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Aus der Notiz konnte kein Entwurf erstellt werden.'), findsNothing);
      expect(await app.jobNotes.fetchOpenNotes('j1'), hasLength(1));
    });

    testApp('a failed note can be discarded', (tester) async {
      final capture = FakeCaptureRemote()..processError = const CaptureRejectedException('kaputt');
      await pumpJobApp(tester, withNote: false, captureRemote: capture);
      await sendTyped(tester, 'x');

      await tester.tap(find.byTooltip('Verwerfen'));
      await tester.pumpAndSettle();

      expect(find.text('WARTEN AUF VERARBEITUNG'), findsNothing);
    });
  });
}

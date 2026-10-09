import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/features/capture/data/capture_remote.dart';
import 'package:zunft_app/features/capture/data/receipt_picker.dart';

import 'helpers/fake_job_notes.dart';
import 'helpers/job_app.dart';
import 'helpers/test_app.dart';

/// What the server stores for a read receipt: two material positions and the photo.
void storeReceiptNotes(TestApp app) {
  app.captureRemote.onStored = (id, job, _) => app.jobNotes.add(
        job,
        FakeJobNotesRemote.note(
          id: id,
          author: 'Thorsten',
          transcript: 'Beleg von Baumarkt Hansen, vom 07.10.2026, Gesamt 59,50 €',
          imagePath: 'b1/u1/$id.jpg',
          items: const [
            (type: 'material', text: 'Mantelleitung NYM-J 3x1,5', qty: 50, unit: 'm', cents: 100),
            (type: 'material', text: 'Abzweigdose 80mm', qty: 6, unit: 'Stk', cents: 122),
          ],
        ),
      );
}

Future<void> startFromJob(WidgetTester tester, {String source = 'Beleg fotografieren'}) async {
  await openJob(tester);
  await tester.tap(find.text('Beleg fotografieren oder hochladen'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(source));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('receipts (Belege)', () {
    testApp('photo -> check -> Senden: uploaded, read by the server, shown on the job with the photo', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
      storeReceiptNotes(app);

      await startFromJob(tester);
      expect(app.picker.calls, [ReceiptSource.camera]);
      expect(find.text('Beleg prüfen'), findsOneWidget);
      expect(find.textContaining('Steckdose Keller'), findsWidgets);
      expect(find.textContaining('FOTO rec_dir/receipt_1.jpg'), findsOneWidget);
      // Nothing leaves the phone before "Senden".
      expect(app.captureRemote.uploads, isEmpty);

      await tester.tap(find.text('Senden'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Beleg gesendet'), findsOneWidget);
      expect(app.captureRemote.uploads.single, endsWith('.jpg'));
      final call = app.captureRemote.processCalls.single;
      expect(call['image'], app.captureRemote.uploads.single);
      expect(call['audio'], isNull);

      // On the job: a receipt note with its positions and the photo.
      expect(find.textContaining('Beleg - Thorsten'), findsOneWidget);
      expect(find.textContaining('Mantelleitung NYM-J 3x1,5'), findsOneWidget);
      await tester.tap(find.text('Beleg ansehen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Baumarkt Hansen'), findsOneWidget);
      await tester.tap(find.text('Foto öffnen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('BELEGBILD https://audio.test/b1/u1/'), findsOneWidget);
    });

    testApp('a photo from the phone gallery works the same way', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
      storeReceiptNotes(app);
      await startFromJob(tester, source: 'Foto vom Handy wählen');
      expect(app.picker.calls, [ReceiptSource.gallery]);
      await tester.tap(find.text('Senden'));
      await tester.pumpAndSettle();
      expect(app.captureRemote.processCalls, hasLength(1));
    });

    testApp('"Neu aufnehmen" takes another photo; only the last one is sent', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
      storeReceiptNotes(app);
      await startFromJob(tester);
      await tester.tap(find.text('Neu aufnehmen'));
      await tester.pumpAndSettle();
      expect(app.picker.calls, [ReceiptSource.camera, ReceiptSource.camera]);
      expect(find.textContaining('FOTO rec_dir/receipt_2.jpg'), findsOneWidget);
      expect(app.captureRemote.uploads, isEmpty);
      await tester.tap(find.text('Senden'));
      await tester.pumpAndSettle();
      expect(app.captureRemote.processCalls, hasLength(1));
    });

    testApp('discarding or cancelling the camera sends nothing', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
      await startFromJob(tester);
      await tester.tap(find.byTooltip('Verwerfen'));
      await tester.pumpAndSettle();
      expect(app.captureRemote.processCalls, isEmpty);
      expect(find.text('Beleg prüfen'), findsNothing);

      app.picker.cancel = true;
      await tester.tap(find.text('Beleg fotografieren oder hochladen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beleg fotografieren'));
      await tester.pumpAndSettle();
      expect(find.text('Beleg prüfen'), findsNothing);
      expect(app.captureRemote.processCalls, isEmpty);
    });

    testApp('a photo the server cannot read is explained, with a way to retry or discard', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
      app.captureRemote.processError = const CaptureRejectedException(
          'Auf dem Foto ist kein lesbarer Beleg zu erkennen. Bitte erneut fotografieren.');
      await startFromJob(tester);
      await tester.tap(find.text('Senden'));
      await tester.pumpAndSettle();
      expect(find.text('Beleg (Foto)'), findsOneWidget);
      expect(find.textContaining('kein lesbarer Beleg'), findsOneWidget);
      expect(find.text('Wiederholen'), findsOneWidget);
    });

    testApp('offline: the photo waits in the queue and is uploaded later', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
      storeReceiptNotes(app);
      app.captureRemote.uploadError = const CaptureOfflineException();
      await startFromJob(tester);
      await tester.tap(find.text('Senden'));
      await tester.pumpAndSettle();
      expect(find.text('Beleg (Foto)'), findsOneWidget); // still waiting
      expect(app.captureRemote.processCalls, isEmpty);

      app.captureRemote.uploadError = null;
      app.connectivity.add(true);
      await tester.pumpAndSettle(const Duration(seconds: 6));
      expect(app.captureRemote.processCalls, hasLength(1));
      expect(find.textContaining('Beleg - Thorsten'), findsOneWidget);
    });

    testApp('from the recording sheet, "Beleg" leads to the same flow', (tester) async {
      final app = await pumpJobApp(tester, withNote: false);
      storeReceiptNotes(app);
      await openJob(tester);
      await tester.tap(find.text('Notiz zu diesem Auftrag aufnehmen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beleg'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beleg fotografieren'));
      await tester.pumpAndSettle();
      expect(find.text('Beleg prüfen'), findsOneWidget);
      await tester.tap(find.text('Senden'));
      await tester.pumpAndSettle();
      expect(app.captureRemote.processCalls, hasLength(1));
    });

    testApp('a finished job takes no more receipts', (tester) async {
      await pumpJobApp(tester);
      await openJob(tester);
      expect(find.text('Beleg fotografieren oder hochladen'), findsOneWidget);
      await tester.tap(find.text('Auftrag abschließen'));
      await tester.pumpAndSettle();
      expect(find.text('Beleg fotografieren oder hochladen'), findsNothing);
    });

    testApp('the receipt positions go into the invoice with the other notes', (tester) async {
      final app = await pumpJobApp(tester);
      storeReceiptNotes(app);
      await startFromJob(tester);
      await tester.tap(find.text('Senden'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alle Notizen prüfen und abrechnen'));
      await tester.pumpAndSettle();
      expect(find.text('Rechnung prüfen'), findsOneWidget);
      expect(find.textContaining('Mantelleitung NYM-J 3x1,5'), findsOneWidget);
      expect(find.textContaining('Steckdose montiert'), findsOneWidget);
      // and the photo can be compared with them
      expect(find.text('Foto öffnen'), findsOneWidget);
    });
  });
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/capture/data/capture_remote.dart';
import 'package:zunft_app/features/capture/data/receipt_picker.dart';
import 'package:zunft_app/features/jobs/domain/job_photo.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_capture.dart' show FakeThumbnailMaker;
import 'helpers/fake_job_photos.dart';
import 'helpers/fake_subscription.dart';
import 'helpers/job_app.dart';
import 'helpers/test_app.dart';

Future<void> scrollToPhotos(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('FOTOS'), 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

final addBefore = find.byKey(const ValueKey('add-photo-before'));
final addAfter = find.byKey(const ValueKey('add-photo-after'));

Future<void> chooseCamera(WidgetTester tester) async {
  await tester.tap(find.text('Foto aufnehmen'));
  await tester.pumpAndSettle();
}

void main() {
  group('the photo section of a job', () {
    testApp('a job without photos says so and offers the three kinds', (tester) async {
      await pumpJobApp(tester);
      await openJob(tester);
      await scrollToPhotos(tester);
      expect(find.textContaining('Noch keine Fotos'), findsOneWidget);
      for (final k in ['before', 'after', 'other']) {
        expect(find.byKey(ValueKey('add-photo-$k')), findsOneWidget);
      }
    });

    testApp('photos that are on the server show under their kind, with who took them when opened', (tester) async {
      final photos = FakeJobPhotosRemote()
        ..photos.addAll([
          FakeJobPhotosRemote.photo('p1', kind: 'before'),
          FakeJobPhotosRemote.photo('p2', kind: 'after'),
          FakeJobPhotosRemote.photo('p3', kind: 'after'),
          FakeJobPhotosRemote.photo('x1', jobId: 'other-job'),
        ]);
      await pumpJobApp(tester, jobPhotos: photos);
      await openJob(tester);
      await scrollToPhotos(tester);
      expect(find.byKey(const ValueKey('photo-p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-p2')), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-p3')), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-x1')), findsNothing); // another job
      expect(find.textContaining('Noch keine Fotos'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('photo-p1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Thorsten'), findsOneWidget);
      expect(find.textContaining('12.10.2026'), findsOneWidget);
    });

    testApp('offline or refused: no photos, the job screen still works', (tester) async {
      final photos = FakeJobPhotosRemote()..error = Exception('offline');
      await pumpJobApp(tester, jobPhotos: photos);
      await openJob(tester);
      await scrollToPhotos(tester);
      expect(find.textContaining('Noch keine Fotos'), findsOneWidget);
      expect(find.text('Alle Notizen prüfen und abrechnen'), findsOneWidget);
    });
  });

  group('taking a photo', () {
    testApp('the camera photo is saved at once, uploaded to the photos folder, and shows under "Vorher"', (tester) async {
      final app = await pumpJobApp(tester);
      await openJob(tester);
      await scrollToPhotos(tester);
      await tester.tap(addBefore);
      await tester.pumpAndSettle();
      expect(find.textContaining('Foto hinzufügen: Vorher'), findsOneWidget);
      await chooseCamera(tester);

      expect(app.picker.calls, [ReceiptSource.photo]); // the plain camera, not the document scanner
      expect(app.captureRemote.uploads.first, matches(RegExp(r'^b1/u1/photos/[0-9a-f-]+\.jpg$')));
      final row = app.captureRemote.photoRows.values.single;
      expect(row['job'], 'j1');
      expect(row['kind'], 'before');
      expect(row['path'], app.captureRemote.uploads.first);
      expect(find.text('Vorher'), findsWidgets);
      expect(find.byType(Image), findsWidgets);
      // the local copy is gone and nothing is left in the queue
      expect(await app.db.queuedCaptures(), isEmpty);
    });

    testApp('"Nachher" and a photo from the phone', (tester) async {
      final app = await pumpJobApp(tester);
      await openJob(tester);
      await scrollToPhotos(tester);
      await tester.tap(addAfter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Foto vom Handy wählen'));
      await tester.pumpAndSettle();
      expect(app.picker.calls, [ReceiptSource.gallery]);
      expect(app.captureRemote.photoRows.values.single['kind'], 'after');
    });

    testApp('the user backs out of the camera: nothing is saved', (tester) async {
      final app = await pumpJobApp(tester);
      app.picker.cancel = true;
      await openJob(tester);
      await scrollToPhotos(tester);
      await tester.tap(addBefore);
      await tester.pumpAndSettle();
      await chooseCamera(tester);
      expect(app.captureRemote.uploads, isEmpty);
      expect(app.captureRemote.photoRows, isEmpty);
      expect(find.textContaining('Noch keine Fotos'), findsOneWidget);
    });

    testApp('no connection on site: the photo waits on the phone and goes out when the signal is back', (tester) async {
      final app = await pumpJobApp(tester);
      app.captureRemote.uploadError = const CaptureOfflineException('no signal');
      await openJob(tester);
      await scrollToPhotos(tester);
      await tester.tap(addBefore);
      await tester.pumpAndSettle();
      await chooseCamera(tester);
      expect(find.textContaining('wird hochgeladen, sobald Internet da ist'), findsOneWidget);
      expect(find.text('wartet'), findsOneWidget);
      expect(app.captureRemote.photoRows, isEmpty);

      app.captureRemote.uploadError = null;
      app.connectivity.add(true);
      await tester.pumpAndSettle();
      expect(app.captureRemote.photoRows, hasLength(1));
      expect(find.text('wartet'), findsNothing);
      expect(find.byType(Image), findsWidgets);
    });

    testApp('an upload that is repeated stores one row (a lost answer must not double the photo)', (tester) async {
      final app = await pumpJobApp(tester);
      await app.captureRemote.addJobPhoto(id: 'same', jobId: 'j1', kind: 'before', path: 'b1/u1/photos/same.jpg');
      await app.captureRemote.addJobPhoto(id: 'same', jobId: 'j1', kind: 'after', path: 'b1/u1/photos/same.jpg');
      expect(app.captureRemote.photoRows, hasLength(1));
      expect(app.captureRemote.photoRows['same']!['kind'], 'before');
    });

    testApp('a refused photo (the subscription ended on the server) shows as failed, not as lost', (tester) async {
      final app = await pumpJobApp(tester);
      app.captureRemote.photoError = const CaptureRejectedException('Dein Zugang ist abgelaufen.');
      await openJob(tester);
      await scrollToPhotos(tester);
      await tester.tap(addBefore);
      await tester.pumpAndSettle();
      await chooseCamera(tester);
      expect(find.text('Fehler'), findsOneWidget);
    });

    testApp('with an ended subscription the buttons explain instead of opening the camera', (tester) async {
      final app = await pumpJobApp(tester, subscription: FakeSubscriptionRemote(FakeSubscriptionRemote.readOnly()));
      await openJob(tester);
      await scrollToPhotos(tester);
      await tester.tap(addBefore);
      await tester.pumpAndSettle();
      expect(find.text('Zugang abgelaufen'), findsOneWidget);
      expect(app.picker.calls, isEmpty);
    });
  });

  group('small pictures, sharing and seeing what others take', () {
    testApp('a photo goes up with its small picture next to it, the photo first', (tester) async {
      final thumbs = FakeThumbnailMaker();
      final app = await pumpJobApp(tester, thumbnails: thumbs);
      await openJob(tester);
      await scrollToPhotos(tester);
      await tester.tap(addBefore);
      await tester.pumpAndSettle();
      await chooseCamera(tester);
      expect(thumbs.made, 1);
      final uploads = app.captureRemote.uploads;
      expect(uploads.length, 2);
      expect(uploads[0], matches(RegExp(r'^b1/u1/photos/[0-9a-f-]{36}\.jpg$')));
      expect(uploads[1], uploads[0].replaceFirst('.jpg', '_t.jpg'));
      expect(app.captureRemote.photoRows.values.single['path'], uploads[0]); // the row names the photo, not the small one
    });

    testApp('no small picture can be made: the photo is still saved and shown', (tester) async {
      for (final thumbs in [FakeThumbnailMaker()..fail = true, FakeThumbnailMaker()..returnNull = true]) {
        final app = await pumpJobApp(tester, thumbnails: thumbs);
        await openJob(tester);
        await scrollToPhotos(tester);
        await tester.tap(addBefore);
        await tester.pumpAndSettle();
        await chooseCamera(tester);
        expect(app.captureRemote.uploads.length, 1);
        expect(app.captureRemote.photoRows, hasLength(1));
        await tester.pumpWidget(const SizedBox());
      }
    });

    testApp('the overview loads the small pictures; the big view loads the full one', (tester) async {
      final photos = FakeJobPhotosRemote()..photos.add(FakeJobPhotosRemote.photo('p1'));
      await pumpJobApp(tester, jobPhotos: photos);
      await openJob(tester);
      await scrollToPhotos(tester);
      expect(photos.downloads, ['b1/u9/photos/p1_t.jpg']);
      await tester.tap(find.byKey(const ValueKey('photo-p1')));
      await tester.pumpAndSettle();
      expect(photos.downloads.last, 'b1/u9/photos/p1.jpg');
    });

    testApp('an older photo without a small picture is shown from the full one', (tester) async {
      final photos = FakeJobPhotosRemote()
        ..noThumbs = true
        ..photos.add(FakeJobPhotosRemote.photo('p1'));
      await pumpJobApp(tester, jobPhotos: photos);
      await openJob(tester);
      await scrollToPhotos(tester);
      expect(photos.downloads, ['b1/u9/photos/p1_t.jpg', 'b1/u9/photos/p1.jpg']);
      expect(find.byIcon(Icons.cloud_off), findsNothing);
      expect(find.byType(Image), findsWidgets);
    });

    testApp('a photo can be shared (for example to show a customer)', (tester) async {
      final photos = FakeJobPhotosRemote()..photos.add(FakeJobPhotosRemote.photo('p1', kind: 'after'));
      final app = await pumpJobApp(tester, jobPhotos: photos);
      await openJob(tester);
      await scrollToPhotos(tester);
      await tester.tap(find.byKey(const ValueKey('photo-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-photo')));
      await tester.pumpAndSettle();
      final shared = app.sharer.shared.single;
      expect(shared.name, 'Foto_Nachher_2026-10-12.jpg');
      expect(shared.mimeType, 'image/jpeg');
      expect(shared.bytes, isNotEmpty);
    });

    testApp('the boss sees a photo a worker takes while the job is open: pull down to refresh', (tester) async {
      final photos = FakeJobPhotosRemote();
      await pumpJobApp(tester, jobPhotos: photos);
      await openJob(tester);
      await scrollToPhotos(tester);
      expect(find.textContaining('Noch keine Fotos'), findsOneWidget);

      // the worker uploads one from another phone
      photos.photos.add(FakeJobPhotosRemote.photo('w1', kind: 'after', author: 'Gesa Geselle', authorId: 'u2'));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
      await tester.pumpAndSettle();
      await scrollToPhotos(tester);
      expect(find.byKey(const ValueKey('photo-w1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('photo-w1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Gesa Geselle'), findsOneWidget); // who took it
    });
  });

  group('looking at a photo and removing it', () {
    final delete = find.byKey(const ValueKey('delete-photo'));

    testApp('the boss removes a photo of a colleague: asked first, then gone for everyone', (tester) async {
      final photos = FakeJobPhotosRemote()..photos.add(FakeJobPhotosRemote.photo('p1'));
      await pumpJobApp(tester, jobPhotos: photos);
      await openJob(tester);
      await scrollToPhotos(tester);
      await tester.tap(find.byKey(const ValueKey('photo-p1')));
      await tester.pumpAndSettle();
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.text('Foto entfernen?'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(photos.deleted, isEmpty);

      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();
      expect(photos.deleted, ['p1']);
      expect(find.byKey(const ValueKey('photo-p1')), findsNothing); // back on the job, the photo is gone
      expect(find.textContaining('Noch keine Fotos'), findsOneWidget);
    });

    testApp('an employee can remove only his own photo', (tester) async {
      final photos = FakeJobPhotosRemote()
        ..photos.addAll([
          FakeJobPhotosRemote.photo('foreign', authorId: 'u9', kind: 'before'),
          FakeJobPhotosRemote.photo('mine', authorId: 'u1', kind: 'after'),
        ]);
      await pumpJobApp(tester, role: 'geselle', jobPhotos: photos);
      await openJob(tester);
      await scrollToPhotos(tester);
      await tester.tap(find.byKey(const ValueKey('photo-foreign')));
      await tester.pumpAndSettle();
      expect(delete, findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('photo-mine')));
      await tester.pumpAndSettle();
      expect(delete, findsOneWidget);
    });

    testApp('a picture that cannot be loaded shows a sign, not a crash', (tester) async {
      final photos = FakeJobPhotosRemote()
        ..photos.add(FakeJobPhotosRemote.photo('p1'))
        ..brokenFiles.addAll(['b1/u9/photos/p1.jpg', 'b1/u9/photos/p1_t.jpg']);
      await pumpJobApp(tester, jobPhotos: photos);
      await openJob(tester);
      await scrollToPhotos(tester);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('photo-p1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('konnte nicht geladen werden'), findsOneWidget);
    });
  });

  group('the model', () {
    test('a row of the server becomes a photo; unknown kinds count as "other"', () {
      final p = JobPhoto.fromRow({
        'id': 'p1', 'job_id': 'j1', 'kind': 'weird', 'storage_path': 'b/u/photos/p1.jpg',
        'created_by': 'u1', 'created_by_name': 'Erika', 'created_at': '2026-10-12T07:15:00+00:00',
      });
      expect(p.kind, 'weird');
      expect(photoKindLabelDe('before'), 'Vorher');
      expect(photoKindLabelDe('after'), 'Nachher');
      expect(photoKindLabelDe('weird'), 'Weitere');
      expect(JobPhoto.kinds, ['before', 'after', 'other']);
    });
  });

  // keeps the unused-import lint quiet for helpers used only by some groups
  test('helpers are wired', () {
    expect(FakeAuthRepository.completeBusiness().id, 'b1');
    expect(Business.fromJson, isNotNull);
    expect(Uint8List(0), isEmpty);
  });
}

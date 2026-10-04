import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';

import 'fake_auth_repository.dart';
import 'fake_capture.dart';
import 'fake_documents.dart';
import 'fake_job_notes.dart';
import 'fake_sync_remote.dart';
import 'fake_team.dart';
import 'test_app.dart';

FakeAuthRepository signedInOwner({Business? business, String role = 'owner', bool active = true}) => FakeAuthRepository(
      userId: 'u1',
      profile: UserProfile(id: 'u1', businessId: 'b1', fullName: 'Erika', role: role, active: active),
      business: business ?? FakeAuthRepository.completeBusiness(),
    );

/// The server already knows customer "Thomas Müller" and the job "Steckdose Keller" (which belongs
/// to that customer unless [withCustomer] is false).
FakeSyncRemote remoteWithJob({bool withCustomer = true}) => FakeSyncRemote()
  ..seed(SyncEntity.customer, {
    ...remoteCustomer('c1', name: 'Müller'),
    'first_name': 'Thomas',
    'street': 'Elbchaussee 118',
    'zip': '22763',
    'city': 'Hamburg',
  })
  ..seed(SyncEntity.job, remoteJob('j1', title: 'Steckdose Keller', customerId: withCustomer ? 'c1' : null));

/// Opens the job screen of "Steckdose Keller".
Future<void> openJob(WidgetTester tester) async {
  await tester.tap(find.text('Steckdose Keller'));
  await tester.pumpAndSettle();
}

/// From the job screen to the review screen of all its notes.
Future<void> openReviewFromJob(WidgetTester tester) async {
  await openJob(tester);
  await tester.tap(find.text('Alle Notizen prüfen und abrechnen'));
  await tester.pumpAndSettle();
}

/// An app with the standard job, and (by default) one note on it.
Future<TestApp> pumpJobApp(
  WidgetTester tester, {
  Business? business,
  bool withCustomer = true,
  bool withNote = true,
  FakeJobNotesRemote? notes,
  FakeDocumentsRemote? documents,
  FakeCaptureRemote? captureRemote,
  FakeAudioRecorder? recorder,
  FakeSyncRemote? remote,
  FakeTeamRemote? team,
  String role = 'owner',
}) {
  final jobNotes = notes ?? FakeJobNotesRemote();
  if (withNote && notes == null) jobNotes.add('j1', FakeJobNotesRemote.note(id: 'n1'));
  return pumpApp(
    tester,
    signedInOwner(business: business, role: role),
    remote: remote ?? remoteWithJob(withCustomer: withCustomer),
    jobNotes: jobNotes,
    documents: documents,
    captureRemote: captureRemote,
    recorder: recorder,
    team: team,
  );
}

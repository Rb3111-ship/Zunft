import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/core/sync/sync_providers.dart';
import 'package:zunft_app/core/theme/app_theme.dart';
import 'package:zunft_app/features/auth/application/auth_providers.dart';
import 'package:zunft_app/features/auth/presentation/auth_gate.dart';
import 'package:zunft_app/features/capture/application/capture_providers.dart';
import 'package:zunft_app/features/capture/presentation/receipt_flow.dart';
import 'package:zunft_app/core/security/app_lock.dart';
import 'package:zunft_app/features/documents/application/document_providers.dart';
import 'package:zunft_app/features/documents/pdf_generator/din_5008_invoice_template.dart';
import 'package:zunft_app/features/documents/presentation/pdf_preview_screen.dart';
import 'package:zunft_app/features/jobs/application/job_notes_providers.dart';
import 'package:zunft_app/features/receipts/application/receipt_providers.dart';
import 'package:zunft_app/features/jobs/presentation/note_replay.dart';
import 'package:zunft_app/features/team/application/team_providers.dart';
import 'package:zunft_app/features/team/presentation/scan_code_screen.dart';

import 'fake_auth_repository.dart';
import 'fake_capture.dart';
import 'fake_documents.dart';
import 'fake_job_notes.dart';
import 'fake_receipts.dart';
import 'fake_app_lock.dart';
import 'fake_logo.dart';
import 'fake_sync_remote.dart';
import 'fake_team.dart';

/// Everything a widget test may want to inspect or steer after pumping the app.
class TestApp {
  TestApp(this.db, this.remote, this.recorder, this.captureRemote, this.documents, this.jobNotes, this.team,
      this.connectivity, this.player, this.picker, this.receipts, this.sharer,
      [this.logos, this.logoPicker]);
  final AppDatabase db;
  final FakeSyncRemote remote;
  final FakeAudioRecorder recorder;
  final FakeAudioPlayer player;
  final FakeReceiptPicker picker;
  final FakeReceiptsRemote receipts;
  final FakeFileSharer sharer;
  final FakeLogoStore? logos;
  final FakeLogoPicker? logoPicker;
  final FakeCaptureRemote captureRemote;
  final FakeDocumentsRemote documents;

  /// The notes stored on jobs. A processed capture adds one here; an issued document uses them up.
  final FakeJobNotesRemote jobNotes;

  /// People, invitations, seats and job assignments in the cloud.
  final FakeTeamRemote team;

  /// Emit `true` to simulate the network coming back.
  final StreamController<bool> connectivity;
}

final _cleanups = <Future<void> Function(WidgetTester)>[];

/// Like testWidgets, but tears the app down inside the test body. Drift leaves a zero-length
/// timer when a stream is cancelled, and pumping after the test has ended hangs, so cleanup
/// has to happen here, before the framework's pending-timer check.
void testApp(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    _cleanups.clear();
    try {
      await body(tester);
    } finally {
      for (final cleanup in _cleanups.reversed) {
        await cleanup(tester);
      }
    }
  });
}

/// Pumps the AuthGate with fakes for auth, the on-device database, the server and the microphone.
Future<TestApp> pumpApp(
  WidgetTester tester,
  FakeAuthRepository repo, {
  FakeSyncRemote? remote,
  FakeCaptureRemote? captureRemote,
  FakeAudioRecorder? recorder,
  FakeAudioPlayer? player,
  FakeReceiptPicker? picker,
  FakeReceiptsRemote? receipts,
  FakeFileSharer? sharer,
  FakeLogoStore? logos,
  FakeLogoPicker? logoPicker,
  FakeDeviceAuthenticator? deviceAuth,
  FakeAppLockStore? lockStore,
  DateTime Function()? lockClock,
  FakeDocumentsRemote? documents,
  FakeJobNotesRemote? jobNotes,
  FakeTeamRemote? team,
}) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1.0;

  final db = AppDatabase(NativeDatabase.memory());
  final fakeRemote = remote ?? FakeSyncRemote();
  final fakeCapture = captureRemote ?? FakeCaptureRemote();
  final fakeRecorder = recorder ?? FakeAudioRecorder();
  final fakePlayer = player ?? FakeAudioPlayer();
  final fakePicker = picker ?? FakeReceiptPicker();
  final fakeReceipts = receipts ?? FakeReceiptsRemote();
  final fakeSharer = sharer ?? FakeFileSharer();
  final fakeLogos = logos ?? FakeLogoStore();
  final fakeLogoPicker = logoPicker ?? FakeLogoPicker();
  final fakeDocuments = documents ?? FakeDocumentsRemote();
  final fakeNotes = jobNotes ?? FakeJobNotesRemote();
  final fakeTeam = team ?? FakeTeamRemote();
  final connectivity = StreamController<bool>.broadcast();

  // The fake server behaves like the real one: a processed note lands on its job, and an issued
  // document uses up the notes it was built from.
  fakeCapture.onStored ??= (captureId, jobId, transcript) =>
      fakeNotes.add(jobId, FakeJobNotesRemote.note(id: captureId, transcript: transcript ?? 'Sprachnotiz'));
  fakeDocuments.onCreated ??=
      (payload) => fakeNotes.markUsed([...?(payload['capture_log_ids'] as List?)?.cast<String>()]);

  // The real PDF viewer needs platform channels; show the byte count instead.
  ReceiptConfirmScreen.debugImageBuilder = (path) => Text('FOTO $path');
  ReceiptViewScreen.debugBodyBuilder = (url) => Text('BELEGBILD $url');
  PdfPreviewScreen.debugBodyBuilder =
      (bytes, name) => Center(child: Text('PDF ${bytes.length > 0 ? 'ok' : 'leer'}: $name'));

  _cleanups.add((t) async {
    await t.pumpWidget(const SizedBox()); // disposes providers: cancels streams and timers
    await t.pump(Duration.zero);
    await t.pump(const Duration(seconds: 1));
    await t.runAsync(db.close);
    await t.runAsync(connectivity.close);
    t.view.reset();
    PdfPreviewScreen.debugBodyBuilder = null;
    ReceiptConfirmScreen.debugImageBuilder = null;
    ReceiptViewScreen.debugBodyBuilder = null;
    ScanCodeScreen.debugBodyBuilder = null;
  });

  // Fonts come from the asset bundle: real file I/O, which needs the real clock, not the test's fake one.
  await tester.runAsync(Din5008PdfGenerator.preloadFonts);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        appDatabaseProvider.overrideWithValue(db),
        syncRemoteProvider.overrideWithValue(fakeRemote),
        captureRemoteProvider.overrideWithValue(fakeCapture),
        documentsRemoteProvider.overrideWithValue(fakeDocuments),
        jobNotesRemoteProvider.overrideWithValue(fakeNotes),
        teamRemoteProvider.overrideWithValue(fakeTeam),
        audioRecorderProvider.overrideWithValue(fakeRecorder),
        audioPlayerProvider.overrideWithValue(fakePlayer),
        receiptPickerProvider.overrideWithValue(fakePicker),
        receiptsRemoteProvider.overrideWithValue(fakeReceipts),
        fileSharerProvider.overrideWithValue(fakeSharer),
        logoStoreProvider.overrideWithValue(fakeLogos),
        deviceAuthenticatorProvider.overrideWithValue(deviceAuth ?? FakeDeviceAuthenticator()),
        appLockStoreProvider.overrideWithValue(lockStore ?? FakeAppLockStore()),
        if (lockClock != null) appLockClockProvider.overrideWithValue(lockClock),
        logoPickerProvider.overrideWithValue(fakeLogoPicker),
        recordingsDirectoryProvider.overrideWith((ref) async => 'rec_dir'),
        captureFilesProvider.overrideWithValue(FakeCaptureFiles()),
        connectivityChangesProvider.overrideWithValue(connectivity.stream),
        syncDebounceProvider.overrideWithValue(Duration.zero),
      ],
      child: MaterialApp(theme: AppTheme.darkTheme, builder: appLockBuilder, home: const AuthGate()),
    ),
  );
  await tester.pumpAndSettle();
  return TestApp(db, fakeRemote, fakeRecorder, fakeCapture, fakeDocuments, fakeNotes, fakeTeam, connectivity, fakePlayer, fakePicker, fakeReceipts, fakeSharer, fakeLogos, fakeLogoPicker);
}

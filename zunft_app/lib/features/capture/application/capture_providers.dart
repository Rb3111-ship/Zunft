import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/sync/sync_providers.dart';
import '../../auth/application/auth_providers.dart';
import '../data/audio_recorder_service.dart';
import '../data/capture_files.dart';
import '../data/capture_processor.dart';
import '../data/capture_remote.dart';
import '../data/capture_repository.dart';

/// The microphone. Tests override this with a fake.
final audioRecorderProvider = Provider<AudioRecorderService>((ref) {
  final recorder = RecordPackageRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});

/// Where recordings are kept until they are processed (private app storage, not the gallery).
final recordingsDirectoryProvider = FutureProvider<String>((ref) async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'captures'));
  await dir.create(recursive: true);
  return dir.path;
});

final captureRemoteProvider = Provider<CaptureRemote>((ref) => SupabaseCaptureRemote(Supabase.instance.client));

/// Reading and deleting recordings on disk. Tests override this with an in-memory fake.
final captureFilesProvider = Provider<CaptureFiles>((ref) => const DiskCaptureFiles());

final captureProcessorProvider = FutureProvider<CaptureProcessor>((ref) async {
  final db = await ref.watch(scopedDatabaseProvider.future);
  final profile = await ref.watch(profileProvider.future);
  return CaptureProcessor(
    db,
    ref.watch(captureRemoteProvider),
    businessId: profile!.businessId,
    files: ref.watch(captureFilesProvider),
    // A job made offline must reach the server before a note can be stored on it.
    syncJobs: () => ref.read(syncControllerProvider.notifier).syncNow(),
  );
});

/// Notes that are waiting, being processed, or failed (processed ones live on the server's job).
final capturesProvider = StreamProvider<List<PendingCapture>>((ref) async* {
  final db = await ref.watch(scopedDatabaseProvider.future);
  yield* db.watchCaptures();
});

final captureRepositoryProvider = FutureProvider<CaptureRepository>((ref) async {
  final db = await ref.watch(scopedDatabaseProvider.future);
  return CaptureRepository(
    db,
    onChanged: () => ref.read(captureControllerProvider.notifier).process(),
    files: ref.watch(captureFilesProvider),
  );
});

class CaptureRunState {
  const CaptureRunState({this.running = false, this.problem});
  final bool running;
  final CaptureProblem? problem;
}

final captureControllerProvider = NotifierProvider<CaptureController, CaptureRunState>(CaptureController.new);

/// Runs the processor: at app start, right after a new capture, and when the network returns.
/// Only one run at a time; a request during a run triggers one more afterwards.
class CaptureController extends Notifier<CaptureRunState> {
  StreamSubscription<bool>? _connectivity;
  bool _running = false;
  bool _again = false;
  bool _started = false;

  @override
  CaptureRunState build() {
    ref.onDispose(() => _connectivity?.cancel());
    return const CaptureRunState();
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _connectivity = ref.read(connectivityChangesProvider).listen((online) {
      if (online) process();
    });
    final db = await ref.read(scopedDatabaseProvider.future);
    await db.requeueInterruptedCaptures(); // the app may have been killed mid-processing
    await process();
  }

  Future<void> process() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    state = CaptureRunState(running: true, problem: state.problem);
    try {
      do {
        _again = false;
        final processor = await ref.read(captureProcessorProvider.future);
        final result = await processor.run();
        state = CaptureRunState(running: true, problem: result.problem);
        if (result.problem != null) _again = false; // retrying immediately cannot help
      } while (_again);
    } catch (_) {
      state = const CaptureRunState(running: true, problem: CaptureProblem.offline);
    } finally {
      _running = false;
      state = CaptureRunState(running: false, problem: state.problem);
    }
  }
}

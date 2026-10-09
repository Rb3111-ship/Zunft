import 'dart:async';
import 'dart:io' show FileSystemException;
import 'dart:typed_data';

import 'package:zunft_app/features/capture/data/audio_player_service.dart';
import 'package:zunft_app/features/capture/data/audio_recorder_service.dart';
import 'package:zunft_app/features/capture/data/capture_files.dart';
import 'package:zunft_app/features/capture/data/capture_remote.dart';
import 'package:zunft_app/features/capture/data/receipt_picker.dart';
import 'package:zunft_app/features/capture/data/storage_status.dart';

/// Microphone stand-in. Nothing is recorded; it just tracks what the UI asked for.
class FakeAudioRecorder implements AudioRecorderService {
  bool permissionGranted = true;
  bool failToStart = false;
  bool recording = false;
  String? startedPath;
  int cancels = 0;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> start(String path) async {
    if (failToStart) throw StateError('mic busy');
    recording = true;
    startedPath = path;
  }

  @override
  Future<String?> stop() async {
    recording = false;
    return startedPath;
  }

  @override
  Future<void> cancel() async {
    recording = false;
    cancels++;
  }

  @override
  Future<void> dispose() async {}
}

/// Server stand-in for the capture flow. Records every call; failures are programmable.
class FakeCaptureRemote implements CaptureRemote {
  /// Thrown by [uploadAudio] while non-null.
  Exception? uploadError;

  /// Thrown by [process] while non-null.
  Exception? processError;

  final List<String> uploads = [];
  final List<Map<String, String?>> processCalls = [];

  /// Builds the answer; override per test for specific drafts.
  Map<String, dynamic> Function(String captureId, String? transcript)? responseBuilder;

  /// Called for every successful [process] (e.g. to let a [FakeJobNotesRemote] store the note).
  void Function(String captureId, String jobId, String? transcript)? onStored;

  @override
  Future<void> uploadAudio(String path, Uint8List bytes) async {
    if (uploadError != null) throw uploadError!;
    uploads.add(path);
  }

  /// What the storage card shows.
  StorageStatus storage = const StorageStatus(usedBytes: 3236817, limitBytes: 1073741824);

  @override
  Future<StorageStatus> storageStatus() async => storage;

  @override
  Future<void> uploadImage(String path, Uint8List bytes) async {
    if (uploadError != null) throw uploadError!;
    uploads.add(path);
  }

  @override
  Future<CaptureResponse> process({
    required String captureId,
    required String jobId,
    String? audioStoragePath,
    String? imageStoragePath,
    String? transcript,
  }) async {
    processCalls.add({
      'captureId': captureId,
      'job': jobId,
      'audio': audioStoragePath,
      'image': imageStoragePath,
      'transcript': transcript
    });
    if (processError != null) throw processError!;
    onStored?.call(captureId, jobId, transcript);
    final build = responseBuilder ?? defaultResponse;
    return CaptureResponse({...build(captureId, transcript), 'jobId': jobId});
  }

  Map<String, dynamic> defaultResponse(String captureId, String? transcript) => {
        'success': true,
        'transcript': transcript ?? 'Kunde Thomas Müller, Steckdose im Keller, zwei Stunden, Material vierzig Euro.',
        'parsedData': {
          'title': 'Steckdose Keller',
          'document_type': 'invoice',
          'customer_hint': {'name': 'Thomas Müller', 'address': null},
          'line_items': [
            {
              'type': 'labor',
              'description': 'Steckdose montiert',
              'quantity': 2,
              'unit': 'Std',
              'unit_price_net_cents': 6800
            },
            {
              'type': 'material',
              'description': 'Doppelsteckdose',
              'quantity': 1,
              'unit': 'Stk',
              'unit_price_net_cents': 4000
            },
          ],
          'warnings': ['Materialpreis geschätzt'],
        },
        'financialSummary': {'total_net_cents': 17600},
      };
}

/// In-memory recordings. A path containing "missing" behaves like a vanished file.
class FakeCaptureFiles implements CaptureFiles {
  final List<String> deleted = [];

  @override
  Future<Uint8List> read(String path) async {
    if (path.contains('missing')) throw const FileSystemException('gone');
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> delete(String path) async => deleted.add(path);
}

/// Speaker stand-in: remembers what was played.
class FakeAudioPlayer implements AudioPlayerService {
  final List<String> played = [];
  int stops = 0;
  final _done = StreamController<void>.broadcast();

  @override
  Future<void> play(String path) async => played.add(path);

  @override
  Future<void> playUrl(String url) async => played.add(url);

  @override
  Future<void> stop() async => stops++;

  @override
  Stream<void> get completed => _done.stream;

  /// Simulates the end of the file.
  void finish() => _done.add(null);

  @override
  Future<void> dispose() async => _done.close();
}

/// Camera / gallery stand-in: hands out numbered file names, or null to simulate cancelling.
class FakeReceiptPicker implements ReceiptPicker {
  final List<ReceiptSource> calls = [];

  /// Set to true to simulate the user backing out of the camera.
  bool cancel = false;

  /// The kind of file handed out ("jpg" or "pdf").
  String extension = 'jpg';

  @override
  Future<String?> pick(ReceiptSource source) async {
    calls.add(source);
    return cancel ? null : 'rec_dir/receipt_${calls.length}.$extension';
  }
}

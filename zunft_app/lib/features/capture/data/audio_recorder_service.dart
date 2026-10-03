import 'package:record/record.dart';

/// Thin wrapper around the microphone so screens and tests do not depend on the plugin.
abstract class AudioRecorderService {
  /// Asks for microphone permission if needed. False if the user said no.
  Future<bool> requestPermission();

  /// Starts recording to [path] (an .m4a file).
  Future<void> start(String path);

  /// Stops and returns the file path, or null if nothing was recorded.
  Future<String?> stop();

  /// Stops and throws the recording away.
  Future<void> cancel();

  Future<void> dispose();
}

class RecordPackageRecorder implements AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  /// Speech, not music: mono 16 kHz AAC keeps the upload small (about 0.5 MB per minute)
  /// and is what speech recognition works best with. Noise suppression helps on a building site.
  static const _config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    sampleRate: 16000,
    numChannels: 1,
    bitRate: 64000,
    autoGain: true,
    noiseSuppress: true,
  );

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) => _recorder.start(_config, path: path);

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}

import 'package:audioplayers/audioplayers.dart';

/// Thin wrapper around playback so screens and tests do not depend on the plugin.
abstract class AudioPlayerService {
  /// Plays the file from the start.
  Future<void> play(String path);

  /// Plays a recording from a web address (a stored note).
  Future<void> playUrl(String url);

  Future<void> stop();

  /// Fires when playback reaches the end of the file.
  Stream<void> get completed;

  Future<void> dispose();
}

class AudioPlayersPlayer implements AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> play(String path) => _player.play(DeviceFileSource(path));

  @override
  Future<void> playUrl(String url) => _player.play(UrlSource(url));

  @override
  Future<void> stop() => _player.stop();

  @override
  Stream<void> get completed => _player.onPlayerComplete;

  @override
  Future<void> dispose() => _player.dispose();
}

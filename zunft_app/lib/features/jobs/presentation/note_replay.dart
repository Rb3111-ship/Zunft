import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../capture/application/capture_providers.dart';
import '../../capture/data/audio_player_service.dart';
import '../application/job_notes_providers.dart';
import '../data/job_notes_remote.dart';

/// Which stored recording is playing right now (one at a time, the player is shared).
final nowPlayingProvider = StateProvider<String?>((ref) => null);

/// Numbers are where speech recognition hurts most ("fünfzehn" heard as "50"), so they stand out.
final _numberPattern = RegExp(
  r'(\d[\d.,]*|\b(?:null|eins|ein|eine|einen|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn|elf|zwölf|'
  r'[a-zäöüß]*zehn|[a-zäöüß]*zig|hundert|tausend|halb|halbe|halbe[nr]?|anderthalb|eineinhalb)\b)',
  caseSensitive: false,
);

/// The transcript with every number in amber, so it is easy to compare with the positions.
List<TextSpan> highlightNumbers(String text, TextStyle base) {
  final spans = <TextSpan>[];
  var last = 0;
  for (final m in _numberPattern.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start), style: base));
    spans.add(TextSpan(
      text: m.group(0),
      style: base.copyWith(color: AppTheme.accentAmber, fontWeight: FontWeight.bold, fontStyle: FontStyle.normal),
    ));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last), style: base));
  return spans;
}

/// What was understood from one note (numbers highlighted) with a button to hear the original.
class NoteReplay extends ConsumerStatefulWidget {
  const NoteReplay({super.key, required this.transcript, this.audioPath, this.author});

  final String transcript;

  /// Where the recording is stored; null for typed notes (nothing to play).
  final String? audioPath;
  final String? author;

  @override
  ConsumerState<NoteReplay> createState() => _NoteReplayState();
}

class _NoteReplayState extends ConsumerState<NoteReplay> {
  late final AudioPlayerService _player;
  late final JobNotesRemote _remote;
  late final StateController<String?> _nowPlaying;
  StreamSubscription<void>? _done;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = ref.read(audioPlayerProvider);
    _remote = ref.read(jobNotesRemoteProvider);
    _nowPlaying = ref.read(nowPlayingProvider.notifier);
    _done = _player.completed.listen((_) {
      final path = widget.audioPath;
      if (mounted && path != null && _nowPlaying.state == path) _nowPlaying.state = null;
    });
  }

  @override
  void dispose() {
    _done?.cancel();
    final path = widget.audioPath;
    if (path != null && _nowPlaying.mounted && _nowPlaying.state == path) {
      _player.stop();
      final state = _nowPlaying;
      Future.microtask(() {
        if (state.mounted) state.state = null; // not during teardown
      });
    }
    super.dispose();
  }

  Future<void> _toggle() async {
    final path = widget.audioPath;
    if (path == null || _loading) return;
    if (ref.read(nowPlayingProvider) == path) {
      await _player.stop();
      _nowPlaying.state = null;
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _player.stop();
      final url = await _remote.audioUrl(path);
      await _player.playUrl(url);
      _nowPlaying.state = path;
    } on JobNotesException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Die Aufnahme konnte nicht abgespielt werden.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playing = widget.audioPath != null && ref.watch(nowPlayingProvider) == widget.audioPath;
    const base = TextStyle(fontStyle: FontStyle.italic, color: AppTheme.textSecondary, fontSize: 13);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.audioPath != null)
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
            onPressed: _toggle,
            icon: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(playing ? Icons.stop_circle_outlined : Icons.play_circle_outline, size: 22),
            label: Text(playing ? 'Anhalten' : 'Aufnahme anhören'),
          ),
        Text.rich(TextSpan(children: [
          if ((widget.author ?? '').isNotEmpty) TextSpan(text: '${widget.author}: ', style: base),
          const TextSpan(text: '"', style: base),
          ...highlightNumbers(widget.transcript, base),
          const TextSpan(text: '"', style: base),
        ])),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!, style: const TextStyle(color: AppTheme.accentRed, fontSize: 12.5)),
          ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

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
  const NoteReplay({super.key, required this.transcript, this.audioPath, this.imagePath, this.author});

  final String transcript;

  /// Where the recording is stored; null for typed notes (nothing to play).
  final String? audioPath;
  final String? author;

  /// Where the photo of a receipt (Beleg) is stored; set instead of [audioPath] for receipts.
  final String? imagePath;

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
        if (widget.imagePath != null)
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => ReceiptViewScreen(imagePath: widget.imagePath!))),
            icon: const Icon(Icons.image_outlined, size: 22),
            label: const Text('Foto öffnen'),
          ),
        Text.rich(TextSpan(children: [
          if ((widget.author ?? '').isNotEmpty) TextSpan(text: '${widget.author}: ', style: base),
          if (widget.imagePath == null) const TextSpan(text: '"', style: base),
          ...highlightNumbers(widget.transcript, base),
          if (widget.imagePath == null) const TextSpan(text: '"', style: base),
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

/// The stored photo of a receipt, large and zoomable, to compare with the positions read from it.
class ReceiptViewScreen extends ConsumerStatefulWidget {
  const ReceiptViewScreen({super.key, required this.imagePath});

  final String imagePath;

  /// Tests replace the network image.
  static Widget Function(String url)? debugBodyBuilder;

  @override
  ConsumerState<ReceiptViewScreen> createState() => _ReceiptViewScreenState();
}

class _ReceiptViewScreenState extends ConsumerState<ReceiptViewScreen> {
  late final Future<String> _url = ref.read(jobNotesRemoteProvider).audioUrl(widget.imagePath);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Beleg')),
      body: FutureBuilder<String>(
        future: _url,
        builder: (context, snap) {
          if (snap.hasError) {
            final e = snap.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(e is JobNotesException ? e.message : 'Der Beleg konnte nicht geladen werden.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.accentAmber));
          }
          final url = snap.data!;
          if (widget.imagePath.toLowerCase().endsWith('.pdf') && ReceiptViewScreen.debugBodyBuilder == null) {
            return _PdfReceipt(url: url);
          }
          return InteractiveViewer(
            maxScale: 6,
            child: Center(
              child: ReceiptViewScreen.debugBodyBuilder?.call(url) ??
                  Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (c, child, p) => p == null
                        ? child
                        : const Center(child: CircularProgressIndicator(color: AppTheme.accentAmber)),
                    errorBuilder: (c, e, s) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Der Beleg konnte nicht geladen werden.'),
                    ),
                  ),
            ),
          );
        },
      ),
    );
  }
}

/// A PDF receipt: downloaded from the temporary link and shown page by page.
class _PdfReceipt extends StatelessWidget {
  const _PdfReceipt({required this.url});

  final String url;

  Future<Uint8List> _load() async {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
    return res.bodyBytes;
  }

  @override
  Widget build(BuildContext context) {
    return PdfPreview(
      build: (_) => _load(),
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      useActions: false,
      maxPageWidth: 700,
      onError: (context, error) => const Center(child: Text('Das PDF konnte nicht geladen werden.')),
    );
  }
}

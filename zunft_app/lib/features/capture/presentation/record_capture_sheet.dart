import '../../../core/i18n/i18n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart' show Job;
import '../../../core/theme/app_theme.dart';
import '../../data/data_repository.dart' show ValidationFailure;
import '../application/capture_providers.dart';
import '../data/audio_player_service.dart';
import '../data/audio_recorder_service.dart';
import '../data/capture_files.dart';
import '../data/capture_repository.dart';

enum _Phase { idle, recording, review, saving }

/// Bottom sheet to dictate (or type) a note for one job. Saving puts it in the queue; the note
/// shows up on the job once processed - the user does not wait here.
///
/// A banner always shows which job (and customer) the note goes to. Pops with [changeJob] if the
/// user wants to pick another job.
class RecordCaptureSheet extends ConsumerStatefulWidget {
  const RecordCaptureSheet({super.key, required this.job, this.customerName});

  final Job job;
  final String? customerName;

  /// Result of the sheet when the user chose "Ändern".
  static const changeJob = 'change-job';

  /// Result of the sheet when the user wants to photograph a receipt instead.
  static const receipt = 'receipt';

  /// The server only reads the first 4000 characters of a transcript, so longer notes would be
  /// cut off silently. About 3 minutes of speech stays safely below that.
  static const maxSeconds = 180;

  @override
  ConsumerState<RecordCaptureSheet> createState() => _RecordCaptureSheetState();
}

class _RecordCaptureSheetState extends ConsumerState<RecordCaptureSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AudioRecorderService _recorder;
  late final AudioPlayerService _player;
  late final CaptureFiles _files;
  StreamSubscription<void>? _playerDone;
  bool _playing = false;
  final _typed = TextEditingController();

  _Phase _phase = _Phase.idle;
  bool _typing = false;
  int _seconds = 0;
  Timer? _ticker;
  String? _path;
  String? _error;

  @override
  void initState() {
    super.initState();
    _recorder = ref.read(audioRecorderProvider);
    _player = ref.read(audioPlayerProvider);
    _files = ref.read(captureFilesProvider);
    _playerDone = _player.completed.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _playerDone?.cancel();
    _player.stop();
    final unsent = _phase == _Phase.review ? _path : null;
    if (unsent != null) {
      // Sheet closed without sending: the recording is dropped, like a cancelled one.
      _files.delete(unsent);
    }
    _pulse.dispose();
    _typed.dispose();
    // Sheet dismissed while recording: throw the recording away rather than leave the mic on.
    if (_phase == _Phase.recording) {
      _recorder.cancel(); // also deletes the partial file ("ref" must not be used in dispose)
    }
    super.dispose();
  }

  String get _clock => '${(_seconds ~/ 60)}:${(_seconds % 60).toString().padLeft(2, '0')}';

  Future<void> _start() async {
    setState(() => _error = null);
    final recorder = _recorder;

    if (!await recorder.requestPermission()) {
      if (mounted) {
        setState(() => _error = 'Ohne Mikrofon-Zugriff geht es nicht. Bitte in den Einstellungen erlauben - oder die Notiz unten eintippen.'.tr);
      }
      return;
    }

    final dir = await ref.read(recordingsDirectoryProvider.future);
    final path = p.join(dir, 'rec_${DateTime.now().millisecondsSinceEpoch}.m4a');
    try {
      await recorder.start(path);
    } catch (_) {
      if (mounted) setState(() => _error = 'Die Aufnahme konnte nicht gestartet werden.'.tr);
      return;
    }
    if (!mounted) return;

    setState(() {
      _phase = _Phase.recording;
      _path = path;
      _seconds = 0;
    });
    _pulse.repeat(reverse: true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
      if (_seconds >= RecordCaptureSheet.maxSeconds) _stop();
    });
  }

  /// Stopping does NOT send: the worker first listens to the note and then sends or deletes it,
  /// because a wrong note ends up on the invoice.
  Future<void> _stop() async {
    if (_phase != _Phase.recording) return;
    _ticker?.cancel();
    _pulse.stop();
    setState(() => _phase = _Phase.saving);

    try {
      final file = await _recorder.stop() ?? _path;
      if (file == null) throw ValidationFailure('Es wurde nichts aufgenommen.'.tr);
      if (_seconds < 1) {
        await _files.delete(file);
        throw ValidationFailure('Die Aufnahme war zu kurz.'.tr);
      }
      if (!mounted) return;
      setState(() {
        _phase = _Phase.review;
        _path = file;
      });
    } on ValidationFailure catch (e) {
      _failBack(e.message);
    } catch (_) {
      _failBack('Die Aufnahme konnte nicht gespeichert werden.'.tr);
    }
  }

  Future<void> _togglePlay() async {
    final path = _path;
    if (path == null) return;
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    try {
      await _player.play(path);
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Die Aufnahme konnte nicht abgespielt werden.'.tr);
    }
  }

  /// Sends the reviewed recording to the queue.
  Future<void> _send() async {
    final file = _path;
    if (_phase != _Phase.review || file == null) return;
    await _player.stop();
    setState(() {
      _phase = _Phase.saving;
      _playing = false;
      _error = null;
    });
    try {
      final repo = await ref.read(captureRepositoryProvider.future);
      await repo.saveRecording(jobId: widget.job.id, filePath: file, seconds: _seconds);
      _finish('Aufnahme gespeichert - sie wird dem Auftrag hinzugefügt.'.tr);
    } on ValidationFailure catch (e) {
      _failBack(e.message);
    } catch (_) {
      _failBack('Die Aufnahme konnte nicht gespeichert werden.'.tr);
    }
  }

  /// Throws the reviewed recording away (nothing was sent) and goes back to the start.
  Future<void> _discard() async {
    final file = _path;
    if (_phase != _Phase.review) return;
    await _player.stop();
    if (file != null) await _files.delete(file);
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _playing = false;
      _path = null;
      _seconds = 0;
    });
  }

  Future<void> _sendTyped() async {
    if (_phase == _Phase.saving) return;
    setState(() {
      _phase = _Phase.saving;
      _error = null;
    });
    try {
      final repo = await ref.read(captureRepositoryProvider.future);
      await repo.saveTypedNote(_typed.text, jobId: widget.job.id);
      _finish('Notiz gespeichert - sie wird dem Auftrag hinzugefügt.'.tr);
    } on ValidationFailure catch (e) {
      _failBack(e.message);
    } catch (_) {
      _failBack('Die Notiz konnte nicht gespeichert werden.'.tr);
    }
  }

  void _failBack(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _error = message;
    });
  }

  void _finish(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Which job this note goes to - always visible, so a busy worker cannot record onto the wrong one.
  Widget _banner({required bool enabled}) {
    final customer = widget.customerName;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppTheme.accentAmber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentAmber, width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AUFNAHME FÜR'.tr,
                  style: TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  customer ?? 'Kein Kunde im Auftrag'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(widget.job.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          TextButton(
            onPressed: enabled ? () => Navigator.of(context).pop(RecordCaptureSheet.changeJob) : null,
            child: Text('Ändern'.tr),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recording = _phase == _Phase.recording;
    final saving = _phase == _Phase.saving;
    final reviewing = _phase == _Phase.review;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(color: AppTheme.dividerColor, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 14),
              _banner(enabled: !recording && !saving && !reviewing),
              const SizedBox(height: 14),
              Text('Sprachnotiz aufnehmen'.tr, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Sprich einfach frei: Was wurde gemacht, Arbeitszeit, Material...'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 24),
              if (reviewing) ...[
                Text('Aufnahme {0}'.trf([_clock]), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _togglePlay,
                  icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
                  label: Text(_playing ? 'Anhalten'.tr : 'Anhören'.tr),
                ),
                const SizedBox(height: 8),
                Text('Erst anhören, dann senden. Zahlen und Namen prüfen!'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _discard,
                        icon: const Icon(Icons.delete_outline, color: AppTheme.accentRed),
                        label: Text('Löschen'.tr),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _send,
                        icon: const Icon(Icons.send),
                        label: Text('Senden'.tr),
                      ),
                    ),
                  ],
                ),
              ] else ...[
              Semantics(
                button: true,
                label: recording ? 'Aufnahme stoppen'.tr : 'Aufnahme starten'.tr,
                child: GestureDetector(
                  onTap: saving ? null : (recording ? _stop : _start),
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: recording ? AppTheme.accentRed : AppTheme.accentAmber,
                        boxShadow: [
                          BoxShadow(
                            color: (recording ? AppTheme.accentRed : AppTheme.accentAmber)
                                .withValues(alpha: recording ? 0.5 * _pulse.value : 0.3),
                            blurRadius: recording ? 24 : 16,
                            spreadRadius: recording ? 8 * _pulse.value : 0,
                          ),
                        ],
                      ),
                      child: saving
                          ? const Padding(
                              padding: EdgeInsets.all(28),
                              child: CircularProgressIndicator(strokeWidth: 3, color: AppTheme.primaryDark),
                            )
                          : Icon(
                              recording ? Icons.stop : Icons.mic,
                              size: 44,
                              color: recording ? Colors.white : AppTheme.primaryDark,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                recording
                    ? '{0}  -  Aufnahme läuft (Tippen zum Stoppen)'.trf([_clock])
                    : saving
                        ? 'Wird gespeichert...'.tr
                        : 'Tippen zum Starten'.tr,
                style: TextStyle(
                  color: recording ? AppTheme.accentRed : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (recording)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Höchstens {0} Minuten pro Notiz'.trf([RecordCaptureSheet.maxSeconds ~/ 60]),
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.accentRed)),
                ),
              const SizedBox(height: 16),
              const Divider(color: AppTheme.dividerColor),
              if (!_typing)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: recording || saving || reviewing ? null : () => setState(() => _typing = true),
                      icon: const Icon(Icons.keyboard, size: 18),
                      label: Text('Lieber tippen'.tr),
                    ),
                    TextButton.icon(
                      onPressed: recording || saving || reviewing
                          ? null
                          : () => Navigator.of(context).pop(RecordCaptureSheet.receipt),
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: Text('Beleg'.tr),
                    ),
                  ],
                )
              else ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _typed,
                  enabled: !saving && !recording && !reviewing,
                  maxLines: 4,
                  maxLength: CaptureRepository.maxTypedChars,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'z.B. Steckdose im Keller gesetzt, 2 Stunden, Material 40 Euro'.tr,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: recording || saving || reviewing ? null : _sendTyped,
                    child: Text('Notiz senden'.tr),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

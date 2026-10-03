import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_engine.dart';
import 'sync_providers.dart';

class SyncStatus {
  const SyncStatus({this.running = false, this.lastSyncAt, this.problem, this.rejected = 0});

  final bool running;
  final DateTime? lastSyncAt;
  final SyncProblem? problem;
  final int rejected;

  SyncStatus copyWith({
    bool? running,
    DateTime? lastSyncAt,
    Object? problem = _keep,
    int? rejected,
  }) =>
      SyncStatus(
        running: running ?? this.running,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        problem: identical(problem, _keep) ? this.problem : problem as SyncProblem?,
        rejected: rejected ?? this.rejected,
      );

  static const _keep = Object();
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);

/// Schedules sync runs: at start, after local edits, when the network returns, every few
/// minutes, and on demand. Only one run at a time; a request during a run triggers one more.
class SyncController extends Notifier<SyncStatus> {
  Timer? _debounce;
  Timer? _periodic;
  StreamSubscription<bool>? _connectivity;
  bool _running = false;
  bool _again = false;
  bool _started = false;

  @override
  SyncStatus build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _periodic?.cancel();
      _connectivity?.cancel();
    });
    return const SyncStatus();
  }

  /// Call once the user is signed in and has a business.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _connectivity = ref.read(connectivityChangesProvider).listen((online) {
      if (online) syncNow();
    });
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => syncNow());
    await syncNow();
  }

  /// After a local edit.
  void requestSync() {
    _debounce?.cancel();
    _debounce = Timer(ref.read(syncDebounceProvider), syncNow);
  }

  Future<void>? _current;

  /// Runs a sync. If one is already running, another pass is queued and the returned future
  /// completes when the running one (including that extra pass) is done.
  Future<void> syncNow() {
    if (_running) {
      _again = true;
      return _current!;
    }
    return _current = _run();
  }

  Future<void> _run() async {
    _running = true;
    state = state.copyWith(running: true);
    try {
      do {
        _again = false;
        final engine = await ref.read(syncEngineProvider.future);
        final result = await engine.run();
        final db = await ref.read(scopedDatabaseProvider.future);
        final stored = await db.getMeta(SyncEngine.lastSyncKey);
        state = state.copyWith(
          lastSyncAt: stored == null ? null : DateTime.tryParse(stored)?.toLocal(),
          problem: result.problem,
          rejected: result.rejected,
        );
        // Offline or signed out: an immediate retry cannot help.
        if (result.problem != null) _again = false;
      } while (_again);
    } catch (_) {
      state = state.copyWith(problem: SyncProblem.offline);
    } finally {
      _running = false;
      state = state.copyWith(running: false);
    }
  }
}

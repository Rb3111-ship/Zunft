import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/sync/sync_controller.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/theme/app_theme.dart';
import '../data_providers.dart';

/// Real sync state: pending changes, last successful sync, problems, manual refresh.
class SyncStatusTile extends ConsumerWidget {
  const SyncStatusTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingChangesProvider).valueOrNull ?? 0;

    final (icon, color, title) = switch (status) {
      SyncStatus(running: true) => (Icons.sync, AppTheme.accentAmber, 'Synchronisiere…'.tr),
      SyncStatus(problem: SyncProblem.authExpired) => (Icons.lock_outline, AppTheme.accentRed, 'Bitte erneut anmelden'.tr),
      SyncStatus(problem: SyncProblem.offline) => (Icons.cloud_off, AppTheme.accentAmber, 'Offline'.tr),
      SyncStatus(rejected: > 0) => (Icons.error_outline, AppTheme.accentRed, 'Einige Änderungen wurden abgelehnt'.tr),
      _ => (Icons.cloud_done, AppTheme.accentGreen, 'Synchronisiert'.tr),
    };

    final last = status.lastSyncAt == null
        ? 'Noch nie synchronisiert'.tr
        : 'Letzter Sync: {0}'.trf([DateFormat('dd.MM.yyyy HH:mm'.tr).format(status.lastSyncAt!)]);
    final pendingText =
        pending == 0 ? '' : '\n{0} {1} auf Upload'.trf([pending, pending == 1 ? 'Änderung wartet'.tr : 'Änderungen warten'.tr]);

    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text('$last$pendingText${status.error == null ? '' : '\n${status.error}'}'),
        isThreeLine: pending > 0 || status.error != null,
        trailing: status.running
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh, color: AppTheme.accentAmber),
        onTap: status.running ? null : () => ref.read(syncControllerProvider.notifier).syncNow(),
      ),
    );
  }
}

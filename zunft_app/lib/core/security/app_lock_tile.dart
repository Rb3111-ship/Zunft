import '../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import 'app_lock.dart';

/// "Betrieb" tab: switch the lock of this phone on or off and choose how soon it locks.
class AppLockTile extends ConsumerWidget {
  const AppLockTile({super.key});

  static const _timeouts = {60: 'nach 1 Minute', 300: 'nach 5 Minuten', 900: 'nach 15 Minuten'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final controller = ref.read(appLockProvider.notifier);

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint, color: AppTheme.accentAmber),
            title: Text('App-Sperre'.tr),
            subtitle: Text('Entsperren mit Fingerabdruck, Gesicht oder Handy-PIN. Gilt nur für dieses Handy.'.tr),
            value: lock.enabled,
            onChanged: lock.loaded
                ? (on) async {
                    final problem = await controller.setEnabled(on);
                    if (problem != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
                    }
                  }
                : null,
          ),
          if (lock.enabled)
            ListTile(
              leading: const Icon(Icons.timer_outlined, color: AppTheme.accentAmber),
              title: Text('Sperren'.tr),
              trailing: DropdownButton<int>(
                value: _timeouts.containsKey(lock.timeoutSeconds) ? lock.timeoutSeconds : 60,
                underline: const SizedBox(),
                items: [for (final e in _timeouts.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) {
                  if (v != null) controller.setTimeout(v);
                },
              ),
            ),
        ],
      ),
    );
  }
}

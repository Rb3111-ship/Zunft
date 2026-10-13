import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/reminder_providers.dart';

/// "Betrieb" tab: reminders before appointments, for this phone.
class ReminderTile extends ConsumerWidget {
  const ReminderTile({super.key});

  static Map<int, String> get _leads => {15: '15 Minuten'.tr, 30: '30 Minuten'.tr, 60: '1 Stunde'.tr, 120: '2 Stunden'.tr};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reminderProvider);
    final controller = ref.read(reminderProvider.notifier);

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined, color: AppTheme.accentAmber),
            title: Text('Terminerinnerungen'.tr),
            subtitle: Text('Eine Erinnerung vor deinen Terminen, auch wenn die App zu ist. Gilt nur für dieses Handy.'.tr),
            value: state.enabled,
            onChanged: state.loaded
                ? (on) async {
                    final problem = await controller.setEnabled(on);
                    if (problem != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
                    }
                  }
                : null,
          ),
          if (state.enabled)
            ListTile(
              leading: const Icon(Icons.timer_outlined, color: AppTheme.accentAmber),
              title: Text('Erinnern'.tr),
              trailing: DropdownButton<int>(
                value: _leads.containsKey(state.leadMinutes) ? state.leadMinutes : 30,
                underline: const SizedBox(),
                items: [for (final e in _leads.entries) DropdownMenuItem(value: e.key, child: Text('${e.value} vorher'))],
                onChanged: (v) {
                  if (v != null) controller.setLead(v);
                },
              ),
            ),
        ],
      ),
    );
  }
}

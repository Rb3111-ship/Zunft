import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/push_providers.dart';

/// "Betrieb" tab: messages when the boss gives, moves or cancels an appointment, also with the app closed.
class PushTile extends ConsumerWidget {
  const PushTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final push = ref.watch(pushProvider);
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.campaign_outlined, color: AppTheme.accentAmber),
        title: const Text('Meldungen bei Terminen'),
        subtitle: const Text(
            'Eine Nachricht, wenn dir ein Termin zugeteilt, verschoben oder abgesagt wird, auch wenn die App zu ist. Gilt nur für dieses Handy.'),
        value: push.enabled,
        onChanged: push.loaded
            ? (on) async {
                final problem = await ref.read(pushProvider.notifier).setEnabled(on);
                if (problem != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
                }
              }
            : null,
      ),
    );
  }
}

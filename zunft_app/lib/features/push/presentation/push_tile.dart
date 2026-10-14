import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_providers.dart';
import '../application/push_providers.dart';

/// "Betrieb" tab: messages when the boss gives, moves or cancels an appointment, also with the app closed.
class PushTile extends ConsumerWidget {
  const PushTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final push = ref.watch(pushProvider);
    final manager = ref.watch(profileProvider).valueOrNull?.isManager ?? false;
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.campaign_outlined, color: AppTheme.accentAmber),
        title: Text('Meldungen bei Terminen'.tr),
        subtitle: Text(
          'Eine Nachricht, wenn dir ein Termin zugeteilt, verschoben oder abgesagt wird, auch wenn die App zu ist. Gilt nur für dieses Handy.'.tr +
              (manager ? ' ${'Du bekommst auch eine Nachricht, wenn jemand ein Foto zu einem Auftrag macht.'.tr}' : ''),
        ),
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

import '../../appointments/application/appointment_actions.dart' show externalActionsProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_theme.dart';
import '../../appointments/domain/appointment_models.dart' show dateLabel;
import '../../auth/application/auth_providers.dart';
import '../application/subscription_providers.dart';

/// A strip above the tabs: the free trial is nearly over, a payment is late, or access has ended.
/// Nothing is shown while everything is fine.
class SubscriptionBanner extends ConsumerWidget {
  const SubscriptionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider).valueOrNull;
    if (sub == null) return const SizedBox.shrink();

    String? text;
    var alarm = false;
    if (sub.isReadOnly) {
      text = 'Dein Zugang ist abgelaufen. Du kannst alles ansehen und exportieren, aber nichts Neues anlegen.'.tr;
      alarm = true;
    } else if (sub.isGrace) {
      final until = sub.graceEndsAt;
      text = until == null
          ? 'Zahlung überfällig.'.tr
          : 'Zahlung überfällig: bis {0} funktioniert noch alles.'.trf([dateLabel(until.toLocal())]);
      alarm = true;
    } else {
      final days = sub.trialDaysLeft(DateTime.now());
      if (days != null && days <= 7) {
        text = days == 0
            ? 'Testphase: endet heute.'.tr
            : days == 1
                ? 'Testphase: noch 1 Tag.'.tr
                : 'Testphase: noch {0} Tage.'.trf([days]);
      }
    }
    if (text == null) return const SizedBox.shrink();

    final color = alarm ? AppTheme.accentRed : AppTheme.accentAmber;
    final isOwner = ref.watch(profileProvider).valueOrNull?.isOwner ?? false;
    return Container(
      key: const ValueKey('subscription-banner'),
      width: double.infinity,
      color: color.withValues(alpha: 0.18),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(alarm ? Icons.lock_outline : Icons.hourglass_bottom, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          if (isOwner)
            TextButton(
              key: const ValueKey('renew-button'),
              onPressed: () => openBilling(context, ref),
              child: Text(sub.isTrial && !sub.isReadOnly ? 'Abo abschließen'.tr : 'Abo verlängern'.tr),
            ),
        ],
      ),
    );
  }
}

/// Call before something is created. If the business's access has ended, tells the person why
/// nothing new is possible and returns false.
Future<bool> ensureWritable(BuildContext context, WidgetRef ref) async {
  if (!ref.read(readOnlyProvider)) return true;
  final isOwner = ref.read(profileProvider).valueOrNull?.isOwner ?? false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Zugang abgelaufen'.tr),
      content: Text(
        'Neue Aufträge, Notizen, Belege, Termine, Zeiten und Rechnungen sind erst nach Verlängerung des Abos möglich. Alles Vorhandene bleibt les- und exportierbar.'.tr +
            (isOwner ? '' : '\n\n${'Bitte wende dich an den Inhaber des Betriebs.'.tr}'),
      ),
      actions: [
        if (isOwner)
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openBilling(context, ref);
            },
            child: Text('Abo verlängern'.tr),
          ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK'.tr)),
      ],
    ),
  );
  return false;
}

/// Opens the page where the owner subscribes or renews. Without an address (not set up yet) it says so.
Future<void> openBilling(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final url = ref.read(billingUrlProvider).trim();
  final uri = url.isEmpty ? null : Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    messenger.showSnackBar(SnackBar(content: Text('Die Bezahlseite ist noch nicht eingerichtet. Bitte melde dich bei uns.'.tr)));
    return;
  }
  final ok = await ref.read(externalActionsProvider).openUrl(uri);
  if (!ok) messenger.showSnackBar(SnackBar(content: Text('Die Seite konnte nicht geöffnet werden.'.tr)));
}

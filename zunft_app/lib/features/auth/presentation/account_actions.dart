import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/sync_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../application/auth_providers.dart';
import '../data/auth_repository.dart';

/// "Betrieb verlassen": ends the link to the business. The account stays; the person can then
/// start their own business or join another one. The phone forgets the business's data.
Future<void> confirmLeaveBusiness(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Betrieb verlassen?'.tr),
      content: Text(
        'Du verlierst den Zugang zu allen Aufträgen und Kunden dieses Betriebs. Deine Notizen bleiben dort erhalten. Dein Konto bleibt bestehen: du kannst einen eigenen Betrieb gründen oder einem anderen beitreten.'.tr,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Abbrechen'.tr)),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Verlassen'.tr, style: TextStyle(color: AppTheme.accentRed)),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(authRepositoryProvider).leaveBusiness();
    await forgetBusinessDataOnDevice(ref);
    ref.invalidate(profileProvider);
  } on AuthFailure catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// "Konto löschen": erases the account itself. An owner cannot do this in the app: the business's
/// invoices have to be kept by law, so closing a business is a deliberate step.
Future<void> confirmDeleteAccount(BuildContext context, WidgetRef ref, {required bool isOwner}) async {
  if (isOwner) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Konto des Inhabers'.tr),
        content: Text(
          'Ein Betrieb kann nicht mit einem Tipp gelöscht werden: Rechnungen müssen gesetzlich über Jahre aufbewahrt werden (GoBD). Wenn du deinen Betrieb schließen oder dein Konto löschen möchtest, wende dich bitte an den Support. Mitarbeiter kannst du unter „Team“ entfernen.'.tr,
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK'.tr))],
      ),
    );
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Konto endgültig löschen?'.tr),
      content: Text(
        'Dein Konto und dein Zugang werden gelöscht. Das kann nicht rückgängig gemacht werden. Notizen, die du für einen Betrieb aufgenommen hast, bleiben dort beim Auftrag (nur dein Name als Text).'.tr,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Abbrechen'.tr)),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Konto löschen'.tr, style: TextStyle(color: AppTheme.accentRed)),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(authRepositoryProvider).deleteAccount();
    await forgetBusinessDataOnDevice(ref);
  } on AuthFailure catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Removes everything of the business from this phone (jobs, customers, queued notes, documents).
Future<void> forgetBusinessDataOnDevice(WidgetRef ref) => ref.read(appDatabaseProvider).wipeAll();

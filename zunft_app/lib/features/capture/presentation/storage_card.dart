import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/capture_providers.dart';

/// "Speicher": how much of the plan's storage is used. Shown to boss and office.
class StorageCard extends ConsumerWidget {
  const StorageCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(storageStatusProvider).valueOrNull;
    if (status == null) return const SizedBox.shrink();
    final color = status.full
        ? AppTheme.accentRed
        : status.nearlyFull
            ? AppTheme.accentAmber
            : AppTheme.accentGreen;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_outlined, color: AppTheme.accentAmber),
                const SizedBox(width: 12),
                Expanded(child: Text('Speicher'.tr, style: TextStyle(fontWeight: FontWeight.bold))),
                Text(status.label, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: status.fraction, color: color, backgroundColor: AppTheme.dividerColor),
            if (status.full || status.nearlyFull)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  status.full
                      ? 'Der Speicher ist voll: neue Aufnahmen und Belege werden abgelehnt. Für mehr Speicher wird ein größeres Paket gebraucht. Rechnungen können weiter erstellt werden.'.tr
                      : 'Der Speicher ist fast voll. Für mehr Speicher wird ein größeres Paket gebraucht.'.tr,
                  style: TextStyle(color: color, fontSize: 12.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

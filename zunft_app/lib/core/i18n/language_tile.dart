import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import 'i18n.dart';

/// "Betrieb" tab: choose the language of the screens.
class LanguageTile extends ConsumerWidget {
  const LanguageTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(languageProvider);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.language, color: AppTheme.accentAmber),
        title: Text('Sprache'.tr),
        subtitle: Text(I18n.language.nativeName),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary),
        onTap: () => pickLanguage(context, ref),
      ),
    );
  }
}

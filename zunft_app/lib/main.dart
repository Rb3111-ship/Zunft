import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/i18n/i18n.dart';
import 'core/navigation/navigator_key.dart';
import 'core/security/app_lock.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Env.isConfigured) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  }

  await I18n.load();
  runApp(const ProviderScope(child: ZunftApp()));
}

class ZunftApp extends ConsumerWidget {
  const ZunftApp({super.key, this.home});

  /// Overridable for widget tests; defaults to the auth gate (or a setup hint without config).
  final Widget? home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    return MaterialApp(
      navigatorKey: ref.watch(navigatorKeyProvider),
      title: 'Zunft - Handwerker Back-Office',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      builder: appLockBuilder,
      locale: appLanguages.firstWhere((l) => l.code == lang, orElse: () => appLanguages.first).locale,
      supportedLocales: [for (final l in appLanguages) l.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // a new key rebuilds every screen when the language changes
      home: KeyedSubtree(
        key: ValueKey(lang),
        child: home ?? (Env.isConfigured ? const AuthGate() : const _MissingConfigScreen()),
      ),
    );
  }
}

class _MissingConfigScreen extends StatelessWidget {
  const _MissingConfigScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Zunft ist nicht konfiguriert.\n\n'
            'Starte die App mit:\n'
            'flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

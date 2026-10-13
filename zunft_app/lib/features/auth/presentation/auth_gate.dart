import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../core/theme/app_theme.dart';
import '../../push/application/push_providers.dart';
import '../application/auth_providers.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

/// Decides what to show: login, business onboarding, or the app.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionUserIdProvider);

    return session.when(
      loading: () => const _Splash(),
      error: (e, _) => _RetryScreen(onRetry: () => ref.invalidate(sessionUserIdProvider)),
      data: (userId) {
        if (userId == null) return const LoginScreen();

        final profile = ref.watch(profileProvider);
        return profile.when(
          loading: () => const _Splash(),
          error: (e, _) => _RetryScreen(
            message: 'Profil konnte nicht geladen werden.'.tr,
            onRetry: () => ref.invalidate(profileProvider),
            onSignOut: () => signOutAndForgetPhone(ref),
          ),
          data: (p) {
            if (p == null) return OnboardingScreen();
            if (!p.active) return _SwitchedOffScreen();
            return ZunftAppShell();
          },
        );
      },
    );
  }
}

/// The owner switched this person's access off. Nothing of the business is shown.
class _SwitchedOffScreen extends ConsumerWidget {
  _SwitchedOffScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 48, color: AppTheme.textSecondary),
              SizedBox(height: 12),
              Text('Dein Zugang wurde abgeschaltet.'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Bitte wende dich an den Inhaber des Betriebs. Deine bisherigen Notizen bleiben im Betrieb erhalten.'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              SizedBox(height: 16),
              FilledButton(onPressed: () => signOutAndForgetPhone(ref), child: Text('Abmelden'.tr)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.accentAmber)));
}

class _RetryScreen extends StatelessWidget {
  const _RetryScreen({
    this.message,
    required this.onRetry,
    this.onSignOut,
  });

  final String? message;
  final VoidCallback onRetry;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: AppTheme.textSecondary),
              const SizedBox(height: 12),
              Text(message ?? 'Keine Verbindung.'.tr, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: Text('Erneut versuchen'.tr)),
              if (onSignOut != null) TextButton(onPressed: onSignOut, child: Text('Abmelden'.tr)),
            ],
          ),
        ),
      ),
    );
  }
}

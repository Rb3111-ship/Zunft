import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../core/theme/app_theme.dart';
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
            message: 'Profil konnte nicht geladen werden.',
            onRetry: () => ref.invalidate(profileProvider),
            onSignOut: () => ref.read(authRepositoryProvider).signOut(),
          ),
          data: (p) => p == null ? const OnboardingScreen() : const ZunftAppShell(),
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.accentAmber)));
}

class _RetryScreen extends StatelessWidget {
  const _RetryScreen({
    this.message = 'Keine Verbindung.',
    required this.onRetry,
    this.onSignOut,
  });

  final String message;
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
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Erneut versuchen')),
              if (onSignOut != null) TextButton(onPressed: onSignOut, child: const Text('Abmelden')),
            ],
          ),
        ),
      ),
    );
  }
}

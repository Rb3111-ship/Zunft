import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/trade_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../application/auth_providers.dart';
import '../data/auth_repository.dart';
import 'account_actions.dart';
import 'join_business_screen.dart';

/// Shown once after the first sign-in: creates the business and the owner profile.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessName = TextEditingController();
  final _ownerName = TextEditingController();
  String _trade = TradeConstants.tradeElektro;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _businessName.dispose();
    _ownerName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).createBusiness(
            businessName: _businessName.text.trim(),
            ownerName: _ownerName.text.trim(),
            tradeCategory: _trade,
          );
      // The gate shows the app once the profile exists.
      ref.invalidate(profileProvider);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Betrieb einrichten'),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('Abmelden'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Willkommen bei Zunft! Zwei Angaben genügen für den Start. '
                  'Anschrift, Steuernummer und IBAN trägst du später unter „Betrieb“ ein.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _businessName,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Betriebsname', border: OutlineInputBorder()),
                  validator: (v) => Validators.required(v, 'Betriebsname'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _ownerName,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Dein Name (Inhaber)', border: OutlineInputBorder()),
                  validator: (v) => Validators.required(v, 'Name'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _trade,
                  decoration: const InputDecoration(labelText: 'Gewerk', border: OutlineInputBorder()),
                  items: [
                    for (final e in TradeConstants.tradeLabels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _trade = v ?? _trade),
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: AppTheme.accentRed)),
                  ),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('Los geht\'s'),
                  ),
                ),
                const SizedBox(height: 28),
                const Divider(color: AppTheme.dividerColor),
                const SizedBox(height: 8),
                const Text(
                  'Dein Chef hat dich eingeladen?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JoinBusinessScreen())),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Mit Einladungscode beitreten'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => confirmDeleteAccount(context, ref, isOwner: false),
                  child: const Text('Konto löschen', style: TextStyle(color: AppTheme.accentRed)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

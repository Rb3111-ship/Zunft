import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/trade_constants.dart';
import 'trade_picker.dart';
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
  bool _creating = false; // false: the first question; true: the form for a new business
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

  /// The first question: owner or invited. Two equal, clearly worded choices, because creating a
  /// business by mistake (instead of joining one) locks the account into an empty business.
  Widget _choice() {
    Widget option({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) =>
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _busy ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(icon, size: 34, color: AppTheme.accentAmber),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textSecondary),
                ],
              ),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text('Willkommen bei Zunft'.tr),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => ref.read(authRepositoryProvider).signOut(),
            child: Text('Abmelden'.tr),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Wie geht es los?'.tr, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              option(
                icon: Icons.storefront_outlined,
                title: 'Ich bin Inhaber'.tr,
                subtitle: 'Ich richte meinen eigenen Betrieb ein.'.tr,
                onTap: () => setState(() => _creating = true),
              ),
              const SizedBox(height: 12),
              option(
                icon: Icons.qr_code_scanner,
                title: 'Ich wurde eingeladen'.tr,
                subtitle: 'Mein Chef hat mir einen Code oder QR-Code gegeben.'.tr,
                onTap: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const JoinBusinessScreen())),
              ),
              const SizedBox(height: 28),
              TextButton(
                onPressed: _busy ? null : () => confirmDeleteAccount(context, ref, isOwner: false),
                child: Text('Konto löschen'.tr, style: TextStyle(color: AppTheme.accentRed)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_creating) return _choice();
    return Scaffold(
      appBar: AppBar(
        title: Text('Betrieb einrichten'.tr),
        leading: IconButton(
          tooltip: 'Zurück'.tr,
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy ? null : () => setState(() => _creating = false),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => ref.read(authRepositoryProvider).signOut(),
            child: Text('Abmelden'.tr),
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.accentAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.accentAmber),
                  ),
                  child: Text(
                    'Das legt einen NEUEN Betrieb an, dem du als Inhaber gehörst. Wurdest du von deinem Chef eingeladen? Dann geh zurück und wähle „Ich wurde eingeladen“.'.tr,
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Zwei Angaben genügen für den Start. Anschrift, Steuernummer und IBAN trägst du später unter „Betrieb“ ein.'.tr,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _businessName,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: 'Betriebsname'.tr, border: OutlineInputBorder()),
                  validator: (v) => Validators.required(v, 'Betriebsname'.tr),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _ownerName,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(labelText: 'Dein Name (Inhaber)'.tr, border: OutlineInputBorder()),
                  validator: (v) => Validators.required(v, 'Name'.tr),
                ),
                const SizedBox(height: 14),
                TradePicker(initialValue: _trade, onChanged: (v) => _trade = v),
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
                        : Text('Los geht\'s'.tr),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

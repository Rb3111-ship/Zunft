import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../team/domain/team_models.dart';
import '../../team/presentation/scan_code_screen.dart';
import '../application/auth_providers.dart';
import '../data/auth_repository.dart';
import 'privacy_notice_screen.dart';

/// For an employee: join the boss's business with the invitation code (typed or scanned).
/// The person has registered with their own e-mail, so they have their own login.
class JoinBusinessScreen extends ConsumerStatefulWidget {
  const JoinBusinessScreen({super.key});

  @override
  ConsumerState<JoinBusinessScreen> createState() => _JoinBusinessScreenState();
}

class _JoinBusinessScreenState extends ConsumerState<JoinBusinessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _noticeRead = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final raw = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanCodeScreen()));
    if (raw == null || !mounted) return;
    final code = parseInviteCode(raw);
    setState(() {
      if (code != null) {
        _code.text = code;
        _error = null;
      } else {
        _error = 'Das ist kein Einladungscode von Zunft.'.tr;
      }
    });
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .joinBusiness(code: parseInviteCode(_code.text)!, fullName: _name.text.trim());
      if (!mounted) return;
      // Back to the root: the gate shows the app now that the profile exists.
      Navigator.of(context).popUntil((route) => route.isFirst);
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
      appBar: AppBar(title: Text('Betrieb beitreten'.tr)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Dein Chef zeigt dir in der App unter „Betrieb → Team“ einen QR-Code und einen Code mit 8 Zeichen. Scanne den QR-Code oder tippe den Code ein.'.tr,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: 'Dein Name'.tr, border: OutlineInputBorder()),
                  validator: (v) => Validators.required(v, 'Name'.tr),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Einladungscode'.tr,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'QR-Code scannen'.tr,
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: _busy ? null : _scan,
                    ),
                  ),
                  validator: (v) =>
                      parseInviteCode(v) == null ? 'Der Code besteht aus 8 Zeichen (Buchstaben und Ziffern).'.tr : null,
                ),
                const SizedBox(height: 14),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _noticeRead,
                  onChanged: _busy ? null : (v) => setState(() => _noticeRead = v ?? false),
                  title: Text('Ich habe den Datenschutzhinweis für Mitarbeiter gelesen.'.tr,
                      style: TextStyle(fontSize: 13.5)),
                  subtitle: TextButton(
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero, minimumSize: const Size(0, 28), alignment: Alignment.centerLeft),
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyNoticeScreen())),
                    child: Text('Hinweis lesen'.tr),
                  ),
                ),
                const SizedBox(height: 6),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: AppTheme.accentRed)),
                  ),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy || !_noticeRead ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Text('Beitreten'.tr),
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

import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../auth/application/auth_providers.dart';
import '../application/team_providers.dart';
import '../data/team_remote.dart';
import '../domain/team_models.dart';

/// Owner only: who is in the business, invitations (QR code + short code), seats, switching
/// people off. Employees register with their own e-mail and join with the code, so everybody
/// has a personal login.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(teamOverviewProvider);
    final me = ref.watch(profileProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text('Team'.tr)),
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accentAmber)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e is TeamException ? e.message : 'Das Team konnte nicht geladen werden.'.tr,
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () => ref.invalidate(teamOverviewProvider), child: Text('Erneut versuchen'.tr)),
              ],
            ),
          ),
        ),
        data: (o) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _seatsCard(o),
            const SizedBox(height: 12),
            _createSwitch(context, ref),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: o.freeSeats == 0 ? null : () => _invite(context, ref),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text('Mitarbeiter einladen'.tr),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
            if (o.freeSeats == 0)
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Alle Plätze sind belegt. Für mehr Personen wird ein größeres Paket gebraucht.'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.accentAmber, fontSize: 12.5),
                ),
              ),
            if (o.invites.isNotEmpty) ...[
              const SizedBox(height: 20),
              _Heading('OFFENE EINLADUNGEN'.tr),
              for (final i in o.invites) _inviteTile(context, ref, i),
            ],
            const SizedBox(height: 20),
            _Heading('PERSONEN'.tr),
            for (final m in o.members) _memberTile(context, ref, m, isMe: m.id == me?.id, rates: ref.watch(memberRatesProvider).valueOrNull ?? const {}),
          ],
        ),
      ),
    );
  }

  Widget _createSwitch(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(businessProvider).valueOrNull?.employeesCanCreate ?? false;
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.edit_note, color: AppTheme.accentAmber),
        title: Text('Mitarbeiter dürfen Kunden und Aufträge anlegen'.tr),
        subtitle: Text(allowed
            ? 'Meister und Gesellen können eigene Kunden und Aufträge erstellen. Inhaber und Büro dürfen das immer.'.tr
            : 'Aus: Meister und Gesellen arbeiten nur an Aufträgen, die du oder das Büro ihnen zuweisen.'.tr),
        value: allowed,
        onChanged: (v) async {
          try {
            await ref.read(authRepositoryProvider).setEmployeesCanCreate(v);
            ref.invalidate(businessProvider);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Die Einstellung konnte nicht gespeichert werden.'.tr)));
            }
          }
        },
      ),
    );
  }

  Widget _seatsCard(TeamOverview o) => Card(
        color: AppTheme.primaryDark,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.groups, color: AppTheme.accentAmber),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('{0} von {1} Plätzen belegt'.trf([o.seatsInUse, o.seatLimit]),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      '{0} aktiv'.trf([o.activeMembers]) +
                          (o.invites.isEmpty
                              ? ''
                              : ', ${o.invites.length == 1 ? '1 Einladung offen'.tr : '{0} Einladungen offen'.trf([o.invites.length])}'),
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _inviteTile(BuildContext context, WidgetRef ref, TeamInvite i) => Card(
        child: ListTile(
          leading: const Icon(Icons.qr_code_2, color: AppTheme.accentAmber),
          title: Text('${Roles.label(i.role)} - ${i.code}', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('gültig bis {0}'.trf([DateFormatter.formatDate(i.expiresAt)])),
          trailing: IconButton(
            tooltip: 'Einladung zurückziehen'.tr,
            icon: const Icon(Icons.close),
            onPressed: () => _revoke(context, ref, i),
          ),
          onTap: () => _showInvite(context, i),
        ),
      );

  Widget _memberTile(BuildContext context, WidgetRef ref, TeamMember m, {required bool isMe, required Map<String, int> rates}) {
    final canSwitch = !isMe && m.role != Roles.owner;
    final rate = rates[m.id];
    return Card(
      child: ListTile(
        onTap: () => _editRate(context, ref, m, rate),
        leading: Icon(m.active ? Icons.person : Icons.person_off,
            color: m.active ? AppTheme.accentAmber : AppTheme.textSecondary),
        title: Text(isMe ? '{0} (du)'.trf([m.fullName]) : m.fullName,
            style: TextStyle(fontWeight: FontWeight.bold, color: m.active ? null : AppTheme.textSecondary)),
        subtitle: Text([
          Roles.label(m.role),
          if (rate != null) 'Stundensatz {0}'.trf([CurrencyFormatter.formatCents(rate)]),
          if (!m.active) 'Zugang abgeschaltet'.tr,
        ].join(' - ')),
        trailing: canSwitch
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => _toggle(context, ref, m),
                    child: Text(m.active ? 'Abschalten'.tr : 'Einschalten'.tr),
                  ),
                  IconButton(
                    tooltip: 'Aus dem Betrieb entfernen'.tr,
                    icon: const Icon(Icons.person_remove_outlined, color: AppTheme.accentRed),
                    onPressed: () => _remove(context, ref, m),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  /// The hourly rate used when this person's tracked time is billed. Empty = the business's rate.
  Future<void> _editRate(BuildContext context, WidgetRef ref, TeamMember m, int? current) async {
    final result = await showDialog<_RateChoice>(context: context, builder: (_) => _RateDialog(name: m.fullName, currentCents: current));
    if (result == null || !context.mounted) return;
    try {
      await ref.read(teamRemoteProvider).setRate(m.id, result.cents);
      ref.invalidate(memberRatesProvider);
    } on TeamException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final role = await showDialog<String>(context: context, builder: (_) => const _RoleDialog());
    if (role == null || !context.mounted) return;
    try {
      final invite = await ref.read(teamRemoteProvider).createInvite(role);
      ref.invalidate(teamOverviewProvider);
      if (context.mounted) await _showInvite(context, invite);
    } on TeamException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  Future<void> _showInvite(BuildContext context, TeamInvite invite) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Einladung: {0}'.trf([Roles.label(invite.role)])),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Die Person installiert Zunft, registriert sich mit der eigenen E-Mail und scannt diesen Code (oder tippt ihn ein).'.tr,
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 14),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(10),
                  // Drawn directly: QrImageView uses a LayoutBuilder, which a dialog cannot measure.
                  child: CustomPaint(
                    key: const ValueKey('invite-qr'),
                    size: const Size(200, 200),
                    painter: QrPainter(data: invite.qrData, version: QrVersions.auto, gapless: true),
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(invite.code,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 4)),
                const SizedBox(height: 4),
                Text('Einmal benutzbar, gültig bis {0}'.trf([DateFormatter.formatDate(invite.expiresAt)]),
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Fertig'.tr))],
        ),
      );

  Future<void> _revoke(BuildContext context, WidgetRef ref, TeamInvite i) async {
    final ok = await _confirm(
        context, 'Einladung zurückziehen?'.tr, 'Der Code {0} funktioniert danach nicht mehr.'.trf([i.code]), 'Zurückziehen'.tr);
    if (ok != true || !context.mounted) return;
    await _run(context, () => ref.read(teamRemoteProvider).revokeInvite(i.id));
    ref.invalidate(teamOverviewProvider);
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, TeamMember m) async {
    final off = m.active;
    final ok = await _confirm(
      context,
      off ? '${m.fullName} abschalten?' : '{0} wieder einschalten?'.trf([m.fullName]),
      off
          ? 'Die Person kommt sofort nicht mehr in den Betrieb. Ihre Notizen bleiben erhalten. Der Platz wird frei.'.tr
          : 'Die Person bekommt wieder Zugang (und belegt einen Platz).'.tr,
      off ? 'Abschalten'.tr : 'Einschalten'.tr,
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () => ref.read(teamRemoteProvider).setMemberActive(m.id, !off));
    ref.invalidate(teamOverviewProvider);
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, TeamMember m) async {
    final ok = await _confirm(
      context,
      '{0} entfernen?'.trf([m.fullName]),
      'Die Person verliert sofort jede Verbindung zu deinem Betrieb: keine Aufträge, keine Kunden, keine Daten. Ihre bisherigen Notizen bleiben bei den Aufträgen (mit ihrem Namen). Ihr Konto gehört ihr: sie kann damit einen eigenen Betrieb gründen oder einem anderen beitreten. Der Platz wird frei.'.tr,
      'Entfernen'.tr,
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () => ref.read(teamRemoteProvider).removeMember(m.id));
    ref.invalidate(teamOverviewProvider);
  }

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } on TeamException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  void _snack(BuildContext context, String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<bool?> _confirm(BuildContext context, String title, String text, String action) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Abbrechen'.tr)),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
          ],
        ),
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
      );
}

/// Which role the invited person gets.
class _RateChoice {
  const _RateChoice(this.cents);

  /// null = back to the business's default rate.
  final int? cents;
}

class _RateDialog extends StatefulWidget {
  const _RateDialog({required this.name, required this.currentCents});

  final String name;
  final int? currentCents;

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  late final TextEditingController _c = TextEditingController(
      text: widget.currentCents == null ? '' : (widget.currentCents! / 100).toStringAsFixed(2).replaceAll('.', ','));
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final cents = CurrencyFormatter.parseToCents(_c.text);
    if (cents == null || cents > 100000) {
      setState(() => _error = 'Bitte einen Betrag zwischen 0 und 1.000 Euro eintragen, zum Beispiel 75,00.'.tr);
      return;
    }
    Navigator.pop(context, _RateChoice(cents));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Stundensatz: {0}'.trf([widget.name])),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mit diesem Satz (netto) wird die erfasste Arbeitszeit dieser Person abgerechnet. Leer lassen: der Stundensatz des Betriebs. Der Satz ist nur für Inhaber und Büro sichtbar.'.tr,
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Euro pro Stunde (netto)'.tr, border: const OutlineInputBorder(), errorText: _error),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Abbrechen'.tr)),
        if (widget.currentCents != null)
          TextButton(onPressed: () => Navigator.pop(context, const _RateChoice(null)), child: Text('Standard verwenden'.tr)),
        FilledButton(onPressed: _save, child: Text('Speichern'.tr)),
      ],
    );
  }
}

class _RoleDialog extends StatefulWidget {
  const _RoleDialog();

  @override
  State<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends State<_RoleDialog> {
  String _role = Roles.geselle;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Wen möchtest du einladen?'.tr),
      content: SingleChildScrollView(
        child: RadioGroup<String>(
          groupValue: _role,
          onChanged: (v) => setState(() => _role = v ?? _role),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in Roles.invitable)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: r,
                  title: Text(Roles.label(r)),
                  subtitle: Text(Roles.descriptions[r] ?? '', style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Abbrechen'.tr)),
        FilledButton(onPressed: () => Navigator.pop(context, _role), child: Text('Einladung erstellen'.tr)),
      ],
    );
  }
}

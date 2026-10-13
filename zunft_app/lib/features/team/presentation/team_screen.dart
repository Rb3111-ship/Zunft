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
      appBar: AppBar(title: const Text('Team')),
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accentAmber)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e is TeamException ? e.message : 'Das Team konnte nicht geladen werden.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () => ref.invalidate(teamOverviewProvider), child: const Text('Erneut versuchen')),
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
              label: const Text('Mitarbeiter einladen'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
            if (o.freeSeats == 0)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Alle Plätze sind belegt. Für mehr Personen wird ein größeres Paket gebraucht.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.accentAmber, fontSize: 12.5),
                ),
              ),
            if (o.invites.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _Heading('OFFENE EINLADUNGEN'),
              for (final i in o.invites) _inviteTile(context, ref, i),
            ],
            const SizedBox(height: 20),
            const _Heading('PERSONEN'),
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
        title: const Text('Mitarbeiter dürfen Kunden und Aufträge anlegen'),
        subtitle: Text(allowed
            ? 'Meister und Gesellen können eigene Kunden und Aufträge erstellen. Inhaber und Büro dürfen das immer.'
            : 'Aus: Meister und Gesellen arbeiten nur an Aufträgen, die du oder das Büro ihnen zuweisen.'),
        value: allowed,
        onChanged: (v) async {
          try {
            await ref.read(authRepositoryProvider).setEmployeesCanCreate(v);
            ref.invalidate(businessProvider);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Die Einstellung konnte nicht gespeichert werden.')));
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
                    Text('${o.seatsInUse} von ${o.seatLimit} Plätzen belegt',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      '${o.activeMembers} aktiv${o.invites.isEmpty ? '' : ', ${o.invites.length} Einladung${o.invites.length == 1 ? '' : 'en'} offen'}',
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
          subtitle: Text('gültig bis ${DateFormatter.formatDate(i.expiresAt)}'),
          trailing: IconButton(
            tooltip: 'Einladung zurückziehen',
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
        title: Text(isMe ? '${m.fullName} (du)' : m.fullName,
            style: TextStyle(fontWeight: FontWeight.bold, color: m.active ? null : AppTheme.textSecondary)),
        subtitle: Text([
          Roles.label(m.role),
          if (rate != null) 'Stundensatz ${CurrencyFormatter.formatCents(rate)}',
          if (!m.active) 'Zugang abgeschaltet',
        ].join(' - ')),
        trailing: canSwitch
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => _toggle(context, ref, m),
                    child: Text(m.active ? 'Abschalten' : 'Einschalten'),
                  ),
                  IconButton(
                    tooltip: 'Aus dem Betrieb entfernen',
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
          title: Text('Einladung: ${Roles.label(invite.role)}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Die Person installiert Zunft, registriert sich mit der eigenen E-Mail und scannt diesen Code '
                  '(oder tippt ihn ein).',
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
                Text('Einmal benutzbar, gültig bis ${DateFormatter.formatDate(invite.expiresAt)}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fertig'))],
        ),
      );

  Future<void> _revoke(BuildContext context, WidgetRef ref, TeamInvite i) async {
    final ok = await _confirm(
        context, 'Einladung zurückziehen?', 'Der Code ${i.code} funktioniert danach nicht mehr.', 'Zurückziehen');
    if (ok != true || !context.mounted) return;
    await _run(context, () => ref.read(teamRemoteProvider).revokeInvite(i.id));
    ref.invalidate(teamOverviewProvider);
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, TeamMember m) async {
    final off = m.active;
    final ok = await _confirm(
      context,
      off ? '${m.fullName} abschalten?' : '${m.fullName} wieder einschalten?',
      off
          ? 'Die Person kommt sofort nicht mehr in den Betrieb. Ihre Notizen bleiben erhalten. Der Platz wird frei.'
          : 'Die Person bekommt wieder Zugang (und belegt einen Platz).',
      off ? 'Abschalten' : 'Einschalten',
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () => ref.read(teamRemoteProvider).setMemberActive(m.id, !off));
    ref.invalidate(teamOverviewProvider);
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, TeamMember m) async {
    final ok = await _confirm(
      context,
      '${m.fullName} entfernen?',
      'Die Person verliert sofort jede Verbindung zu deinem Betrieb: keine Aufträge, keine Kunden, keine Daten. '
          'Ihre bisherigen Notizen bleiben bei den Aufträgen (mit ihrem Namen). '
          'Ihr Konto gehört ihr: sie kann damit einen eigenen Betrieb gründen oder einem anderen beitreten. '
          'Der Platz wird frei.',
      'Entfernen',
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
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
      setState(() => _error = 'Bitte einen Betrag zwischen 0 und 1.000 Euro eintragen, zum Beispiel 75,00.');
      return;
    }
    Navigator.pop(context, _RateChoice(cents));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Stundensatz: ${widget.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mit diesem Satz (netto) wird die erfasste Arbeitszeit dieser Person abgerechnet. Leer lassen: der Stundensatz des Betriebs. Der Satz ist nur für Inhaber und Büro sichtbar.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Euro pro Stunde (netto)', border: const OutlineInputBorder(), errorText: _error),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        if (widget.currentCents != null)
          TextButton(onPressed: () => Navigator.pop(context, const _RateChoice(null)), child: const Text('Standard verwenden')),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
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
      title: const Text('Wen möchtest du einladen?'),
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(context, _role), child: const Text('Einladung erstellen')),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_theme.dart';
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
                Text(e is TeamException ? e.message : 'Das Team konnte nicht geladen werden.', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => ref.invalidate(teamOverviewProvider), child: const Text('Erneut versuchen')),
              ],
            ),
          ),
        ),
        data: (o) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _seatsCard(o),
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
            for (final m in o.members) _memberTile(context, ref, m, isMe: m.id == me?.id),
          ],
        ),
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
                    Text('${o.seatsInUse} von ${o.seatLimit} Plätzen belegt', style: const TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _memberTile(BuildContext context, WidgetRef ref, TeamMember m, {required bool isMe}) {
    final canSwitch = !isMe && m.role != Roles.owner;
    return Card(
      child: ListTile(
        leading: Icon(m.active ? Icons.person : Icons.person_off, color: m.active ? AppTheme.accentAmber : AppTheme.textSecondary),
        title: Text(isMe ? '${m.fullName} (du)' : m.fullName, style: TextStyle(fontWeight: FontWeight.bold, color: m.active ? null : AppTheme.textSecondary)),
        subtitle: Text(m.active ? Roles.label(m.role) : '${Roles.label(m.role)} - Zugang abgeschaltet'),
        trailing: canSwitch
            ? TextButton(
                onPressed: () => _toggle(context, ref, m),
                child: Text(m.active ? 'Abschalten' : 'Einschalten'),
              )
            : null,
      ),
    );
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
                SelectableText(invite.code, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 4)),
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
    final ok = await _confirm(context, 'Einladung zurückziehen?', 'Der Code ${i.code} funktioniert danach nicht mehr.', 'Zurückziehen');
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

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } on TeamException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  void _snack(BuildContext context, String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

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
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
      );
}

/// Which role the invited person gets.
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

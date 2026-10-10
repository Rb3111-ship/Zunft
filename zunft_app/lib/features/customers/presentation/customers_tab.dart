import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/refresh_all.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../data/data_providers.dart';
import '../../../core/utils/customer_duplicates.dart';
import 'customer_edit_screen.dart';
import 'customer_merge_screens.dart';

String customerDisplayName(Customer c) => [c.firstName, c.name].where((s) => (s ?? '').isNotEmpty).join(' ');

/// Case-insensitive match on name, address and phone.
bool customerMatches(Customer c, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final haystack =
      [c.name, c.firstName, c.street, c.zip, c.city, c.phone, c.email].whereType<String>().join(' ').toLowerCase();
  return q.split(RegExp(r'\s+')).every(haystack.contains);
}

class CustomersTab extends ConsumerStatefulWidget {
  const CustomersTab({super.key});

  @override
  ConsumerState<CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends ConsumerState<CustomersTab> {
  String _query = '';

  void _open([Customer? customer]) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerEditScreen(customer: customer)));
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider);
    final canCreate = ref.watch(canCreateRecordsProvider);
    final manager = ref.watch(profileProvider).valueOrNull?.isManager ?? false;

    return RefreshIndicator(
      onRefresh: () => refreshAll(ref),
      child: customers.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accentAmber)),
      error: (e, _) => Center(
        child: TextButton(
            onPressed: () => ref.invalidate(customersProvider),
            child: const Text('Kunden konnten nicht geladen werden. Erneut versuchen')),
      ),
      data: (all) {
        final shown = all.where((c) => customerMatches(c, _query)).toList();
        final duplicates = manager ? findDuplicatePairs(all).length : 0;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Kunde suchen (Name, Straße, Telefon)...',
                      prefixIcon: const Icon(Icons.search, color: AppTheme.accentAmber),
                      filled: true,
                      fillColor: AppTheme.surfaceCard,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                if (canCreate) ...[
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Kunde anlegen',
                    onPressed: () => _open(),
                    icon: const Icon(Icons.person_add),
                  ),
                ],
              ],
            ),
            if (duplicates > 0)
              Card(
                margin: const EdgeInsets.only(top: 12),
                color: AppTheme.accentAmber.withValues(alpha: 0.15),
                child: ListTile(
                  leading: const Icon(Icons.merge_type, color: AppTheme.accentAmber),
                  title: Text(duplicates == 1 ? '1 möglicher Doppelter' : '$duplicates mögliche Doppelte'),
                  subtitle: const Text('Prüfen und zusammenführen'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DuplicatesScreen())),
                ),
              ),
            const SizedBox(height: 16),
            if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  canCreate
                      ? 'Noch keine Kunden. Lege einen Kunden an oder sprich eine Notiz ein – neue Kunden werden automatisch erkannt.'
                      : 'Hier erscheinen die Kunden deiner zugewiesenen Aufträge.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              )
            else if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Kein Kunde gefunden.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
              ),
            for (final c in shown)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppTheme.primaryDark,
                    child: Icon(Icons.person, color: AppTheme.accentAmber),
                  ),
                  title: Text(customerDisplayName(c), style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text([
                    [
                      c.street,
                      [c.zip, c.city].where((s) => (s ?? '').isNotEmpty).join(' ')
                    ].where((s) => (s ?? '').isNotEmpty).join(', '),
                    c.phone ?? '',
                  ].where((s) => s.isNotEmpty).join('\n')),
                  isThreeLine: (c.phone ?? '').isNotEmpty && ((c.street ?? '').isNotEmpty || (c.city ?? '').isNotEmpty),
                  onTap: () => _open(c),
                ),
              ),
          ],
        );
      },
    ));
  }
}

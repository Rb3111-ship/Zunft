import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../data/data_providers.dart';
import 'customer_edit_screen.dart';

String customerDisplayName(Customer c) => [c.firstName, c.name].where((s) => (s ?? '').isNotEmpty).join(' ');

/// Case-insensitive match on name, address and phone.
bool customerMatches(Customer c, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final haystack = [c.name, c.firstName, c.street, c.zip, c.city, c.phone, c.email]
      .whereType<String>()
      .join(' ')
      .toLowerCase();
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

    return customers.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accentAmber)),
      error: (e, _) => Center(
        child: TextButton(onPressed: () => ref.invalidate(customersProvider), child: const Text('Kunden konnten nicht geladen werden. Erneut versuchen')),
      ),
      data: (all) {
        final shown = all.where((c) => customerMatches(c, _query)).toList();
        return ListView(
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
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Kunde anlegen',
                  onPressed: () => _open(),
                  icon: const Icon(Icons.person_add),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (all.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Noch keine Kunden. Lege einen Kunden an oder sprich eine Notiz ein – neue Kunden werden automatisch erkannt.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              )
            else if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Kein Kunde gefunden.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
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
                    [c.street, [c.zip, c.city].where((s) => (s ?? '').isNotEmpty).join(' ')]
                        .where((s) => (s ?? '').isNotEmpty)
                        .join(', '),
                    c.phone ?? '',
                  ].where((s) => s.isNotEmpty).join('\n')),
                  isThreeLine: (c.phone ?? '').isNotEmpty && ((c.street ?? '').isNotEmpty || (c.city ?? '').isNotEmpty),
                  onTap: () => _open(c),
                ),
              ),
          ],
        );
      },
    );
  }
}

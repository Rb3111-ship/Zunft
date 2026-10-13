import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/customer_duplicates.dart';
import '../../data/data_providers.dart';
import '../../data/data_repository.dart';
import 'customers_tab.dart';

/// The list of customers that may be the same person. Only the boss and the office see it.
class DuplicatesScreen extends ConsumerWidget {
  const DuplicatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairs = findDuplicatePairs(ref.watch(customersProvider).valueOrNull ?? const []);
    return Scaffold(
      appBar: AppBar(title: Text('Mögliche Doppelte'.tr)),
      body: SafeArea(
        child: pairs.isEmpty
            ? Center(child: Text('Keine möglichen Doppelten.'.tr, style: TextStyle(color: AppTheme.textSecondary)))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('Ein Name allein reicht nicht: zwei gleiche Namen an verschiedenen Adressen sind verschiedene Personen und erscheinen hier nicht.'.tr,
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                  for (final p in pairs)
                    Card(
                      child: ListTile(
                        title: Text('${customerDisplayName(p.a)}  ·  ${customerDisplayName(p.b)}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(p.sharedContact != null
                            ? 'Gleiche {0}'.trf([p.sharedContact])
                            : p.strong
                                ? 'Gleicher Name und gleiche Anschrift, Telefon oder E-Mail'.tr
                                : 'Gleicher Name, aber es fehlen Angaben zum Vergleich'.tr),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => CustomerMergeScreen(first: p.a, second: p.b)),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Choose the customer to merge [customer] with (a search list; likely duplicates first).
class MergePickerScreen extends ConsumerStatefulWidget {
  const MergePickerScreen({super.key, required this.customer});

  final Customer customer;

  @override
  ConsumerState<MergePickerScreen> createState() => _MergePickerScreenState();
}

class _MergePickerScreenState extends ConsumerState<MergePickerScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = (ref.watch(customersProvider).valueOrNull ?? const <Customer>[])
        .where((c) => c.id != widget.customer.id)
        .toList();
    final c = widget.customer;
    final likely = findDuplicateCustomers(all,
            name: c.name,
            firstName: c.firstName,
            street: c.street,
            zip: c.zip,
            phone: c.phone,
            email: c.email,
            includeContactOnly: true)
        .map((m) => m.customer.id)
        .toSet();
    final shown = all.where((x) => customerMatches(x, _query)).toList()
      ..sort((a, b) => (likely.contains(b.id) ? 1 : 0) - (likely.contains(a.id) ? 1 : 0));
    return Scaffold(
      appBar: AppBar(title: Text('Mit wem zusammenführen?'.tr)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(hintText: 'Kunde suchen...'.tr, prefixIcon: Icon(Icons.search)),
            ),
            const SizedBox(height: 12),
            for (final x in shown)
              Card(
                child: ListTile(
                  title: Text(customerDisplayName(x), style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text([x.street, x.city, x.phone].where((s) => (s ?? '').isNotEmpty).join(' · ')),
                  trailing: likely.contains(x.id)
                      ? Chip(label: Text('möglich'.tr, style: TextStyle(fontSize: 11)))
                      : null,
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => CustomerMergeScreen(first: widget.customer, second: x)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows two customers side by side. The boss picks which one is kept; the other one is merged into
/// it (jobs move over, nothing is deleted).
class CustomerMergeScreen extends ConsumerStatefulWidget {
  const CustomerMergeScreen({super.key, required this.first, required this.second});

  final Customer first;
  final Customer second;

  @override
  ConsumerState<CustomerMergeScreen> createState() => _CustomerMergeScreenState();
}

class _CustomerMergeScreenState extends ConsumerState<CustomerMergeScreen> {
  late String _keepId = widget.first.id;
  bool _busy = false;
  String? _error;

  Future<void> _merge() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(dataRepositoryProvider.future);
      final removeId = _keepId == widget.first.id ? widget.second.id : widget.first.id;
      await repo.mergeCustomers(keepId: _keepId, removeId: removeId);
      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunden zusammengeführt.'.tr)));
      }
    } on ValidationFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Zusammenführen fehlgeschlagen.'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _column(Customer c, int jobs) {
    final selected = _keepId == c.id;
    String v(String? s) => (s ?? '').isEmpty ? '–' : s!;
    return Expanded(
      child: GestureDetector(
        onTap: _busy ? null : () => setState(() => _keepId = c.id),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: selected ? AppTheme.accentAmber : Colors.transparent, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(selected ? 'BLEIBT'.tr : 'WIRD ZUSAMMENGEFÜHRT'.tr,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: selected ? AppTheme.accentAmber : AppTheme.textSecondary)),
                const SizedBox(height: 6),
                Text(customerDisplayName(c), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(v(c.street), style: const TextStyle(fontSize: 13)),
                Text(v([c.zip, c.city].where((s) => (s ?? '').isNotEmpty).join(' ')), style: const TextStyle(fontSize: 13)),
                Text(v(c.phone), style: const TextStyle(fontSize: 13)),
                Text(v(c.email), style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                Text('{0} Aufträge'.trf([jobs]), style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(jobsProvider).valueOrNull ?? const <Job>[];
    int jobsOf(Customer c) => jobs.where((j) => j.customerId == c.id).length;
    return Scaffold(
      appBar: AppBar(title: Text('Kunden zusammenführen'.tr)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Tippe auf den Kunden, der bleiben soll.'.tr, style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_column(widget.first, jobsOf(widget.first)), _column(widget.second, jobsOf(widget.second))],
            ),
            const SizedBox(height: 8),
            Text(
              'Alle Aufträge wandern zum bleibenden Kunden. Fehlende Angaben werden ergänzt, abweichende Angaben stehen danach in den Notizen. Bereits erstellte Angebote und Rechnungen bleiben unverändert (sie müssen laut Gesetz so aufbewahrt werden).'.tr,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: AppTheme.accentRed)),
              ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _merge, child: Text('Zusammenführen'.tr)),
          ],
        ),
      ),
    );
  }
}

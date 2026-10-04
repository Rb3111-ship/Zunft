import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/trade_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/currency_formatter.dart';
import 'features/auth/application/auth_providers.dart';
import 'features/auth/data/business_models.dart';
import 'features/auth/presentation/business_settings_screen.dart';
import 'features/capture/application/capture_providers.dart';
import 'features/capture/presentation/record_flow.dart';
import 'features/customers/presentation/customers_tab.dart';
import 'features/documents/presentation/documents_tab.dart';
import 'features/data/presentation/sync_status_tile.dart';
import 'features/jobs/presentation/jobs_tab.dart';
import 'features/team/domain/team_models.dart';
import 'features/team/presentation/team_screen.dart';
import 'core/sync/sync_controller.dart';

class ZunftAppShell extends ConsumerStatefulWidget {
  const ZunftAppShell({super.key});

  @override
  ConsumerState<ZunftAppShell> createState() => _ZunftAppShellState();
}

class _ZunftAppShellState extends ConsumerState<ZunftAppShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Start background sync once the signed-in shell is on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(syncControllerProvider.notifier).start();
      ref.read(captureControllerProvider.notifier).start();
    });
  }

  void _openRecordModal() => startRecordingFlow(context, ref);

  @override
  Widget build(BuildContext context) {
    // Boss and office see documents; employees (Meister, Geselle) only their jobs and customers.
    final manager = ref.watch(profileProvider).valueOrNull?.isManager ?? false;
    final tabCount = manager ? 4 : 3;
    final index = _currentIndex.clamp(0, tabCount - 1);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accentAmber,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'ZUNFT',
                style: TextStyle(
                  color: AppTheme.primaryDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                ref.watch(businessProvider).valueOrNull?.name ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic, color: AppTheme.accentAmber),
            tooltip: 'Neue Sprachnotiz',
            onPressed: _openRecordModal,
          ),
        ],
      ),
      body: IndexedStack(
        index: index,
        children: [
          const JobsTab(),
          const CustomersTab(),
          if (manager) const DocumentsTab(),
          _buildSettingsView(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.accentAmber,
        foregroundColor: AppTheme.primaryDark,
        elevation: 4,
        onPressed: _openRecordModal,
        icon: const Icon(Icons.mic, size: 26),
        label: const Text(
          'SPRECHEN',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, // 4 tabs: keep every label visible
        currentIndex: index,
        backgroundColor: AppTheme.primaryDark,
        selectedItemColor: AppTheme.accentAmber,
        unselectedItemColor: AppTheme.textSecondary,
        onTap: (i) {
          setState(() {
            _currentIndex = i;
          });
        },
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            activeIcon: Icon(Icons.assignment),
            label: 'Aufträge',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: 'Kunden',
          ),
          if (manager)
            const BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long),
              label: 'Belege',
            ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Betrieb',
          ),
        ],
      ),
    );
  }

  // --- TAB 3: BETRIEB (SETTINGS) ---
  Widget _buildSettingsView() {
    final business = ref.watch(businessProvider);
    final profile = ref.watch(profileProvider).valueOrNull;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        business.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(color: AppTheme.accentAmber)),
          ),
          error: (e, _) => Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_off, color: AppTheme.accentRed),
              title: const Text('Betriebsdaten konnten nicht geladen werden'),
              subtitle: const Text('Tippen zum erneuten Laden'),
              onTap: () => ref.invalidate(businessProvider),
            ),
          ),
          data: (b) => _businessCard(b, canEdit: profile?.canEditBusiness ?? false),
        ),
        if (profile?.isOwner ?? false) ...[
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.groups, color: AppTheme.accentAmber),
              title: const Text('Team'),
              subtitle: const Text('Mitarbeiter einladen, Plätze, Zugang'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeamScreen())),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const SyncStatusTile(),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.logout, color: AppTheme.accentAmber),
            title: const Text('Abmelden'),
            subtitle: Text(profile == null ? '' : '${profile.fullName} (${Roles.label(profile.role)})'),
            onTap: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ),
      ],
    );
  }

  Widget _businessCard(Business b, {required bool canEdit}) {
    final missing = b.missingInvoiceFields;
    final address = [
      if ((b.addressStreet ?? '').isNotEmpty) b.addressStreet,
      [b.addressZip, b.addressCity].where((s) => (s ?? '').isNotEmpty).join(' '),
    ].where((s) => (s ?? '').isNotEmpty).join(', ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('BETRIEBSDATEN (DIN 5008)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.edit, size: 16),
                  label: Text(canEdit ? 'Bearbeiten' : 'Ansehen'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => BusinessSettingsScreen(business: b, canEdit: canEdit)),
                  ),
                ),
              ],
            ),
            if (missing.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.accentAmber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Für Rechnungen fehlt noch: ${missing.join(', ')}',
                  style: const TextStyle(color: AppTheme.accentAmber, fontSize: 13),
                ),
              ),
            ],
            _settingsField('Betriebsname', b.name),
            _settingsField('Inhaber', b.ownerName),
            _settingsField('Gewerk', TradeConstants.tradeLabels[b.tradeCategory] ?? b.tradeCategory),
            _settingsField('Anschrift', address),
            _settingsField('Standard-Stundensatz', '${CurrencyFormatter.formatCents(b.defaultHourlyRateCents)} / Std'),
            _settingsField('Umsatzsteuer', '${b.defaultVatRate.toStringAsFixed(b.defaultVatRate % 1 == 0 ? 0 : 1)} %'),
            _settingsField('Steuernummer', b.taxNumber ?? ''),
            _settingsField('USt-IdNr.', b.vatId ?? ''),
            _settingsField('IBAN', b.iban ?? ''),
          ],
        ),
      ),
    );
  }

  Widget _settingsField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value.isEmpty ? '–' : value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: value.isEmpty ? AppTheme.textSecondary : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

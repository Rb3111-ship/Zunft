import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../appointments/application/appointment_actions.dart' show externalActionsProvider;
import '../../auth/application/auth_providers.dart';
import '../application/document_providers.dart';
import '../data/documents_remote.dart';
import '../domain/document_data.dart';
import '../domain/open_invoices.dart';
import 'document_detail_screen.dart';

/// Who has not paid yet: unpaid invoices, the most overdue first, with a friendly payment reminder
/// to send (a text for the share sheet: WhatsApp, e-mail, SMS) and a quick "paid".
class OpenInvoicesScreen extends ConsumerStatefulWidget {
  const OpenInvoicesScreen({super.key});

  @override
  ConsumerState<OpenInvoicesScreen> createState() => _OpenInvoicesScreenState();
}

class _OpenInvoicesScreenState extends ConsumerState<OpenInvoicesScreen> {
  bool _busy = false;

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// The reminder text goes to the customer: always German, whatever language the app speaks.
  Future<void> _remind(OpenInvoice o) async {
    final business = ref.read(businessProvider).valueOrNull;
    if (business == null) return _snack('Die Betriebsdaten werden noch geladen.'.tr);
    final earlier = ref.read(paymentRemindersProvider).valueOrNull?[o.document.id];
    final text = paymentReminderText(
      invoice: o,
      company: CompanyDetails.fromBusiness(business),
      now: ref.read(documentsClockProvider)(),
      lastReminder: (earlier == null || earlier.isEmpty) ? null : earlier.last,
    );
    try {
      await ref.read(externalActionsProvider).shareText(text, subject: paymentReminderSubject(o.document));
    } catch (_) {
      _snack('Die Erinnerung konnte nicht geteilt werden.'.tr);
      return;
    }
    // The share sheet was opened: note it, like "versendet" for a document, so nobody reminds twice by accident.
    try {
      await ref.read(documentsRemoteProvider).recordReminder(o.document.id);
      ref.invalidate(paymentRemindersProvider);
    } catch (_) {
      _snack('Die Erinnerung wurde geteilt, konnte aber nicht vermerkt werden (keine Verbindung).'.tr);
    }
  }

  Future<void> _markPaid(OpenInvoice o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('{0} als bezahlt markieren?'.trf([o.document.docNumber])),
        content: Text('Bezahlte Rechnungen können nicht storniert werden. Bitte mit dem Steuerberater klären, wie sie korrigiert wird.'.tr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Abbrechen'.tr)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Als bezahlt markieren'.tr)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final service = await ref.read(documentServiceProvider.future);
      await service.markStatus(o.document.id, 'paid');
    } on DocumentOfflineException {
      _snack('Keine Verbindung. Der Status kann nur online geändert werden.'.tr);
    } catch (_) {
      _snack('Der Status konnte nicht geändert werden.'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _remindedText(List<DateTime> r) {
    final last = DateFormatter.formatDate(r.last);
    return r.length == 1 ? 'Erinnert am {0}'.trf([last]) : 'Erinnert am {0} ({1}×)'.trf([last, r.length]);
  }

  String _dueText(OpenInvoice o) {
    final due = DateFormatter.formatDate(o.due);
    if (o.daysOverdue > 1) return 'fällig am {0} - seit {1} Tagen überfällig'.trf([due, o.daysOverdue]);
    if (o.daysOverdue == 1) return 'fällig am {0} - seit 1 Tag überfällig'.trf([due]);
    if (o.daysOverdue == 0) return 'heute fällig'.tr;
    if (o.daysOverdue == -1) return 'fällig am {0} - morgen'.trf([due]);
    return 'fällig am {0} - in {1} Tagen'.trf([due, -o.daysOverdue]);
  }

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(issuedDocumentsProvider).valueOrNull ?? const <IssuedDocument>[];
    final now = ref.watch(documentsClockProvider)();
    final open = openInvoices(docs, now);
    final reminders = ref.watch(paymentRemindersProvider).valueOrNull ?? const <String, List<DateTime>>{};
    final sum = summarizeOpen(open);

    return Scaffold(
      appBar: AppBar(title: Text('Offene Rechnungen'.tr)),
      body: SafeArea(
        child: open.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('Alles bezahlt: Es gibt keine offenen Rechnungen.'.tr,
                      textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary)),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    key: const ValueKey('open-summary'),
                    color: AppTheme.primaryDark,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _metric('Offen'.tr, CurrencyFormatter.formatCents(sum.openCents), '${sum.count}', AppTheme.accentAmber),
                          Container(height: 40, width: 1, color: AppTheme.dividerColor),
                          _metric('Überfällig'.tr, CurrencyFormatter.formatCents(sum.overdueCents), '${sum.overdueCount}',
                              sum.overdueCount > 0 ? AppTheme.accentRed : AppTheme.accentGreen),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final o in open) _tile(o, reminders[o.document.id] ?? const []),
                ],
              ),
      ),
    );
  }

  Widget _metric(String label, String amount, String count, Color color) => Column(
        children: [
          Text(amount, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text('$label ($count)', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        ],
      );

  Widget _tile(OpenInvoice o, List<DateTime> reminded) {
    final d = o.document;
    final late = o.overdue;
    return Card(
      key: ValueKey('open-${d.docNumber}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentDetailScreen(documentId: d.id))),
              title: Text(d.recipientName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${d.docNumber}\n${_dueText(o)}${reminded.isEmpty ? '' : '\n${_remindedText(reminded)}'}',
                  style: TextStyle(color: late ? AppTheme.accentRed : AppTheme.textSecondary, fontSize: 12.5)),
              isThreeLine: true,
              trailing: Text(CurrencyFormatter.formatCents(d.totalGrossCents),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  if (late)
                    TextButton.icon(
                      key: ValueKey('remind-${d.docNumber}'),
                      onPressed: _busy ? null : () => _remind(o),
                      icon: const Icon(Icons.notifications_active_outlined, size: 18),
                      label: Text(reminded.isEmpty ? 'Zahlungserinnerung senden'.tr : 'Erneut erinnern'.tr),
                    ),
                  TextButton.icon(
                    key: ValueKey('paid-${d.docNumber}'),
                    onPressed: _busy ? null : () => _markPaid(o),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text('Als bezahlt markieren'.tr),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

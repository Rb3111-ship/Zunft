import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../documents/application/document_providers.dart';
import '../../jobs/application/job_notes_providers.dart';
import '../../receipts/application/receipt_providers.dart';
import '../../team/application/team_providers.dart';
import '../domain/full_export.dart';

/// "Betrieb" tab (boss and office): everything the business has in Zunft as one ZIP file for its own
/// records, the tax advisor or a change of tool. Reading only: it works even when the subscription
/// has ended.
class FullExportTile extends ConsumerStatefulWidget {
  const FullExportTile({super.key});

  @override
  ConsumerState<FullExportTile> createState() => _FullExportTileState();
}

class _FullExportTileState extends ConsumerState<FullExportTile> {
  bool _busy = false;

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    final business = ref.read(businessProvider).valueOrNull;
    if (business == null) return _snack('Die Betriebsdaten werden noch geladen.'.tr);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Alle Daten exportieren?'.tr),
        content: Text(
            'Du bekommst eine ZIP-Datei mit Kunden, Aufträgen, Notizen (als Text), allen Rechnungen und Angeboten mit PDF, den Einkaufsbelegen mit Fotos, Terminen und Arbeitszeiten. Das dauert je nach Menge eine Weile und braucht Internet. Bewahre die Datei sicher auf: sie enthält Daten deiner Kunden.'.tr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Abbrechen'.tr)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Exportieren'.tr)),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final progress = ValueNotifier<String>('Daten werden gesammelt...'.tr);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 18),
            Expanded(child: ValueListenableBuilder<String>(valueListenable: progress, builder: (_, v, __) => Text(v))),
          ]),
        ),
      ),
    );
    var dialogOpen = true;
    void closeDialog() {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    try {
      final db = await ref.read(scopedDatabaseProvider.future);
      final receipts = await ref.read(receiptsRemoteProvider).fetchAll();
      final notes = await ref.read(jobNotesRemoteProvider).fetchAllNotes();
      final members = ref.read(teamOverviewProvider).valueOrNull?.members ?? (await ref.read(teamOverviewProvider.future)).members;
      final service = await ref.read(documentServiceProvider.future);
      final documents = await (db.select(db.issuedDocuments)..orderBy([(d) => OrderingTerm.asc(d.dateIssued), (d) => OrderingTerm.asc(d.docNumber)])).get();
      final data = FullExportData(
        businessName: business.name,
        now: ref.read(documentsClockProvider)(),
        customers: await db.select(db.customers).get(),
        jobs: await db.select(db.jobs).get(),
        documents: documents,
        appointments: await db.select(db.appointments).get(),
        timeEntries: await db.select(db.timeEntries).get(),
        notes: notes,
        receipts: receipts,
        memberNames: {for (final m in members) m.id: m.fullName},
      );
      final result = await buildFullExport(
        data,
        fetchPdf: (doc) => service.pdfFor(doc, business),
        fetchPhoto: (path) => ref.read(receiptsRemoteProvider).downloadPhoto(path),
        onProgress: (done, total) => progress.value = 'Dateien {0} von {1}'.trf([done, total]),
      );
      closeDialog();
      await ref.read(fileSharerProvider).share(result.zip, fullExportFileName(data.now),
          subject: 'Zunft: Datenexport {0}'.trf([business.name]), mimeType: 'application/zip');
      if (result.missingFiles.isNotEmpty) {
        _snack('{0} Datei(en) konnten nicht geladen werden; sie stehen in der Datei LIESMICH.txt.'.trf([result.missingFiles.length]));
      }
    } catch (_) {
      closeDialog();
      _snack('Der Export ist fehlgeschlagen. Bitte Internetverbindung prüfen und erneut versuchen.'.tr);
    } finally {
      progress.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        key: const ValueKey('full-export'),
        leading: const Icon(Icons.folder_zip_outlined, color: AppTheme.accentAmber),
        title: Text('Alle Daten exportieren'.tr),
        subtitle: Text('Kunden, Aufträge, Notizen, Rechnungen mit PDF, Belege, Termine und Zeiten als ZIP-Datei'.tr),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary),
        onTap: _busy ? null : _export,
      ),
    );
  }
}

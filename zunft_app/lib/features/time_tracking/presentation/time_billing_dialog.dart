import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../domain/time_billing.dart';
import '../domain/time_models.dart';

/// What to do with the tracked working time when an invoice is made.
enum TimeBilling {
  /// Add the tracked time as a position; positions of the notes stay as they are.
  add,

  /// The tracked time replaces the working time that was said in the notes (no double billing).
  replace,

  /// Do not bill it now: the entries stay open for a later invoice.
  skip,
}

/// Asks the boss. [noteLaborHours] > 0 means the notes also contain working time (spoken), which
/// is the case where it could be billed twice.
Future<TimeBilling?> askTimeBilling(
  BuildContext context, {
  required int minutes,
  required Map<String, int> byPerson,
  required List<TimeBillingLine> lines,
  required double noteLaborHours,
  required bool timerStillRunning,
}) {
  return showDialog<TimeBilling>(
    context: context,
    builder: (ctx) => _TimeBillingDialog(
      minutes: minutes,
      byPerson: byPerson,
      lines: lines,
      noteLaborHours: noteLaborHours,
      timerStillRunning: timerStillRunning,
    ),
  );
}

class _TimeBillingDialog extends StatefulWidget {
  const _TimeBillingDialog(
      {required this.minutes,
      required this.byPerson,
      required this.lines,
      required this.noteLaborHours,
      required this.timerStillRunning});

  final int minutes;
  final Map<String, int> byPerson;
  final List<TimeBillingLine> lines;
  final double noteLaborHours;
  final bool timerStillRunning;

  @override
  State<_TimeBillingDialog> createState() => _TimeBillingDialogState();
}

class _TimeBillingDialogState extends State<_TimeBillingDialog> {
  late TimeBilling _choice = widget.noteLaborHours > 0 ? TimeBilling.replace : TimeBilling.add;

  String _hours(double h) => h.toStringAsFixed(h % 1 == 0 ? 0 : 2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final hasNotes = widget.noteLaborHours > 0;
    return AlertDialog(
      title: Text('Erfasste Arbeitszeit'.tr),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Für diesen Auftrag ist Zeit erfasst: {0} Std ({1}).'.trf([clockLabel(Duration(minutes: widget.minutes)), hoursText(widget.minutes)]),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              widget.byPerson.entries.map((e) => '${e.key} ${clockLabel(Duration(minutes: e.value))}').join('  ·  '),
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            if (widget.lines.length > 1) ...[
              const SizedBox(height: 10),
              Text(
                'Wegen unterschiedlicher Stundensätze entstehen {0} Positionen: {1}.'.trf([widget.lines.length, widget.lines.map((l) => '{0} Std à {1}'.trf([clockLabel(Duration(minutes: l.minutes)), CurrencyFormatter.formatCents(l.rateCents)])).join(' · ')]),
                style: const TextStyle(fontSize: 13),
              ),
            ],
            if (hasNotes) ...[
              const SizedBox(height: 10),
              Text(
                'In den Notizen steht außerdem Arbeitszeit: {0} Std. Sonst würde sie doppelt berechnet.'.trf([_hours(widget.noteLaborHours)]),
                style: const TextStyle(fontSize: 13, color: AppTheme.accentAmber),
              ),
            ],
            if (widget.timerStillRunning)
              Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Ein Timer für diesen Auftrag läuft noch und ist nicht dabei.'.tr,
                    style: TextStyle(fontSize: 13, color: AppTheme.accentAmber)),
              ),
            const SizedBox(height: 8),
            RadioGroup<TimeBilling>(
              groupValue: _choice,
              onChanged: (v) => setState(() => _choice = v ?? _choice),
              child: Column(
                children: [
                  if (hasNotes)
                    RadioListTile<TimeBilling>(
                      value: TimeBilling.replace,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Erfasste Zeit statt der Arbeitszeit aus den Notizen'.tr, style: TextStyle(fontSize: 14)),
                    ),
                  RadioListTile<TimeBilling>(
                    value: TimeBilling.add,
                    contentPadding: EdgeInsets.zero,
                    title: Text(hasNotes ? 'Beides berechnen'.tr : 'Erfasste Zeit abrechnen'.tr, style: const TextStyle(fontSize: 14)),
                  ),
                  RadioListTile<TimeBilling>(
                    value: TimeBilling.skip,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Erfasste Zeit jetzt nicht abrechnen'.tr, style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Abbrechen'.tr)),
        FilledButton(onPressed: () => Navigator.pop(context, _choice), child: Text('Weiter'.tr)),
      ],
    );
  }
}

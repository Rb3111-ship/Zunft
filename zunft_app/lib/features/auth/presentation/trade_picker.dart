import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/trade_constants.dart';
import '../../../core/utils/validators.dart';

/// Trade dropdown with an "Other" entry. The value is either one of the [TradeConstants]
/// keys or the free text the person typed (the database column is plain text).
class TradePicker extends StatefulWidget {
  const TradePicker({super.key, required this.initialValue, required this.onChanged, this.enabled = true});

  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  State<TradePicker> createState() => _TradePickerState();
}

class _TradePickerState extends State<TradePicker> {
  static const _other = '__other__';
  static const maxLength = 60;

  late String _choice;
  late final TextEditingController _custom;

  @override
  void initState() {
    super.initState();
    final known = TradeConstants.tradeLabels.containsKey(widget.initialValue);
    _choice = known ? widget.initialValue : _other;
    _custom = TextEditingController(text: known ? '' : widget.initialValue);
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(_choice == _other ? _custom.text.trim() : _choice);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _choice,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'Gewerk'.tr, border: OutlineInputBorder()),
          items: [
            for (final e in TradeConstants.tradeLabels.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: _other, child: Text('Sonstiges (selbst eingeben)'.tr)),
          ],
          onChanged: widget.enabled
              ? (v) {
                  setState(() => _choice = v ?? _choice);
                  _emit();
                }
              : null,
        ),
        if (_choice == _other) ...[
          const SizedBox(height: 14),
          TextFormField(
            controller: _custom,
            enabled: widget.enabled,
            maxLength: maxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Art des Betriebs'.tr,
              hintText: 'z. B. Gebäudereinigung, Gartenbau, Fotograf'.tr,
              border: OutlineInputBorder(),
            ),
            validator: (v) => Validators.required(v, 'Art des Betriebs'.tr),
            onChanged: (_) => _emit(),
          ),
        ],
      ],
    );
  }
}

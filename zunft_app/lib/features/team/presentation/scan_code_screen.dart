import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_theme.dart';

/// Opens the camera and pops with the text of the first QR code it sees.
///
/// The camera needs a real phone, so tests replace the viewfinder through [debugBodyBuilder].
class ScanCodeScreen extends StatefulWidget {
  const ScanCodeScreen({super.key});

  /// Test seam: builds the body instead of the camera; call `onScan` to simulate a scanned code.
  static Widget Function(void Function(String raw) onScan)? debugBodyBuilder;

  @override
  State<ScanCodeScreen> createState() => _ScanCodeScreenState();
}

class _ScanCodeScreenState extends State<ScanCodeScreen> {
  bool _done = false;

  void _found(String raw) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final seam = ScanCodeScreen.debugBodyBuilder;
    return Scaffold(
      appBar: AppBar(title: Text('QR-Code scannen'.tr)),
      body: seam != null
          ? seam(_found)
          : Stack(
              children: [
                MobileScanner(
                  onDetect: (capture) {
                    for (final code in capture.barcodes) {
                      final raw = code.rawValue;
                      if (raw != null && raw.isNotEmpty) return _found(raw);
                    }
                  },
                  errorBuilder: (context, error) => Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Die Kamera ist nicht verfügbar. Bitte den Zugriff in den Einstellungen erlauben oder den Code von Hand eintippen.'.tr,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Halte die Kamera auf den QR-Code auf dem Handy deines Chefs.'.tr,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, backgroundColor: Colors.black54, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
      backgroundColor: AppTheme.primaryDark,
    );
  }
}

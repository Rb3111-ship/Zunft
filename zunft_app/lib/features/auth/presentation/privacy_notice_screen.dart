import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/privacy_notice.dart';

/// Shows the employee privacy notice.
class PrivacyNoticeScreen extends StatelessWidget {
  const PrivacyNoticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Datenschutz')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(PrivacyNotice.title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          for (final s in PrivacyNotice.sections) ...[
            Text(s.heading, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentAmber)),
            const SizedBox(height: 4),
            Text(s.text, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

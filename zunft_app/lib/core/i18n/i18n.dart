import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translations.dart';

/// The languages of the screens. The German text in the code is the source: every other language
/// is looked up by it ([TrString.tr]); a text without a translation stays German. Documents
/// (quotes, invoices, e-invoices) are always German.
class AppLanguage {
  const AppLanguage(this.code, this.nativeName, {this.rtl = false});

  final String code;
  final String nativeName;
  final bool rtl;

  Locale get locale => Locale(code);
}

const appLanguages = <AppLanguage>[
  AppLanguage('de', 'Deutsch'),
  AppLanguage('en', 'English'),
  AppLanguage('tr', 'Türkçe'),
  AppLanguage('ar', 'العربية', rtl: true),
  AppLanguage('sq', 'Shqip'),
  AppLanguage('pl', 'Polski'),
  AppLanguage('ro', 'Română'),
  AppLanguage('ru', 'Русский'),
  AppLanguage('uk', 'Українська'),
];

const _prefsKey = 'app_language';

/// The language currently shown; read by [TrString.tr] (no BuildContext needed).
class I18n {
  I18n._();

  static String current = 'de';

  static AppLanguage get language => appLanguages.firstWhere((l) => l.code == current, orElse: () => appLanguages.first);

  /// Called once before the app starts. A saved choice wins, then the phone's language if we
  /// have it, otherwise German.
  static Future<void> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_prefsKey);
      if (saved != null && appLanguages.any((l) => l.code == saved)) {
        current = saved;
        return;
      }
      final device = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      if (appLanguages.any((l) => l.code == device)) current = device;
    } catch (_) {}
  }
}

extension TrString on String {
  /// This German text in the chosen language (German if there is no translation).
  String get tr {
    if (I18n.current == 'de') return this;
    return translations[I18n.current]?[this] ?? this;
  }

  /// Like [tr] for a text with values: `'Hallo {0}, {1}'.trf([name, x])`. The German text with
  /// {0}, {1} ... is the translation key.
  String trf(List<Object?> values) {
    var t = tr;
    for (var i = 0; i < values.length; i++) {
      t = t.replaceAll('{$i}', '${values[i]}');
    }
    return t;
  }
}

class LanguageNotifier extends StateNotifier<String> {
  LanguageNotifier() : super(I18n.current);

  Future<void> set(String code) async {
    if (!appLanguages.any((l) => l.code == code)) return;
    I18n.current = code;
    state = code;
    try {
      await (await SharedPreferences.getInstance()).setString(_prefsKey, code);
    } catch (_) {}
  }
}

final languageProvider = StateNotifierProvider<LanguageNotifier, String>((ref) => LanguageNotifier());

/// Opens the language list; returns after the choice is applied.
Future<void> pickLanguage(BuildContext context, WidgetRef ref) async {
  final chosen = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Sprache / Language'),
      children: [
        for (final l in appLanguages)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, l.code),
            child: Row(children: [
              Icon(l.code == I18n.current ? Icons.radio_button_checked : Icons.radio_button_off, size: 20),
              const SizedBox(width: 12),
              Text(l.nativeName, style: const TextStyle(fontSize: 16)),
            ]),
          ),
      ],
    ),
  );
  if (chosen != null) await ref.read(languageProvider.notifier).set(chosen);
}

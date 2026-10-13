import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/i18n/i18n.dart';
import 'package:zunft_app/core/i18n/translations.dart';
import 'package:zunft_app/main.dart';

final _placeholder = RegExp(r'\{\d+\}');

List<String> _placeholders(String s) => (_placeholder.allMatches(s).map((m) => m.group(0)!).toList()..sort());

void main() {
  tearDown(() => I18n.current = 'de');

  group('languages', () {
    test('German stays as written, other languages are looked up by the German text', () {
      expect('Abbrechen'.tr, 'Abbrechen');
      I18n.current = 'en';
      expect('Abbrechen'.tr, 'Cancel');
      I18n.current = 'tr';
      expect('Abbrechen'.tr, 'İptal');
      I18n.current = 'ar';
      expect('Abbrechen'.tr, 'إلغاء');
    });

    test('a text without translation stays German; values are filled in', () {
      I18n.current = 'en';
      expect('Das gibt es nicht'.tr, 'Das gibt es nicht');
      expect('Stundensatz {0}'.trf(['75,00 EUR']), 'Hourly rate 75,00 EUR');
      I18n.current = 'de';
      expect('Stundensatz {0}'.trf(['75,00 EUR']), 'Stundensatz 75,00 EUR');
    });

    test('every language has the same texts and the same {0} {1} values as the English one', () {
      final en = translations['en']!;
      expect(en.length, greaterThan(500));
      for (final l in appLanguages.where((l) => l.code != 'de')) {
        final t = translations[l.code];
        expect(t, isNotNull, reason: l.code);
        expect(t!.keys.toSet(), en.keys.toSet(), reason: '${l.code} has other texts than en');
        for (final k in en.keys) {
          expect(t[k], isNotEmpty, reason: '${l.code}: $k');
          expect(_placeholders(t[k]!), _placeholders(k), reason: '${l.code}: "$k" -> "${t[k]}"');
        }
      }
    });

    test('Arabic and Persian are the right-to-left languages', () {
      expect(appLanguages.where((l) => l.rtl).map((l) => l.code), ['ar', 'fa']);
    });
  });

  group('on the screen', () {
    testWidgets('the app shows the chosen language; Arabic is laid out right to left', (tester) async {
      I18n.current = 'en';
      await tester.pumpWidget(ProviderScope(child: ZunftApp(home: Builder(builder: (c) => Text('Abbrechen'.tr, key: const Key('t'))))));
      expect(find.text('Cancel'), findsOneWidget);
      expect(Directionality.of(tester.element(find.byKey(const Key('t')))), TextDirection.ltr);

      I18n.current = 'ar';
      await tester.pumpWidget(ProviderScope(key: UniqueKey(), child: ZunftApp(home: Builder(builder: (c) => Text('Abbrechen'.tr, key: const Key('t'))))));
      await tester.pumpAndSettle();
      expect(find.text('إلغاء'), findsOneWidget);
      expect(Directionality.of(tester.element(find.byKey(const Key('t')))), TextDirection.rtl);
    });

    testWidgets('switching the language in the picker re-draws the screen', (tester) async {
      await tester.pumpWidget(ProviderScope(
          child: ZunftApp(home: Consumer(builder: (c, ref, _) {
        return Scaffold(body: TextButton(onPressed: () => pickLanguage(c, ref), child: Text('Abbrechen'.tr)));
      }))));
      expect(find.text('Abbrechen'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsOneWidget);
    });
  });
}

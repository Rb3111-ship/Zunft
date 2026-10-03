import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/utils/currency_formatter.dart';

void main() {
  group('CurrencyFormatter German Locale Tests', () {
    test('Correctly formats cents into German Euro strings', () {
      expect(CurrencyFormatter.formatCents(6500), '65,00\u00a0€');
      expect(CurrencyFormatter.formatCents(20230), '202,30\u00a0€');
      expect(CurrencyFormatter.formatCents(125050), '1.250,50\u00a0€');
      expect(CurrencyFormatter.formatCents(0), '0,00\u00a0€');
    });

    test('Correctly parses German price strings with commas and dots into cents', () {
      expect(CurrencyFormatter.parseToCents('65,00 €'), 6500);
      expect(CurrencyFormatter.parseToCents('65,50'), 6550);
      expect(CurrencyFormatter.parseToCents('1.250,50 €'), 125050);
      expect(CurrencyFormatter.parseToCents('40'), 4000);
      expect(CurrencyFormatter.parseToCents(''), isNull);
    });

    test('Parses plain decimal points and thousands separators unambiguously', () {
      expect(CurrencyFormatter.parseToCents('65.50'), 6550);
      expect(CurrencyFormatter.parseToCents('1.5'), 150);
      expect(CurrencyFormatter.parseToCents('1.250'), 125000);
      expect(CurrencyFormatter.parseToCents('1.250.000,00'), 125000000);
      expect(CurrencyFormatter.parseToCents('65,5'), 6550);
      expect(CurrencyFormatter.parseToCents('68 EUR'), 6800);
    });

    test('Rejects invalid or negative price input', () {
      expect(CurrencyFormatter.parseToCents('abc'), isNull);
      expect(CurrencyFormatter.parseToCents('-5'), isNull);
      expect(CurrencyFormatter.parseToCents('1,2,3'), isNull);
      expect(CurrencyFormatter.parseToCents('12,345'), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/features/review/models/draft_models.dart';

void main() {
  group('FinancialSummary and § 35a EStG Calculations', () {
    test('Correctly separates labor and material and calculates 19% German VAT', () {
      final items = [
        // 2 hours labor @ 68,00 €/hr = 136,00 € (13600 cents)
        DraftLineItem(
          id: '1',
          type: 'labor',
          description: 'Steckdosenmontage',
          quantity: 2.0,
          unit: 'Std',
          unitPriceNetCents: 6800,
        ),
        // 1 piece Gira socket @ 40,00 € = 40,00 € (4000 cents)
        DraftLineItem(
          id: '2',
          type: 'material',
          description: 'Gira Doppelsteckdose',
          quantity: 1.0,
          unit: 'Stk',
          unitPriceNetCents: 4000,
        ),
      ];

      final summary = FinancialSummary.calculate(items: items, vatRate: 19.0);

      // Verify Labor Subtotal (§ 35a EStG)
      expect(summary.subtotalLaborCents, 13600); // 136,00 €

      // Verify Material Subtotal
      expect(summary.subtotalMaterialCents, 4000); // 40,00 €

      // Verify Total Net: 136,00 + 40,00 = 176,00 € (17600 cents)
      expect(summary.totalNetCents, 17600);

      // Verify 19% VAT: 176,00 * 0.19 = 33,44 € (3344 cents)
      expect(summary.vatAmountCents, 3344);

      // Verify Gross Total: 176,00 + 33,44 = 209,44 € (20944 cents)
      expect(summary.totalGrossCents, 20944);
    });

    test('Handles fractional hours correctly with integer cent precision', () {
      final items = [
        // 1.5 hours labor @ 68,00 €/hr = 102,00 € (10200 cents)
        DraftLineItem(
          id: '1',
          type: 'labor',
          description: 'Notdienst Fehlersuche',
          quantity: 1.5,
          unit: 'Std',
          unitPriceNetCents: 6800,
        ),
      ];

      final summary = FinancialSummary.calculate(items: items, vatRate: 19.0);

      expect(summary.subtotalLaborCents, 10200);
      expect(summary.subtotalMaterialCents, 0);
      expect(summary.totalNetCents, 10200);
      expect(summary.vatAmountCents, 1938); // 102.00 * 0.19 = 19.38
      expect(summary.totalGrossCents, 12138); // 102.00 + 19.38 = 121.38
    });

    test('Counts flat fees (Anfahrtspauschale) as labor for § 35a', () {
      final items = [
        DraftLineItem(
          id: '1',
          type: 'flat_fee',
          description: 'Anfahrtspauschale',
          quantity: 1.0,
          unit: 'Pauschal',
          unitPriceNetCents: 3500,
        ),
        DraftLineItem(
          id: '2',
          type: 'material',
          description: 'Kabel',
          quantity: 1.0,
          unit: 'Stk',
          unitPriceNetCents: 1000,
        ),
      ];

      final summary = FinancialSummary.calculate(items: items, vatRate: 19.0);

      expect(summary.subtotalLaborCents, 3500);
      expect(summary.subtotalMaterialCents, 1000);
    });
  });
}

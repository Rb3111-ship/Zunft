import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/documents/domain/document_data.dart';
import 'package:zunft_app/features/documents/pdf_generator/din_5008_invoice_template.dart';

import 'helpers/fake_auth_repository.dart';

PdfDocumentData sample({
  String docType = 'invoice',
  String? number = 'RE-2026-0001',
  double vatRate = 19,
  int lineCount = 2,
  String? address = 'Elbchaussee 118, 22763 Hamburg',
  Business? business,
}) {
  final lines = [
    for (var i = 0; i < lineCount; i++)
      DocumentLine(
        type: i.isEven ? 'labor' : 'material',
        description: i.isEven ? 'Demontage Altgerät & Montage Doppelsteckdose' : 'Gira Zweifach-Steckdose reinweiß Unterputz',
        quantity: i.isEven ? 1.5 : 2,
        unit: i.isEven ? 'Std' : 'Stk',
        unitPriceNetCents: i.isEven ? 6800 : 4000,
        totalNetCents: i.isEven ? 10200 : 8000,
      ),
  ];
  final labor = lines.where((l) => l.isService).fold<int>(0, (s, l) => s + l.totalNetCents);
  final material = lines.where((l) => !l.isService).fold<int>(0, (s, l) => s + l.totalNetCents);
  final net = labor + material;
  final vat = (net * vatRate / 100).round();
  return PdfDocumentData(
    docType: docType,
    docNumber: number,
    title: 'Steckdoseninstallation Büro Süd',
    issueDate: DateTime(2026, 10, 1),
    dueDate: DateTime(2026, 10, 15),
    deliveryPeriod: '01.10.2026',
    recipientName: 'Thomas Müller',
    recipientAddress: address,
    lines: lines,
    laborNetCents: labor,
    materialNetCents: material,
    netCents: net,
    vatRate: vatRate,
    vatCents: vat,
    grossCents: net + vat,
    company: CompanyDetails.fromBusiness(business ?? FakeAuthRepository.completeBusiness()),
  );
}

/// Runs [body] and returns everything the pdf package printed (it reports font problems that way).
Future<(T, List<String>)> capturePrints<T>(Future<T> Function() body) async {
  final lines = <String>[];
  final result = await runZoned(body, zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => lines.add(line)));
  return (result, lines);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // the fonts are loaded from the asset bundle

  test('creates a valid PDF', () async {
    final bytes = await Din5008PdfGenerator.generate(sample());
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('umlauts, ß, € and § print with an embedded font (no "no Unicode support" warning)', () async {
    final (bytes, prints) = await capturePrints(() => Din5008PdfGenerator.generate(sample()));
    expect(prints.where((l) => l.contains('Unicode')), isEmpty, reason: prints.join('\n'));
    // The font file is embedded in the document.
    expect(String.fromCharCodes(bytes), contains('Lato'));
  });

  test('works for a quote, a draft preview, a small business and a missing address', () async {
    for (final data in [
      sample(docType: 'quote', number: 'ANG-2026-0001'),
      sample(number: null), // preview without a number
      sample(vatRate: 0),
      sample(address: null),
      sample(business: const Business(id: 'x', name: 'Nur Name', ownerName: '', tradeCategory: 'elektro', defaultHourlyRateCents: 6500, defaultVatRate: 19)),
    ]) {
      final (bytes, prints) = await capturePrints(() => Din5008PdfGenerator.generate(data));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(prints.where((l) => l.contains('Unicode')), isEmpty);
    }
  });

  test('many positions flow onto more than one page', () async {
    final one = await Din5008PdfGenerator.generate(sample(lineCount: 2));
    final many = await Din5008PdfGenerator.generate(sample(lineCount: 70));
    int pages(List<int> b) => RegExp(r'/Type\s*/Page(?![s\w])').allMatches(String.fromCharCodes(b)).length;
    expect(pages(one), 1);
    expect(pages(many), greaterThan(1));
  });
}

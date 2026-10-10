import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/documents/domain/document_data.dart';
import 'package:zunft_app/features/documents/pdf_generator/din_5008_invoice_template.dart';
import 'package:zunft_app/features/documents/pdf_generator/einvoice_xml.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_logo.dart';
import 'pdf_generator_test.dart' as g;

/// The text of the first element called [name] (any prefix) below [from].
String text(XmlNode from, String name) =>
    from.descendants.whereType<XmlElement>().firstWhere((e) => e.name.local == name).innerText.trim();

Iterable<XmlElement> all(XmlNode from, String name) => from.descendants.whereType<XmlElement>().where((e) => e.name.local == name);

XmlDocument parse(PdfDocumentData d, {String? email}) => XmlDocument.parse(buildCrossIndustryInvoice(d, buyerEmail: email));

Business business({String? vatId, String? taxNumber = '48/123/45678', String? iban = 'DE89370400440532013000'}) =>
    Business.fromJson({
      ...FakeAuthRepository.completeBusiness().toUpdateJson(),
      'id': 'b1',
      'vat_id': vatId,
      'tax_number': taxNumber,
      'iban': iban,
      'bic': 'COBADEFFXXX',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the XML is the same invoice as the PDF', () {
    test('number, date, type, parties and the totals are the document\'s own', () {
      final d = g.sample(business: business());
      final x = parse(d, email: 'einkauf@mueller.de');
      expect(text(x, 'ID'), einvoiceGuideline); // first ID is the guideline
      expect(all(x, 'ExchangedDocument').single.children.whereType<XmlElement>().first.innerText, 'RE-2026-0001');
      expect(text(x, 'TypeCode'), '380');
      expect(all(x, 'DateTimeString').first.innerText, '20261001');
      expect(all(x, 'DateTimeString').first.getAttribute('format'), '102');

      expect(text(x, 'LineTotalAmount'), isNotEmpty);
      final sum = all(x, 'SpecifiedTradeSettlementHeaderMonetarySummation').single;
      expect(text(sum, 'TaxBasisTotalAmount'), '${d.netCents ~/ 100}.${(d.netCents % 100).toString().padLeft(2, '0')}');
      expect(text(sum, 'GrandTotalAmount'), '${d.grossCents ~/ 100}.${(d.grossCents % 100).toString().padLeft(2, '0')}');
      expect(text(sum, 'DuePayableAmount'), text(sum, 'GrandTotalAmount'));
      expect(text(sum, 'TaxTotalAmount'), '${d.vatCents ~/ 100}.${(d.vatCents % 100).toString().padLeft(2, '0')}');
      expect(all(sum, 'TaxTotalAmount').single.getAttribute('currencyID'), 'EUR');

      final seller = all(x, 'SellerTradeParty').single;
      expect(text(seller, 'Name'), 'Elektro Test GmbH');
      expect(text(seller, 'CityName'), 'Hamburg');
      final buyer = all(x, 'BuyerTradeParty').single;
      expect(text(buyer, 'Name'), 'Thomas Müller');
      expect(text(buyer, 'LineOne'), 'Elbchaussee 118');
      expect(text(buyer, 'PostcodeCode'), '22763');
      expect(text(buyer, 'URIID'), 'einkauf@mueller.de');
      expect(text(x, 'IBANID'), 'DE89370400440532013000');
      expect(text(x, 'DueDateDateTime'), '20261015');
    });

    test('every position keeps its quantity, unit code, price and total', () {
      final d = g.sample(business: business(), lineCount: 2);
      final lines = all(parse(d), 'IncludedSupplyChainTradeLineItem').toList();
      expect(lines, hasLength(2));
      expect(text(lines[0], 'LineID'), '1');
      expect(text(lines[0], 'BilledQuantity'), '1.5');
      expect(all(lines[0], 'BilledQuantity').single.getAttribute('unitCode'), 'HUR'); // Std
      expect(text(lines[0], 'ChargeAmount'), '68.00');
      expect(text(lines[0], 'LineTotalAmount'), '102.00');
      expect(all(lines[1], 'BilledQuantity').single.getAttribute('unitCode'), 'C62'); // Stk
      expect(text(lines[1], 'LineTotalAmount'), '80.00');
    });

    test('units map to the UN/ECE codes: Std, m, Stk, Pauschal', () {
      final base = g.sample(business: business(), lineCount: 1);
      PdfDocumentData withUnit(String u) => PdfDocumentData(
            docType: 'invoice',
            docNumber: 'RE-2026-0002',
            title: 't',
            issueDate: base.issueDate,
            dueDate: base.dueDate,
            deliveryPeriod: base.deliveryPeriod,
            recipientName: base.recipientName,
            recipientAddress: base.recipientAddress,
            lines: [DocumentLine(type: 'material', description: 'x', quantity: 3, unit: u, unitPriceNetCents: 100, totalNetCents: 300)],
            laborNetCents: 0,
            materialNetCents: 300,
            netCents: 300,
            vatRate: 19,
            vatCents: 57,
            grossCents: 357,
            company: base.company,
          );
      String code(String u) => all(parse(withUnit(u)), 'BilledQuantity').single.getAttribute('unitCode')!;
      expect([code('Std'), code('m'), code('Stk'), code('Pauschal')], ['HUR', 'MTR', 'C62', 'C62']);
    });

    test('19 % is category S with the rate; the same rate is on the lines and in the totals', () {
      final x = parse(g.sample(business: business()));
      final tax = all(x, 'ApplicableHeaderTradeSettlement').single.descendants.whereType<XmlElement>().firstWhere((e) => e.name.local == 'ApplicableTradeTax');
      expect(text(tax, 'CategoryCode'), 'S');
      expect(text(tax, 'RateApplicablePercent'), '19.00');
      expect(text(tax, 'TypeCode'), 'VAT');
      for (final line in all(x, 'IncludedSupplyChainTradeLineItem')) {
        expect(text(line, 'CategoryCode'), 'S');
      }
    });

    test('Kleinunternehmer: category E with the § 19 reason and no VAT', () {
      final d = g.sample(business: business(), vatRate: 0);
      final x = parse(d);
      final tax = all(x, 'ApplicableHeaderTradeSettlement').single.descendants.whereType<XmlElement>().firstWhere((e) => e.name.local == 'ApplicableTradeTax');
      expect(text(tax, 'CategoryCode'), 'E');
      expect(text(tax, 'RateApplicablePercent'), '0.00');
      expect(text(tax, 'ExemptionReason'), contains('§ 19 UStG'));
      expect(text(tax, 'CalculatedAmount'), '0.00');
    });

    test('names and descriptions with & < > " are escaped, not broken', () {
      final base = g.sample(business: business(), lineCount: 1);
      final d = PdfDocumentData(
        docType: 'invoice',
        docNumber: 'RE-2026-0003',
        title: 't',
        issueDate: base.issueDate,
        dueDate: null,
        deliveryPeriod: null,
        recipientName: 'Müller & Söhne <Bau> "GmbH"',
        recipientAddress: 'Weg 1, 20095 Hamburg',
        lines: [DocumentLine(type: 'labor', description: 'A & B < C', quantity: 1, unit: 'Std', unitPriceNetCents: 100, totalNetCents: 100)],
        laborNetCents: 100,
        materialNetCents: 0,
        netCents: 100,
        vatRate: 19,
        vatCents: 19,
        grossCents: 119,
        company: base.company,
      );
      final x = parse(d);
      expect(text(all(x, 'BuyerTradeParty').single, 'Name'), 'Müller & Söhne <Bau> "GmbH"');
      expect(text(all(x, 'IncludedSupplyChainTradeLineItem').single, 'Name'), 'A & B < C');
    });

    test('the delivery period: one date, two dates, or free text (then the issue date)', () {
      PdfDocumentData forPeriod(String? period) {
        final b = g.sample(business: business());
        return PdfDocumentData(
          docType: 'invoice', docNumber: 'RE-2026-0004', title: 't', issueDate: b.issueDate, dueDate: null,
          deliveryPeriod: period, recipientName: b.recipientName, recipientAddress: b.recipientAddress,
          lines: b.lines, laborNetCents: b.laborNetCents, materialNetCents: b.materialNetCents, netCents: b.netCents,
          vatRate: b.vatRate, vatCents: b.vatCents, grossCents: b.grossCents, company: b.company);
      }

      var x = parse(forPeriod('05.10.2026'));
      expect(text(all(x, 'ApplicableHeaderTradeDelivery').single, 'DateTimeString'), '20261005');
      expect(all(x, 'BillingSpecifiedPeriod'), isEmpty);

      x = parse(forPeriod('05.10.2026 - 07.10.2026'));
      expect(text(all(x, 'ApplicableHeaderTradeDelivery').single, 'DateTimeString'), '20261007');
      expect(text(all(x, 'StartDateTime').single, 'DateTimeString'), '20261005');
      expect(text(all(x, 'EndDateTime').single, 'DateTimeString'), '20261007');

      x = parse(forPeriod('im Oktober'));
      expect(text(all(x, 'ApplicableHeaderTradeDelivery').single, 'DateTimeString'), '20261001'); // the issue date
    });

    test('the seller is identified (EN 16931 BR-CO-26): by USt-IdNr, or else by the tax number', () {
      final withVat = all(parse(g.sample(business: business(vatId: 'DE123456789'))), 'SellerTradeParty').single;
      expect(withVat.children.whereType<XmlElement>().first.name.local, 'Name'); // no extra identifier needed
      expect(all(withVat, 'ID').map((e) => '${e.getAttribute('schemeID')}:${e.innerText}'), ['VA:DE123456789', 'FC:48/123/45678']);

      final taxOnly = all(parse(g.sample(business: business())), 'SellerTradeParty').single;
      expect(taxOnly.children.whereType<XmlElement>().first.name.local, 'ID');
      expect(taxOnly.children.whereType<XmlElement>().first.innerText, '48/123/45678');
    });
  });

  group('a Stornorechnung is a credit note', () {
    PdfDocumentData storno() {
      final b = g.sample(business: business());
      return PdfDocumentData(
        docType: 'cancellation',
        docNumber: 'ST-2026-0001',
        title: 'Stornierung der Rechnung RE-2026-0001 vom 01.10.2026',
        issueDate: DateTime(2026, 10, 9),
        dueDate: null,
        deliveryPeriod: b.deliveryPeriod,
        recipientName: b.recipientName,
        recipientAddress: b.recipientAddress,
        lines: [
          for (final l in b.lines)
            DocumentLine(type: l.type, description: l.description, quantity: l.quantity, unit: l.unit,
                unitPriceNetCents: -l.unitPriceNetCents, totalNetCents: -l.totalNetCents),
        ],
        laborNetCents: -b.laborNetCents,
        materialNetCents: -b.materialNetCents,
        netCents: -b.netCents,
        vatRate: b.vatRate,
        vatCents: -b.vatCents,
        grossCents: -b.grossCents,
        company: b.company,
      );
    }

    test('type 381, positive amounts, and it names the invoice it reverses', () {
      final d = storno();
      final x = parse(d);
      expect(text(x, 'TypeCode'), '381');
      final sum = all(x, 'SpecifiedTradeSettlementHeaderMonetarySummation').single;
      expect(text(sum, 'GrandTotalAmount'), '${d.grossCents.abs() ~/ 100}.${(d.grossCents.abs() % 100).toString().padLeft(2, '0')}');
      expect(text(sum, 'GrandTotalAmount').startsWith('-'), isFalse);
      for (final line in all(x, 'IncludedSupplyChainTradeLineItem')) {
        expect(text(line, 'ChargeAmount').startsWith('-'), isFalse);
        expect(text(line, 'LineTotalAmount').startsWith('-'), isFalse);
      }
      final ref = all(x, 'InvoiceReferencedDocument').single;
      expect(text(ref, 'IssuerAssignedID'), 'RE-2026-0001');
      expect(text(ref, 'DateTimeString'), '20261001');
      expect(all(x, 'SpecifiedTradePaymentTerms'), isEmpty); // nothing is payable on a credit note
    });
  });

  group('what is missing is said before anything is issued', () {
    CompanyDetails company({String taxNumber = '48/123/45678', String vatId = '', String iban = 'DE89370400440532013000', String street = 'Hauptstraße 1'}) =>
        CompanyDetails(name: 'X', ownerName: 'Y', street: street, zip: '20095', city: 'Hamburg', taxNumber: taxNumber, vatId: vatId, iban: iban);

    test('nothing missing: null', () => expect(eInvoiceBlockReason(company: company(), recipientAddress: 'Weg 1, 20095 Hamburg'), isNull));

    test('no tax number and no USt-IdNr', () {
      expect(eInvoiceBlockReason(company: company(taxNumber: ''), recipientAddress: 'Weg 1, 20095 Hamburg'), contains('Steuernummer'));
      expect(eInvoiceBlockReason(company: company(taxNumber: '', vatId: 'DE123456789'), recipientAddress: 'Weg 1, 20095 Hamburg'), isNull);
    });

    test('no IBAN, no business address', () {
      expect(eInvoiceBlockReason(company: company(iban: ''), recipientAddress: 'Weg 1, 20095 Hamburg'), contains('IBAN'));
      expect(eInvoiceBlockReason(company: company(street: ''), recipientAddress: 'Weg 1, 20095 Hamburg'), contains('Anschrift des Betriebs'));
    });

    test('the customer needs street, ZIP and city', () {
      for (final a in [null, '', 'Hamburg', 'Weg 1', 'Weg 1, Hamburg']) {
        expect(eInvoiceBlockReason(company: company(), recipientAddress: a), contains('Kunde'), reason: '$a');
      }
    });

    test('a quote and a preview have no e-invoice; building one with missing data throws', () {
      final quote = PdfDocumentData(
        docType: 'quote', docNumber: 'ANG-1', title: 't', issueDate: DateTime(2026), dueDate: null, deliveryPeriod: null,
        recipientName: 'A', recipientAddress: 'Weg 1, 20095 Hamburg', lines: g.sample().lines, laborNetCents: 0,
        materialNetCents: 0, netCents: 0, vatRate: 19, vatCents: 0, grossCents: 0, company: g.sample(business: business()).company);
      expect(() => buildCrossIndustryInvoice(quote), throwsA(isA<EInvoiceException>()));
      expect(() => buildCrossIndustryInvoice(g.sample(number: null, business: business())), throwsA(isA<EInvoiceException>()));
      expect(() => buildCrossIndustryInvoice(g.sample(business: business(iban: null))), throwsA(isA<EInvoiceException>()));
    });
  });

  group('which customers get an e-invoice by default', () {
    test('companies yes, private persons no', () {
      expect(defaultEInvoiceFor(name: 'Hausverwaltung Alster Gmbh'), isTrue);
      expect(defaultEInvoiceFor(name: 'Müller & Söhne GmbH & Co. KG'), isTrue);
      expect(defaultEInvoiceFor(name: 'Immobilienverwaltung Nord'), isTrue);
      expect(defaultEInvoiceFor(name: 'Meier Bau e.K.'), isTrue);
      expect(defaultEInvoiceFor(name: 'Thomas Müller', salutation: 'Firma'), isTrue);
      expect(defaultEInvoiceFor(name: 'Thomas Müller'), isFalse);
      expect(defaultEInvoiceFor(name: 'Sabine Hagen'), isFalse); // "ag" inside a name is not a legal form
      expect(defaultEInvoiceFor(name: 'Frau Seeger', salutation: 'Frau'), isFalse);
    });
  });

  group('the PDF is a PDF/A-3 that carries the XML', () {
    bool has(Uint8List pdf, String s) => String.fromCharCodes(pdf).contains(s);

    test('an e-invoice PDF names the attachment, the profile and PDF/A; a normal PDF does not', () async {
      final d = g.sample(business: business());
      final plain = await Din5008PdfGenerator.generate(d);
      final e = await Din5008PdfGenerator.generate(d, eInvoice: true, logo: onePixelPng);
      expect(has(plain, 'factur-x.xml'), isFalse);
      expect(has(plain, 'pdfaid'), isFalse);
      expect(has(e, 'factur-x.xml'), isTrue);
      expect(has(e, 'EN 16931'), isTrue);
      expect(has(e, '<pdfaid:part>3</pdfaid:part>'), isTrue);
      expect(has(e, '/AFRelationship'), isTrue);
      expect(String.fromCharCodes(e.take(5)), '%PDF-');
    });

    test('missing data stops the e-invoice instead of delivering a half one', () async {
      expect(() => Din5008PdfGenerator.generate(g.sample(business: business(iban: null)), eInvoice: true),
          throwsA(isA<EInvoiceException>()));
    });
  });

  // The official validators (PDF/A-3 by veraPDF and the EN 16931 rules by Mustang). They need Java and
  // the Mustang jar, so they run only where it exists: D:/tmp/ei/mustang.jar, or MUSTANG_JAR.
  final jar = Platform.environment['MUSTANG_JAR'] ?? 'D:/tmp/ei/mustang.jar';
  final canValidate = File(jar).existsSync();

  group('validated by Mustang (PDF/A-3 and EN 16931)', skip: canValidate ? false : 'Mustang jar not found ($jar)', () {
    Future<void> expectValid(String name, Uint8List pdf) async {
      final dir = Directory.systemTemp.createTempSync('einvoice_');
      final file = File('${dir.path}/$name.pdf')..writeAsBytesSync(pdf);
      final result = await Process.run('java', ['-jar', jar, '--action', 'validate', '--source', file.path, '--disable-file-logging']);
      final out = '${result.stdout}${result.stderr}';
      final line = out.split('\n').firstWhere((l) => l.contains('Parsed PDF:'), orElse: () => out);
      expect(line, contains('Parsed PDF:valid'), reason: '$name: $line');
      expect(line, contains('XML:valid'), reason: '$name: $line');
      // Only the notices of the German XRechnung profile (type 27) may remain; no real error.
      final errors = RegExp(r'<error type="(\d+)"').allMatches(out).map((m) => m.group(1)).toList();
      expect(errors, isEmpty, reason: '$name: $out');
      dir.deleteSync(recursive: true);
    }

    test('a normal invoice with and without USt-IdNr, with a logo', () async {
      await expectValid('normal', await Din5008PdfGenerator.generate(g.sample(business: business()), eInvoice: true));
      await expectValid('vat_id_logo',
          await Din5008PdfGenerator.generate(g.sample(business: business(vatId: 'DE123456789')), eInvoice: true, logo: onePixelPng));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('Kleinunternehmer, many positions, special characters', () async {
      await expectValid('kleinunternehmer', await Din5008PdfGenerator.generate(g.sample(business: business(), vatRate: 0), eInvoice: true));
      await expectValid('many', await Din5008PdfGenerator.generate(g.sample(business: business(), lineCount: 40), eInvoice: true));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a Stornorechnung (credit note)', () async {
      final b = g.sample(business: business());
      final storno = PdfDocumentData(
        docType: 'cancellation', docNumber: 'ST-2026-0001',
        title: 'Stornierung der Rechnung RE-2026-0001 vom 01.10.2026', issueDate: DateTime(2026, 10, 9),
        dueDate: null, deliveryPeriod: b.deliveryPeriod, recipientName: b.recipientName, recipientAddress: b.recipientAddress,
        lines: [for (final l in b.lines) DocumentLine(type: l.type, description: l.description, quantity: l.quantity, unit: l.unit, unitPriceNetCents: -l.unitPriceNetCents, totalNetCents: -l.totalNetCents)],
        laborNetCents: -b.laborNetCents, materialNetCents: -b.materialNetCents, netCents: -b.netCents,
        vatRate: b.vatRate, vatCents: -b.vatCents, grossCents: -b.grossCents, company: b.company);
      await expectValid('storno', await Din5008PdfGenerator.generate(storno, eInvoice: true));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/database/app_database.dart';
import 'package:zunft_app/core/sync/sync_mapping.dart';
import 'package:zunft_app/core/utils/address_parser.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';
import 'package:zunft_app/features/documents/domain/document_data.dart';
import 'package:zunft_app/features/review/models/draft_models.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_documents.dart';

DraftDocument draft() => DraftDocument(
      title: 'Steckdose',
      documentType: 'invoice',
      customer: CustomerMatch(extractedName: 'Müller', confidence: 'new'),
      lineItems: [
        DraftLineItem(
            id: '1', type: 'labor', description: 'Montage', quantity: 2, unit: 'Std', unitPriceNetCents: 6800),
        DraftLineItem(
            id: '2', type: 'flat_fee', description: 'Anfahrt', quantity: 1, unit: 'Pauschal', unitPriceNetCents: 3500),
        DraftLineItem(
            id: '3', type: 'material', description: 'Steckdose', quantity: 1, unit: 'Stk', unitPriceNetCents: 4000),
      ],
    );

void main() {
  group('preview totals match the server\'s rules', () {
    // The same example the SQL tests use for create_document(): the app and the database must agree.
    test('labor + flat fee = service, material separate, 19 % VAT', () {
      final data = PdfDocumentData.preview(
          draft: draft(), business: FakeAuthRepository.completeBusiness(), issueDate: DateTime(2026, 10, 1));
      expect(data.laborNetCents, 17100);
      expect(data.materialNetCents, 4000);
      expect(data.netCents, 21100);
      expect(data.vatCents, 4009);
      expect(data.grossCents, 25109);
      expect(data.isPreview, isTrue);
    });

    test('§ 35a deduction is based on the labor amount including VAT', () {
      final data = PdfDocumentData.preview(
          draft: draft(), business: FakeAuthRepository.completeBusiness(), issueDate: DateTime(2026, 10, 1));
      expect(data.laborGrossCents, 20349); // 17100 + 19 %
    });

    test('a small business (0 % VAT) is recognised and the labor amount has no VAT added', () {
      final zero = PdfDocumentData.preview(
        draft: draft(),
        business: withVat(FakeAuthRepository.completeBusiness(), 0),
        issueDate: DateTime(2026, 10, 1),
      );
      expect(zero.isSmallBusiness, isTrue);
      expect(zero.vatCents, 0);
      expect(zero.laborGrossCents, 17100);
      expect(zero.grossCents, 21100);
    });
  });

  group('from a stored document', () {
    test('uses the stored (server) numbers and does not recalculate', () async {
      final companion =
          documentFromRemote({...remoteDocument('d1', gross: 99999), 'updated_at': '2026-10-01T10:00:00Z'});
      final row = IssuedDocument(
        id: companion.id.value,
        businessId: companion.businessId.value,
        docType: companion.docType.value,
        docNumber: companion.docNumber.value,
        status: companion.status.value,
        title: companion.title.value,
        dateIssued: companion.dateIssued.value,
        dateDue: companion.dateDue.value,
        deliveryPeriod: companion.deliveryPeriod.value,
        subtotalLaborCents: companion.subtotalLaborCents.value,
        subtotalMaterialCents: companion.subtotalMaterialCents.value,
        totalNetCents: companion.totalNetCents.value,
        vatRate: companion.vatRate.value,
        vatAmountCents: companion.vatAmountCents.value,
        totalGrossCents: companion.totalGrossCents.value,
        lineItemsJson: companion.lineItemsJson.value,
        recipientName: companion.recipientName.value,
        recipientAddress: companion.recipientAddress.value,
        updatedAt: DateTime.utc(2026, 10, 1),
      );

      final data = PdfDocumentData.fromIssued(row, FakeAuthRepository.completeBusiness());

      expect(data.docNumber, 'RE-2026-0001');
      expect(data.isPreview, isFalse);
      expect(data.grossCents, 99999); // whatever the server stored
      expect(data.vatRate, 19.0); // NUMERIC arrived as the string "19.00"
      expect(data.lines, hasLength(2));
      expect(data.lines.first.isService, isTrue);
      expect(data.recipientName, 'Thomas Müller');
      expect(data.issueDate, DateTime(2026, 10, 1));
      expect(data.dueDate, DateTime(2026, 10, 15));
    });

    test('documentFromRemote accepts JSON given as strings too', () {
      final j = remoteDocument('d2');
      final c = documentFromRemote({
        ...j,
        'line_items': jsonEncode(j['line_items']),
        'recipient_snapshot': jsonEncode(j['recipient_snapshot']),
        'updated_at': '2026-10-01T10:00:00Z',
      });
      expect(c.recipientName.value, 'Thomas Müller');
      expect(jsonDecode(c.lineItemsJson.value) as List, hasLength(2));
    });
  });

  group('parseGermanAddress', () {
    test('splits street, ZIP and city', () {
      final a = parseGermanAddress('Elbchaussee 118, 22763 Hamburg');
      expect((a.street, a.zip, a.city), ('Elbchaussee 118', '22763', 'Hamburg'));
    });
    test('works without a comma and with multi-word cities', () {
      final a = parseGermanAddress('Mühlenkamp 34 22303 Hamburg Winterhude');
      expect((a.street, a.zip, a.city), ('Mühlenkamp 34', '22303', 'Hamburg Winterhude'));
    });
    test('keeps everything as the street when there is no ZIP', () {
      final a = parseGermanAddress('Hinterhof links, Elbchaussee');
      expect(a.street, 'Hinterhof links, Elbchaussee');
      expect(a.zip, isNull);
      expect(a.city, isNull);
    });
    test('empty input gives nothing', () {
      expect(parseGermanAddress(null).street, isNull);
      expect(parseGermanAddress('  ').street, isNull);
    });
    test('a ZIP-only address does not invent a city', () {
      final a = parseGermanAddress('22763');
      expect(a.city, isNull);
    });
  });
}

/// A copy of a business with another VAT rate.
Business withVat(Business b, double rate) =>
    Business.fromJson({...b.toUpdateJson(), 'id': b.id, 'default_vat_rate': rate});

import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/features/auth/data/business_models.dart';

void main() {
  final row = <String, dynamic>{
    'id': 'b1',
    'name': 'Elektro Test',
    'owner_name': 'Erika',
    'trade_category': 'elektro',
    'tax_number': null,
    'vat_id': 'DE123456789',
    'iban': null,
    'bic': null,
    'bank_name': null,
    'phone': null,
    'email': null,
    'website': null,
    'address_street': 'Elbchaussee 1',
    'address_zip': '22763',
    'address_city': 'Hamburg',
    'default_hourly_rate_cents': 6800,
    'default_vat_rate': 19, // NUMERIC may arrive as int, double or string
  };

  test('Business.fromJson handles NUMERIC as int, double and string', () {
    expect(Business.fromJson(row).defaultVatRate, 19.0);
    expect(Business.fromJson({...row, 'default_vat_rate': 7.5}).defaultVatRate, 7.5);
    expect(Business.fromJson({...row, 'default_vat_rate': '19.00'}).defaultVatRate, 19.0);
  });

  test('toUpdateJson only contains editable columns', () {
    final json = Business.fromJson(row).toUpdateJson();
    expect(json.keys, isNot(contains('id')));
    expect(json.keys, isNot(contains('subscription_status')));
    expect(json['name'], 'Elektro Test');
    expect(json['default_hourly_rate_cents'], 6800);
  });

  test('missingInvoiceFields lists what § 14 UStG invoices still need', () {
    expect(Business.fromJson(row).missingInvoiceFields, ['IBAN']);
    final empty = Business.fromJson({
      ...row,
      'vat_id': null,
      'address_street': null,
    });
    expect(empty.missingInvoiceFields, ['Anschrift', 'Steuernummer oder USt-IdNr.', 'IBAN']);
    final complete = Business.fromJson({...row, 'iban': 'DE89370400440532013000'});
    expect(complete.missingInvoiceFields, isEmpty);
  });

  test('only owner and buero may edit business data', () {
    UserProfile p(String role) => UserProfile(id: 'u', businessId: 'b', fullName: 'x', role: role);
    expect(p('owner').canEditBusiness, isTrue);
    expect(p('buero').canEditBusiness, isTrue);
    expect(p('geselle').canEditBusiness, isFalse);
    expect(p('meister').canEditBusiness, isFalse);
  });
}

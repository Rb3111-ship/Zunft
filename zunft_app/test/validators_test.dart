import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/core/utils/validators.dart';

void main() {
  group('email', () {
    test('accepts normal addresses', () {
      expect(Validators.email('a@b.de'), isNull);
      expect(Validators.email('  max.mustermann@firma-hamburg.de '), isNull);
    });
    test('rejects empty and malformed', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email(null), isNotNull);
      expect(Validators.email('abc'), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
      expect(Validators.email('a b@c.de'), isNotNull);
    });
  });

  group('password', () {
    test('needs at least 8 characters', () {
      expect(Validators.password('1234567'), isNotNull);
      expect(Validators.password('12345678'), isNull);
      expect(Validators.password(''), isNotNull);
    });
  });

  group('iban', () {
    test('empty is allowed (optional)', () => expect(Validators.iban(''), isNull));
    test('accepts valid IBANs, with spaces and lowercase', () {
      expect(Validators.iban('DE89 3704 0044 0532 0130 00'), isNull);
      expect(Validators.iban('de89370400440532013000'), isNull);
      expect(Validators.iban('GB82 WEST 1234 5698 7654 32'), isNull);
    });
    test('rejects wrong checksum, length and format', () {
      expect(Validators.iban('DE89 3704 0044 0532 0130 01'), isNotNull); // last digit changed
      expect(Validators.iban('DE89 3704 0044 0532 0130'), isNotNull); // too short for DE
      expect(Validators.iban('12345'), isNotNull);
    });
  });

  group('vatId', () {
    test('optional, DE + 9 digits', () {
      expect(Validators.vatId(''), isNull);
      expect(Validators.vatId('DE123456789'), isNull);
      expect(Validators.vatId('de 123 456 789'), isNull);
      expect(Validators.vatId('DE12345678'), isNotNull);
      expect(Validators.vatId('FR123456789'), isNotNull);
    });
  });

  group('rates', () {
    test('hourly rate accepts German input within 1..1000 EUR', () {
      expect(Validators.hourlyRate('68'), isNull);
      expect(Validators.hourlyRate('68,50'), isNull);
      expect(Validators.hourlyRate('0,50'), isNotNull);
      expect(Validators.hourlyRate('1500'), isNotNull);
      expect(Validators.hourlyRate('abc'), isNotNull);
      expect(Validators.hourlyRate(''), isNotNull);
    });
    test('vat rate accepts 0..100 with comma or point', () {
      expect(Validators.vatRate('19'), isNull);
      expect(Validators.vatRate('7'), isNull);
      expect(Validators.vatRate('0'), isNull);
      expect(Validators.vatRate('19,0 %'), isNull);
      expect(Validators.vatRate('101'), isNotNull);
      expect(Validators.vatRate('-1'), isNotNull);
      expect(Validators.vatRate(''), isNotNull);
      expect(Validators.parseRate('7,5'), 7.5);
    });
  });

  group('phone and tidy', () {
    test('a phone number needs its area code: starts with 0 or +', () {
      expect(Validators.phone(''), isNull);
      expect(Validators.phone('040 1234567'), isNull);
      expect(Validators.phone('0157 5334 9727'), isNull);
      expect(Validators.phone('+49 40 1234567'), isNull);
      expect(Validators.phone('040/123 45 67'), isNull);
      expect(Validators.phone('(040) 123-4567'), isNull);
      expect(Validators.phone('15753349727'), isNotNull); // the leading 0 is missing
      expect(Validators.phone('12345'), isNotNull);
      expect(Validators.phone('abc'), isNotNull);
    });

    test('tidy collapses runs of spaces and line breaks', () {
      expect(Validators.tidy('  Test  Steckdose  Keller '), 'Test Steckdose Keller');
      expect(Validators.tidy('Zeile eins\n  Zeile zwei'), 'Zeile eins Zeile zwei');
      expect(Validators.tidy(''), '');
    });
  });
}

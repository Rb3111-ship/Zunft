import 'currency_formatter.dart';

/// Form validators (German UI strings). Each returns null when valid, otherwise a message.
class Validators {
  static const int minPasswordLength = 8;

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Bitte E-Mail-Adresse eingeben';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(v)) return 'Ungültige E-Mail-Adresse';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Bitte Passwort eingeben';
    if (v.length < minPasswordLength) return 'Mindestens $minPasswordLength Zeichen';
    return null;
  }

  static String? required(String? value, String label) {
    if ((value?.trim() ?? '').isEmpty) return '$label darf nicht leer sein';
    return null;
  }

  /// Optional German USt-IdNr.: "DE" + 9 digits.
  static String? vatId(String? value) {
    final v = _compact(value);
    if (v.isEmpty) return null;
    if (!RegExp(r'^DE\d{9}$').hasMatch(v)) return 'Format: DE und 9 Ziffern';
    return null;
  }

  /// Optional IBAN with the ISO 13616 mod-97 check (any country, 15-34 chars).
  static String? iban(String? value) {
    final v = _compact(value);
    if (v.isEmpty) return null;
    if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$').hasMatch(v)) return 'Ungültige IBAN';
    if (v.startsWith('DE') && v.length != 22) return 'Deutsche IBAN hat 22 Zeichen';
    final rearranged = v.substring(4) + v.substring(0, 4);
    var remainder = 0;
    for (final unit in rearranged.codeUnits) {
      // Letters A-Z map to 10-35, digits stay as they are.
      final digits = unit >= 65 ? (unit - 55).toString() : String.fromCharCode(unit);
      for (final d in digits.split('')) {
        remainder = (remainder * 10 + int.parse(d)) % 97;
      }
    }
    return remainder == 1 ? null : 'IBAN-Prüfsumme stimmt nicht';
  }

  /// Required hourly rate in euros ("68", "68,50"); between 1 and 1000 EUR.
  static String? hourlyRate(String? value) {
    final cents = CurrencyFormatter.parseToCents(value ?? '');
    if (cents == null) return 'Bitte gültigen Betrag eingeben';
    if (cents < 100 || cents > 100000) return 'Zwischen 1 und 1.000 € erwartet';
    return null;
  }

  /// Required VAT rate in percent ("19", "7", "0", "19,0").
  static String? vatRate(String? value) {
    final rate = parseRate(value);
    if (rate == null) return 'Bitte gültigen Satz eingeben';
    if (rate < 0 || rate > 100) return 'Zwischen 0 und 100 % erwartet';
    return null;
  }

  static double? parseRate(String? value) {
    final s = (value ?? '').replaceAll('%', '').replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) return null;
    return double.tryParse(s);
  }

  /// Optional phone number: an area code is needed, so it starts with 0 or + ("040 1234567",
  /// "+49 40 1234567"). Spaces, dashes, slashes and brackets are allowed. A number typed without
  /// the leading 0 ("15753349727") prints on invoices as something nobody can call.
  static String? phone(String? value) {
    final v = (value ?? '').replaceAll(RegExp(r'[\s\-/()]'), '');
    if (v.isEmpty) return null;
    if (!RegExp(r'^(\+\d{6,15}|0\d{5,15})$').hasMatch(v)) {
      return 'Mit Vorwahl, z. B. 040 1234567 oder +49 40 1234567';
    }
    return null;
  }

  /// Trims and turns runs of spaces/line breaks into a single space ("Test  Steckdose" -> "Test Steckdose").
  static String tidy(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Uppercase, no spaces: normalized form to store.
  static String normalizeCompact(String? value) => _compact(value);

  static String _compact(String? value) => (value ?? '').replaceAll(RegExp(r'\s'), '').toUpperCase();
}

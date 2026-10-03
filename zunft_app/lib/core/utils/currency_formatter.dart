import 'package:intl/intl.dart';

/// Utilities for German currency formatting according to DIN standards
class CurrencyFormatter {
  static final NumberFormat _euroFormat = NumberFormat.currency(
    locale: 'de_DE',
    symbol: '€',
    decimalDigits: 2,
  );

  /// Converts cents (integer) to formatted German Euro string, e.g. 6500 -> "65,00 €"
  static String formatCents(int cents) {
    final euros = cents / 100.0;
    return _euroFormat.format(euros);
  }

  /// Converts cents to German Euro string with EUR suffix for PDF font compatibility, e.g. 6500 -> "65,00 EUR"
  static String formatCentsEur(int cents) {
    final euros = (cents / 100.0).toStringAsFixed(2).replaceAll('.', ',');
    return '$euros EUR';
  }

  /// Converts euros (double) to formatted German Euro string, e.g. 65.0 -> "65,00 €"
  static String formatEuros(double euros) {
    return _euroFormat.format(euros);
  }

  /// Parses a price string to cents. Accepts German ("1.250,50", "65,5") and
  /// plain ("65.50", "40") input. Returns null for empty, negative or invalid input.
  ///
  /// A comma is always the decimal separator. Without a comma, a single dot followed
  /// by one or two digits is a decimal point ("65.50"); any other dot is a thousands
  /// separator ("1.250", "1.250.000").
  static int? parseToCents(String input) {
    var s = input.replaceAll(RegExp(r'[€\s ]|EUR', caseSensitive: false), '');
    if (s.isEmpty) return null;

    if (s.contains(',')) {
      if (!RegExp(r'^(\d{1,3}(\.\d{3})+|\d+),\d{1,2}$').hasMatch(s)) return null;
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else if (RegExp(r'^\d+\.\d{1,2}$').hasMatch(s)) {
      // plain decimal point, keep as is
    } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
      s = s.replaceAll('.', '');
    } else if (!RegExp(r'^\d+$').hasMatch(s)) {
      return null;
    }

    final val = double.tryParse(s);
    if (val == null || val.isNaN || val.isInfinite) return null;
    return (val * 100).round();
  }
}

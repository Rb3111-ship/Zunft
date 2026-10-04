import 'package:intl/date_symbol_data_local.dart';

/// Utilities for German date formatting according to DIN 5008 standards
class DateFormatter {
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (!_initialized) {
      await initializeDateFormatting('de_DE', null);
      _initialized = true;
    }
  }

  /// Formats DateTime to "01.10.2026"
  static String formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day.$month.$year';
  }

  /// Formats DateTime to "01.10.2026 14:30"
  static String formatDateTime(DateTime date) {
    final d = formatDate(date);
    final hour = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$d $hour:$min';
  }

  /// Formats DateTime to German Month Year, e.g. "Oktober 2026"
  static String formatMonthYear(DateTime date) {
    const months = [
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

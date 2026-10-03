import '../database/app_database.dart';

/// A customer that may be the same person as a new one.
class DuplicateMatch {
  const DuplicateMatch(this.customer, {required this.strong});

  final Customer customer;

  /// Same name AND a second thing that matches (address, phone or e-mail): almost certainly the
  /// same customer. Otherwise the name matches and nothing contradicts it, but too little is known.
  final bool strong;
}

/// Finds customers who may be the same as the one described.
///
/// A name alone does not identify a customer (there are many Müllers), so:
/// - same name + same address, phone or e-mail  -> strong match,
/// - same name, but the address differs          -> NOT a match (a different person),
/// - same name, address missing on either side   -> possible match (worth a question).
List<DuplicateMatch> findDuplicateCustomers(
  Iterable<Customer> existing, {
  required String name,
  String? firstName,
  String? street,
  String? zip,
  String? phone,
  String? email,
  String? excludeId,
}) {
  final wantedName = _nameKey(firstName, name);
  if (wantedName.isEmpty) return const [];
  final wantedStreet = _streetKey(street);
  final wantedZip = _digits(zip);
  final wantedPhone = _phoneKey(phone);
  final wantedMail = (email ?? '').trim().toLowerCase();

  final result = <DuplicateMatch>[];
  for (final c in existing) {
    if (c.id == excludeId) continue;
    if (_nameKey(c.firstName, c.name) != wantedName) continue;

    final cStreet = _streetKey(c.street);
    final cZip = _digits(c.zip);
    final cPhone = _phoneKey(c.phone);
    final cMail = (c.email ?? '').trim().toLowerCase();

    final sameAddress = wantedZip.isNotEmpty && wantedZip == cZip && wantedStreet.isNotEmpty && wantedStreet == cStreet;
    final samePhone = wantedPhone.isNotEmpty && wantedPhone == cPhone;
    final sameMail = wantedMail.isNotEmpty && wantedMail == cMail;
    if (sameAddress || samePhone || sameMail) {
      result.add(DuplicateMatch(c, strong: true));
      continue;
    }

    final differentPlace = (wantedZip.isNotEmpty && cZip.isNotEmpty && wantedZip != cZip) ||
        (wantedStreet.isNotEmpty && cStreet.isNotEmpty && wantedStreet != cStreet);
    if (!differentPlace) result.add(DuplicateMatch(c, strong: false));
  }
  // strong ones first
  result.sort((a, b) => (b.strong ? 1 : 0) - (a.strong ? 1 : 0));
  return result;
}

/// Lower case, umlauts and ß spelled out, punctuation dropped, words in alphabetical order, so
/// "Müller, Thomas" equals "thomas mueller".
String _nameKey(String? first, String last) {
  final words = _fold('${first ?? ''} $last').split(' ').where((w) => w.isNotEmpty).toList()..sort();
  return words.join(' ');
}

/// "Hauptstraße 5" equals "Hauptstr. 5".
String _streetKey(String? street) {
  final s = _fold(street ?? '').replaceAll(RegExp(r'strasse|str\b'), 'str').replaceAll(' ', '');
  return s;
}

String _fold(String s) => s
    .toLowerCase()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss')
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _digits(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');

/// The last 8 digits, so "+49 171 1234567" equals "0171 1234567".
String _phoneKey(String? phone) {
  final d = _digits(phone);
  if (d.length < 6) return '';
  return d.length > 8 ? d.substring(d.length - 8) : d;
}

/// A German address split into the parts a customer record stores.
class ParsedAddress {
  const ParsedAddress({this.street, this.zip, this.city});
  final String? street;
  final String? zip;
  final String? city;
}

/// Splits "Elbchaussee 118, 22763 Hamburg" (also "Elbchaussee 118 22763 Hamburg") into street,
/// ZIP and city. If no 5-digit ZIP is found the whole text is kept as the street, so nothing
/// the user dictated is lost.
ParsedAddress parseGermanAddress(String? raw) {
  final text = (raw ?? '').replaceAll('\n', ', ').trim();
  if (text.isEmpty) return const ParsedAddress();

  final m = RegExp(r'^(.*?)[,\s]*\b(\d{5})\s+([^,\d][^,]*)$').firstMatch(text);
  if (m == null) return ParsedAddress(street: text);

  final street = m.group(1)!.trim().replaceAll(RegExp(r',$'), '').trim();
  return ParsedAddress(
    street: street.isEmpty ? null : street,
    zip: m.group(2),
    city: m.group(3)!.trim(),
  );
}

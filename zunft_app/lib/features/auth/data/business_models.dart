/// A staff member linked to Supabase Auth (table `profiles`).
class UserProfile {
  final String id;
  final String businessId;
  final String fullName;
  final String role; // owner | meister | geselle | buero

  /// False once the owner switched this person's access off (e.g. they left the business).
  final bool active;

  const UserProfile({
    required this.id,
    required this.businessId,
    required this.fullName,
    required this.role,
    this.active = true,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        businessId: json['business_id'] as String,
        fullName: json['full_name'] as String,
        role: json['role'] as String,
        active: (json['active'] as bool?) ?? true,
      );

  /// Owners and the office role may edit business data (matches the RLS policy).
  bool get canEditBusiness => role == 'owner' || role == 'buero';

  /// Boss and office: see every job, assign jobs, issue and see documents. Everyone else (Meister,
  /// Geselle) sees only the jobs assigned to them. A self-employed person is an owner.
  bool get isManager => role == 'owner' || role == 'buero';

  /// Only the owner invites people and switches access on and off.
  bool get isOwner => role == 'owner';
}

/// The business (table `businesses`): the data printed on every quote and invoice.
class Business {
  final String id;
  final String name;
  final String ownerName;
  final String tradeCategory;
  final String? taxNumber;
  final String? vatId;
  final String? iban;
  final String? bic;
  final String? bankName;
  final String? phone;
  final String? email;
  final String? website;
  final String? addressStreet;
  final String? addressZip;
  final String? addressCity;
  final int defaultHourlyRateCents;
  final double defaultVatRate;

  const Business({
    required this.id,
    required this.name,
    required this.ownerName,
    required this.tradeCategory,
    this.taxNumber,
    this.vatId,
    this.iban,
    this.bic,
    this.bankName,
    this.phone,
    this.email,
    this.website,
    this.addressStreet,
    this.addressZip,
    this.addressCity,
    required this.defaultHourlyRateCents,
    required this.defaultVatRate,
  });

  /// Column list for `.select(...)`.
  static const String columns = 'id, name, owner_name, trade_category, tax_number, vat_id, iban, bic, '
      'bank_name, phone, email, website, address_street, address_zip, address_city, '
      'default_hourly_rate_cents, default_vat_rate';

  factory Business.fromJson(Map<String, dynamic> json) => Business(
        id: json['id'] as String,
        name: json['name'] as String,
        ownerName: json['owner_name'] as String,
        tradeCategory: json['trade_category'] as String,
        taxNumber: json['tax_number'] as String?,
        vatId: json['vat_id'] as String?,
        iban: json['iban'] as String?,
        bic: json['bic'] as String?,
        bankName: json['bank_name'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        website: json['website'] as String?,
        addressStreet: json['address_street'] as String?,
        addressZip: json['address_zip'] as String?,
        addressCity: json['address_city'] as String?,
        defaultHourlyRateCents: (json['default_hourly_rate_cents'] as num).toInt(),
        // NUMERIC columns can arrive as int, double or String depending on the transport.
        defaultVatRate: double.parse(json['default_vat_rate'].toString()),
      );

  /// Columns a user may edit. Never includes id, subscription_status or location.
  Map<String, dynamic> toUpdateJson() => {
        'name': name,
        'owner_name': ownerName,
        'trade_category': tradeCategory,
        'tax_number': taxNumber,
        'vat_id': vatId,
        'iban': iban,
        'bic': bic,
        'bank_name': bankName,
        'phone': phone,
        'email': email,
        'website': website,
        'address_street': addressStreet,
        'address_zip': addressZip,
        'address_city': addressCity,
        'default_hourly_rate_cents': defaultHourlyRateCents,
        'default_vat_rate': defaultVatRate,
      };

  /// True when everything an invoice needs from the sender is filled in.
  /// § 14 UStG requires the sender's name, address and a tax number or USt-IdNr.
  List<String> get missingInvoiceFields => [
        if (_blank(addressStreet) || _blank(addressZip) || _blank(addressCity)) 'Anschrift',
        if (_blank(taxNumber) && _blank(vatId)) 'Steuernummer oder USt-IdNr.',
        if (_blank(iban)) 'IBAN',
      ];

  static bool _blank(String? v) => v == null || v.trim().isEmpty;
}

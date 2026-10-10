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

  /// May Meister and Geselle create their own customers and jobs? Set by the owner; off by default.
  final bool employeesCanCreate;

  /// Days after a job is closed until the audio of its voice notes is deleted (the text stays).
  /// The business may shorten this, never go above 90 (enforced by the database).
  final int recordingRetentionDays;

  /// Storage path of the logo printed on the PDFs (documents bucket), or null.
  final String? logoPath;

  /// Percent added to the price of material that comes from receipts (Belege) when it is invoiced.
  final double materialMarkupPercent;

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
    this.employeesCanCreate = false,
    this.materialMarkupPercent = 0,
    this.recordingRetentionDays = 90,
    this.logoPath,
  });

  Business withEmployeesCanCreate(bool value) => Business(
        id: id,
        name: name,
        ownerName: ownerName,
        tradeCategory: tradeCategory,
        taxNumber: taxNumber,
        vatId: vatId,
        iban: iban,
        bic: bic,
        bankName: bankName,
        phone: phone,
        email: email,
        website: website,
        addressStreet: addressStreet,
        addressZip: addressZip,
        addressCity: addressCity,
        defaultHourlyRateCents: defaultHourlyRateCents,
        defaultVatRate: defaultVatRate,
        employeesCanCreate: value,
        materialMarkupPercent: materialMarkupPercent,
        recordingRetentionDays: recordingRetentionDays,
        logoPath: logoPath,
      );

  /// Column list for `.select(...)`.
  static const String columns = 'id, name, owner_name, trade_category, tax_number, vat_id, iban, bic, '
      'bank_name, phone, email, website, address_street, address_zip, address_city, '
      'default_hourly_rate_cents, default_vat_rate, employees_can_create, material_markup_percent, recording_retention_days, logo_path';

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
        employeesCanCreate: (json['employees_can_create'] as bool?) ?? false,
        materialMarkupPercent: double.parse((json['material_markup_percent'] ?? 0).toString()),
        recordingRetentionDays: (json['recording_retention_days'] as num?)?.toInt() ?? 90,
        logoPath: json['logo_path'] as String?,
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
        'material_markup_percent': materialMarkupPercent,
        'recording_retention_days': recordingRetentionDays,
        'logo_path': logoPath,
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

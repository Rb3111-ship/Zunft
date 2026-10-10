// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CustomersTable extends Customers
    with TableInfo<$CustomersTable, Customer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _businessIdMeta =
      const VerificationMeta('businessId');
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
      'business_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _salutationMeta =
      const VerificationMeta('salutation');
  @override
  late final GeneratedColumn<String> salutation = GeneratedColumn<String>(
      'salutation', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _firstNameMeta =
      const VerificationMeta('firstName');
  @override
  late final GeneratedColumn<String> firstName = GeneratedColumn<String>(
      'first_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
      'email', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
      'phone', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _streetMeta = const VerificationMeta('street');
  @override
  late final GeneratedColumn<String> street = GeneratedColumn<String>(
      'street', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _zipMeta = const VerificationMeta('zip');
  @override
  late final GeneratedColumn<String> zip = GeneratedColumn<String>(
      'zip', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _cityMeta = const VerificationMeta('city');
  @override
  late final GeneratedColumn<String> city = GeneratedColumn<String>(
      'city', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _mergedIntoMeta =
      const VerificationMeta('mergedInto');
  @override
  late final GeneratedColumn<String> mergedInto = GeneratedColumn<String>(
      'merged_into', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        businessId,
        salutation,
        name,
        firstName,
        email,
        phone,
        street,
        zip,
        city,
        notes,
        mergedInto,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'customers';
  @override
  VerificationContext validateIntegrity(Insertable<Customer> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
          _businessIdMeta,
          businessId.isAcceptableOrUnknown(
              data['business_id']!, _businessIdMeta));
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('salutation')) {
      context.handle(
          _salutationMeta,
          salutation.isAcceptableOrUnknown(
              data['salutation']!, _salutationMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('first_name')) {
      context.handle(_firstNameMeta,
          firstName.isAcceptableOrUnknown(data['first_name']!, _firstNameMeta));
    }
    if (data.containsKey('email')) {
      context.handle(
          _emailMeta, email.isAcceptableOrUnknown(data['email']!, _emailMeta));
    }
    if (data.containsKey('phone')) {
      context.handle(
          _phoneMeta, phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta));
    }
    if (data.containsKey('street')) {
      context.handle(_streetMeta,
          street.isAcceptableOrUnknown(data['street']!, _streetMeta));
    }
    if (data.containsKey('zip')) {
      context.handle(
          _zipMeta, zip.isAcceptableOrUnknown(data['zip']!, _zipMeta));
    }
    if (data.containsKey('city')) {
      context.handle(
          _cityMeta, city.isAcceptableOrUnknown(data['city']!, _cityMeta));
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('merged_into')) {
      context.handle(
          _mergedIntoMeta,
          mergedInto.isAcceptableOrUnknown(
              data['merged_into']!, _mergedIntoMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Customer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Customer(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      businessId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}business_id'])!,
      salutation: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}salutation']),
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      firstName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}first_name']),
      email: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}email']),
      phone: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}phone']),
      street: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}street']),
      zip: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}zip']),
      city: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}city']),
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
      mergedInto: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}merged_into']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $CustomersTable createAlias(String alias) {
    return $CustomersTable(attachedDatabase, alias);
  }
}

class Customer extends DataClass implements Insertable<Customer> {
  final String id;
  final String businessId;
  final String? salutation;
  final String name;
  final String? firstName;
  final String? email;
  final String? phone;
  final String? street;
  final String? zip;
  final String? city;
  final String? notes;

  /// Set when this customer was merged into another one: hidden from lists and pickers, but kept,
  /// because issued documents still point at it (they are frozen by law).
  final String? mergedInto;
  final DateTime updatedAt;
  const Customer(
      {required this.id,
      required this.businessId,
      this.salutation,
      required this.name,
      this.firstName,
      this.email,
      this.phone,
      this.street,
      this.zip,
      this.city,
      this.notes,
      this.mergedInto,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    if (!nullToAbsent || salutation != null) {
      map['salutation'] = Variable<String>(salutation);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || firstName != null) {
      map['first_name'] = Variable<String>(firstName);
    }
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || street != null) {
      map['street'] = Variable<String>(street);
    }
    if (!nullToAbsent || zip != null) {
      map['zip'] = Variable<String>(zip);
    }
    if (!nullToAbsent || city != null) {
      map['city'] = Variable<String>(city);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || mergedInto != null) {
      map['merged_into'] = Variable<String>(mergedInto);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CustomersCompanion toCompanion(bool nullToAbsent) {
    return CustomersCompanion(
      id: Value(id),
      businessId: Value(businessId),
      salutation: salutation == null && nullToAbsent
          ? const Value.absent()
          : Value(salutation),
      name: Value(name),
      firstName: firstName == null && nullToAbsent
          ? const Value.absent()
          : Value(firstName),
      email:
          email == null && nullToAbsent ? const Value.absent() : Value(email),
      phone:
          phone == null && nullToAbsent ? const Value.absent() : Value(phone),
      street:
          street == null && nullToAbsent ? const Value.absent() : Value(street),
      zip: zip == null && nullToAbsent ? const Value.absent() : Value(zip),
      city: city == null && nullToAbsent ? const Value.absent() : Value(city),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      mergedInto: mergedInto == null && nullToAbsent
          ? const Value.absent()
          : Value(mergedInto),
      updatedAt: Value(updatedAt),
    );
  }

  factory Customer.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Customer(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      salutation: serializer.fromJson<String?>(json['salutation']),
      name: serializer.fromJson<String>(json['name']),
      firstName: serializer.fromJson<String?>(json['firstName']),
      email: serializer.fromJson<String?>(json['email']),
      phone: serializer.fromJson<String?>(json['phone']),
      street: serializer.fromJson<String?>(json['street']),
      zip: serializer.fromJson<String?>(json['zip']),
      city: serializer.fromJson<String?>(json['city']),
      notes: serializer.fromJson<String?>(json['notes']),
      mergedInto: serializer.fromJson<String?>(json['mergedInto']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'salutation': serializer.toJson<String?>(salutation),
      'name': serializer.toJson<String>(name),
      'firstName': serializer.toJson<String?>(firstName),
      'email': serializer.toJson<String?>(email),
      'phone': serializer.toJson<String?>(phone),
      'street': serializer.toJson<String?>(street),
      'zip': serializer.toJson<String?>(zip),
      'city': serializer.toJson<String?>(city),
      'notes': serializer.toJson<String?>(notes),
      'mergedInto': serializer.toJson<String?>(mergedInto),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Customer copyWith(
          {String? id,
          String? businessId,
          Value<String?> salutation = const Value.absent(),
          String? name,
          Value<String?> firstName = const Value.absent(),
          Value<String?> email = const Value.absent(),
          Value<String?> phone = const Value.absent(),
          Value<String?> street = const Value.absent(),
          Value<String?> zip = const Value.absent(),
          Value<String?> city = const Value.absent(),
          Value<String?> notes = const Value.absent(),
          Value<String?> mergedInto = const Value.absent(),
          DateTime? updatedAt}) =>
      Customer(
        id: id ?? this.id,
        businessId: businessId ?? this.businessId,
        salutation: salutation.present ? salutation.value : this.salutation,
        name: name ?? this.name,
        firstName: firstName.present ? firstName.value : this.firstName,
        email: email.present ? email.value : this.email,
        phone: phone.present ? phone.value : this.phone,
        street: street.present ? street.value : this.street,
        zip: zip.present ? zip.value : this.zip,
        city: city.present ? city.value : this.city,
        notes: notes.present ? notes.value : this.notes,
        mergedInto: mergedInto.present ? mergedInto.value : this.mergedInto,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Customer copyWithCompanion(CustomersCompanion data) {
    return Customer(
      id: data.id.present ? data.id.value : this.id,
      businessId:
          data.businessId.present ? data.businessId.value : this.businessId,
      salutation:
          data.salutation.present ? data.salutation.value : this.salutation,
      name: data.name.present ? data.name.value : this.name,
      firstName: data.firstName.present ? data.firstName.value : this.firstName,
      email: data.email.present ? data.email.value : this.email,
      phone: data.phone.present ? data.phone.value : this.phone,
      street: data.street.present ? data.street.value : this.street,
      zip: data.zip.present ? data.zip.value : this.zip,
      city: data.city.present ? data.city.value : this.city,
      notes: data.notes.present ? data.notes.value : this.notes,
      mergedInto:
          data.mergedInto.present ? data.mergedInto.value : this.mergedInto,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Customer(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('salutation: $salutation, ')
          ..write('name: $name, ')
          ..write('firstName: $firstName, ')
          ..write('email: $email, ')
          ..write('phone: $phone, ')
          ..write('street: $street, ')
          ..write('zip: $zip, ')
          ..write('city: $city, ')
          ..write('notes: $notes, ')
          ..write('mergedInto: $mergedInto, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, businessId, salutation, name, firstName,
      email, phone, street, zip, city, notes, mergedInto, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Customer &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.salutation == this.salutation &&
          other.name == this.name &&
          other.firstName == this.firstName &&
          other.email == this.email &&
          other.phone == this.phone &&
          other.street == this.street &&
          other.zip == this.zip &&
          other.city == this.city &&
          other.notes == this.notes &&
          other.mergedInto == this.mergedInto &&
          other.updatedAt == this.updatedAt);
}

class CustomersCompanion extends UpdateCompanion<Customer> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String?> salutation;
  final Value<String> name;
  final Value<String?> firstName;
  final Value<String?> email;
  final Value<String?> phone;
  final Value<String?> street;
  final Value<String?> zip;
  final Value<String?> city;
  final Value<String?> notes;
  final Value<String?> mergedInto;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CustomersCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.salutation = const Value.absent(),
    this.name = const Value.absent(),
    this.firstName = const Value.absent(),
    this.email = const Value.absent(),
    this.phone = const Value.absent(),
    this.street = const Value.absent(),
    this.zip = const Value.absent(),
    this.city = const Value.absent(),
    this.notes = const Value.absent(),
    this.mergedInto = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomersCompanion.insert({
    required String id,
    required String businessId,
    this.salutation = const Value.absent(),
    required String name,
    this.firstName = const Value.absent(),
    this.email = const Value.absent(),
    this.phone = const Value.absent(),
    this.street = const Value.absent(),
    this.zip = const Value.absent(),
    this.city = const Value.absent(),
    this.notes = const Value.absent(),
    this.mergedInto = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        businessId = Value(businessId),
        name = Value(name),
        updatedAt = Value(updatedAt);
  static Insertable<Customer> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? salutation,
    Expression<String>? name,
    Expression<String>? firstName,
    Expression<String>? email,
    Expression<String>? phone,
    Expression<String>? street,
    Expression<String>? zip,
    Expression<String>? city,
    Expression<String>? notes,
    Expression<String>? mergedInto,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (salutation != null) 'salutation': salutation,
      if (name != null) 'name': name,
      if (firstName != null) 'first_name': firstName,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (street != null) 'street': street,
      if (zip != null) 'zip': zip,
      if (city != null) 'city': city,
      if (notes != null) 'notes': notes,
      if (mergedInto != null) 'merged_into': mergedInto,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomersCompanion copyWith(
      {Value<String>? id,
      Value<String>? businessId,
      Value<String?>? salutation,
      Value<String>? name,
      Value<String?>? firstName,
      Value<String?>? email,
      Value<String?>? phone,
      Value<String?>? street,
      Value<String?>? zip,
      Value<String?>? city,
      Value<String?>? notes,
      Value<String?>? mergedInto,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return CustomersCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      salutation: salutation ?? this.salutation,
      name: name ?? this.name,
      firstName: firstName ?? this.firstName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      street: street ?? this.street,
      zip: zip ?? this.zip,
      city: city ?? this.city,
      notes: notes ?? this.notes,
      mergedInto: mergedInto ?? this.mergedInto,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (salutation.present) {
      map['salutation'] = Variable<String>(salutation.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (firstName.present) {
      map['first_name'] = Variable<String>(firstName.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (street.present) {
      map['street'] = Variable<String>(street.value);
    }
    if (zip.present) {
      map['zip'] = Variable<String>(zip.value);
    }
    if (city.present) {
      map['city'] = Variable<String>(city.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (mergedInto.present) {
      map['merged_into'] = Variable<String>(mergedInto.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomersCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('salutation: $salutation, ')
          ..write('name: $name, ')
          ..write('firstName: $firstName, ')
          ..write('email: $email, ')
          ..write('phone: $phone, ')
          ..write('street: $street, ')
          ..write('zip: $zip, ')
          ..write('city: $city, ')
          ..write('notes: $notes, ')
          ..write('mergedInto: $mergedInto, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $JobsTable extends Jobs with TableInfo<$JobsTable, Job> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _businessIdMeta =
      const VerificationMeta('businessId');
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
      'business_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _customerIdMeta =
      const VerificationMeta('customerId');
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
      'customer_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('draft'));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, businessId, customerId, title, description, status, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'jobs';
  @override
  VerificationContext validateIntegrity(Insertable<Job> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
          _businessIdMeta,
          businessId.isAcceptableOrUnknown(
              data['business_id']!, _businessIdMeta));
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('customer_id')) {
      context.handle(
          _customerIdMeta,
          customerId.isAcceptableOrUnknown(
              data['customer_id']!, _customerIdMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Job map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Job(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      businessId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}business_id'])!,
      customerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}customer_id']),
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $JobsTable createAlias(String alias) {
    return $JobsTable(attachedDatabase, alias);
  }
}

class Job extends DataClass implements Insertable<Job> {
  final String id;
  final String businessId;
  final String? customerId;
  final String title;
  final String? description;
  final String status;
  final DateTime updatedAt;
  const Job(
      {required this.id,
      required this.businessId,
      this.customerId,
      required this.title,
      this.description,
      required this.status,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    if (!nullToAbsent || customerId != null) {
      map['customer_id'] = Variable<String>(customerId);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['status'] = Variable<String>(status);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  JobsCompanion toCompanion(bool nullToAbsent) {
    return JobsCompanion(
      id: Value(id),
      businessId: Value(businessId),
      customerId: customerId == null && nullToAbsent
          ? const Value.absent()
          : Value(customerId),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      status: Value(status),
      updatedAt: Value(updatedAt),
    );
  }

  factory Job.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Job(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      customerId: serializer.fromJson<String?>(json['customerId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      status: serializer.fromJson<String>(json['status']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'customerId': serializer.toJson<String?>(customerId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'status': serializer.toJson<String>(status),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Job copyWith(
          {String? id,
          String? businessId,
          Value<String?> customerId = const Value.absent(),
          String? title,
          Value<String?> description = const Value.absent(),
          String? status,
          DateTime? updatedAt}) =>
      Job(
        id: id ?? this.id,
        businessId: businessId ?? this.businessId,
        customerId: customerId.present ? customerId.value : this.customerId,
        title: title ?? this.title,
        description: description.present ? description.value : this.description,
        status: status ?? this.status,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Job copyWithCompanion(JobsCompanion data) {
    return Job(
      id: data.id.present ? data.id.value : this.id,
      businessId:
          data.businessId.present ? data.businessId.value : this.businessId,
      customerId:
          data.customerId.present ? data.customerId.value : this.customerId,
      title: data.title.present ? data.title.value : this.title,
      description:
          data.description.present ? data.description.value : this.description,
      status: data.status.present ? data.status.value : this.status,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Job(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('customerId: $customerId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, businessId, customerId, title, description, status, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Job &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.customerId == this.customerId &&
          other.title == this.title &&
          other.description == this.description &&
          other.status == this.status &&
          other.updatedAt == this.updatedAt);
}

class JobsCompanion extends UpdateCompanion<Job> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String?> customerId;
  final Value<String> title;
  final Value<String?> description;
  final Value<String> status;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const JobsCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.customerId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  JobsCompanion.insert({
    required String id,
    required String businessId,
    this.customerId = const Value.absent(),
    required String title,
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        businessId = Value(businessId),
        title = Value(title),
        updatedAt = Value(updatedAt);
  static Insertable<Job> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? customerId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? status,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (customerId != null) 'customer_id': customerId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  JobsCompanion copyWith(
      {Value<String>? id,
      Value<String>? businessId,
      Value<String?>? customerId,
      Value<String>? title,
      Value<String?>? description,
      Value<String>? status,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return JobsCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      customerId: customerId ?? this.customerId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JobsCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('customerId: $customerId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
      'entity', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entityIdMeta =
      const VerificationMeta('entityId');
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
      'entity_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _opMeta = const VerificationMeta('op');
  @override
  late final GeneratedColumn<String> op = GeneratedColumn<String>(
      'op', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _revMeta = const VerificationMeta('rev');
  @override
  late final GeneratedColumn<int> rev = GeneratedColumn<int>(
      'rev', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _attemptsMeta =
      const VerificationMeta('attempts');
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
      'attempts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastErrorMeta =
      const VerificationMeta('lastError');
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
      'last_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, entity, entityId, op, createdAt, rev, attempts, lastError];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(Insertable<OutboxData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entity')) {
      context.handle(_entityMeta,
          entity.isAcceptableOrUnknown(data['entity']!, _entityMeta));
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(_entityIdMeta,
          entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta));
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('op')) {
      context.handle(_opMeta, op.isAcceptableOrUnknown(data['op']!, _opMeta));
    } else if (isInserting) {
      context.missing(_opMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('rev')) {
      context.handle(
          _revMeta, rev.isAcceptableOrUnknown(data['rev']!, _revMeta));
    }
    if (data.containsKey('attempts')) {
      context.handle(_attemptsMeta,
          attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta));
    }
    if (data.containsKey('last_error')) {
      context.handle(_lastErrorMeta,
          lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {entity, entityId},
      ];
  @override
  OutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      entity: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity'])!,
      entityId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_id'])!,
      op: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}op'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      rev: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}rev'])!,
      attempts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempts'])!,
      lastError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_error']),
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxData extends DataClass implements Insertable<OutboxData> {
  final int id;
  final String entity;
  final String entityId;
  final String op;
  final DateTime createdAt;

  /// Bumped on every re-queue. A push only clears the entry if the rev it started with is
  /// still current, so an edit made during an in-flight push is never lost.
  final int rev;
  final int attempts;
  final String? lastError;
  const OutboxData(
      {required this.id,
      required this.entity,
      required this.entityId,
      required this.op,
      required this.createdAt,
      required this.rev,
      required this.attempts,
      this.lastError});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['entity'] = Variable<String>(entity);
    map['entity_id'] = Variable<String>(entityId);
    map['op'] = Variable<String>(op);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['rev'] = Variable<int>(rev);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      id: Value(id),
      entity: Value(entity),
      entityId: Value(entityId),
      op: Value(op),
      createdAt: Value(createdAt),
      rev: Value(rev),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory OutboxData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxData(
      id: serializer.fromJson<int>(json['id']),
      entity: serializer.fromJson<String>(json['entity']),
      entityId: serializer.fromJson<String>(json['entityId']),
      op: serializer.fromJson<String>(json['op']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      rev: serializer.fromJson<int>(json['rev']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'entity': serializer.toJson<String>(entity),
      'entityId': serializer.toJson<String>(entityId),
      'op': serializer.toJson<String>(op),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'rev': serializer.toJson<int>(rev),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  OutboxData copyWith(
          {int? id,
          String? entity,
          String? entityId,
          String? op,
          DateTime? createdAt,
          int? rev,
          int? attempts,
          Value<String?> lastError = const Value.absent()}) =>
      OutboxData(
        id: id ?? this.id,
        entity: entity ?? this.entity,
        entityId: entityId ?? this.entityId,
        op: op ?? this.op,
        createdAt: createdAt ?? this.createdAt,
        rev: rev ?? this.rev,
        attempts: attempts ?? this.attempts,
        lastError: lastError.present ? lastError.value : this.lastError,
      );
  OutboxData copyWithCompanion(OutboxCompanion data) {
    return OutboxData(
      id: data.id.present ? data.id.value : this.id,
      entity: data.entity.present ? data.entity.value : this.entity,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      op: data.op.present ? data.op.value : this.op,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      rev: data.rev.present ? data.rev.value : this.rev,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxData(')
          ..write('id: $id, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('op: $op, ')
          ..write('createdAt: $createdAt, ')
          ..write('rev: $rev, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, entity, entityId, op, createdAt, rev, attempts, lastError);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxData &&
          other.id == this.id &&
          other.entity == this.entity &&
          other.entityId == this.entityId &&
          other.op == this.op &&
          other.createdAt == this.createdAt &&
          other.rev == this.rev &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class OutboxCompanion extends UpdateCompanion<OutboxData> {
  final Value<int> id;
  final Value<String> entity;
  final Value<String> entityId;
  final Value<String> op;
  final Value<DateTime> createdAt;
  final Value<int> rev;
  final Value<int> attempts;
  final Value<String?> lastError;
  const OutboxCompanion({
    this.id = const Value.absent(),
    this.entity = const Value.absent(),
    this.entityId = const Value.absent(),
    this.op = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rev = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  OutboxCompanion.insert({
    this.id = const Value.absent(),
    required String entity,
    required String entityId,
    required String op,
    required DateTime createdAt,
    this.rev = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  })  : entity = Value(entity),
        entityId = Value(entityId),
        op = Value(op),
        createdAt = Value(createdAt);
  static Insertable<OutboxData> custom({
    Expression<int>? id,
    Expression<String>? entity,
    Expression<String>? entityId,
    Expression<String>? op,
    Expression<DateTime>? createdAt,
    Expression<int>? rev,
    Expression<int>? attempts,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entity != null) 'entity': entity,
      if (entityId != null) 'entity_id': entityId,
      if (op != null) 'op': op,
      if (createdAt != null) 'created_at': createdAt,
      if (rev != null) 'rev': rev,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
    });
  }

  OutboxCompanion copyWith(
      {Value<int>? id,
      Value<String>? entity,
      Value<String>? entityId,
      Value<String>? op,
      Value<DateTime>? createdAt,
      Value<int>? rev,
      Value<int>? attempts,
      Value<String?>? lastError}) {
    return OutboxCompanion(
      id: id ?? this.id,
      entity: entity ?? this.entity,
      entityId: entityId ?? this.entityId,
      op: op ?? this.op,
      createdAt: createdAt ?? this.createdAt,
      rev: rev ?? this.rev,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (op.present) {
      map['op'] = Variable<String>(op.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rev.present) {
      map['rev'] = Variable<int>(rev.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('id: $id, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('op: $op, ')
          ..write('createdAt: $createdAt, ')
          ..write('rev: $rev, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta
    with TableInfo<$SyncMetaTable, SyncMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(Insertable<SyncMetaData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetaData(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class SyncMetaData extends DataClass implements Insertable<SyncMetaData> {
  final String key;
  final String value;
  const SyncMetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory SyncMetaData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncMetaData copyWith({String? key, String? value}) => SyncMetaData(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  SyncMetaData copyWithCompanion(SyncMetaCompanion data) {
    return SyncMetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaData &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<SyncMetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetaCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return SyncMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingCapturesTable extends PendingCaptures
    with TableInfo<$PendingCapturesTable, PendingCapture> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingCapturesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _localPathMeta =
      const VerificationMeta('localPath');
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
      'local_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _transcriptMeta =
      const VerificationMeta('transcript');
  @override
  late final GeneratedColumn<String> transcript = GeneratedColumn<String>(
      'transcript', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _durationSecondsMeta =
      const VerificationMeta('durationSeconds');
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
      'duration_seconds', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('queued'));
  static const VerificationMeta _uploadedMeta =
      const VerificationMeta('uploaded');
  @override
  late final GeneratedColumn<bool> uploaded = GeneratedColumn<bool>(
      'uploaded', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("uploaded" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _attemptsMeta =
      const VerificationMeta('attempts');
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
      'attempts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _errorMessageMeta =
      const VerificationMeta('errorMessage');
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
      'error_message', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _draftJsonMeta =
      const VerificationMeta('draftJson');
  @override
  late final GeneratedColumn<String> draftJson = GeneratedColumn<String>(
      'draft_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
      'job_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        kind,
        localPath,
        transcript,
        durationSeconds,
        status,
        uploaded,
        attempts,
        errorMessage,
        draftJson,
        jobId,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_captures';
  @override
  VerificationContext validateIntegrity(Insertable<PendingCapture> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(_localPathMeta,
          localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta));
    }
    if (data.containsKey('transcript')) {
      context.handle(
          _transcriptMeta,
          transcript.isAcceptableOrUnknown(
              data['transcript']!, _transcriptMeta));
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
          _durationSecondsMeta,
          durationSeconds.isAcceptableOrUnknown(
              data['duration_seconds']!, _durationSecondsMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('uploaded')) {
      context.handle(_uploadedMeta,
          uploaded.isAcceptableOrUnknown(data['uploaded']!, _uploadedMeta));
    }
    if (data.containsKey('attempts')) {
      context.handle(_attemptsMeta,
          attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta));
    }
    if (data.containsKey('error_message')) {
      context.handle(
          _errorMessageMeta,
          errorMessage.isAcceptableOrUnknown(
              data['error_message']!, _errorMessageMeta));
    }
    if (data.containsKey('draft_json')) {
      context.handle(_draftJsonMeta,
          draftJson.isAcceptableOrUnknown(data['draft_json']!, _draftJsonMeta));
    }
    if (data.containsKey('job_id')) {
      context.handle(
          _jobIdMeta, jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingCapture map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingCapture(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      localPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_path']),
      transcript: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}transcript']),
      durationSeconds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_seconds'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      uploaded: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}uploaded'])!,
      attempts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempts'])!,
      errorMessage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}error_message']),
      draftJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}draft_json']),
      jobId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}job_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $PendingCapturesTable createAlias(String alias) {
    return $PendingCapturesTable(attachedDatabase, alias);
  }
}

class PendingCapture extends DataClass implements Insertable<PendingCapture> {
  final String id;
  final String kind;
  final String? localPath;
  final String? transcript;
  final int durationSeconds;
  final String status;
  final bool uploaded;
  final int attempts;
  final String? errorMessage;
  final String? draftJson;
  final String? jobId;
  final DateTime createdAt;
  const PendingCapture(
      {required this.id,
      required this.kind,
      this.localPath,
      this.transcript,
      required this.durationSeconds,
      required this.status,
      required this.uploaded,
      required this.attempts,
      this.errorMessage,
      this.draftJson,
      this.jobId,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    if (!nullToAbsent || transcript != null) {
      map['transcript'] = Variable<String>(transcript);
    }
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['status'] = Variable<String>(status);
    map['uploaded'] = Variable<bool>(uploaded);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    if (!nullToAbsent || draftJson != null) {
      map['draft_json'] = Variable<String>(draftJson);
    }
    if (!nullToAbsent || jobId != null) {
      map['job_id'] = Variable<String>(jobId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PendingCapturesCompanion toCompanion(bool nullToAbsent) {
    return PendingCapturesCompanion(
      id: Value(id),
      kind: Value(kind),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      transcript: transcript == null && nullToAbsent
          ? const Value.absent()
          : Value(transcript),
      durationSeconds: Value(durationSeconds),
      status: Value(status),
      uploaded: Value(uploaded),
      attempts: Value(attempts),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      draftJson: draftJson == null && nullToAbsent
          ? const Value.absent()
          : Value(draftJson),
      jobId:
          jobId == null && nullToAbsent ? const Value.absent() : Value(jobId),
      createdAt: Value(createdAt),
    );
  }

  factory PendingCapture.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingCapture(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      transcript: serializer.fromJson<String?>(json['transcript']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      status: serializer.fromJson<String>(json['status']),
      uploaded: serializer.fromJson<bool>(json['uploaded']),
      attempts: serializer.fromJson<int>(json['attempts']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      draftJson: serializer.fromJson<String?>(json['draftJson']),
      jobId: serializer.fromJson<String?>(json['jobId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'localPath': serializer.toJson<String?>(localPath),
      'transcript': serializer.toJson<String?>(transcript),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'status': serializer.toJson<String>(status),
      'uploaded': serializer.toJson<bool>(uploaded),
      'attempts': serializer.toJson<int>(attempts),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'draftJson': serializer.toJson<String?>(draftJson),
      'jobId': serializer.toJson<String?>(jobId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PendingCapture copyWith(
          {String? id,
          String? kind,
          Value<String?> localPath = const Value.absent(),
          Value<String?> transcript = const Value.absent(),
          int? durationSeconds,
          String? status,
          bool? uploaded,
          int? attempts,
          Value<String?> errorMessage = const Value.absent(),
          Value<String?> draftJson = const Value.absent(),
          Value<String?> jobId = const Value.absent(),
          DateTime? createdAt}) =>
      PendingCapture(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        localPath: localPath.present ? localPath.value : this.localPath,
        transcript: transcript.present ? transcript.value : this.transcript,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        status: status ?? this.status,
        uploaded: uploaded ?? this.uploaded,
        attempts: attempts ?? this.attempts,
        errorMessage:
            errorMessage.present ? errorMessage.value : this.errorMessage,
        draftJson: draftJson.present ? draftJson.value : this.draftJson,
        jobId: jobId.present ? jobId.value : this.jobId,
        createdAt: createdAt ?? this.createdAt,
      );
  PendingCapture copyWithCompanion(PendingCapturesCompanion data) {
    return PendingCapture(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      transcript:
          data.transcript.present ? data.transcript.value : this.transcript,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      status: data.status.present ? data.status.value : this.status,
      uploaded: data.uploaded.present ? data.uploaded.value : this.uploaded,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      draftJson: data.draftJson.present ? data.draftJson.value : this.draftJson,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingCapture(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('localPath: $localPath, ')
          ..write('transcript: $transcript, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('status: $status, ')
          ..write('uploaded: $uploaded, ')
          ..write('attempts: $attempts, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('draftJson: $draftJson, ')
          ..write('jobId: $jobId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      kind,
      localPath,
      transcript,
      durationSeconds,
      status,
      uploaded,
      attempts,
      errorMessage,
      draftJson,
      jobId,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingCapture &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.localPath == this.localPath &&
          other.transcript == this.transcript &&
          other.durationSeconds == this.durationSeconds &&
          other.status == this.status &&
          other.uploaded == this.uploaded &&
          other.attempts == this.attempts &&
          other.errorMessage == this.errorMessage &&
          other.draftJson == this.draftJson &&
          other.jobId == this.jobId &&
          other.createdAt == this.createdAt);
}

class PendingCapturesCompanion extends UpdateCompanion<PendingCapture> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String?> localPath;
  final Value<String?> transcript;
  final Value<int> durationSeconds;
  final Value<String> status;
  final Value<bool> uploaded;
  final Value<int> attempts;
  final Value<String?> errorMessage;
  final Value<String?> draftJson;
  final Value<String?> jobId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PendingCapturesCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.localPath = const Value.absent(),
    this.transcript = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.status = const Value.absent(),
    this.uploaded = const Value.absent(),
    this.attempts = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.draftJson = const Value.absent(),
    this.jobId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingCapturesCompanion.insert({
    required String id,
    required String kind,
    this.localPath = const Value.absent(),
    this.transcript = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.status = const Value.absent(),
    this.uploaded = const Value.absent(),
    this.attempts = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.draftJson = const Value.absent(),
    this.jobId = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        kind = Value(kind),
        createdAt = Value(createdAt);
  static Insertable<PendingCapture> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? localPath,
    Expression<String>? transcript,
    Expression<int>? durationSeconds,
    Expression<String>? status,
    Expression<bool>? uploaded,
    Expression<int>? attempts,
    Expression<String>? errorMessage,
    Expression<String>? draftJson,
    Expression<String>? jobId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (localPath != null) 'local_path': localPath,
      if (transcript != null) 'transcript': transcript,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (status != null) 'status': status,
      if (uploaded != null) 'uploaded': uploaded,
      if (attempts != null) 'attempts': attempts,
      if (errorMessage != null) 'error_message': errorMessage,
      if (draftJson != null) 'draft_json': draftJson,
      if (jobId != null) 'job_id': jobId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingCapturesCompanion copyWith(
      {Value<String>? id,
      Value<String>? kind,
      Value<String?>? localPath,
      Value<String?>? transcript,
      Value<int>? durationSeconds,
      Value<String>? status,
      Value<bool>? uploaded,
      Value<int>? attempts,
      Value<String?>? errorMessage,
      Value<String?>? draftJson,
      Value<String?>? jobId,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return PendingCapturesCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      localPath: localPath ?? this.localPath,
      transcript: transcript ?? this.transcript,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      status: status ?? this.status,
      uploaded: uploaded ?? this.uploaded,
      attempts: attempts ?? this.attempts,
      errorMessage: errorMessage ?? this.errorMessage,
      draftJson: draftJson ?? this.draftJson,
      jobId: jobId ?? this.jobId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (transcript.present) {
      map['transcript'] = Variable<String>(transcript.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (uploaded.present) {
      map['uploaded'] = Variable<bool>(uploaded.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (draftJson.present) {
      map['draft_json'] = Variable<String>(draftJson.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingCapturesCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('localPath: $localPath, ')
          ..write('transcript: $transcript, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('status: $status, ')
          ..write('uploaded: $uploaded, ')
          ..write('attempts: $attempts, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('draftJson: $draftJson, ')
          ..write('jobId: $jobId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IssuedDocumentsTable extends IssuedDocuments
    with TableInfo<$IssuedDocumentsTable, IssuedDocument> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IssuedDocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _businessIdMeta =
      const VerificationMeta('businessId');
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
      'business_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
      'job_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _customerIdMeta =
      const VerificationMeta('customerId');
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
      'customer_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _docTypeMeta =
      const VerificationMeta('docType');
  @override
  late final GeneratedColumn<String> docType = GeneratedColumn<String>(
      'doc_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _docNumberMeta =
      const VerificationMeta('docNumber');
  @override
  late final GeneratedColumn<String> docNumber = GeneratedColumn<String>(
      'doc_number', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _dateIssuedMeta =
      const VerificationMeta('dateIssued');
  @override
  late final GeneratedColumn<String> dateIssued = GeneratedColumn<String>(
      'date_issued', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dateDueMeta =
      const VerificationMeta('dateDue');
  @override
  late final GeneratedColumn<String> dateDue = GeneratedColumn<String>(
      'date_due', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _deliveryPeriodMeta =
      const VerificationMeta('deliveryPeriod');
  @override
  late final GeneratedColumn<String> deliveryPeriod = GeneratedColumn<String>(
      'delivery_period', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _subtotalLaborCentsMeta =
      const VerificationMeta('subtotalLaborCents');
  @override
  late final GeneratedColumn<int> subtotalLaborCents = GeneratedColumn<int>(
      'subtotal_labor_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _subtotalMaterialCentsMeta =
      const VerificationMeta('subtotalMaterialCents');
  @override
  late final GeneratedColumn<int> subtotalMaterialCents = GeneratedColumn<int>(
      'subtotal_material_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _totalNetCentsMeta =
      const VerificationMeta('totalNetCents');
  @override
  late final GeneratedColumn<int> totalNetCents = GeneratedColumn<int>(
      'total_net_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _vatRateMeta =
      const VerificationMeta('vatRate');
  @override
  late final GeneratedColumn<double> vatRate = GeneratedColumn<double>(
      'vat_rate', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _vatAmountCentsMeta =
      const VerificationMeta('vatAmountCents');
  @override
  late final GeneratedColumn<int> vatAmountCents = GeneratedColumn<int>(
      'vat_amount_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _totalGrossCentsMeta =
      const VerificationMeta('totalGrossCents');
  @override
  late final GeneratedColumn<int> totalGrossCents = GeneratedColumn<int>(
      'total_gross_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _lineItemsJsonMeta =
      const VerificationMeta('lineItemsJson');
  @override
  late final GeneratedColumn<String> lineItemsJson = GeneratedColumn<String>(
      'line_items_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recipientNameMeta =
      const VerificationMeta('recipientName');
  @override
  late final GeneratedColumn<String> recipientName = GeneratedColumn<String>(
      'recipient_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recipientAddressMeta =
      const VerificationMeta('recipientAddress');
  @override
  late final GeneratedColumn<String> recipientAddress = GeneratedColumn<String>(
      'recipient_address', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _pdfPathMeta =
      const VerificationMeta('pdfPath');
  @override
  late final GeneratedColumn<String> pdfPath = GeneratedColumn<String>(
      'pdf_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _eInvoiceMeta =
      const VerificationMeta('eInvoice');
  @override
  late final GeneratedColumn<bool> eInvoice = GeneratedColumn<bool>(
      'e_invoice', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("e_invoice" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        businessId,
        jobId,
        customerId,
        docType,
        docNumber,
        status,
        title,
        dateIssued,
        dateDue,
        deliveryPeriod,
        subtotalLaborCents,
        subtotalMaterialCents,
        totalNetCents,
        vatRate,
        vatAmountCents,
        totalGrossCents,
        lineItemsJson,
        recipientName,
        recipientAddress,
        pdfPath,
        eInvoice,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'issued_documents';
  @override
  VerificationContext validateIntegrity(Insertable<IssuedDocument> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
          _businessIdMeta,
          businessId.isAcceptableOrUnknown(
              data['business_id']!, _businessIdMeta));
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('job_id')) {
      context.handle(
          _jobIdMeta, jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta));
    }
    if (data.containsKey('customer_id')) {
      context.handle(
          _customerIdMeta,
          customerId.isAcceptableOrUnknown(
              data['customer_id']!, _customerIdMeta));
    }
    if (data.containsKey('doc_type')) {
      context.handle(_docTypeMeta,
          docType.isAcceptableOrUnknown(data['doc_type']!, _docTypeMeta));
    } else if (isInserting) {
      context.missing(_docTypeMeta);
    }
    if (data.containsKey('doc_number')) {
      context.handle(_docNumberMeta,
          docNumber.isAcceptableOrUnknown(data['doc_number']!, _docNumberMeta));
    } else if (isInserting) {
      context.missing(_docNumberMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    }
    if (data.containsKey('date_issued')) {
      context.handle(
          _dateIssuedMeta,
          dateIssued.isAcceptableOrUnknown(
              data['date_issued']!, _dateIssuedMeta));
    } else if (isInserting) {
      context.missing(_dateIssuedMeta);
    }
    if (data.containsKey('date_due')) {
      context.handle(_dateDueMeta,
          dateDue.isAcceptableOrUnknown(data['date_due']!, _dateDueMeta));
    }
    if (data.containsKey('delivery_period')) {
      context.handle(
          _deliveryPeriodMeta,
          deliveryPeriod.isAcceptableOrUnknown(
              data['delivery_period']!, _deliveryPeriodMeta));
    }
    if (data.containsKey('subtotal_labor_cents')) {
      context.handle(
          _subtotalLaborCentsMeta,
          subtotalLaborCents.isAcceptableOrUnknown(
              data['subtotal_labor_cents']!, _subtotalLaborCentsMeta));
    } else if (isInserting) {
      context.missing(_subtotalLaborCentsMeta);
    }
    if (data.containsKey('subtotal_material_cents')) {
      context.handle(
          _subtotalMaterialCentsMeta,
          subtotalMaterialCents.isAcceptableOrUnknown(
              data['subtotal_material_cents']!, _subtotalMaterialCentsMeta));
    } else if (isInserting) {
      context.missing(_subtotalMaterialCentsMeta);
    }
    if (data.containsKey('total_net_cents')) {
      context.handle(
          _totalNetCentsMeta,
          totalNetCents.isAcceptableOrUnknown(
              data['total_net_cents']!, _totalNetCentsMeta));
    } else if (isInserting) {
      context.missing(_totalNetCentsMeta);
    }
    if (data.containsKey('vat_rate')) {
      context.handle(_vatRateMeta,
          vatRate.isAcceptableOrUnknown(data['vat_rate']!, _vatRateMeta));
    } else if (isInserting) {
      context.missing(_vatRateMeta);
    }
    if (data.containsKey('vat_amount_cents')) {
      context.handle(
          _vatAmountCentsMeta,
          vatAmountCents.isAcceptableOrUnknown(
              data['vat_amount_cents']!, _vatAmountCentsMeta));
    } else if (isInserting) {
      context.missing(_vatAmountCentsMeta);
    }
    if (data.containsKey('total_gross_cents')) {
      context.handle(
          _totalGrossCentsMeta,
          totalGrossCents.isAcceptableOrUnknown(
              data['total_gross_cents']!, _totalGrossCentsMeta));
    } else if (isInserting) {
      context.missing(_totalGrossCentsMeta);
    }
    if (data.containsKey('line_items_json')) {
      context.handle(
          _lineItemsJsonMeta,
          lineItemsJson.isAcceptableOrUnknown(
              data['line_items_json']!, _lineItemsJsonMeta));
    } else if (isInserting) {
      context.missing(_lineItemsJsonMeta);
    }
    if (data.containsKey('recipient_name')) {
      context.handle(
          _recipientNameMeta,
          recipientName.isAcceptableOrUnknown(
              data['recipient_name']!, _recipientNameMeta));
    } else if (isInserting) {
      context.missing(_recipientNameMeta);
    }
    if (data.containsKey('recipient_address')) {
      context.handle(
          _recipientAddressMeta,
          recipientAddress.isAcceptableOrUnknown(
              data['recipient_address']!, _recipientAddressMeta));
    }
    if (data.containsKey('pdf_path')) {
      context.handle(_pdfPathMeta,
          pdfPath.isAcceptableOrUnknown(data['pdf_path']!, _pdfPathMeta));
    }
    if (data.containsKey('e_invoice')) {
      context.handle(_eInvoiceMeta,
          eInvoice.isAcceptableOrUnknown(data['e_invoice']!, _eInvoiceMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  IssuedDocument map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IssuedDocument(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      businessId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}business_id'])!,
      jobId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}job_id']),
      customerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}customer_id']),
      docType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}doc_type'])!,
      docNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}doc_number'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title']),
      dateIssued: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}date_issued'])!,
      dateDue: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}date_due']),
      deliveryPeriod: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}delivery_period']),
      subtotalLaborCents: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}subtotal_labor_cents'])!,
      subtotalMaterialCents: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}subtotal_material_cents'])!,
      totalNetCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_net_cents'])!,
      vatRate: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}vat_rate'])!,
      vatAmountCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}vat_amount_cents'])!,
      totalGrossCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_gross_cents'])!,
      lineItemsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}line_items_json'])!,
      recipientName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}recipient_name'])!,
      recipientAddress: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}recipient_address']),
      pdfPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pdf_path']),
      eInvoice: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}e_invoice'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $IssuedDocumentsTable createAlias(String alias) {
    return $IssuedDocumentsTable(attachedDatabase, alias);
  }
}

class IssuedDocument extends DataClass implements Insertable<IssuedDocument> {
  final String id;
  final String businessId;
  final String? jobId;
  final String? customerId;
  final String docType;
  final String docNumber;
  final String status;
  final String? title;
  final String dateIssued;
  final String? dateDue;
  final String? deliveryPeriod;
  final int subtotalLaborCents;
  final int subtotalMaterialCents;
  final int totalNetCents;
  final double vatRate;
  final int vatAmountCents;
  final int totalGrossCents;
  final String lineItemsJson;
  final String recipientName;
  final String? recipientAddress;
  final String? pdfPath;

  /// The PDF carries an embedded ZUGFeRD / Factur-X XML (frozen with the document).
  final bool eInvoice;
  final DateTime updatedAt;
  const IssuedDocument(
      {required this.id,
      required this.businessId,
      this.jobId,
      this.customerId,
      required this.docType,
      required this.docNumber,
      required this.status,
      this.title,
      required this.dateIssued,
      this.dateDue,
      this.deliveryPeriod,
      required this.subtotalLaborCents,
      required this.subtotalMaterialCents,
      required this.totalNetCents,
      required this.vatRate,
      required this.vatAmountCents,
      required this.totalGrossCents,
      required this.lineItemsJson,
      required this.recipientName,
      this.recipientAddress,
      this.pdfPath,
      required this.eInvoice,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    if (!nullToAbsent || jobId != null) {
      map['job_id'] = Variable<String>(jobId);
    }
    if (!nullToAbsent || customerId != null) {
      map['customer_id'] = Variable<String>(customerId);
    }
    map['doc_type'] = Variable<String>(docType);
    map['doc_number'] = Variable<String>(docNumber);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['date_issued'] = Variable<String>(dateIssued);
    if (!nullToAbsent || dateDue != null) {
      map['date_due'] = Variable<String>(dateDue);
    }
    if (!nullToAbsent || deliveryPeriod != null) {
      map['delivery_period'] = Variable<String>(deliveryPeriod);
    }
    map['subtotal_labor_cents'] = Variable<int>(subtotalLaborCents);
    map['subtotal_material_cents'] = Variable<int>(subtotalMaterialCents);
    map['total_net_cents'] = Variable<int>(totalNetCents);
    map['vat_rate'] = Variable<double>(vatRate);
    map['vat_amount_cents'] = Variable<int>(vatAmountCents);
    map['total_gross_cents'] = Variable<int>(totalGrossCents);
    map['line_items_json'] = Variable<String>(lineItemsJson);
    map['recipient_name'] = Variable<String>(recipientName);
    if (!nullToAbsent || recipientAddress != null) {
      map['recipient_address'] = Variable<String>(recipientAddress);
    }
    if (!nullToAbsent || pdfPath != null) {
      map['pdf_path'] = Variable<String>(pdfPath);
    }
    map['e_invoice'] = Variable<bool>(eInvoice);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  IssuedDocumentsCompanion toCompanion(bool nullToAbsent) {
    return IssuedDocumentsCompanion(
      id: Value(id),
      businessId: Value(businessId),
      jobId:
          jobId == null && nullToAbsent ? const Value.absent() : Value(jobId),
      customerId: customerId == null && nullToAbsent
          ? const Value.absent()
          : Value(customerId),
      docType: Value(docType),
      docNumber: Value(docNumber),
      status: Value(status),
      title:
          title == null && nullToAbsent ? const Value.absent() : Value(title),
      dateIssued: Value(dateIssued),
      dateDue: dateDue == null && nullToAbsent
          ? const Value.absent()
          : Value(dateDue),
      deliveryPeriod: deliveryPeriod == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveryPeriod),
      subtotalLaborCents: Value(subtotalLaborCents),
      subtotalMaterialCents: Value(subtotalMaterialCents),
      totalNetCents: Value(totalNetCents),
      vatRate: Value(vatRate),
      vatAmountCents: Value(vatAmountCents),
      totalGrossCents: Value(totalGrossCents),
      lineItemsJson: Value(lineItemsJson),
      recipientName: Value(recipientName),
      recipientAddress: recipientAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(recipientAddress),
      pdfPath: pdfPath == null && nullToAbsent
          ? const Value.absent()
          : Value(pdfPath),
      eInvoice: Value(eInvoice),
      updatedAt: Value(updatedAt),
    );
  }

  factory IssuedDocument.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IssuedDocument(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      jobId: serializer.fromJson<String?>(json['jobId']),
      customerId: serializer.fromJson<String?>(json['customerId']),
      docType: serializer.fromJson<String>(json['docType']),
      docNumber: serializer.fromJson<String>(json['docNumber']),
      status: serializer.fromJson<String>(json['status']),
      title: serializer.fromJson<String?>(json['title']),
      dateIssued: serializer.fromJson<String>(json['dateIssued']),
      dateDue: serializer.fromJson<String?>(json['dateDue']),
      deliveryPeriod: serializer.fromJson<String?>(json['deliveryPeriod']),
      subtotalLaborCents: serializer.fromJson<int>(json['subtotalLaborCents']),
      subtotalMaterialCents:
          serializer.fromJson<int>(json['subtotalMaterialCents']),
      totalNetCents: serializer.fromJson<int>(json['totalNetCents']),
      vatRate: serializer.fromJson<double>(json['vatRate']),
      vatAmountCents: serializer.fromJson<int>(json['vatAmountCents']),
      totalGrossCents: serializer.fromJson<int>(json['totalGrossCents']),
      lineItemsJson: serializer.fromJson<String>(json['lineItemsJson']),
      recipientName: serializer.fromJson<String>(json['recipientName']),
      recipientAddress: serializer.fromJson<String?>(json['recipientAddress']),
      pdfPath: serializer.fromJson<String?>(json['pdfPath']),
      eInvoice: serializer.fromJson<bool>(json['eInvoice']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'jobId': serializer.toJson<String?>(jobId),
      'customerId': serializer.toJson<String?>(customerId),
      'docType': serializer.toJson<String>(docType),
      'docNumber': serializer.toJson<String>(docNumber),
      'status': serializer.toJson<String>(status),
      'title': serializer.toJson<String?>(title),
      'dateIssued': serializer.toJson<String>(dateIssued),
      'dateDue': serializer.toJson<String?>(dateDue),
      'deliveryPeriod': serializer.toJson<String?>(deliveryPeriod),
      'subtotalLaborCents': serializer.toJson<int>(subtotalLaborCents),
      'subtotalMaterialCents': serializer.toJson<int>(subtotalMaterialCents),
      'totalNetCents': serializer.toJson<int>(totalNetCents),
      'vatRate': serializer.toJson<double>(vatRate),
      'vatAmountCents': serializer.toJson<int>(vatAmountCents),
      'totalGrossCents': serializer.toJson<int>(totalGrossCents),
      'lineItemsJson': serializer.toJson<String>(lineItemsJson),
      'recipientName': serializer.toJson<String>(recipientName),
      'recipientAddress': serializer.toJson<String?>(recipientAddress),
      'pdfPath': serializer.toJson<String?>(pdfPath),
      'eInvoice': serializer.toJson<bool>(eInvoice),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  IssuedDocument copyWith(
          {String? id,
          String? businessId,
          Value<String?> jobId = const Value.absent(),
          Value<String?> customerId = const Value.absent(),
          String? docType,
          String? docNumber,
          String? status,
          Value<String?> title = const Value.absent(),
          String? dateIssued,
          Value<String?> dateDue = const Value.absent(),
          Value<String?> deliveryPeriod = const Value.absent(),
          int? subtotalLaborCents,
          int? subtotalMaterialCents,
          int? totalNetCents,
          double? vatRate,
          int? vatAmountCents,
          int? totalGrossCents,
          String? lineItemsJson,
          String? recipientName,
          Value<String?> recipientAddress = const Value.absent(),
          Value<String?> pdfPath = const Value.absent(),
          bool? eInvoice,
          DateTime? updatedAt}) =>
      IssuedDocument(
        id: id ?? this.id,
        businessId: businessId ?? this.businessId,
        jobId: jobId.present ? jobId.value : this.jobId,
        customerId: customerId.present ? customerId.value : this.customerId,
        docType: docType ?? this.docType,
        docNumber: docNumber ?? this.docNumber,
        status: status ?? this.status,
        title: title.present ? title.value : this.title,
        dateIssued: dateIssued ?? this.dateIssued,
        dateDue: dateDue.present ? dateDue.value : this.dateDue,
        deliveryPeriod:
            deliveryPeriod.present ? deliveryPeriod.value : this.deliveryPeriod,
        subtotalLaborCents: subtotalLaborCents ?? this.subtotalLaborCents,
        subtotalMaterialCents:
            subtotalMaterialCents ?? this.subtotalMaterialCents,
        totalNetCents: totalNetCents ?? this.totalNetCents,
        vatRate: vatRate ?? this.vatRate,
        vatAmountCents: vatAmountCents ?? this.vatAmountCents,
        totalGrossCents: totalGrossCents ?? this.totalGrossCents,
        lineItemsJson: lineItemsJson ?? this.lineItemsJson,
        recipientName: recipientName ?? this.recipientName,
        recipientAddress: recipientAddress.present
            ? recipientAddress.value
            : this.recipientAddress,
        pdfPath: pdfPath.present ? pdfPath.value : this.pdfPath,
        eInvoice: eInvoice ?? this.eInvoice,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  IssuedDocument copyWithCompanion(IssuedDocumentsCompanion data) {
    return IssuedDocument(
      id: data.id.present ? data.id.value : this.id,
      businessId:
          data.businessId.present ? data.businessId.value : this.businessId,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      customerId:
          data.customerId.present ? data.customerId.value : this.customerId,
      docType: data.docType.present ? data.docType.value : this.docType,
      docNumber: data.docNumber.present ? data.docNumber.value : this.docNumber,
      status: data.status.present ? data.status.value : this.status,
      title: data.title.present ? data.title.value : this.title,
      dateIssued:
          data.dateIssued.present ? data.dateIssued.value : this.dateIssued,
      dateDue: data.dateDue.present ? data.dateDue.value : this.dateDue,
      deliveryPeriod: data.deliveryPeriod.present
          ? data.deliveryPeriod.value
          : this.deliveryPeriod,
      subtotalLaborCents: data.subtotalLaborCents.present
          ? data.subtotalLaborCents.value
          : this.subtotalLaborCents,
      subtotalMaterialCents: data.subtotalMaterialCents.present
          ? data.subtotalMaterialCents.value
          : this.subtotalMaterialCents,
      totalNetCents: data.totalNetCents.present
          ? data.totalNetCents.value
          : this.totalNetCents,
      vatRate: data.vatRate.present ? data.vatRate.value : this.vatRate,
      vatAmountCents: data.vatAmountCents.present
          ? data.vatAmountCents.value
          : this.vatAmountCents,
      totalGrossCents: data.totalGrossCents.present
          ? data.totalGrossCents.value
          : this.totalGrossCents,
      lineItemsJson: data.lineItemsJson.present
          ? data.lineItemsJson.value
          : this.lineItemsJson,
      recipientName: data.recipientName.present
          ? data.recipientName.value
          : this.recipientName,
      recipientAddress: data.recipientAddress.present
          ? data.recipientAddress.value
          : this.recipientAddress,
      pdfPath: data.pdfPath.present ? data.pdfPath.value : this.pdfPath,
      eInvoice: data.eInvoice.present ? data.eInvoice.value : this.eInvoice,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IssuedDocument(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('jobId: $jobId, ')
          ..write('customerId: $customerId, ')
          ..write('docType: $docType, ')
          ..write('docNumber: $docNumber, ')
          ..write('status: $status, ')
          ..write('title: $title, ')
          ..write('dateIssued: $dateIssued, ')
          ..write('dateDue: $dateDue, ')
          ..write('deliveryPeriod: $deliveryPeriod, ')
          ..write('subtotalLaborCents: $subtotalLaborCents, ')
          ..write('subtotalMaterialCents: $subtotalMaterialCents, ')
          ..write('totalNetCents: $totalNetCents, ')
          ..write('vatRate: $vatRate, ')
          ..write('vatAmountCents: $vatAmountCents, ')
          ..write('totalGrossCents: $totalGrossCents, ')
          ..write('lineItemsJson: $lineItemsJson, ')
          ..write('recipientName: $recipientName, ')
          ..write('recipientAddress: $recipientAddress, ')
          ..write('pdfPath: $pdfPath, ')
          ..write('eInvoice: $eInvoice, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        businessId,
        jobId,
        customerId,
        docType,
        docNumber,
        status,
        title,
        dateIssued,
        dateDue,
        deliveryPeriod,
        subtotalLaborCents,
        subtotalMaterialCents,
        totalNetCents,
        vatRate,
        vatAmountCents,
        totalGrossCents,
        lineItemsJson,
        recipientName,
        recipientAddress,
        pdfPath,
        eInvoice,
        updatedAt
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IssuedDocument &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.jobId == this.jobId &&
          other.customerId == this.customerId &&
          other.docType == this.docType &&
          other.docNumber == this.docNumber &&
          other.status == this.status &&
          other.title == this.title &&
          other.dateIssued == this.dateIssued &&
          other.dateDue == this.dateDue &&
          other.deliveryPeriod == this.deliveryPeriod &&
          other.subtotalLaborCents == this.subtotalLaborCents &&
          other.subtotalMaterialCents == this.subtotalMaterialCents &&
          other.totalNetCents == this.totalNetCents &&
          other.vatRate == this.vatRate &&
          other.vatAmountCents == this.vatAmountCents &&
          other.totalGrossCents == this.totalGrossCents &&
          other.lineItemsJson == this.lineItemsJson &&
          other.recipientName == this.recipientName &&
          other.recipientAddress == this.recipientAddress &&
          other.pdfPath == this.pdfPath &&
          other.eInvoice == this.eInvoice &&
          other.updatedAt == this.updatedAt);
}

class IssuedDocumentsCompanion extends UpdateCompanion<IssuedDocument> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String?> jobId;
  final Value<String?> customerId;
  final Value<String> docType;
  final Value<String> docNumber;
  final Value<String> status;
  final Value<String?> title;
  final Value<String> dateIssued;
  final Value<String?> dateDue;
  final Value<String?> deliveryPeriod;
  final Value<int> subtotalLaborCents;
  final Value<int> subtotalMaterialCents;
  final Value<int> totalNetCents;
  final Value<double> vatRate;
  final Value<int> vatAmountCents;
  final Value<int> totalGrossCents;
  final Value<String> lineItemsJson;
  final Value<String> recipientName;
  final Value<String?> recipientAddress;
  final Value<String?> pdfPath;
  final Value<bool> eInvoice;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const IssuedDocumentsCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.jobId = const Value.absent(),
    this.customerId = const Value.absent(),
    this.docType = const Value.absent(),
    this.docNumber = const Value.absent(),
    this.status = const Value.absent(),
    this.title = const Value.absent(),
    this.dateIssued = const Value.absent(),
    this.dateDue = const Value.absent(),
    this.deliveryPeriod = const Value.absent(),
    this.subtotalLaborCents = const Value.absent(),
    this.subtotalMaterialCents = const Value.absent(),
    this.totalNetCents = const Value.absent(),
    this.vatRate = const Value.absent(),
    this.vatAmountCents = const Value.absent(),
    this.totalGrossCents = const Value.absent(),
    this.lineItemsJson = const Value.absent(),
    this.recipientName = const Value.absent(),
    this.recipientAddress = const Value.absent(),
    this.pdfPath = const Value.absent(),
    this.eInvoice = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IssuedDocumentsCompanion.insert({
    required String id,
    required String businessId,
    this.jobId = const Value.absent(),
    this.customerId = const Value.absent(),
    required String docType,
    required String docNumber,
    required String status,
    this.title = const Value.absent(),
    required String dateIssued,
    this.dateDue = const Value.absent(),
    this.deliveryPeriod = const Value.absent(),
    required int subtotalLaborCents,
    required int subtotalMaterialCents,
    required int totalNetCents,
    required double vatRate,
    required int vatAmountCents,
    required int totalGrossCents,
    required String lineItemsJson,
    required String recipientName,
    this.recipientAddress = const Value.absent(),
    this.pdfPath = const Value.absent(),
    this.eInvoice = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        businessId = Value(businessId),
        docType = Value(docType),
        docNumber = Value(docNumber),
        status = Value(status),
        dateIssued = Value(dateIssued),
        subtotalLaborCents = Value(subtotalLaborCents),
        subtotalMaterialCents = Value(subtotalMaterialCents),
        totalNetCents = Value(totalNetCents),
        vatRate = Value(vatRate),
        vatAmountCents = Value(vatAmountCents),
        totalGrossCents = Value(totalGrossCents),
        lineItemsJson = Value(lineItemsJson),
        recipientName = Value(recipientName),
        updatedAt = Value(updatedAt);
  static Insertable<IssuedDocument> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? jobId,
    Expression<String>? customerId,
    Expression<String>? docType,
    Expression<String>? docNumber,
    Expression<String>? status,
    Expression<String>? title,
    Expression<String>? dateIssued,
    Expression<String>? dateDue,
    Expression<String>? deliveryPeriod,
    Expression<int>? subtotalLaborCents,
    Expression<int>? subtotalMaterialCents,
    Expression<int>? totalNetCents,
    Expression<double>? vatRate,
    Expression<int>? vatAmountCents,
    Expression<int>? totalGrossCents,
    Expression<String>? lineItemsJson,
    Expression<String>? recipientName,
    Expression<String>? recipientAddress,
    Expression<String>? pdfPath,
    Expression<bool>? eInvoice,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (jobId != null) 'job_id': jobId,
      if (customerId != null) 'customer_id': customerId,
      if (docType != null) 'doc_type': docType,
      if (docNumber != null) 'doc_number': docNumber,
      if (status != null) 'status': status,
      if (title != null) 'title': title,
      if (dateIssued != null) 'date_issued': dateIssued,
      if (dateDue != null) 'date_due': dateDue,
      if (deliveryPeriod != null) 'delivery_period': deliveryPeriod,
      if (subtotalLaborCents != null)
        'subtotal_labor_cents': subtotalLaborCents,
      if (subtotalMaterialCents != null)
        'subtotal_material_cents': subtotalMaterialCents,
      if (totalNetCents != null) 'total_net_cents': totalNetCents,
      if (vatRate != null) 'vat_rate': vatRate,
      if (vatAmountCents != null) 'vat_amount_cents': vatAmountCents,
      if (totalGrossCents != null) 'total_gross_cents': totalGrossCents,
      if (lineItemsJson != null) 'line_items_json': lineItemsJson,
      if (recipientName != null) 'recipient_name': recipientName,
      if (recipientAddress != null) 'recipient_address': recipientAddress,
      if (pdfPath != null) 'pdf_path': pdfPath,
      if (eInvoice != null) 'e_invoice': eInvoice,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IssuedDocumentsCompanion copyWith(
      {Value<String>? id,
      Value<String>? businessId,
      Value<String?>? jobId,
      Value<String?>? customerId,
      Value<String>? docType,
      Value<String>? docNumber,
      Value<String>? status,
      Value<String?>? title,
      Value<String>? dateIssued,
      Value<String?>? dateDue,
      Value<String?>? deliveryPeriod,
      Value<int>? subtotalLaborCents,
      Value<int>? subtotalMaterialCents,
      Value<int>? totalNetCents,
      Value<double>? vatRate,
      Value<int>? vatAmountCents,
      Value<int>? totalGrossCents,
      Value<String>? lineItemsJson,
      Value<String>? recipientName,
      Value<String?>? recipientAddress,
      Value<String?>? pdfPath,
      Value<bool>? eInvoice,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return IssuedDocumentsCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      jobId: jobId ?? this.jobId,
      customerId: customerId ?? this.customerId,
      docType: docType ?? this.docType,
      docNumber: docNumber ?? this.docNumber,
      status: status ?? this.status,
      title: title ?? this.title,
      dateIssued: dateIssued ?? this.dateIssued,
      dateDue: dateDue ?? this.dateDue,
      deliveryPeriod: deliveryPeriod ?? this.deliveryPeriod,
      subtotalLaborCents: subtotalLaborCents ?? this.subtotalLaborCents,
      subtotalMaterialCents:
          subtotalMaterialCents ?? this.subtotalMaterialCents,
      totalNetCents: totalNetCents ?? this.totalNetCents,
      vatRate: vatRate ?? this.vatRate,
      vatAmountCents: vatAmountCents ?? this.vatAmountCents,
      totalGrossCents: totalGrossCents ?? this.totalGrossCents,
      lineItemsJson: lineItemsJson ?? this.lineItemsJson,
      recipientName: recipientName ?? this.recipientName,
      recipientAddress: recipientAddress ?? this.recipientAddress,
      pdfPath: pdfPath ?? this.pdfPath,
      eInvoice: eInvoice ?? this.eInvoice,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (docType.present) {
      map['doc_type'] = Variable<String>(docType.value);
    }
    if (docNumber.present) {
      map['doc_number'] = Variable<String>(docNumber.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (dateIssued.present) {
      map['date_issued'] = Variable<String>(dateIssued.value);
    }
    if (dateDue.present) {
      map['date_due'] = Variable<String>(dateDue.value);
    }
    if (deliveryPeriod.present) {
      map['delivery_period'] = Variable<String>(deliveryPeriod.value);
    }
    if (subtotalLaborCents.present) {
      map['subtotal_labor_cents'] = Variable<int>(subtotalLaborCents.value);
    }
    if (subtotalMaterialCents.present) {
      map['subtotal_material_cents'] =
          Variable<int>(subtotalMaterialCents.value);
    }
    if (totalNetCents.present) {
      map['total_net_cents'] = Variable<int>(totalNetCents.value);
    }
    if (vatRate.present) {
      map['vat_rate'] = Variable<double>(vatRate.value);
    }
    if (vatAmountCents.present) {
      map['vat_amount_cents'] = Variable<int>(vatAmountCents.value);
    }
    if (totalGrossCents.present) {
      map['total_gross_cents'] = Variable<int>(totalGrossCents.value);
    }
    if (lineItemsJson.present) {
      map['line_items_json'] = Variable<String>(lineItemsJson.value);
    }
    if (recipientName.present) {
      map['recipient_name'] = Variable<String>(recipientName.value);
    }
    if (recipientAddress.present) {
      map['recipient_address'] = Variable<String>(recipientAddress.value);
    }
    if (pdfPath.present) {
      map['pdf_path'] = Variable<String>(pdfPath.value);
    }
    if (eInvoice.present) {
      map['e_invoice'] = Variable<bool>(eInvoice.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IssuedDocumentsCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('jobId: $jobId, ')
          ..write('customerId: $customerId, ')
          ..write('docType: $docType, ')
          ..write('docNumber: $docNumber, ')
          ..write('status: $status, ')
          ..write('title: $title, ')
          ..write('dateIssued: $dateIssued, ')
          ..write('dateDue: $dateDue, ')
          ..write('deliveryPeriod: $deliveryPeriod, ')
          ..write('subtotalLaborCents: $subtotalLaborCents, ')
          ..write('subtotalMaterialCents: $subtotalMaterialCents, ')
          ..write('totalNetCents: $totalNetCents, ')
          ..write('vatRate: $vatRate, ')
          ..write('vatAmountCents: $vatAmountCents, ')
          ..write('totalGrossCents: $totalGrossCents, ')
          ..write('lineItemsJson: $lineItemsJson, ')
          ..write('recipientName: $recipientName, ')
          ..write('recipientAddress: $recipientAddress, ')
          ..write('pdfPath: $pdfPath, ')
          ..write('eInvoice: $eInvoice, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CustomersTable customers = $CustomersTable(this);
  late final $JobsTable jobs = $JobsTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  late final $PendingCapturesTable pendingCaptures =
      $PendingCapturesTable(this);
  late final $IssuedDocumentsTable issuedDocuments =
      $IssuedDocumentsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [customers, jobs, outbox, syncMeta, pendingCaptures, issuedDocuments];
}

typedef $$CustomersTableCreateCompanionBuilder = CustomersCompanion Function({
  required String id,
  required String businessId,
  Value<String?> salutation,
  required String name,
  Value<String?> firstName,
  Value<String?> email,
  Value<String?> phone,
  Value<String?> street,
  Value<String?> zip,
  Value<String?> city,
  Value<String?> notes,
  Value<String?> mergedInto,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$CustomersTableUpdateCompanionBuilder = CustomersCompanion Function({
  Value<String> id,
  Value<String> businessId,
  Value<String?> salutation,
  Value<String> name,
  Value<String?> firstName,
  Value<String?> email,
  Value<String?> phone,
  Value<String?> street,
  Value<String?> zip,
  Value<String?> city,
  Value<String?> notes,
  Value<String?> mergedInto,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$CustomersTableFilterComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get businessId => $composableBuilder(
      column: $table.businessId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get salutation => $composableBuilder(
      column: $table.salutation, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get firstName => $composableBuilder(
      column: $table.firstName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get email => $composableBuilder(
      column: $table.email, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get street => $composableBuilder(
      column: $table.street, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get zip => $composableBuilder(
      column: $table.zip, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get city => $composableBuilder(
      column: $table.city, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mergedInto => $composableBuilder(
      column: $table.mergedInto, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$CustomersTableOrderingComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get businessId => $composableBuilder(
      column: $table.businessId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get salutation => $composableBuilder(
      column: $table.salutation, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get firstName => $composableBuilder(
      column: $table.firstName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get email => $composableBuilder(
      column: $table.email, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get street => $composableBuilder(
      column: $table.street, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get zip => $composableBuilder(
      column: $table.zip, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get city => $composableBuilder(
      column: $table.city, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mergedInto => $composableBuilder(
      column: $table.mergedInto, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$CustomersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(
      column: $table.businessId, builder: (column) => column);

  GeneratedColumn<String> get salutation => $composableBuilder(
      column: $table.salutation, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get firstName =>
      $composableBuilder(column: $table.firstName, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get street =>
      $composableBuilder(column: $table.street, builder: (column) => column);

  GeneratedColumn<String> get zip =>
      $composableBuilder(column: $table.zip, builder: (column) => column);

  GeneratedColumn<String> get city =>
      $composableBuilder(column: $table.city, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get mergedInto => $composableBuilder(
      column: $table.mergedInto, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CustomersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CustomersTable,
    Customer,
    $$CustomersTableFilterComposer,
    $$CustomersTableOrderingComposer,
    $$CustomersTableAnnotationComposer,
    $$CustomersTableCreateCompanionBuilder,
    $$CustomersTableUpdateCompanionBuilder,
    (Customer, BaseReferences<_$AppDatabase, $CustomersTable, Customer>),
    Customer,
    PrefetchHooks Function()> {
  $$CustomersTableTableManager(_$AppDatabase db, $CustomersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> businessId = const Value.absent(),
            Value<String?> salutation = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> firstName = const Value.absent(),
            Value<String?> email = const Value.absent(),
            Value<String?> phone = const Value.absent(),
            Value<String?> street = const Value.absent(),
            Value<String?> zip = const Value.absent(),
            Value<String?> city = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<String?> mergedInto = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CustomersCompanion(
            id: id,
            businessId: businessId,
            salutation: salutation,
            name: name,
            firstName: firstName,
            email: email,
            phone: phone,
            street: street,
            zip: zip,
            city: city,
            notes: notes,
            mergedInto: mergedInto,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String businessId,
            Value<String?> salutation = const Value.absent(),
            required String name,
            Value<String?> firstName = const Value.absent(),
            Value<String?> email = const Value.absent(),
            Value<String?> phone = const Value.absent(),
            Value<String?> street = const Value.absent(),
            Value<String?> zip = const Value.absent(),
            Value<String?> city = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<String?> mergedInto = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CustomersCompanion.insert(
            id: id,
            businessId: businessId,
            salutation: salutation,
            name: name,
            firstName: firstName,
            email: email,
            phone: phone,
            street: street,
            zip: zip,
            city: city,
            notes: notes,
            mergedInto: mergedInto,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CustomersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CustomersTable,
    Customer,
    $$CustomersTableFilterComposer,
    $$CustomersTableOrderingComposer,
    $$CustomersTableAnnotationComposer,
    $$CustomersTableCreateCompanionBuilder,
    $$CustomersTableUpdateCompanionBuilder,
    (Customer, BaseReferences<_$AppDatabase, $CustomersTable, Customer>),
    Customer,
    PrefetchHooks Function()>;
typedef $$JobsTableCreateCompanionBuilder = JobsCompanion Function({
  required String id,
  required String businessId,
  Value<String?> customerId,
  required String title,
  Value<String?> description,
  Value<String> status,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$JobsTableUpdateCompanionBuilder = JobsCompanion Function({
  Value<String> id,
  Value<String> businessId,
  Value<String?> customerId,
  Value<String> title,
  Value<String?> description,
  Value<String> status,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$JobsTableFilterComposer extends Composer<_$AppDatabase, $JobsTable> {
  $$JobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get businessId => $composableBuilder(
      column: $table.businessId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get customerId => $composableBuilder(
      column: $table.customerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$JobsTableOrderingComposer extends Composer<_$AppDatabase, $JobsTable> {
  $$JobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get businessId => $composableBuilder(
      column: $table.businessId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get customerId => $composableBuilder(
      column: $table.customerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$JobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $JobsTable> {
  $$JobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(
      column: $table.businessId, builder: (column) => column);

  GeneratedColumn<String> get customerId => $composableBuilder(
      column: $table.customerId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$JobsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $JobsTable,
    Job,
    $$JobsTableFilterComposer,
    $$JobsTableOrderingComposer,
    $$JobsTableAnnotationComposer,
    $$JobsTableCreateCompanionBuilder,
    $$JobsTableUpdateCompanionBuilder,
    (Job, BaseReferences<_$AppDatabase, $JobsTable, Job>),
    Job,
    PrefetchHooks Function()> {
  $$JobsTableTableManager(_$AppDatabase db, $JobsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> businessId = const Value.absent(),
            Value<String?> customerId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              JobsCompanion(
            id: id,
            businessId: businessId,
            customerId: customerId,
            title: title,
            description: description,
            status: status,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String businessId,
            Value<String?> customerId = const Value.absent(),
            required String title,
            Value<String?> description = const Value.absent(),
            Value<String> status = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              JobsCompanion.insert(
            id: id,
            businessId: businessId,
            customerId: customerId,
            title: title,
            description: description,
            status: status,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$JobsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $JobsTable,
    Job,
    $$JobsTableFilterComposer,
    $$JobsTableOrderingComposer,
    $$JobsTableAnnotationComposer,
    $$JobsTableCreateCompanionBuilder,
    $$JobsTableUpdateCompanionBuilder,
    (Job, BaseReferences<_$AppDatabase, $JobsTable, Job>),
    Job,
    PrefetchHooks Function()>;
typedef $$OutboxTableCreateCompanionBuilder = OutboxCompanion Function({
  Value<int> id,
  required String entity,
  required String entityId,
  required String op,
  required DateTime createdAt,
  Value<int> rev,
  Value<int> attempts,
  Value<String?> lastError,
});
typedef $$OutboxTableUpdateCompanionBuilder = OutboxCompanion Function({
  Value<int> id,
  Value<String> entity,
  Value<String> entityId,
  Value<String> op,
  Value<DateTime> createdAt,
  Value<int> rev,
  Value<int> attempts,
  Value<String?> lastError,
});

class $$OutboxTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entity => $composableBuilder(
      column: $table.entity, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityId => $composableBuilder(
      column: $table.entityId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get op => $composableBuilder(
      column: $table.op, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get rev => $composableBuilder(
      column: $table.rev, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnFilters(column));
}

class $$OutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entity => $composableBuilder(
      column: $table.entity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityId => $composableBuilder(
      column: $table.entityId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get op => $composableBuilder(
      column: $table.op, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get rev => $composableBuilder(
      column: $table.rev, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnOrderings(column));
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get op =>
      $composableBuilder(column: $table.op, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get rev =>
      $composableBuilder(column: $table.rev, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$OutboxTableTableManager extends RootTableManager<
    _$AppDatabase,
    $OutboxTable,
    OutboxData,
    $$OutboxTableFilterComposer,
    $$OutboxTableOrderingComposer,
    $$OutboxTableAnnotationComposer,
    $$OutboxTableCreateCompanionBuilder,
    $$OutboxTableUpdateCompanionBuilder,
    (OutboxData, BaseReferences<_$AppDatabase, $OutboxTable, OutboxData>),
    OutboxData,
    PrefetchHooks Function()> {
  $$OutboxTableTableManager(_$AppDatabase db, $OutboxTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> entity = const Value.absent(),
            Value<String> entityId = const Value.absent(),
            Value<String> op = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rev = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
          }) =>
              OutboxCompanion(
            id: id,
            entity: entity,
            entityId: entityId,
            op: op,
            createdAt: createdAt,
            rev: rev,
            attempts: attempts,
            lastError: lastError,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String entity,
            required String entityId,
            required String op,
            required DateTime createdAt,
            Value<int> rev = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
          }) =>
              OutboxCompanion.insert(
            id: id,
            entity: entity,
            entityId: entityId,
            op: op,
            createdAt: createdAt,
            rev: rev,
            attempts: attempts,
            lastError: lastError,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$OutboxTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $OutboxTable,
    OutboxData,
    $$OutboxTableFilterComposer,
    $$OutboxTableOrderingComposer,
    $$OutboxTableAnnotationComposer,
    $$OutboxTableCreateCompanionBuilder,
    $$OutboxTableUpdateCompanionBuilder,
    (OutboxData, BaseReferences<_$AppDatabase, $OutboxTable, OutboxData>),
    OutboxData,
    PrefetchHooks Function()>;
typedef $$SyncMetaTableCreateCompanionBuilder = SyncMetaCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SyncMetaTableUpdateCompanionBuilder = SyncMetaCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SyncMetaTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncMetaTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncMetaTable,
    SyncMetaData,
    $$SyncMetaTableFilterComposer,
    $$SyncMetaTableOrderingComposer,
    $$SyncMetaTableAnnotationComposer,
    $$SyncMetaTableCreateCompanionBuilder,
    $$SyncMetaTableUpdateCompanionBuilder,
    (SyncMetaData, BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>),
    SyncMetaData,
    PrefetchHooks Function()> {
  $$SyncMetaTableTableManager(_$AppDatabase db, $SyncMetaTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncMetaCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncMetaCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncMetaTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncMetaTable,
    SyncMetaData,
    $$SyncMetaTableFilterComposer,
    $$SyncMetaTableOrderingComposer,
    $$SyncMetaTableAnnotationComposer,
    $$SyncMetaTableCreateCompanionBuilder,
    $$SyncMetaTableUpdateCompanionBuilder,
    (SyncMetaData, BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>),
    SyncMetaData,
    PrefetchHooks Function()>;
typedef $$PendingCapturesTableCreateCompanionBuilder = PendingCapturesCompanion
    Function({
  required String id,
  required String kind,
  Value<String?> localPath,
  Value<String?> transcript,
  Value<int> durationSeconds,
  Value<String> status,
  Value<bool> uploaded,
  Value<int> attempts,
  Value<String?> errorMessage,
  Value<String?> draftJson,
  Value<String?> jobId,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$PendingCapturesTableUpdateCompanionBuilder = PendingCapturesCompanion
    Function({
  Value<String> id,
  Value<String> kind,
  Value<String?> localPath,
  Value<String?> transcript,
  Value<int> durationSeconds,
  Value<String> status,
  Value<bool> uploaded,
  Value<int> attempts,
  Value<String?> errorMessage,
  Value<String?> draftJson,
  Value<String?> jobId,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$PendingCapturesTableFilterComposer
    extends Composer<_$AppDatabase, $PendingCapturesTable> {
  $$PendingCapturesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get localPath => $composableBuilder(
      column: $table.localPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get transcript => $composableBuilder(
      column: $table.transcript, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get uploaded => $composableBuilder(
      column: $table.uploaded, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get draftJson => $composableBuilder(
      column: $table.draftJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get jobId => $composableBuilder(
      column: $table.jobId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$PendingCapturesTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingCapturesTable> {
  $$PendingCapturesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get localPath => $composableBuilder(
      column: $table.localPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get transcript => $composableBuilder(
      column: $table.transcript, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get uploaded => $composableBuilder(
      column: $table.uploaded, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get draftJson => $composableBuilder(
      column: $table.draftJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get jobId => $composableBuilder(
      column: $table.jobId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$PendingCapturesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingCapturesTable> {
  $$PendingCapturesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get transcript => $composableBuilder(
      column: $table.transcript, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
      column: $table.durationSeconds, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get uploaded =>
      $composableBuilder(column: $table.uploaded, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => column);

  GeneratedColumn<String> get draftJson =>
      $composableBuilder(column: $table.draftJson, builder: (column) => column);

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PendingCapturesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PendingCapturesTable,
    PendingCapture,
    $$PendingCapturesTableFilterComposer,
    $$PendingCapturesTableOrderingComposer,
    $$PendingCapturesTableAnnotationComposer,
    $$PendingCapturesTableCreateCompanionBuilder,
    $$PendingCapturesTableUpdateCompanionBuilder,
    (
      PendingCapture,
      BaseReferences<_$AppDatabase, $PendingCapturesTable, PendingCapture>
    ),
    PendingCapture,
    PrefetchHooks Function()> {
  $$PendingCapturesTableTableManager(
      _$AppDatabase db, $PendingCapturesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingCapturesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingCapturesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingCapturesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String?> localPath = const Value.absent(),
            Value<String?> transcript = const Value.absent(),
            Value<int> durationSeconds = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<bool> uploaded = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<String?> errorMessage = const Value.absent(),
            Value<String?> draftJson = const Value.absent(),
            Value<String?> jobId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingCapturesCompanion(
            id: id,
            kind: kind,
            localPath: localPath,
            transcript: transcript,
            durationSeconds: durationSeconds,
            status: status,
            uploaded: uploaded,
            attempts: attempts,
            errorMessage: errorMessage,
            draftJson: draftJson,
            jobId: jobId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String kind,
            Value<String?> localPath = const Value.absent(),
            Value<String?> transcript = const Value.absent(),
            Value<int> durationSeconds = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<bool> uploaded = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<String?> errorMessage = const Value.absent(),
            Value<String?> draftJson = const Value.absent(),
            Value<String?> jobId = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingCapturesCompanion.insert(
            id: id,
            kind: kind,
            localPath: localPath,
            transcript: transcript,
            durationSeconds: durationSeconds,
            status: status,
            uploaded: uploaded,
            attempts: attempts,
            errorMessage: errorMessage,
            draftJson: draftJson,
            jobId: jobId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PendingCapturesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PendingCapturesTable,
    PendingCapture,
    $$PendingCapturesTableFilterComposer,
    $$PendingCapturesTableOrderingComposer,
    $$PendingCapturesTableAnnotationComposer,
    $$PendingCapturesTableCreateCompanionBuilder,
    $$PendingCapturesTableUpdateCompanionBuilder,
    (
      PendingCapture,
      BaseReferences<_$AppDatabase, $PendingCapturesTable, PendingCapture>
    ),
    PendingCapture,
    PrefetchHooks Function()>;
typedef $$IssuedDocumentsTableCreateCompanionBuilder = IssuedDocumentsCompanion
    Function({
  required String id,
  required String businessId,
  Value<String?> jobId,
  Value<String?> customerId,
  required String docType,
  required String docNumber,
  required String status,
  Value<String?> title,
  required String dateIssued,
  Value<String?> dateDue,
  Value<String?> deliveryPeriod,
  required int subtotalLaborCents,
  required int subtotalMaterialCents,
  required int totalNetCents,
  required double vatRate,
  required int vatAmountCents,
  required int totalGrossCents,
  required String lineItemsJson,
  required String recipientName,
  Value<String?> recipientAddress,
  Value<String?> pdfPath,
  Value<bool> eInvoice,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$IssuedDocumentsTableUpdateCompanionBuilder = IssuedDocumentsCompanion
    Function({
  Value<String> id,
  Value<String> businessId,
  Value<String?> jobId,
  Value<String?> customerId,
  Value<String> docType,
  Value<String> docNumber,
  Value<String> status,
  Value<String?> title,
  Value<String> dateIssued,
  Value<String?> dateDue,
  Value<String?> deliveryPeriod,
  Value<int> subtotalLaborCents,
  Value<int> subtotalMaterialCents,
  Value<int> totalNetCents,
  Value<double> vatRate,
  Value<int> vatAmountCents,
  Value<int> totalGrossCents,
  Value<String> lineItemsJson,
  Value<String> recipientName,
  Value<String?> recipientAddress,
  Value<String?> pdfPath,
  Value<bool> eInvoice,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$IssuedDocumentsTableFilterComposer
    extends Composer<_$AppDatabase, $IssuedDocumentsTable> {
  $$IssuedDocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get businessId => $composableBuilder(
      column: $table.businessId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get jobId => $composableBuilder(
      column: $table.jobId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get customerId => $composableBuilder(
      column: $table.customerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get docType => $composableBuilder(
      column: $table.docType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get docNumber => $composableBuilder(
      column: $table.docNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dateIssued => $composableBuilder(
      column: $table.dateIssued, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dateDue => $composableBuilder(
      column: $table.dateDue, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deliveryPeriod => $composableBuilder(
      column: $table.deliveryPeriod,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get subtotalLaborCents => $composableBuilder(
      column: $table.subtotalLaborCents,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get subtotalMaterialCents => $composableBuilder(
      column: $table.subtotalMaterialCents,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalNetCents => $composableBuilder(
      column: $table.totalNetCents, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get vatRate => $composableBuilder(
      column: $table.vatRate, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get vatAmountCents => $composableBuilder(
      column: $table.vatAmountCents,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalGrossCents => $composableBuilder(
      column: $table.totalGrossCents,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lineItemsJson => $composableBuilder(
      column: $table.lineItemsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recipientName => $composableBuilder(
      column: $table.recipientName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recipientAddress => $composableBuilder(
      column: $table.recipientAddress,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pdfPath => $composableBuilder(
      column: $table.pdfPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get eInvoice => $composableBuilder(
      column: $table.eInvoice, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$IssuedDocumentsTableOrderingComposer
    extends Composer<_$AppDatabase, $IssuedDocumentsTable> {
  $$IssuedDocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get businessId => $composableBuilder(
      column: $table.businessId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get jobId => $composableBuilder(
      column: $table.jobId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get customerId => $composableBuilder(
      column: $table.customerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get docType => $composableBuilder(
      column: $table.docType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get docNumber => $composableBuilder(
      column: $table.docNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dateIssued => $composableBuilder(
      column: $table.dateIssued, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dateDue => $composableBuilder(
      column: $table.dateDue, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deliveryPeriod => $composableBuilder(
      column: $table.deliveryPeriod,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get subtotalLaborCents => $composableBuilder(
      column: $table.subtotalLaborCents,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get subtotalMaterialCents => $composableBuilder(
      column: $table.subtotalMaterialCents,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalNetCents => $composableBuilder(
      column: $table.totalNetCents,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get vatRate => $composableBuilder(
      column: $table.vatRate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get vatAmountCents => $composableBuilder(
      column: $table.vatAmountCents,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalGrossCents => $composableBuilder(
      column: $table.totalGrossCents,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lineItemsJson => $composableBuilder(
      column: $table.lineItemsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recipientName => $composableBuilder(
      column: $table.recipientName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recipientAddress => $composableBuilder(
      column: $table.recipientAddress,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pdfPath => $composableBuilder(
      column: $table.pdfPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get eInvoice => $composableBuilder(
      column: $table.eInvoice, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$IssuedDocumentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $IssuedDocumentsTable> {
  $$IssuedDocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(
      column: $table.businessId, builder: (column) => column);

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get customerId => $composableBuilder(
      column: $table.customerId, builder: (column) => column);

  GeneratedColumn<String> get docType =>
      $composableBuilder(column: $table.docType, builder: (column) => column);

  GeneratedColumn<String> get docNumber =>
      $composableBuilder(column: $table.docNumber, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get dateIssued => $composableBuilder(
      column: $table.dateIssued, builder: (column) => column);

  GeneratedColumn<String> get dateDue =>
      $composableBuilder(column: $table.dateDue, builder: (column) => column);

  GeneratedColumn<String> get deliveryPeriod => $composableBuilder(
      column: $table.deliveryPeriod, builder: (column) => column);

  GeneratedColumn<int> get subtotalLaborCents => $composableBuilder(
      column: $table.subtotalLaborCents, builder: (column) => column);

  GeneratedColumn<int> get subtotalMaterialCents => $composableBuilder(
      column: $table.subtotalMaterialCents, builder: (column) => column);

  GeneratedColumn<int> get totalNetCents => $composableBuilder(
      column: $table.totalNetCents, builder: (column) => column);

  GeneratedColumn<double> get vatRate =>
      $composableBuilder(column: $table.vatRate, builder: (column) => column);

  GeneratedColumn<int> get vatAmountCents => $composableBuilder(
      column: $table.vatAmountCents, builder: (column) => column);

  GeneratedColumn<int> get totalGrossCents => $composableBuilder(
      column: $table.totalGrossCents, builder: (column) => column);

  GeneratedColumn<String> get lineItemsJson => $composableBuilder(
      column: $table.lineItemsJson, builder: (column) => column);

  GeneratedColumn<String> get recipientName => $composableBuilder(
      column: $table.recipientName, builder: (column) => column);

  GeneratedColumn<String> get recipientAddress => $composableBuilder(
      column: $table.recipientAddress, builder: (column) => column);

  GeneratedColumn<String> get pdfPath =>
      $composableBuilder(column: $table.pdfPath, builder: (column) => column);

  GeneratedColumn<bool> get eInvoice =>
      $composableBuilder(column: $table.eInvoice, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$IssuedDocumentsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $IssuedDocumentsTable,
    IssuedDocument,
    $$IssuedDocumentsTableFilterComposer,
    $$IssuedDocumentsTableOrderingComposer,
    $$IssuedDocumentsTableAnnotationComposer,
    $$IssuedDocumentsTableCreateCompanionBuilder,
    $$IssuedDocumentsTableUpdateCompanionBuilder,
    (
      IssuedDocument,
      BaseReferences<_$AppDatabase, $IssuedDocumentsTable, IssuedDocument>
    ),
    IssuedDocument,
    PrefetchHooks Function()> {
  $$IssuedDocumentsTableTableManager(
      _$AppDatabase db, $IssuedDocumentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IssuedDocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IssuedDocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IssuedDocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> businessId = const Value.absent(),
            Value<String?> jobId = const Value.absent(),
            Value<String?> customerId = const Value.absent(),
            Value<String> docType = const Value.absent(),
            Value<String> docNumber = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> title = const Value.absent(),
            Value<String> dateIssued = const Value.absent(),
            Value<String?> dateDue = const Value.absent(),
            Value<String?> deliveryPeriod = const Value.absent(),
            Value<int> subtotalLaborCents = const Value.absent(),
            Value<int> subtotalMaterialCents = const Value.absent(),
            Value<int> totalNetCents = const Value.absent(),
            Value<double> vatRate = const Value.absent(),
            Value<int> vatAmountCents = const Value.absent(),
            Value<int> totalGrossCents = const Value.absent(),
            Value<String> lineItemsJson = const Value.absent(),
            Value<String> recipientName = const Value.absent(),
            Value<String?> recipientAddress = const Value.absent(),
            Value<String?> pdfPath = const Value.absent(),
            Value<bool> eInvoice = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              IssuedDocumentsCompanion(
            id: id,
            businessId: businessId,
            jobId: jobId,
            customerId: customerId,
            docType: docType,
            docNumber: docNumber,
            status: status,
            title: title,
            dateIssued: dateIssued,
            dateDue: dateDue,
            deliveryPeriod: deliveryPeriod,
            subtotalLaborCents: subtotalLaborCents,
            subtotalMaterialCents: subtotalMaterialCents,
            totalNetCents: totalNetCents,
            vatRate: vatRate,
            vatAmountCents: vatAmountCents,
            totalGrossCents: totalGrossCents,
            lineItemsJson: lineItemsJson,
            recipientName: recipientName,
            recipientAddress: recipientAddress,
            pdfPath: pdfPath,
            eInvoice: eInvoice,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String businessId,
            Value<String?> jobId = const Value.absent(),
            Value<String?> customerId = const Value.absent(),
            required String docType,
            required String docNumber,
            required String status,
            Value<String?> title = const Value.absent(),
            required String dateIssued,
            Value<String?> dateDue = const Value.absent(),
            Value<String?> deliveryPeriod = const Value.absent(),
            required int subtotalLaborCents,
            required int subtotalMaterialCents,
            required int totalNetCents,
            required double vatRate,
            required int vatAmountCents,
            required int totalGrossCents,
            required String lineItemsJson,
            required String recipientName,
            Value<String?> recipientAddress = const Value.absent(),
            Value<String?> pdfPath = const Value.absent(),
            Value<bool> eInvoice = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              IssuedDocumentsCompanion.insert(
            id: id,
            businessId: businessId,
            jobId: jobId,
            customerId: customerId,
            docType: docType,
            docNumber: docNumber,
            status: status,
            title: title,
            dateIssued: dateIssued,
            dateDue: dateDue,
            deliveryPeriod: deliveryPeriod,
            subtotalLaborCents: subtotalLaborCents,
            subtotalMaterialCents: subtotalMaterialCents,
            totalNetCents: totalNetCents,
            vatRate: vatRate,
            vatAmountCents: vatAmountCents,
            totalGrossCents: totalGrossCents,
            lineItemsJson: lineItemsJson,
            recipientName: recipientName,
            recipientAddress: recipientAddress,
            pdfPath: pdfPath,
            eInvoice: eInvoice,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$IssuedDocumentsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $IssuedDocumentsTable,
    IssuedDocument,
    $$IssuedDocumentsTableFilterComposer,
    $$IssuedDocumentsTableOrderingComposer,
    $$IssuedDocumentsTableAnnotationComposer,
    $$IssuedDocumentsTableCreateCompanionBuilder,
    $$IssuedDocumentsTableUpdateCompanionBuilder,
    (
      IssuedDocument,
      BaseReferences<_$AppDatabase, $IssuedDocumentsTable, IssuedDocument>
    ),
    IssuedDocument,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db, _db.customers);
  $$JobsTableTableManager get jobs => $$JobsTableTableManager(_db, _db.jobs);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
  $$PendingCapturesTableTableManager get pendingCaptures =>
      $$PendingCapturesTableTableManager(_db, _db.pendingCaptures);
  $$IssuedDocumentsTableTableManager get issuedDocuments =>
      $$IssuedDocumentsTableTableManager(_db, _db.issuedDocuments);
}

import 'package:xml/xml.dart';

import '../../../core/utils/address_parser.dart';
import '../domain/document_data.dart';

/// The data needed for an e-invoice is missing (the message says what, in German, for the user).
class EInvoiceException implements Exception {
  const EInvoiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The guideline of the ZUGFeRD / Factur-X profile "EN 16931" (the European standard).
const einvoiceGuideline = 'urn:cen.eu:en16931:2017';

/// The conformance level written into the PDF metadata for the profile above.
const einvoiceConformanceLevel = 'EN 16931';

const _rsm = 'urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100';
const _ram = 'urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100';
const _udt = 'urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100';
const _qdt = 'urn:un:unece:uncefact:data:standard:QualifiedDataType:100';

String _amount(int cents) {
  final c = cents.abs();
  return '${c ~/ 100}.${(c % 100).toString().padLeft(2, '0')}';
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

/// UN/ECE recommendation 20 unit codes.
String _unitCode(String unit) => switch (unit) {
      'Std' => 'HUR',
      'm' => 'MTR',
      _ => 'C62', // Stk, Pauschal: "one" (a piece)
    };

String _quantity(double q) {
  final s = q.toStringAsFixed(4);
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '.0');
}

/// "Gemäß ... vom 01.10.2026" style date inside a cancellation title -> (number, date).
({String number, DateTime date})? _cancelledInvoice(String? title) {
  final m = RegExp(r'Rechnung\s+(\S+)\s+vom\s+(\d{2})\.(\d{2})\.(\d{4})').firstMatch(title ?? '');
  if (m == null) return null;
  return (number: m.group(1)!, date: DateTime(int.parse(m.group(4)!), int.parse(m.group(3)!), int.parse(m.group(2)!)));
}

/// "01.10.2026" or "01.10.2026 - 05.10.2026" -> one or two dates; null if it is free text.
List<DateTime>? _period(String? text) {
  final found = RegExp(r'(\d{2})\.(\d{2})\.(\d{4})').allMatches(text ?? '').toList();
  if (found.isEmpty || found.length > 2) return null;
  final dates = [for (final m in found) DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!))];
  return dates;
}

/// What an e-invoice needs that a normal invoice can do without, or null if everything is there.
/// Checked BEFORE the number is issued: once issued, a document cannot be redone.
String? eInvoiceBlockReason({required CompanyDetails company, required String? recipientAddress}) {
  final c = company;
  if (c.taxNumber.trim().isEmpty && c.vatId.trim().isEmpty) {
    return 'Für die E-Rechnung fehlt die Steuernummer oder USt-IdNr. des Betriebs.';
  }
  if (c.street.isEmpty || c.zip.isEmpty || c.city.isEmpty) {
    return 'Für die E-Rechnung fehlt die vollständige Anschrift des Betriebs.';
  }
  if (c.iban.trim().isEmpty) return 'Für die E-Rechnung fehlt die IBAN des Betriebs (Betrieb → Bearbeiten).';
  final buyer = parseGermanAddress(recipientAddress);
  if ((buyer.street ?? '').isEmpty || (buyer.zip ?? '').isEmpty || (buyer.city ?? '').isEmpty) {
    return 'Für die E-Rechnung braucht der Kunde eine vollständige Anschrift (Straße, PLZ, Ort).';
  }
  return null;
}

/// Should the e-invoice be pre-selected for this customer? Businesses need one (private customers
/// do not): a customer marked "Firma", or a name that looks like a company. The user can change it.
bool defaultEInvoiceFor({required String name, String? salutation}) {
  if (salutation == 'Firma') return true;
  final lower = name.toLowerCase();
  if (lower.contains('verwaltung')) return true; // Hausverwaltung, Immobilienverwaltung, ...
  const legalForms = {'gmbh', 'mbh', 'ag', 'kg', 'ug', 'ohg', 'gbr', 'se', 'eg', 'ek', 'ev', 'stiftung', 'verein'};
  final words = lower.replaceAll('.', '').split(RegExp(r'[^a-zäöüß&]+')).where((w) => w.isNotEmpty);
  return words.any(legalForms.contains);
}

/// The machine-readable half of an e-invoice: a UN/CEFACT "Cross Industry Invoice" (CII) in the
/// profile EN 16931, built from the SAME document data as the printed PDF. Amounts are copied from
/// the stored document (the server's numbers), never recalculated by the AI.
///
/// A Stornorechnung becomes a credit note (type 381): the amounts are positive there and the
/// document says which invoice it reverses.
String buildCrossIndustryInvoice(PdfDocumentData d, {String? buyerEmail}) {
  final number = d.docNumber;
  if (number == null) throw const EInvoiceException('Für eine Vorschau gibt es keine E-Rechnung.');
  if (d.docType == 'quote') throw const EInvoiceException('Ein Angebot ist keine Rechnung.');
  final c = d.company;
  final missing = eInvoiceBlockReason(company: c, recipientAddress: d.recipientAddress);
  if (missing != null) throw EInvoiceException(missing);
  final buyer = parseGermanAddress(d.recipientAddress);
  if (d.lines.isEmpty) throw const EInvoiceException('Die Rechnung hat keine Positionen.');

  final isCredit = d.isCancellation;
  final exempt = d.vatRate == 0;
  final vatCategory = exempt ? 'E' : 'S';
  final vatPercent = d.vatRate.toStringAsFixed(2);
  final issue = d.issueDate;

  final b = XmlBuilder();
  b.processing('xml', 'version="1.0" encoding="UTF-8"');
  b.element('rsm:CrossIndustryInvoice', namespaces: {
    _rsm: 'rsm',
    _ram: 'ram',
    _udt: 'udt',
    _qdt: 'qdt',
    'http://www.w3.org/2001/XMLSchema-instance': 'xsi',
  }, nest: () {
    b.element('rsm:ExchangedDocumentContext', nest: () {
      b.element('ram:GuidelineSpecifiedDocumentContextParameter', nest: () {
        b.element('ram:ID', nest: einvoiceGuideline);
      });
    });

    b.element('rsm:ExchangedDocument', nest: () {
      b.element('ram:ID', nest: number);
      b.element('ram:TypeCode', nest: isCredit ? '381' : '380');
      b.element('ram:IssueDateTime', nest: () {
        b.element('udt:DateTimeString', attributes: {'format': '102'}, nest: _date(issue));
      });
      if (exempt) {
        b.element('ram:IncludedNote', nest: () {
          b.element('ram:Content', nest: 'Gemäß § 19 UStG wird keine Umsatzsteuer berechnet.');
        });
      }
    });

    b.element('rsm:SupplyChainTradeTransaction', nest: () {
      for (final (i, line) in d.lines.indexed) {
        b.element('ram:IncludedSupplyChainTradeLineItem', nest: () {
          b.element('ram:AssociatedDocumentLineDocument', nest: () {
            b.element('ram:LineID', nest: '${i + 1}');
          });
          b.element('ram:SpecifiedTradeProduct', nest: () {
            b.element('ram:Name', nest: line.description);
          });
          b.element('ram:SpecifiedLineTradeAgreement', nest: () {
            b.element('ram:NetPriceProductTradePrice', nest: () {
              b.element('ram:ChargeAmount', nest: _amount(line.unitPriceNetCents));
            });
          });
          b.element('ram:SpecifiedLineTradeDelivery', nest: () {
            b.element('ram:BilledQuantity',
                attributes: {'unitCode': _unitCode(line.unit)}, nest: _quantity(line.quantity.abs()));
          });
          b.element('ram:SpecifiedLineTradeSettlement', nest: () {
            b.element('ram:ApplicableTradeTax', nest: () {
              b.element('ram:TypeCode', nest: 'VAT');
              b.element('ram:CategoryCode', nest: vatCategory);
              b.element('ram:RateApplicablePercent', nest: vatPercent);
            });
            b.element('ram:SpecifiedTradeSettlementLineMonetarySummation', nest: () {
              b.element('ram:LineTotalAmount', nest: _amount(line.totalNetCents));
            });
          });
        });
      }

      b.element('ram:ApplicableHeaderTradeAgreement', nest: () {
        b.element('ram:SellerTradeParty', nest: () {
          // EN 16931 rule BR-CO-26: the buyer must be able to identify the seller by an identifier or a
          // VAT id. A craftsman without USt-IdNr is identified by the tax number (seller identifier).
          if (c.vatId.trim().isEmpty) b.element('ram:ID', nest: c.taxNumber.trim());
          b.element('ram:Name', nest: c.name);
          if (c.ownerName.isNotEmpty || c.phone.isNotEmpty || c.email.isNotEmpty) {
            b.element('ram:DefinedTradeContact', nest: () {
              if (c.ownerName.isNotEmpty) b.element('ram:PersonName', nest: c.ownerName);
              if (c.phone.isNotEmpty) {
                b.element('ram:TelephoneUniversalCommunication', nest: () {
                  b.element('ram:CompleteNumber', nest: c.phone);
                });
              }
              if (c.email.isNotEmpty) {
                b.element('ram:EmailURIUniversalCommunication', nest: () {
                  b.element('ram:URIID', nest: c.email);
                });
              }
            });
          }
          b.element('ram:PostalTradeAddress', nest: () {
            b.element('ram:PostcodeCode', nest: c.zip);
            b.element('ram:LineOne', nest: c.street);
            b.element('ram:CityName', nest: c.city);
            b.element('ram:CountryID', nest: 'DE');
          });
          if (c.email.isNotEmpty) {
            b.element('ram:URIUniversalCommunication', nest: () {
              b.element('ram:URIID', attributes: {'schemeID': 'EM'}, nest: c.email);
            });
          }
          if (c.vatId.trim().isNotEmpty) {
            b.element('ram:SpecifiedTaxRegistration', nest: () {
              b.element('ram:ID', attributes: {'schemeID': 'VA'}, nest: c.vatId.trim());
            });
          }
          if (c.taxNumber.trim().isNotEmpty) {
            b.element('ram:SpecifiedTaxRegistration', nest: () {
              b.element('ram:ID', attributes: {'schemeID': 'FC'}, nest: c.taxNumber.trim());
            });
          }
        });
        b.element('ram:BuyerTradeParty', nest: () {
          b.element('ram:Name', nest: d.recipientName);
          b.element('ram:PostalTradeAddress', nest: () {
            b.element('ram:PostcodeCode', nest: buyer.zip!);
            b.element('ram:LineOne', nest: buyer.street!);
            b.element('ram:CityName', nest: buyer.city!);
            b.element('ram:CountryID', nest: 'DE');
          });
          if ((buyerEmail ?? '').trim().isNotEmpty) {
            b.element('ram:URIUniversalCommunication', nest: () {
              b.element('ram:URIID', attributes: {'schemeID': 'EM'}, nest: buyerEmail!.trim());
            });
          }
        });
      });

      final period = _period(d.deliveryPeriod);
      b.element('ram:ApplicableHeaderTradeDelivery', nest: () {
        b.element('ram:ActualDeliverySupplyChainEvent', nest: () {
          b.element('ram:OccurrenceDateTime', nest: () {
            b.element('udt:DateTimeString', attributes: {'format': '102'}, nest: _date(period?.last ?? issue));
          });
        });
      });

      b.element('ram:ApplicableHeaderTradeSettlement', nest: () {
        b.element('ram:PaymentReference', nest: number);
        b.element('ram:InvoiceCurrencyCode', nest: 'EUR');
        b.element('ram:SpecifiedTradeSettlementPaymentMeans', nest: () {
          b.element('ram:TypeCode', nest: '58'); // SEPA credit transfer
          b.element('ram:PayeePartyCreditorFinancialAccount', nest: () {
            b.element('ram:IBANID', nest: c.iban.replaceAll(' ', ''));
          });
          if (c.bic.trim().isNotEmpty) {
            b.element('ram:PayeeSpecifiedCreditorFinancialInstitution', nest: () {
              b.element('ram:BICID', nest: c.bic.replaceAll(' ', ''));
            });
          }
        });
        b.element('ram:ApplicableTradeTax', nest: () {
          b.element('ram:CalculatedAmount', nest: _amount(d.vatCents));
          b.element('ram:TypeCode', nest: 'VAT');
          if (exempt) b.element('ram:ExemptionReason', nest: 'Gemäß § 19 UStG wird keine Umsatzsteuer berechnet.');
          b.element('ram:BasisAmount', nest: _amount(d.netCents));
          b.element('ram:CategoryCode', nest: vatCategory);
          b.element('ram:RateApplicablePercent', nest: vatPercent);
        });
        if (period != null && period.length == 2) {
          b.element('ram:BillingSpecifiedPeriod', nest: () {
            b.element('ram:StartDateTime', nest: () {
              b.element('udt:DateTimeString', attributes: {'format': '102'}, nest: _date(period.first));
            });
            b.element('ram:EndDateTime', nest: () {
              b.element('udt:DateTimeString', attributes: {'format': '102'}, nest: _date(period.last));
            });
          });
        }
        if (!isCredit && d.dueDate != null) {
          b.element('ram:SpecifiedTradePaymentTerms', nest: () {
            b.element('ram:Description', nest: 'Zahlbar bis zum ${_germanDate(d.dueDate!)} ohne Abzug.');
            b.element('ram:DueDateDateTime', nest: () {
              b.element('udt:DateTimeString', attributes: {'format': '102'}, nest: _date(d.dueDate!));
            });
          });
        }
        b.element('ram:SpecifiedTradeSettlementHeaderMonetarySummation', nest: () {
          b.element('ram:LineTotalAmount', nest: _amount(d.netCents));
          b.element('ram:TaxBasisTotalAmount', nest: _amount(d.netCents));
          b.element('ram:TaxTotalAmount', attributes: {'currencyID': 'EUR'}, nest: _amount(d.vatCents));
          b.element('ram:GrandTotalAmount', nest: _amount(d.grossCents));
          b.element('ram:DuePayableAmount', nest: _amount(d.grossCents));
        });
        final cancelled = isCredit ? _cancelledInvoice(d.title) : null;
        if (cancelled != null) {
          b.element('ram:InvoiceReferencedDocument', nest: () {
            b.element('ram:IssuerAssignedID', nest: cancelled.number);
            b.element('ram:FormattedIssueDateTime', nest: () {
              b.element('qdt:DateTimeString', attributes: {'format': '102'}, nest: _date(cancelled.date));
            });
          });
        }
      });
    });
  });
  return b.buildDocument().toXmlString(pretty: true);
}

String _germanDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

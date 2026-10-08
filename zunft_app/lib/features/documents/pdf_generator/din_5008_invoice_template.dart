import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../domain/document_data.dart';

/// Generates the DIN 5008 style PDF for a quote or invoice.
///
/// Uses an embedded Unicode font (Lato, SIL Open Font License, see assets/fonts/OFL.txt) so
/// umlauts, ß, € and § print correctly. The PDF's built-in Helvetica cannot draw them.
class Din5008PdfGenerator {
  static pw.ThemeData? _theme;

  /// Loads the fonts once (they are cached). Call at start-up so the first PDF is not slower, and
  /// from tests before the simulated clock starts.
  static Future<void> preloadFonts() => _loadTheme();

  static Future<pw.ThemeData> _loadTheme() async {
    if (_theme != null) return _theme!;
    Future<pw.Font> font(String file) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$file'));
    final bold = await font('Lato-Bold.ttf');
    return _theme = pw.ThemeData.withFont(
      base: await font('Lato-Regular.ttf'),
      bold: bold,
      italic: await font('Lato-Italic.ttf'),
      boldItalic: bold, // no bold-italic file shipped; bold is the closest
    );
  }

  static Future<Uint8List> generate(PdfDocumentData data) async {
    final theme = await _loadTheme();
    final company = data.company;
    final docTitle = data.isCancellation ? 'Stornorechnung' : (data.isInvoice ? 'Rechnung' : 'Angebot');
    final numberLabel = data.isCancellation ? 'Storno-Nr.' : (data.isInvoice ? 'Rechnungs-Nr.' : 'Angebots-Nr.');

    final pdf = pw.Document(
      title: data.isPreview ? '$docTitle (Entwurf)' : '$docTitle ${data.docNumber}',
      author: company.name,
    );

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          theme: theme,
          margin: const pw.EdgeInsets.fromLTRB(
              25 * PdfPageFormat.mm, 20 * PdfPageFormat.mm, 20 * PdfPageFormat.mm, 18 * PdfPageFormat.mm),
        ),
        footer: (context) => _footer(data, context),
        build: (context) => [
          // 1. Sender line, recipient block, and the info box (DIN 5008 window layout)
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                flex: 5,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${company.name} · ${company.addressLine}',
                      style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(data.recipientName, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    for (final line in _addressLines(data.recipientAddress))
                      pw.Text(line, style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                flex: 4,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      company.name,
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
                    ),
                    if (company.ownerName.isNotEmpty)
                      pw.Text('Inh. ${company.ownerName}',
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.SizedBox(height: 10),
                    _metaRow('Datum:', DateFormatter.formatDate(data.issueDate)),
                    _metaRow('$numberLabel:', data.docNumber ?? 'wird vergeben'),
                    if (data.isInvoice || data.isCancellation)
                      _metaRow('Leistungszeitraum:', data.deliveryPeriod ?? DateFormatter.formatDate(data.issueDate)),
                    if (company.taxNumber.isNotEmpty) _metaRow('Steuernummer:', company.taxNumber),
                    if (company.vatId.isNotEmpty) _metaRow('USt-IdNr.:', company.vatId),
                    if (company.phone.isNotEmpty) _metaRow('Tel.:', company.phone),
                    if (company.email.isNotEmpty) _metaRow('E-Mail:', company.email),
                  ],
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 24),

          // 2. Title and introduction
          pw.Text(
            data.isPreview ? '$docTitle (Entwurf)' : '$docTitle Nr. ${data.docNumber}',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
          ),
          if (data.isPreview)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text(
                'Vorschau - noch keine Nummer vergeben, nicht gültig.',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.red800),
              ),
            ),
          if ((data.title ?? '').isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                data.title!,
                style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic, color: PdfColors.grey800),
              ),
            ),
          pw.SizedBox(height: 10),
          pw.Text(
            data.isCancellation
                ? 'Sehr geehrte Damen und Herren, wir stornieren die oben genannte Rechnung. Die Beträge werden mit umgekehrtem Vorzeichen gutgeschrieben. Die Rechnung ist damit gegenstandslos.'
                : data.isInvoice
                ? 'Sehr geehrte Damen und Herren, für die ausgeführten Arbeiten stellen wir Ihnen folgende Leistungen in Rechnung:'
                : 'Sehr geehrte Damen und Herren, gerne unterbreiten wir Ihnen für die angefragten Arbeiten folgendes Angebot:',
            style: const pw.TextStyle(fontSize: 9.5),
          ),

          pw.SizedBox(height: 14),

          // 3. Positions
          pw.Table(
            border: const pw.TableBorder(
              bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
              horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(0.7),
              1: pw.FlexColumnWidth(4.6),
              2: pw.FlexColumnWidth(1.1),
              3: pw.FlexColumnWidth(1.1),
              4: pw.FlexColumnWidth(1.8),
              5: pw.FlexColumnWidth(2.0),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  _th('Pos.'),
                  _th('Bezeichnung'),
                  _th('Menge', align: pw.TextAlign.right),
                  _th('Einheit'),
                  _th('Einzelpreis', align: pw.TextAlign.right),
                  _th('Gesamt', align: pw.TextAlign.right),
                ],
              ),
              for (final (index, item) in data.lines.indexed)
                pw.TableRow(
                  children: [
                    _td('${index + 1}.'),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(item.description, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                          pw.Text(_typeLabel(item), style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                        ],
                      ),
                    ),
                    _td(_quantity(item.quantity), align: pw.TextAlign.right),
                    _td(item.unit),
                    _td(CurrencyFormatter.formatCents(item.unitPriceNetCents), align: pw.TextAlign.right),
                    _td(CurrencyFormatter.formatCents(item.totalNetCents), align: pw.TextAlign.right),
                  ],
                ),
            ],
          ),

          pw.SizedBox(height: 14),

          // 4. Totals
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.SizedBox(
                width: 230,
                child: pw.Column(
                  children: [
                    _totalRow('Nettobetrag:', CurrencyFormatter.formatCents(data.netCents)),
                    if (!data.isSmallBusiness)
                      _totalRow('zzgl. ${_rate(data.vatRate)} % MwSt.:', CurrencyFormatter.formatCents(data.vatCents)),
                    pw.Divider(color: PdfColors.grey800, thickness: 1),
                    _totalRow('Gesamtbetrag:', CurrencyFormatter.formatCents(data.grossCents),
                        isBold: true, fontSize: 11),
                  ],
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 12),

          if (data.isSmallBusiness) _note('Gemäß § 19 UStG wird keine Umsatzsteuer berechnet.'),

          // 5. § 35a EStG note for private customers (invoices only)
          if (data.isInvoice && !data.isCancellation)
            _note(
              'Steuerlicher Hinweis für private Auftraggeber (§ 35a Abs. 3 EStG): '
              'In dem Gesamtbetrag sind Arbeitskosten für Handwerkerleistungen in Höhe von '
              '${CurrencyFormatter.formatCents(data.laborGrossCents)} (brutto${data.isSmallBusiness ? '' : ', inkl. MwSt.'}) enthalten, '
              'davon ${CurrencyFormatter.formatCents(data.laborNetCents)} netto. '
              'Materialkosten (${CurrencyFormatter.formatCents(data.materialNetCents)} netto) sind nicht begünstigt. '
              'Bitte bewahren Sie diese Rechnung und den Zahlungsbeleg (Überweisung) für Ihre Einkommensteuererklärung auf.',
            ),

          pw.SizedBox(height: 10),
          pw.Text(
            data.isCancellation
                ? 'Bereits gezahlte Beträge werden Ihnen erstattet beziehungsweise mit offenen Forderungen verrechnet.'
                : data.isInvoice
                ? (data.dueDate == null
                    ? 'Bitte überweisen Sie den Betrag ohne Abzug.'
                    : 'Zahlbar bis zum ${DateFormatter.formatDate(data.dueDate!)} ohne Abzug.')
                : (data.dueDate == null
                    ? 'Dieses Angebot ist freibleibend.'
                    : 'Dieses Angebot ist gültig bis zum ${DateFormatter.formatDate(data.dueDate!)}.'),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ---- helpers -------------------------------------------------------------------------

  static List<String> _addressLines(String? address) =>
      (address ?? '').split(RegExp(r'\s*,\s*|\n')).where((l) => l.trim().isNotEmpty).toList();

  static String _typeLabel(DocumentLine item) => switch (item.type) {
        'labor' => 'Arbeitsleistung (Handwerkerleistung § 35a EStG)',
        'flat_fee' => 'Pauschale (Handwerkerleistung § 35a EStG)',
        _ => 'Material',
      };

  /// 2 -> "2", 1.5 -> "1,5", 0.25 -> "0,25"
  static String _quantity(double q) {
    if (q == q.roundToDouble()) return q.toStringAsFixed(0);
    return q.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceAll('.', ',');
  }

  static String _rate(double r) => (r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString()).replaceAll('.', ',');

  static pw.Widget _footer(PdfDocumentData data, pw.Context context) {
    final c = data.company;
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey400, thickness: 0.5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Seite ${context.pageNumber} von ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
            if (c.iban.isNotEmpty)
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (c.bankName.isNotEmpty) pw.Text('Bank: ${c.bankName}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('IBAN: ${c.iban}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  if (c.bic.isNotEmpty) pw.Text('BIC: ${c.bic}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _note(String text) => pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 6),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        ),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
      );

  static pw.Widget _metaRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text('$label ', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text(value, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  static pw.Widget _totalRow(String label, String value, {bool isBold = false, double fontSize = 9}) {
    final style = pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(label, style: style), pw.Text(value, style: style)],
      ),
    );
  }

  static pw.Widget _th(String text, {pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
        ),
      );

  static pw.Widget _td(String text, {pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: pw.Text(text, textAlign: align, style: const pw.TextStyle(fontSize: 8.5)),
      );
}

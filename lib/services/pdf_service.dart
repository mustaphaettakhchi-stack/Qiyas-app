import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format.dart';
import '../domain/calculations.dart';
import '../domain/models.dart';

/// Génération du devis PDF A4 (écran E10), entièrement hors connexion.
/// Les polices intégrées (Helvetica) couvrent les accents français ; on évite
/// les caractères hors Latin-1 (tirets longs, espaces fines).
class PdfService {
  static String _safe(String s) => s
      .replaceAll('−', '-')
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('’', "'")
      .replaceAll(' ', ' ')
      .replaceAll(' ', ' ')
      .replaceAll('…', '...');

  static Future<Uint8List> build({required Company company, required Project project, required Quote quote}) async {
    final doc = pw.Document(title: quote.number, author: company.name);
    final totals = quoteTotals(project, quote, company.vatPercent);
    final m = projectMeasures(project);

    pw.ImageProvider? logo;
    if (company.logoPath != null) {
      final f = File(company.logoPath!);
      if (await f.exists()) logo = pw.MemoryImage(await f.readAsBytes());
    }

    pw.Widget txt(String s, {double size = 9, bool bold = false, PdfColor? color}) => pw.Text(
          _safe(s),
          style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color),
        );

    pw.Widget totalRow(String label, String value, {bool strong = false}) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          decoration: strong ? const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 1.2))) : null,
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            txt(label, bold: strong, size: strong ? 11 : 9),
            txt(value, bold: strong, size: strong ? 11 : 9),
          ]),
        );

    final grey = PdfColor.fromInt(0xFF5B6476);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if (logo != null) pw.Container(width: 56, height: 56, margin: const pw.EdgeInsets.only(right: 10), child: pw.Image(logo)),
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                txt(company.name, size: 14, bold: true),
                txt('${company.address}, ${company.city} - ${company.phone}'),
                txt('ICE ${company.ice} - IF ${company.ifNumber} - RC ${company.rc} - Patente ${company.patente}', color: grey),
              ]),
            ),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              txt('DEVIS', size: 16, bold: true),
              txt(quote.number, bold: true),
              txt(frDate(quote.date)),
            ]),
          ]),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              txt('Client : ${project.client} - ${project.phone}'),
              txt('Chantier : ${project.address}, ${project.city}'),
            ]),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Désignation', 'Qté', 'Unité', 'P.U. HT', 'Total HT'],
            data: [
              for (final l in quote.lines)
                [
                  _safe(l.description.isEmpty ? l.label : '${l.label}\n${l.description}'),
                  fmt2(lineQuantity(project, l, measures: m)),
                  _safe(l.unit),
                  _safe(dh(l.unitPriceCents)),
                  _safe(dh(lineTotalCents(project, l, measures: m))),
                ],
            ],
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.center,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1.6),
              4: const pw.FlexColumnWidth(1.8),
            },
          ),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 230,
              child: pw.Column(children: [
                if (totals.discount > 0) ...[
                  totalRow('Sous-total HT', _safe(dh(totals.subtotal))),
                  totalRow('Remise ${fmt2(quote.discountPercent)} %', _safe('- ${dh(totals.discount)}')),
                ],
                totalRow('Total HT', _safe(dh(totals.ht))),
                totalRow('TVA ${fmt2(company.vatPercent)} %', _safe(dh(totals.vat))),
                totalRow('Total TTC', _safe(dh(totals.ttc)), strong: true),
                totalRow('Acompte demandé (${fmt2(quote.depositPercent)} %)', _safe(dh(totals.deposit))),
              ]),
            ),
          ),
          pw.SizedBox(height: 14),
          txt('Annexe - métré', bold: true),
          txt('Sol ${fmt2(m.floor)} m² - plafond ${fmt2(m.ceiling)} m² - murs nets ${fmt2(m.walls)} m² - '
              'plinthes ${fmt2(m.skirting)} ml - ${project.rooms.length} pièce(s)'),
          for (final r in project.rooms)
            txt('${r.name} : ${fmt2(r.length)} x ${fmt2(r.width)} x ${fmt2(r.height)} m, '
                '${r.doorCount} porte(s), ${r.windowCount} fenêtre(s)', color: grey),
          pw.SizedBox(height: 18),
          txt('Devis valable ${company.validityDays} jours. ${company.footer}', color: grey),
          pw.SizedBox(height: 24),
          txt('Bon pour accord, date et signature du client :'),
        ],
      ),
    );
    return doc.save();
  }
}

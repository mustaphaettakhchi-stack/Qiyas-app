import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format.dart';
import '../domain/calculations.dart';
import '../domain/models.dart';

/// Polices embarquées (Noto, licence SIL OFL 1.1) : latin complet et arabe.
class PdfFonts {
  PdfFonts(this.regular, this.bold, this.arabic, this.arabicBold);
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font arabic;
  final pw.Font arabicBold;

  static PdfFonts? _cache;

  static Future<PdfFonts> load() async {
    Future<pw.Font> f(String name) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$name'));
    return _cache ??= PdfFonts(
      await f('NotoSans-Regular.ttf'),
      await f('NotoSans-Bold.ttf'),
      await f('NotoSansArabic-Regular.ttf'),
      await f('NotoSansArabic-Bold.ttf'),
    );
  }
}

final _arabic = RegExp(r'[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]');

/// Génération du devis PDF A4, entièrement hors connexion.
///
/// Le PDF client ne montre ni déboursés, ni frais, ni marge (USER_FLOWS A6.5) et ne
/// prétend à aucune signature électronique (A6.6). Un brouillon porte un filigrane.
class PdfService {
  static Future<Uint8List> build({
    required Company company,
    required Project project,
    required Quote quote,
    Client? client,
  }) async {
    final fonts = await PdfFonts.load();
    final doc = pw.Document(title: quote.displayNumber, author: company.name);
    final m = projectMeasures(project);
    final totals = quoteTotals(project, quote);
    final cur = quote.currency;
    String money2(int cents) => money(cents, cur);

    pw.ImageProvider logo;
    final custom = company.logoPath == null ? null : File(company.logoPath!);
    if (custom != null && await custom.exists()) {
      logo = pw.MemoryImage(await custom.readAsBytes());
    } else {
      logo = pw.MemoryImage((await rootBundle.load('assets/branding/logo_lamaalam_corrige_512.png')).buffer.asUint8List());
    }

    final grey = PdfColor.fromInt(0xFF5B6476);
    final orange = PdfColor.fromInt(0xFFF28C00);

    /// Texte : un passage en arabe est composé de droite à gauche avec la police arabe.
    pw.Widget txt(String s, {double size = 9, bool bold = false, PdfColor? color, pw.TextAlign? align}) {
      final rtl = _arabic.hasMatch(s);
      return pw.Text(
        s,
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        textAlign: align,
        style: pw.TextStyle(
          font: rtl ? (bold ? fonts.arabicBold : fonts.arabic) : (bold ? fonts.bold : fonts.regular),
          fontFallback: [bold ? fonts.arabicBold : fonts.arabic],
          fontSize: size,
          color: color,
        ),
      );
    }

    pw.Widget labelled(String label, String value) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [txt('$label : ', color: grey), pw.Flexible(child: txt(value))],
        );

    pw.Widget totalRow(String label, String value, {bool strong = false}) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          decoration: strong ? const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 1.2))) : null,
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            txt(label, bold: strong, size: strong ? 11 : 9),
            txt(value, bold: strong, size: strong ? 11 : 9),
          ]),
        );

    final legal = [
      if (company.ice.isNotEmpty) 'ICE ${company.ice}',
      if (company.ifNumber.isNotEmpty) 'IF ${company.ifNumber}',
      if (company.rc.isNotEmpty) 'RC ${company.rc}',
      if (company.patente.isNotEmpty) 'Patente ${company.patente}',
    ].join(' · ');
    final draft = quote.status == QuoteStatus.draft;
    final validUntil = quote.date.add(Duration(days: quote.validityDays));

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold, fontFallback: [fonts.arabic]),
          buildForeground: draft
              ? (ctx) => pw.Center(
                    child: pw.Transform.rotate(
                      angle: 0.6,
                      child: pw.Opacity(
                        opacity: 0.12,
                        child: pw.Text('BROUILLON - NON VALABLE',
                            style: pw.TextStyle(font: fonts.bold, fontSize: 48, color: PdfColors.red)),
                      ),
                    ),
                  )
              : null,
        ),
        footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          txt(legal, size: 7, color: grey),
          txt('Page ${ctx.pageNumber} / ${ctx.pagesCount}', size: 7, color: grey),
        ]),
        build: (ctx) => [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 70, height: 70, child: pw.Image(logo)),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                txt(company.name.isEmpty ? 'Group LAMAALAM' : company.name, size: 13, bold: true),
                txt([company.address, company.city].where((x) => x.isNotEmpty).join(', ')),
                if (company.phone.isNotEmpty) txt('Tél. ${company.phone}'),
              ]),
            ),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              txt('DEVIS', size: 16, bold: true, color: orange),
              txt(draft ? 'Brouillon (version ${quote.versionNo})' : 'N° ${quote.displayNumber}', bold: true),
              txt('Date : ${frDate(quote.date)}'),
              txt('Valable jusqu\'au ${frDate(validUntil)}'),
            ]),
          ]),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: grey, width: 0.5)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              labelled('Client', client?.displayName ?? ''),
              if ((client?.phone ?? '').isNotEmpty) labelled('Téléphone', client!.phone),
              if ((client?.ice ?? '').isNotEmpty) labelled('ICE du client', client!.ice),
              labelled('Chantier', [project.address, project.city].where((x) => x.isNotEmpty).join(', ')),
              if (project.reference != null) labelled('Projet', project.reference!),
              if (quote.title.isNotEmpty) labelled('Objet', quote.title),
            ]),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Désignation', 'Quantité', 'Prix unitaire HT', 'TVA', 'Total HT'],
            headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8.5),
            cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8.5, fontFallback: [fonts.arabic]),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(1.6),
              2: const pw.FlexColumnWidth(1.8),
              3: const pw.FlexColumnWidth(0.8),
              4: const pw.FlexColumnWidth(1.8),
            },
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            data: [
              for (final l in quote.lines)
                [
                  [l.label, if (l.description.isNotEmpty) l.description].join('\n'),
                  '${fmt2(lineQuantity(project, l, measures: m))} ${l.unit}',
                  lineUnitPriceCents(quote, l) == null ? 'à renseigner' : money2(lineUnitPriceCents(quote, l)!),
                  pctBp(l.vatRateBp),
                  money2(lineTotalCents(project, quote, l, measures: m)),
                ],
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 250,
              child: pw.Column(children: [
                if (totals.discount > 0) ...[
                  totalRow('Sous-total HT', money2(totals.subtotal)),
                  totalRow('Remise ${pctBp(quote.discountBp)}', '- ${money2(totals.discount)}'),
                ],
                totalRow('Total HT', money2(totals.ht)),
                for (final e in (totals.vatByRate.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                  totalRow('TVA ${pctBp(e.key)}', money2(e.value)),
                totalRow('Total TTC', money2(totals.ttc), strong: true),
                if (quote.depositBp > 0) totalRow('Acompte à la commande (${pctBp(quote.depositBp)})', money2(totals.deposit)),
              ]),
            ),
          ),
          if (cur == 'EUR' && quote.exchangeRateE4 != null) ...[
            pw.SizedBox(height: 6),
            txt('Montants en euros. Taux de change appliqué : 1 € = ${rateE4(quote.exchangeRateE4!)} MAD '
                '(${quote.exchangeRateDate == null ? 'date non précisée' : 'au ${frDate(quote.exchangeRateDate!)}'}'
                '${quote.exchangeRateSource.isEmpty ? '' : ', source : ${quote.exchangeRateSource}'}).', size: 8, color: grey),
          ],
          pw.SizedBox(height: 14),
          txt('Annexe - métré', bold: true),
          txt('Sol ${fmt2(m.floor)} m² - plafond ${fmt2(m.ceiling)} m² - murs nets ${fmt2(m.walls)} m² - '
              'plinthes ${fmt2(m.skirting)} m - ${project.rooms.length} pièce(s)', color: grey),
          for (final r in project.rooms)
            txt('${r.name} : sol ${fmt2(roomMeasures(r).floor)} m², périmètre ${fmt2(roomMeasures(r).perimeter)} m, '
                'hauteur ${fmt2(r.height)} m, ${r.doorCount} porte(s), ${r.windowCount} fenêtre(s)', color: grey, size: 8),
          pw.SizedBox(height: 14),
          txt('Devis valable ${quote.validityDays} jours. ${company.footer}', color: grey),
          pw.SizedBox(height: 22),
          pw.Container(
            width: 260,
            height: 70,
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: grey, width: 0.5)),
            child: txt('Bon pour accord - date et signature manuscrite du client :', size: 8),
          ),
        ],
      ),
    );
    return doc.save();
  }
}

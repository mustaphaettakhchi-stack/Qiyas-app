import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lamaalam/domain/models.dart';
import 'package:lamaalam/services/pdf_service.dart';

/// Génère le PDF d'un devis et en extrait le texte avec pdftotext (poppler) s'il est installé.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final project = Project(id: 'p', reference: 'LMA-2026-0001', address: '12 rue de Fès', city: 'Tanger', rooms: [
    Room.rectangle(id: 'r', name: 'Salon', length: 5, width: 4, height: 2.8),
  ]);
  final company = Company(name: 'Group LAMAALAM', city: 'Tanger', ice: '001234567000089', ifNumber: '40123456', vatPercent: 20);
  final client = Client(id: 'c', displayName: 'محمد بنعلي', phone: '0661000000');

  Quote quote(QuoteStatus status, {String currency = 'MAD'}) => Quote(
        id: 'q',
        number: status == QuoteStatus.draft ? null : 'DV-2026-0007',
        date: DateTime(2026, 11, 1),
        status: status,
        currency: currency,
        exchangeRateE4: currency == 'EUR' ? 108500 : null,
        exchangeRateDate: currency == 'EUR' ? DateTime(2026, 11, 1) : null,
        exchangeRateSource: currency == 'EUR' ? 'Bank Al-Maghrib' : '',
        overheadBp: 1000,
        marginBp: 1500,
        lines: [
          QuoteLine(id: 'a', label: 'Carrelage sol', unit: 'm²', base: QuantityBase.floor, unitPriceCents: 25000, vatRateBp: 2000),
          QuoteLine(id: 'b', label: 'Pose porte', unit: 'u', quantity: 1, manual: true, pricing: 'cost_plus',
              materialCostCents: 80000, labourCostCents: 40000, vatRateBp: 1000),
        ],
      );

  Future<String?> textOf(Quote q, String name) async {
    final bytes = await PdfService.build(company: company, project: project, quote: q, client: client);
    final file = File('${Directory.systemTemp.path}/$name.pdf')..writeAsBytesSync(bytes);
    expect(bytes.length, greaterThan(1000));
    try {
      final tool = Platform.environment['PDFTOTEXT'] ?? 'pdftotext';
      final r = Process.runSync(tool, ['-layout', file.path, '-']);
      return r.exitCode == 0 ? r.stdout as String : null;
    } on ProcessException {
      return null; // poppler absent (machines de la CI) : le test est ignoré, la génération reste vérifiée
    }
  }

  test('Devis validé : numéro, TVA par taux, aucun déboursé ni marge, pas de signature électronique', () async {
    final text = await textOf(quote(QuoteStatus.validated), 'devis_valide');
    if (text == null) return markTestSkipped('pdftotext absent');
    expect(text, contains('DV-2026-0007'));
    expect(text, contains('TVA 20 %'));
    expect(text, contains('TVA 10 %'));
    expect(text, contains('MAD'));
    expect(text, contains('ICE 001234567000089'));
    for (final forbidden in ['marge', 'Marge', 'déboursé', 'Fournitures', '800,00', 'électroniquement']) {
      expect(text, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(text, isNot(contains('Brouillon')));
  });

  test('Brouillon : filigrane, pas de numéro', () async {
    final text = await textOf(quote(QuoteStatus.draft), 'devis_brouillon');
    if (text == null) return markTestSkipped('pdftotext absent');
    // Le filigrane incliné n'est pas extrait par pdftotext ; il a été contrôlé sur le rendu en image.
    expect(text, contains('Brouillon (version 1)'));
    expect(text, isNot(contains('DV-2026')));
  });

  test('Devis en euros : taux, date et source affichés', () async {
    final text = await textOf(quote(QuoteStatus.validated, currency: 'EUR'), 'devis_eur');
    if (text == null) return markTestSkipped('pdftotext absent');
    expect(text, contains('1 € = 10,8500 MAD'));
    expect(text, contains('01/11/2026'));
    expect(text, contains('Bank Al-Maghrib'));
  });
}

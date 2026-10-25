import '../domain/calculations.dart';
import '../domain/models.dart';
import 'format.dart';

const Map<QuoteStatus, String> kStatusLabel = {
  QuoteStatus.draft: 'Brouillon',
  QuoteStatus.sent: 'Devis envoyé',
  QuoteStatus.accepted: 'Accepté',
  QuoteStatus.refused: 'Refusé',
};

const Map<QuantityBase, String> kBaseLabel = {
  QuantityBase.floor: 'Sol (m²)',
  QuantityBase.ceiling: 'Plafond (m²)',
  QuantityBase.walls: 'Murs nets (m²)',
  QuantityBase.skirting: 'Plinthes (ml)',
  QuantityBase.free: 'Saisie libre',
};

const List<String> kUnits = ['m²', 'ml', 'u', 'forfait'];

/// Message envoyé au client avec le devis (WhatsApp, e-mail).
String quoteMessage(Company c, Project p, Quote q) {
  final t = quoteTotals(p, q, c.vatPercent);
  return 'Bonjour ${p.client},\n'
      'Voici notre devis ${q.number} pour ${p.address}, ${p.city}.\n'
      'Total HT : ${dh(t.ht)} - TVA ${fmt2(c.vatPercent)} % : ${dh(t.vat)} - Total TTC : ${dh(t.ttc)}.\n'
      'Acompte demandé : ${dh(t.deposit)}. Devis valable ${c.validityDays} jours.\n'
      '${c.name} - ${c.phone}';
}

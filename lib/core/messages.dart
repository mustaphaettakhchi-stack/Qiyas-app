import '../domain/calculations.dart';
import '../domain/models.dart';
import 'format.dart';

const Map<QuoteStatus, String> kStatusLabel = {
  QuoteStatus.draft: 'Brouillon',
  QuoteStatus.validated: 'Validé',
  QuoteStatus.sent: 'Envoyé',
  QuoteStatus.accepted: 'Accepté',
  QuoteStatus.refused: 'Refusé',
  QuoteStatus.superseded: 'Remplacé',
};

const Map<QuantityBase, String> kBaseLabel = {
  QuantityBase.floor: 'Surface de sol (m²)',
  QuantityBase.ceiling: 'Surface de plafond (m²)',
  QuantityBase.walls: 'Murs nets d\'ouvertures (m²)',
  QuantityBase.wallsGross: 'Murs bruts (m²)',
  QuantityBase.skirting: 'Plinthes (m)',
  QuantityBase.perimeter: 'Périmètre (m)',
  QuantityBase.volume: 'Volume (m³)',
  QuantityBase.doors: 'Nombre de portes',
  QuantityBase.windows: 'Nombre de fenêtres',
  QuantityBase.count: 'Élément compté dans les pièces',
  QuantityBase.free: 'Quantité saisie',
};

const List<String> kUnits = ['m²', 'm', 'm³', 'kg', 'l', 'u', 'forfait'];

/// Message envoyé au client avec le devis (WhatsApp, e-mail).
String quoteMessage(Company c, Project p, Quote q, {Client? client}) {
  final t = quoteTotals(p, q);
  final name = client?.displayName.trim() ?? '';
  return '${name.isEmpty ? 'Bonjour' : 'Bonjour $name'},\n'
      'Voici notre devis ${q.displayNumber} pour ${[p.address, p.city].where((x) => x.isNotEmpty).join(', ')}.\n'
      'Total HT : ${money(t.ht, q.currency)} - TVA : ${money(t.vat, q.currency)} - Total TTC : ${money(t.ttc, q.currency)}.\n'
      '${q.depositBp > 0 ? 'Acompte demandé : ${money(t.deposit, q.currency)}. ' : ''}Devis valable ${q.validityDays} jours.\n'
      '${c.name} - ${c.phone}';
}

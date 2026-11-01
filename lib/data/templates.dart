// Modèles de prestations par métier. Aucun prix n'est proposé : l'utilisateur les saisit
// (règle « ne jamais inventer un prix » du cahier des charges LAMAALAM).

import '../domain/models.dart';

QuoteLine lineFrom(Prestation p, String id) => QuoteLine(
      id: id,
      prestationId: p.id,
      label: p.name,
      description: p.description,
      unit: p.unit,
      base: p.base,
      quantity: p.base == QuantityBase.free ? 1 : 0,
      unitPriceCents: p.unitPriceCents,
    );

/// Grilles modèles par métier (E8). Les prix sont à zéro : l'artisan les complète.
const Map<String, List<(String, String, String, QuantityBase)>> kPriceTemplates = {
  'Peinture': [
    ('Peinture murs', '2 couches', 'm²', QuantityBase.walls),
    ('Peinture plafond', '2 couches', 'm²', QuantityBase.ceiling),
    ('Enduit de rebouchage', '', 'm²', QuantityBase.walls),
  ],
  'Carrelage': [
    ('Carrelage sol', 'fourni et posé', 'm²', QuantityBase.floor),
    ('Plinthes', 'assorties', 'ml', QuantityBase.skirting),
    ('Faïence murale', '', 'm²', QuantityBase.free),
  ],
  'Plâtre et faux plafond': [
    ('Faux plafond BA13', 'sur ossature', 'm²', QuantityBase.ceiling),
    ('Corniche plâtre', '', 'ml', QuantityBase.skirting),
  ],
  'Plomberie simple': [
    ('Remplacement robinetterie', '', 'u', QuantityBase.free),
    ('Pose lavabo', '', 'u', QuantityBase.free),
  ],
  'Électricité simple': [
    ('Point lumineux', '', 'u', QuantityBase.free),
    ('Prise de courant', '', 'u', QuantityBase.free),
  ],
  'Rénovation générale': [
    ('Dépose et évacuation', '', 'm²', QuantityBase.floor),
    ('Nettoyage fin de chantier', '', 'forfait', QuantityBase.free),
  ],
};

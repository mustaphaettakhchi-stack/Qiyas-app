// Modèles d'ouvrages par métier. Aucun prix n'est proposé : l'administrateur les saisit
// (règle « ne jamais inventer un prix » du cahier des charges). Aucun taux de perte n'est
// appliqué d'office.

import '../domain/models.dart';

/// Ligne de devis créée depuis un ouvrage de la bibliothèque.
QuoteLine lineFrom(WorkItem w, String id) => QuoteLine(
      id: id,
      workItemId: w.id,
      label: w.name,
      description: w.description,
      unit: w.unitLabel,
      base: w.base,
      countKey: w.countKey,
      wasteRateBp: w.wasteRateBp,
      quantity: w.base == QuantityBase.free ? 1 : 0,
      unitPriceCents: w.salePriceCents ?? 0,
      priceMissing: w.salePriceCents == null,
    );

/// (désignation, description, unité, base, élément compté, catégorie)
typedef Template = (String, String, String, QuantityBase, String?, String);

const Map<String, List<Template>> kPriceTemplates = {
  'Peinture': [
    ('Peinture murs', '2 couches', 'm2', QuantityBase.walls, null, 'wall'),
    ('Peinture plafond', '2 couches', 'm2', QuantityBase.ceiling, null, 'ceiling'),
    ('Enduit de rebouchage', '', 'm2', QuantityBase.walls, null, 'wall'),
  ],
  'Carrelage': [
    ('Carrelage sol', 'fourni et posé', 'm2', QuantityBase.floor, null, 'floor'),
    ('Plinthes', 'assorties', 'm', QuantityBase.skirting, null, 'floor'),
    ('Faïence murale', '', 'm2', QuantityBase.free, null, 'wall'),
  ],
  'Plâtre et faux plafond': [
    ('Faux plafond BA13', 'sur ossature', 'm2', QuantityBase.ceiling, null, 'ceiling'),
    ('Corniche plâtre', '', 'm', QuantityBase.perimeter, null, 'ceiling'),
  ],
  'Plomberie simple': [
    ('Point d\'eau', 'alimentation et raccordement', 'u', QuantityBase.count, 'points_eau', 'plumbing'),
    ('Pose appareil sanitaire', '', 'u', QuantityBase.count, 'sanitaires', 'plumbing'),
  ],
  'Électricité simple': [
    ('Point lumineux', '', 'u', QuantityBase.count, 'points_lumineux', 'electricity'),
    ('Prise de courant', '', 'u', QuantityBase.count, 'prises', 'electricity'),
    ('Interrupteur', '', 'u', QuantityBase.count, 'interrupteurs', 'electricity'),
  ],
  'Menuiseries': [
    ('Pose de porte intérieure', '', 'u', QuantityBase.doors, null, 'joinery'),
    ('Pose de fenêtre', '', 'u', QuantityBase.windows, null, 'joinery'),
  ],
  'Maçonnerie': [
    ('Cloison', '', 'm2', QuantityBase.count, 'cloisons_m2', 'masonry'),
    ('Démolition', 'évacuation des gravats', 'm2', QuantityBase.count, 'demolition_m2', 'masonry'),
    ('Dépose revêtement de sol', '', 'm2', QuantityBase.floor, null, 'floor'),
    ('Nettoyage fin de chantier', '', 'forfait', QuantityBase.free, null, 'other'),
  ],
};

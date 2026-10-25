// Règles de calcul du métré et du devis (cahier des charges, section « Règles de calcul »).
// Fonctions pures, couvertes par test/calculations_test.dart.

import 'dart:math' as math;

import 'models.dart';

double round2(double v) => (v * 100).roundToDouble() / 100;

class Measures {
  const Measures({
    required this.perimeter,
    required this.floor,
    required this.ceiling,
    required this.walls,
    required this.skirting,
    required this.volume,
  });

  static const zero = Measures(perimeter: 0, floor: 0, ceiling: 0, walls: 0, skirting: 0, volume: 0);

  final double perimeter;
  final double floor;
  final double ceiling;
  final double walls;
  final double skirting;
  final double volume;

  double of(QuantityBase base) {
    switch (base) {
      case QuantityBase.floor:
        return floor;
      case QuantityBase.ceiling:
        return ceiling;
      case QuantityBase.walls:
        return walls;
      case QuantityBase.skirting:
        return skirting;
      case QuantityBase.free:
        return 0;
    }
  }

  Measures operator +(Measures o) => Measures(
        perimeter: perimeter + o.perimeter,
        floor: floor + o.floor,
        ceiling: ceiling + o.ceiling,
        walls: walls + o.walls,
        skirting: skirting + o.skirting,
        volume: volume + o.volume,
      );

  Measures rounded() => Measures(
        perimeter: round2(perimeter),
        floor: round2(floor),
        ceiling: round2(ceiling),
        walls: round2(walls),
        skirting: round2(skirting),
        volume: round2(volume),
      );
}

/// P = 2(L + l) ; sol = plafond = L × l ;
/// murs nets = max(0, P × h − surfaces des ouvertures) ;
/// plinthes = max(0, P − largeurs des portes) ; volume = L × l × h.
Measures roomMeasures(Room r) {
  final perimeter = 2 * (r.length + r.width);
  final floor = r.length * r.width;
  final openingsArea = r.openings.fold<double>(0, (s, o) => s + o.area);
  final doorsWidth = r.openings
      .where((o) => o.type == OpeningType.door)
      .fold<double>(0, (s, o) => s + o.width);
  return Measures(
    perimeter: perimeter,
    floor: floor,
    ceiling: floor,
    walls: math.max(0.0, perimeter * r.height - openingsArea),
    skirting: math.max(0.0, perimeter - doorsWidth),
    volume: floor * r.height,
  );
}

/// Totaux du projet, arrondis à 2 décimales (quantités affichées et facturées).
Measures projectMeasures(Project p) =>
    p.rooms.fold<Measures>(Measures.zero, (s, r) => s + roomMeasures(r)).rounded();

/// Quantité effective d'une ligne de devis.
double lineQuantity(Project p, QuoteLine l, {Measures? measures}) {
  if (l.frozenQuantity != null) return l.frozenQuantity!;
  if (l.manual || l.base == QuantityBase.free) return l.quantity;
  return (measures ?? projectMeasures(p)).of(l.base);
}

/// Total HT d'une ligne, en centimes. Les calculs se font en entiers.
int lineTotalCents(Project p, QuoteLine l, {Measures? measures}) {
  final qtyHundredths = (lineQuantity(p, l, measures: measures) * 100).round();
  return (qtyHundredths * l.unitPriceCents / 100).round();
}

class QuoteTotals {
  const QuoteTotals({
    required this.subtotal,
    required this.discount,
    required this.ht,
    required this.vat,
    required this.ttc,
    required this.deposit,
  });

  final int subtotal;
  final int discount;
  final int ht;
  final int vat;
  final int ttc;
  final int deposit;
}

QuoteTotals quoteTotals(Project p, Quote q, double vatPercent) {
  final m = projectMeasures(p);
  final subtotal = q.lines.fold<int>(0, (s, l) => s + lineTotalCents(p, l, measures: m));
  final discount = (subtotal * q.discountPercent / 100).round();
  final ht = subtotal - discount;
  final vat = (ht * vatPercent / 100).round();
  final ttc = ht + vat;
  final deposit = (ttc * q.depositPercent / 100).round();
  return QuoteTotals(subtotal: subtotal, discount: discount, ht: ht, vat: vat, ttc: ttc, deposit: deposit);
}

/// Alertes de saisie : cote hors de 0,5 à 15 m, hauteur hors de 2,0 à 4,5 m.
List<String> roomWarnings(Room r) {
  final out = <String>[];
  void check(String label, double v) {
    if (v < 0.5 || v > 15) {
      out.add('$label de ${v.toStringAsFixed(2).replaceAll('.', ',')} m : vérifiez la cote (attendu entre 0,50 et 15 m).');
    }
  }

  check('Longueur', r.length);
  check('Largeur', r.width);
  if (r.height < 2 || r.height > 4.5) {
    out.add('Hauteur de ${r.height.toStringAsFixed(2).replaceAll('.', ',')} m inhabituelle (attendu entre 2,00 et 4,50 m).');
  }
  return out;
}

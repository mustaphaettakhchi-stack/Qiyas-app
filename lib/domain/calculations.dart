// Règles de calcul du métré et du devis (cahier des charges, section « Règles de calcul »).
// Fonctions pures, couvertes par test/calculations_test.dart.

import 'dart:math' as math;

import 'geometry.dart';
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
    this.wallsGross = 0,
    this.openingsArea = 0,
    this.doors = 0,
    this.windows = 0,
    this.counts = const {},
  });

  static const zero = Measures(perimeter: 0, floor: 0, ceiling: 0, walls: 0, skirting: 0, volume: 0);

  final double perimeter;
  final double floor;
  final double ceiling;

  /// Murs nets d'ouvertures.
  final double walls;
  final double wallsGross;
  final double openingsArea;
  final double skirting;
  final double volume;
  final double doors;
  final double windows;

  /// Éléments comptés (clés de [kCountItems]).
  final Map<String, double> counts;

  double of(QuantityBase base, [String? countKey]) => switch (base) {
        QuantityBase.floor => floor,
        QuantityBase.ceiling => ceiling,
        QuantityBase.walls => walls,
        QuantityBase.wallsGross => wallsGross,
        QuantityBase.skirting => skirting,
        QuantityBase.perimeter => perimeter,
        QuantityBase.volume => volume,
        QuantityBase.doors => doors,
        QuantityBase.windows => windows,
        QuantityBase.count => counts[countKey] ?? 0,
        QuantityBase.free => 0,
      };

  Measures operator +(Measures o) => Measures(
        perimeter: perimeter + o.perimeter,
        floor: floor + o.floor,
        ceiling: ceiling + o.ceiling,
        walls: walls + o.walls,
        wallsGross: wallsGross + o.wallsGross,
        openingsArea: openingsArea + o.openingsArea,
        skirting: skirting + o.skirting,
        volume: volume + o.volume,
        doors: doors + o.doors,
        windows: windows + o.windows,
        counts: {
          for (final k in {...counts.keys, ...o.counts.keys}) k: (counts[k] ?? 0) + (o.counts[k] ?? 0),
        },
      );

  Measures rounded() => Measures(
        perimeter: round2(perimeter),
        floor: round2(floor),
        ceiling: round2(ceiling),
        walls: round2(walls),
        wallsGross: round2(wallsGross),
        openingsArea: round2(openingsArea),
        skirting: round2(skirting),
        volume: round2(volume),
        doors: doors,
        windows: windows,
        counts: {for (final e in counts.entries) e.key: round2(e.value)},
      );
}

/// Métré d'une pièce décrite mur par mur :
/// périmètre = Σ longueurs des murs ; sol = plafond = aire du contour (formule du lacet) ;
/// murs nets = Σ max(0, longueur × hauteur − ouvertures du mur) ;
/// plinthes = max(0, périmètre − largeurs des portes) ; volume = sol × hauteur.
/// Formules identiques côté serveur (backend/app/geometry.py), vérifiées sur shared/metre_cases.json.
Measures roomMeasures(Room r) {
  final perimeter = r.walls.fold<double>(0, (s, w) => s + w.length);
  final shape = outline([for (final w in r.walls) w.length], [for (final w in r.walls) w.angle]);
  var walls = 0.0;
  for (var i = 0; i < r.walls.length; i++) {
    final openingsArea = r.openings.where((o) => o.wallIndex == i).fold<double>(0, (s, o) => s + o.area);
    walls += math.max(0.0, r.walls[i].length * r.height - openingsArea);
  }
  final doorsWidth = r.openings
      .where((o) => o.type == OpeningType.door)
      .fold<double>(0, (s, o) => s + o.width);
  final openingsArea = r.openings.fold<double>(0, (s, o) => s + o.area);
  return Measures(
    perimeter: perimeter,
    floor: shape.area,
    ceiling: shape.area,
    walls: walls,
    wallsGross: perimeter * r.height,
    openingsArea: openingsArea,
    skirting: math.max(0.0, perimeter - doorsWidth),
    volume: shape.area * r.height,
    doors: r.doorCount.toDouble(),
    windows: r.windowCount.toDouble(),
    counts: Map.of(r.counts),
  );
}

/// Totaux du projet, arrondis à 2 décimales (quantités affichées et facturées).
Measures projectMeasures(Project p) =>
    p.rooms.fold<Measures>(Measures.zero, (s, r) => s + roomMeasures(r)).rounded();

/// Quantité nette d'une ligne issue du métré (avant perte), ou null si saisie à la main.
double? lineNetQuantity(Project p, QuoteLine l, {Measures? measures}) {
  if (l.manual || l.base == QuantityBase.free) return null;
  return (measures ?? projectMeasures(p)).of(l.base, l.countKey);
}

/// Quantité effective d'une ligne de devis :
/// figée si le devis est envoyé ; saisie si la ligne est manuelle ;
/// sinon quantité nette du métré × (1 + taux de perte), arrondie au centième.
double lineQuantity(Project p, QuoteLine l, {Measures? measures}) {
  if (l.frozenQuantity != null) return l.frozenQuantity!;
  final net = lineNetQuantity(p, l, measures: measures);
  if (net == null) return l.quantity;
  if (l.wasteRateBp == 0) return net;
  return round2(net * (1 + l.wasteRateBp / 10000));
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

/// Alertes de saisie. Les plages sont indicatives : elles avertissent sans bloquer.
List<String> roomWarnings(Room r) {
  String m(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
  final out = <String>[];
  if (r.walls.length < 3) {
    out.add('Une pièce doit avoir au moins 3 murs.');
    return out;
  }
  final shape = outline([for (final w in r.walls) w.length], [for (final w in r.walls) w.angle]);
  if (!shape.closes) {
    out.add('Les cotes ne se referment pas : il manque ${m(shape.closureError)} m pour revenir au point de départ. '
        'Vérifiez la longueur des murs et les angles.');
  }
  if (shape.angleSumError.abs() > 0.5) {
    out.add('La somme des angles devrait être ${((r.walls.length - 2) * 180).toString()}° '
        '(écart de ${shape.angleSumError.toStringAsFixed(1).replaceAll('.', ',')}°).');
  }
  if (shape.selfIntersecting) out.add('Des murs se croisent : vérifiez l\'ordre des murs et les angles.');
  for (var i = 0; i < r.walls.length; i++) {
    final l = r.walls[i].length;
    if (l < 0.3 || l > 30) out.add('Mur ${i + 1} : ${m(l)} m, vérifiez la cote (attendu entre 0,30 et 30 m).');
  }
  if (r.height < 1.8 || r.height > 6) {
    out.add('Hauteur de ${m(r.height)} m inhabituelle (attendu entre 1,80 et 6,00 m).');
  }
  for (final o in r.openings) {
    final label = o.type == OpeningType.door ? 'Porte' : 'Fenêtre';
    if (o.wallIndex < 0 || o.wallIndex >= r.walls.length) {
      out.add('$label rattachée à un mur qui n\'existe plus : choisissez son mur.');
    } else if (o.width > r.walls[o.wallIndex].length) {
      out.add('$label plus large que le mur ${o.wallIndex + 1}.');
    }
    if (o.height > r.height) out.add('$label plus haute que la pièce.');
  }
  return out;
}

/// La pièce peut-elle alimenter un métré validé ? (contour fermé, murs ne se croisant pas)
bool roomGeometryValid(Room r) {
  final shape = outline([for (final w in r.walls) w.length], [for (final w in r.walls) w.angle]);
  return shape.valid && r.openings.every((o) => o.wallIndex >= 0 && o.wallIndex < r.walls.length);
}

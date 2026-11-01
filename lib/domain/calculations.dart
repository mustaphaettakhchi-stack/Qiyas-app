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

// ---------- montants du devis ----------
// Mêmes règles que backend/app/quotes.py, vérifiées sur shared/quote_cases.json.
// Montants en centimes entiers ; arrondis au plus proche, la moitié vers le haut.

int _divHalfUp(int a, int b) => (a + b ~/ 2) ~/ b;

/// Prix calculé = (fournitures + main-d'œuvre) × (1 + frais indirects) × (1 + marge).
int costPlusPriceCents(int materialCents, int labourCents, int overheadBp, int marginBp) =>
    _divHalfUp((materialCents + labourCents) * (10000 + overheadBp) * (10000 + marginBp), 100000000);

/// Prix unitaire HT de la ligne, ou null s'il manque.
int? lineUnitPriceCents(Quote q, QuoteLine l) {
  if (l.pricing == 'cost_plus') {
    if (l.materialCostCents == null && l.labourCostCents == null) return null;
    return costPlusPriceCents(l.materialCostCents ?? 0, l.labourCostCents ?? 0, q.overheadBp, q.marginBp);
  }
  return l.priceMissing ? null : l.unitPriceCents;
}

/// Total HT d'une ligne = quantité (arrondie au centième) × prix unitaire, au centime.
int lineAmountCents(double quantity, int priceCents) => _divHalfUp((quantity * 100).round() * priceCents, 100);

int lineTotalCents(Project p, Quote q, QuoteLine l, {Measures? measures}) {
  final price = lineUnitPriceCents(q, l);
  return price == null ? 0 : lineAmountCents(lineQuantity(p, l, measures: measures), price);
}

class QuoteTotals {
  const QuoteTotals({
    required this.subtotal,
    required this.discount,
    required this.ht,
    required this.vatByRate,
    required this.ttc,
    required this.deposit,
  });

  final int subtotal;
  final int discount;
  final int ht;

  /// TVA par taux (points de base → montant).
  final Map<int, int> vatByRate;
  final int ttc;
  final int deposit;

  int get vat => vatByRate.values.fold<int>(0, (a, b) => a + b);

  /// Forme envoyée au serveur, qui la recalcule et refuse tout écart.
  Map<String, dynamic> toServer() => {
        'subtotal': subtotal,
        'discount': discount,
        'ht': ht,
        'vat': {for (final k in (vatByRate.keys.toList()..sort())) '$k': vatByRate[k]},
        'ttc': ttc,
        'deposit': deposit,
      };
}

/// Totaux à partir des quantités et prix de chaque ligne. La remise est répartie par taux de TVA.
QuoteTotals computeTotals(List<(double quantity, int? price, int vatBp)> lines, int discountBp, int depositBp) {
  final byRate = <int, int>{};
  var subtotal = 0;
  for (final (qty, price, vat) in lines) {
    final t = price == null ? 0 : lineAmountCents(qty, price);
    subtotal += t;
    byRate[vat] = (byRate[vat] ?? 0) + t;
  }
  var discount = 0;
  final vatByRate = <int, int>{};
  for (final e in byRate.entries) {
    final d = _divHalfUp(e.value * discountBp, 10000);
    discount += d;
    vatByRate[e.key] = _divHalfUp((e.value - d) * e.key, 10000);
  }
  final ht = subtotal - discount;
  final ttc = ht + vatByRate.values.fold<int>(0, (a, b) => a + b);
  return QuoteTotals(
    subtotal: subtotal,
    discount: discount,
    ht: ht,
    vatByRate: vatByRate,
    ttc: ttc,
    deposit: _divHalfUp(ttc * depositBp, 10000),
  );
}

QuoteTotals quoteTotals(Project p, Quote q) {
  final m = projectMeasures(p);
  return computeTotals(
    [for (final l in q.lines) (lineQuantity(p, l, measures: m), lineUnitPriceCents(q, l), l.vatRateBp)],
    q.discountBp,
    q.depositBp,
  );
}

/// Données d'une version de devis pour le serveur (quantités effectives et totaux inclus).
Map<String, dynamic> quoteToServer(Project p, Quote q) {
  final m = projectMeasures(p);
  return q.toServer(
    projectId: p.id,
    lineQuantities: [for (final l in q.lines) lineQuantity(p, l, measures: m)],
    totals: quoteTotals(p, q).toServer(),
  );
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

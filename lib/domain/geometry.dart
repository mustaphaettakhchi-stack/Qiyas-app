// Géométrie d'une pièce décrite mur par mur (docs/ARCHITECTURE.md §6).
//
// Convention : on parcourt les murs dans le sens inverse des aiguilles d'une montre,
// en partant de l'origine vers l'est. Pour chaque mur on donne sa longueur et l'angle
// intérieur au coin qui le termine (90° par défaut, 270° pour un angle rentrant).
// La même convention est implémentée côté serveur (backend/app/geometry.py) et vérifiée
// sur les cas partagés de shared/metre_cases.json.

import 'dart:math' as math;

/// Écart de fermeture toléré (m) : au-delà, les cotes sont incohérentes.
const double kClosureTolerance = 0.02;

class Pt {
  const Pt(this.x, this.y);
  final double x;
  final double y;

  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  double get length => math.sqrt(x * x + y * y);
}

class Outline {
  const Outline({
    required this.vertices,
    required this.closureError,
    required this.area,
    required this.angleSumError,
    required this.selfIntersecting,
  });

  /// Sommets p0…p(n-1) ; p0 = (0, 0). Le dernier mur relie p(n-1) à p0.
  final List<Pt> vertices;

  /// Distance entre le point d'arrivée du dernier mur et le point de départ (m).
  final double closureError;

  /// Aire du polygone (formule du lacet), en m².
  final double area;

  /// Écart entre la somme des angles saisis et (n − 2) × 180°.
  final double angleSumError;

  final bool selfIntersecting;

  bool get closes => closureError <= kClosureTolerance;
  bool get valid => closes && !selfIntersecting && vertices.length >= 3;
}

/// Calcule le contour à partir des longueurs et des angles intérieurs (degrés).
Outline outline(List<double> lengths, List<double> interiorAngles) {
  final n = lengths.length;
  if (n < 3) {
    return const Outline(vertices: [], closureError: double.infinity, area: 0, angleSumError: 0, selfIntersecting: false);
  }
  final pts = <Pt>[const Pt(0, 0)];
  var heading = 0.0;
  var p = const Pt(0, 0);
  for (var i = 0; i < n; i++) {
    p = p + Pt(lengths[i] * math.cos(heading), lengths[i] * math.sin(heading));
    pts.add(p);
    heading += math.pi - interiorAngles[i] * math.pi / 180;
  }
  final end = pts.removeLast();
  final closure = end.length;
  var twice = 0.0;
  for (var i = 0; i < n; i++) {
    final a = pts[i], b = pts[(i + 1) % n];
    twice += a.x * b.y - b.x * a.y;
  }
  final angleSum = interiorAngles.fold<double>(0, (s, a) => s + a);
  return Outline(
    vertices: pts,
    closureError: closure,
    area: twice.abs() / 2,
    angleSumError: angleSum - (n - 2) * 180,
    selfIntersecting: _selfIntersects(pts),
  );
}

bool _selfIntersects(List<Pt> pts) {
  final n = pts.length;
  double cross(Pt o, Pt a, Pt b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  bool segs(Pt a, Pt b, Pt c, Pt d) {
    final d1 = cross(c, d, a), d2 = cross(c, d, b), d3 = cross(a, b, c), d4 = cross(a, b, d);
    return ((d1 > 1e-9 && d2 < -1e-9) || (d1 < -1e-9 && d2 > 1e-9)) &&
        ((d3 > 1e-9 && d4 < -1e-9) || (d3 < -1e-9 && d4 > 1e-9));
  }

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (j == i + 1 || (i == 0 && j == n - 1)) continue; // murs voisins
      if (segs(pts[i], pts[(i + 1) % n], pts[j], pts[(j + 1) % n])) return true;
    }
  }
  return false;
}

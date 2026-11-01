import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../domain/calculations.dart';
import '../../domain/geometry.dart';
import '../../domain/models.dart';
import '../widgets/common.dart';


/// Contour d'une pièce dans le repère du plan (mètres, y vers le bas, origine au coin
/// haut-gauche de sa boîte englobante), et dimensions de cette boîte.
(List<Pt>, double, double) planShape(Room r) {
  final shape = outline([for (final w in r.walls) w.length], [for (final w in r.walls) w.angle]);
  if (shape.vertices.length < 3) return (const [], 0, 0);
  final xs = shape.vertices.map((p) => p.x), ys = shape.vertices.map((p) => p.y);
  final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
  final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
  return ([for (final v in shape.vertices) Pt(v.x - minX, maxY - v.y)], maxX - minX, maxY - minY);
}

/// E6 · Plan schématique coté : pièces juxtaposées à l'échelle, déplaçables au doigt.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.projectId});
  final String projectId;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  static const double _pad = 32;
  static const double _gap = 0.6;
  double _zoom = 1;
  Room? _dragging;

  double get _scale => 48 * _zoom;

  /// Place les pièces sans position, en rangées d'environ 9 m.
  static void autoLayout(Project p, {bool reset = false}) {
    if (reset) {
      for (final r in p.rooms) {
        r.planX = null;
        r.planY = null;
      }
    }
    final maxRow = math.max(9.0, p.rooms.fold<double>(0, (s, r) => math.max(s, planShape(r).$2)));
    double x = 0, y = 0, rowH = 0;
    for (final r in p.rooms) {
      if (r.planX != null && r.planY != null) continue;
      final (_, w, h) = planShape(r);
      if (x > 0 && x + w > maxRow) {
        x = 0;
        y += rowH + _gap;
        rowH = 0;
      }
      r.planX = x;
      r.planY = y;
      x += w + _gap;
      rowH = math.max(rowH, h);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = context.read<AppState>();
      final p = s.project(widget.projectId);
      if (p != null && p.rooms.any((r) => r.planX == null || r.planY == null)) {
        s.mutate(() => autoLayout(p));
      }
    });
  }

  Room? _hit(Project p, Offset pos) {
    for (final r in p.rooms.reversed) {
      final (pts, _, _) = planShape(r);
      if (pts.isEmpty) continue;
      final ox = _pad + (r.planX ?? 0.0) * _scale, oy = _pad + (r.planY ?? 0.0) * _scale;
      final path = Path()..addPolygon([for (final v in pts) Offset(ox + v.x * _scale, oy + v.y * _scale)], true);
      if (path.contains(pos)) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.project(widget.projectId);
    if (p == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Projet introuvable.')));
    final maxX = p.rooms.fold<double>(6, (m, r) => math.max(m, (r.planX ?? 0.0) + planShape(r).$2)) + 1;
    final maxY = p.rooms.fold<double>(4, (m, r) => math.max(m, (r.planY ?? 0.0) + planShape(r).$3)) + 1;
    final size = Size(maxX * _scale + _pad * 2, maxY * _scale + _pad * 2);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Plan'), actions: const [SyncBadge()]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Glissez une pièce pour la placer. Cotes en mètres.', style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            physics: _dragging == null ? null : const NeverScrollableScrollPhysics(),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: _dragging == null ? null : const NeverScrollableScrollPhysics(),
              child: GestureDetector(
                onPanStart: (d) => setState(() => _dragging = _hit(p, d.localPosition)),
                onPanUpdate: (d) {
                  final r = _dragging;
                  if (r == null) return;
                  setState(() {
                    r.planX = math.max(0.0, (r.planX ?? 0.0) + d.delta.dx / _scale);
                    r.planY = math.max(0.0, (r.planY ?? 0.0) + d.delta.dy / _scale);
                  });
                },
                onPanEnd: (_) {
                  final r = _dragging;
                  if (r == null) return;
                  s.mutate(() {
                    r.planX = (r.planX! * 10).roundToDouble() / 10;
                    r.planY = (r.planY! * 10).roundToDouble() / 10;
                  }, touch: p, room: r);
                  setState(() => _dragging = null);
                },
                child: CustomPaint(size: size, painter: _PlanPainter(p.rooms, _scale, _pad, cs, _dragging?.id)),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: () => setState(() => _zoom = math.min(2.0, _zoom + 0.25)), child: const Text('Zoom +')),
              OutlinedButton(onPressed: () => setState(() => _zoom = math.max(0.5, _zoom - 0.25)), child: const Text('Zoom −')),
              OutlinedButton(
                onPressed: () => s.mutate(() {
                  autoLayout(p, reset: true);
                  for (final r in p.rooms) {
                    r.markEdited();
                  }
                }, touch: p),
                child: const Text('Réorganiser'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _PlanPainter extends CustomPainter {
  _PlanPainter(this.rooms, this.scale, this.pad, this.cs, this.activeId);
  final List<Room> rooms;
  final double scale;
  final double pad;
  final ColorScheme cs;
  final String? activeId;

  void _text(Canvas c, String s, Offset center, TextStyle style, {double angle = 0}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    c.save();
    c.translate(center.dx, center.dy);
    if (angle != 0) c.rotate(angle);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final wall = Paint()
      ..color = cs.onSurface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final fill = Paint()..color = cs.surface;
    final activeFill = Paint()..color = cs.primaryContainer;
    final window = Paint()
      ..color = cs.primary
      ..strokeWidth = 6;
    final doorGap = Paint()
      ..color = cs.surface
      ..strokeWidth = 5;
    final doorArc = Paint()
      ..color = cs.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final cote = TextStyle(fontSize: 10, color: cs.tertiary);

    for (final r in rooms) {
      final (pts, bw, bh) = planShape(r);
      if (pts.isEmpty) continue;
      final ox = pad + (r.planX ?? 0.0) * scale, oy = pad + (r.planY ?? 0.0) * scale;
      Offset at(Pt v) => Offset(ox + v.x * scale, oy + v.y * scale);
      final poly = [for (final v in pts) at(v)];
      final path = Path()..addPolygon(poly, true);
      canvas.drawPath(path, r.id == activeId ? activeFill : fill);
      canvas.drawPath(path, wall);
      final n = pts.length;
      for (var i = 0; i < n && i < r.walls.length; i++) {
        final a = poly[i], b = poly[(i + 1) % n];
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        final dir = b - a;
        final len = dir.distance;
        if (len < 1) continue;
        final u = dir / len;
        // Normale vers l'extérieur (le contour est parcouru avec l'intérieur à gauche).
        final out = Offset(u.dy, -u.dx) * -12;
        var angle = math.atan2(dir.dy, dir.dx);
        if (angle > math.pi / 2 || angle < -math.pi / 2) angle += math.pi;
        _text(canvas, fmt2(r.walls[i].length), mid + out, cote, angle: angle);
        // Ouvertures du mur, centrées : fenêtre en trait épais, porte en arc.
        for (final o in r.openings.where((o) => o.wallIndex == i)) {
          final w = math.min(o.width * scale, len - 4);
          final p1 = mid - u * (w / 2), p2 = mid + u * (w / 2);
          if (o.type == OpeningType.window) {
            canvas.drawLine(p1, p2, window);
          } else {
            canvas.drawLine(p1, p2, doorGap);
            final inward = Offset(u.dy, -u.dx); // intérieur de la pièce (repère écran, y vers le bas)
            canvas.drawLine(p1, p1 + inward * w, doorArc);
          }
        }
      }
      final center = Offset(ox + bw * scale / 2, oy + bh * scale / 2);
      _text(canvas, r.name, center - const Offset(0, 7), TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface));
      _text(canvas, '${fmt2(roomMeasures(r).floor)} m²', center + const Offset(0, 9), TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant));
    }
  }

  @override
  bool shouldRepaint(covariant _PlanPainter old) => true;
}

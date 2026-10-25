import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../domain/calculations.dart';
import '../../domain/models.dart';
import '../widgets/common.dart';

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
    final maxRow = math.max(9.0, p.rooms.fold<double>(0, (s, r) => math.max(s, r.length)));
    double x = 0, y = 0, rowH = 0;
    for (final r in p.rooms) {
      if (r.planX != null && r.planY != null) continue;
      if (x > 0 && x + r.length > maxRow) {
        x = 0;
        y += rowH + _gap;
        rowH = 0;
      }
      r.planX = x;
      r.planY = y;
      x += r.length + _gap;
      rowH = math.max(rowH, r.width);
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
      final rect = Rect.fromLTWH(_pad + (r.planX ?? 0.0) * _scale, _pad + (r.planY ?? 0.0) * _scale, r.length * _scale, r.width * _scale);
      if (rect.contains(pos)) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.project(widget.projectId);
    if (p == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Projet introuvable.')));
    final maxX = p.rooms.fold<double>(6, (m, r) => math.max(m, (r.planX ?? 0.0) + r.length)) + 1;
    final maxY = p.rooms.fold<double>(4, (m, r) => math.max(m, (r.planY ?? 0.0) + r.width)) + 1;
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
                  }, touch: p);
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
              OutlinedButton(onPressed: () => s.mutate(() => autoLayout(p, reset: true), touch: p), child: const Text('Réorganiser')),
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
      final x = pad + (r.planX ?? 0.0) * scale, y = pad + (r.planY ?? 0.0) * scale;
      final w = r.length * scale, h = r.width * scale;
      final rect = Rect.fromLTWH(x, y, w, h);
      canvas.drawRect(rect, r.id == activeId ? activeFill : fill);
      canvas.drawRect(rect, wall);
      if (r.windowCount > 0) canvas.drawLine(Offset(x + w * 0.3, y), Offset(x + w * 0.7, y), window);
      if (r.doorCount > 0) {
        final d = math.min(kDoorWidth * scale, w - 16);
        canvas.drawLine(Offset(x + 8, y + h), Offset(x + 8 + d, y + h), doorGap);
        canvas.drawArc(Rect.fromCircle(center: Offset(x + 8, y + h), radius: d), -math.pi / 2, math.pi / 2, false, doorArc);
      }
      _text(canvas, r.name, Offset(x + w / 2, y + h / 2 - 7), TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface));
      _text(canvas, '${fmt2(roomMeasures(r).floor)} m²', Offset(x + w / 2, y + h / 2 + 9), TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant));
      _text(canvas, fmt2(r.length), Offset(x + w / 2, y - 9), cote);
      _text(canvas, fmt2(r.width), Offset(x - 10, y + h / 2), cote, angle: -math.pi / 2);
    }
  }

  @override
  bool shouldRepaint(covariant _PlanPainter old) => true;
}

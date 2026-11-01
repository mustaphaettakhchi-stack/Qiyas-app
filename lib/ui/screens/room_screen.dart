import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../domain/calculations.dart';
import '../../domain/geometry.dart';
import '../../domain/models.dart';
import '../widgets/common.dart';
import '../widgets/photos.dart';

/// Saisie d'une pièce : rectangle (longueur × largeur) ou mur par mur avec les angles.
/// Chaque cote garde son origine ; une valeur standard reste marquée « à vérifier ».
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.projectId, required this.roomId});
  final String projectId;
  final String roomId;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  /// Mode choisi par l'utilisateur ; par défaut, déduit de la forme de la pièce.
  bool? _rectangleMode;

  String get projectId => widget.projectId;
  String get roomId => widget.roomId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.project(projectId);
    final r = p?.rooms.where((x) => x.id == roomId).firstOrNull;
    if (p == null || r == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Pièce introuvable.')));
    }
    void edit(VoidCallback f) => s.mutate(f, touch: p, room: r);
    final m = roomMeasures(r);
    final warnings = roomWarnings(r);
    final t = Theme.of(context).textTheme;
    final rectangle = _rectangleMode ?? r.isRectangle;

    return Scaffold(
      appBar: AppBar(title: Text(r.name), actions: const [SyncBadge()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (r.syncError != null) ...[AlertBox('Envoi refusé : ${r.syncError}', kind: AlertKind.error), const SizedBox(height: 8)],
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in AppState.roomNames)
            ChoiceChip(label: Text(n), selected: r.name == n, onSelected: (_) => edit(() => r.name = n)),
        ]),
        EditField(key: ValueKey('name-${r.id}'), label: 'Nom de la pièce', value: r.name, onChanged: (v) => edit(() => r.name = v)),
        const SizedBox(height: 8),
        _MeasureField(
          key: ValueKey('h-${r.id}'),
          label: 'Hauteur sous plafond (m)',
          value: r.height,
          source: r.heightSource,
          onChanged: (v) => edit(() {
            r.height = v;
            r.heightSource = MeasureSource.manual;
          }),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Rectangle'), icon: Icon(Icons.crop_square)),
            ButtonSegment(value: false, label: Text('Mur par mur'), icon: Icon(Icons.polyline_outlined)),
          ],
          selected: {rectangle},
          onSelectionChanged: (v) async {
            if (v.first && !rectangle) {
              if (r.isRectangle || await _toRectangle(context, s, p, r)) setState(() => _rectangleMode = true);
            } else if (!v.first && rectangle) {
              // Forme libre : les 4 murs sont conservés et deviennent modifiables un par un.
              setState(() => _rectangleMode = false);
            }
          },
        ),
        const SizedBox(height: 8),
        if (rectangle) _RectangleEditor(room: r, edit: edit) else _WallsEditor(room: r, edit: edit, newId: s.newId),
        const SizedBox(height: 8),
        _OutlinePreview(room: r),
        for (final w in warnings) ...[const SizedBox(height: 8), AlertBox(w, kind: AlertKind.warning)],
        if (r.unverifiedCount > 0) ...[
          const SizedBox(height: 8),
          AlertBox(
            '${r.unverifiedCount} cote(s) à la valeur standard : mesurez-les sur place (repérées en orange).',
            kind: AlertKind.warning,
          ),
        ],
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 20, runSpacing: 6, children: [
              Text('Sol ${fmt2(m.floor)} m²'),
              Text('Périmètre ${fmt2(m.perimeter)} m'),
              Text('Murs nets ${fmt2(m.walls)} m²'),
              Text('Plinthes ${fmt2(m.skirting)} m'),
              Text('Volume ${fmt2(m.volume)} m³'),
            ]),
          ),
        ),
        SectionHeader(
          'Ouvertures',
          trailing: Wrap(spacing: 4, children: [
            TextButton(
              onPressed: () => edit(() => r.openings.add(Opening.standard(s.newId(), OpeningType.door))),
              child: const Text('+ Porte'),
            ),
            TextButton(
              onPressed: () => edit(() => r.openings.add(Opening.standard(s.newId(), OpeningType.window))),
              child: const Text('+ Fenêtre'),
            ),
          ]),
        ),
        if (r.openings.isEmpty) Text('Aucune ouverture.', style: t.bodySmall),
        for (final o in r.openings) _OpeningRow(key: ValueKey('o-${o.id}'), room: r, opening: o, edit: edit),
        SectionHeader(
          'Photos de la pièce',
          trailing: TextButton.icon(
            onPressed: () async {
              final client = s.clientOf(p);
              if (client == null || !client.hasConsent) {
                showToast(context, 'Recueillez d\'abord le consentement du client sur sa fiche.');
                return;
              }
              final paths = await pickPhotos(context);
              if (paths.isNotEmpty) edit(() => r.photoPaths.addAll(paths));
            },
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Ajouter'),
          ),
        ),
        PhotoStrip(paths: r.photoPaths),
        Text('Photos enregistrées sur ce téléphone uniquement.', style: t.bodySmall),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                final next = s.addRoom(p);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute<void>(builder: (_) => RoomScreen(projectId: p.id, roomId: next.id)),
                );
              },
              child: const Text('Pièce suivante'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Terminer'))),
        ]),
        TextButton(
          onPressed: () async {
            if (await confirm(context, 'Supprimer cette pièce ?', 'Ses cotes et ses photos seront retirées du projet.',
                ok: 'Supprimer')) {
              s.deleteRoom(p, r);
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: const Text('Supprimer cette pièce'),
        ),
      ]),
    );
  }

  Future<bool> _toRectangle(BuildContext context, AppState s, Project p, Room r) async {
    if (!await confirm(context, 'Revenir à un rectangle ?',
        'Les murs seront remplacés par 4 murs à angle droit (longueur = mur 1, largeur = mur 2). '
        'Les ouvertures des murs supprimés passeront sur le mur 1.',
        ok: 'Rectangle')) {
      return false;
    }
    s.mutate(() {
      final l = r.walls.isNotEmpty ? r.walls[0] : Wall(id: s.newId(), length: 0, lengthSource: MeasureSource.standard);
      final w = r.walls.length > 1 ? r.walls[1] : Wall(id: s.newId(), length: 0, lengthSource: MeasureSource.standard);
      r.walls = [
        Wall(id: s.newId(), length: l.length, lengthSource: l.lengthSource),
        Wall(id: s.newId(), length: w.length, lengthSource: w.lengthSource),
        Wall(id: s.newId(), length: l.length, lengthSource: l.lengthSource),
        Wall(id: s.newId(), length: w.length, lengthSource: w.lengthSource),
      ];
      for (final o in r.openings) {
        if (o.wallIndex > 3 || o.wallIndex < 0) o.wallIndex = 0;
      }
    }, touch: p, room: r);
    return true;
  }
}

/// Champ de cote : orange et marqué « à vérifier » tant que la valeur est standard.
class _MeasureField extends StatelessWidget {
  const _MeasureField({super.key, required this.label, required this.value, required this.source, required this.onChanged});
  final String label;
  final double value;
  final String source;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final unverified = !MeasureSource.verified(source);
    final field = NumField(label: unverified ? '$label · à vérifier' : label, value: value, onChanged: onChanged);
    if (!unverified) return field;
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 4)),
      ),
      padding: const EdgeInsets.only(left: 6),
      child: field,
    );
  }
}

class _RectangleEditor extends StatelessWidget {
  const _RectangleEditor({required this.room, required this.edit});
  final Room room;
  final void Function(VoidCallback) edit;

  @override
  Widget build(BuildContext context) {
    final r = room;
    void setPair(int a, int b, double v) => edit(() {
          for (final i in [a, b]) {
            r.walls[i]
              ..length = v
              ..lengthSource = MeasureSource.manual;
          }
        });
    return Row(children: [
      Expanded(
        child: _MeasureField(
          key: ValueKey('L-${r.id}'),
          label: 'Longueur (m)',
          value: r.length,
          source: r.walls[0].lengthSource,
          onChanged: (v) => setPair(0, 2, v),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _MeasureField(
          key: ValueKey('W-${r.id}'),
          label: 'Largeur (m)',
          value: r.width,
          source: r.walls[1].lengthSource,
          onChanged: (v) => setPair(1, 3, v),
        ),
      ),
    ]);
  }
}

class _WallsEditor extends StatelessWidget {
  const _WallsEditor({required this.room, required this.edit, required this.newId});
  final Room room;
  final void Function(VoidCallback) edit;
  final String Function() newId;

  @override
  Widget build(BuildContext context) {
    final r = room;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'Parcourez la pièce en gardant l\'intérieur à votre gauche. Angle : 90° pour un coin normal, '
        '270° pour un coin rentrant.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      for (var i = 0; i < r.walls.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            SizedBox(width: 56, child: Text('Mur ${i + 1}')),
            Expanded(
              flex: 3,
              child: _MeasureField(
                key: ValueKey('wl-${r.walls[i].id}'),
                label: 'Longueur (m)',
                value: r.walls[i].length,
                source: r.walls[i].lengthSource,
                onChanged: (v) => edit(() {
                  r.walls[i]
                    ..length = v
                    ..lengthSource = MeasureSource.manual;
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: NumField(
                key: ValueKey('wa-${r.walls[i].id}'),
                label: 'Angle (°)',
                decimals: 1,
                value: r.walls[i].angle,
                onChanged: (v) => edit(() => r.walls[i].angle = (v > 0 && v < 360) ? v : 90),
              ),
            ),
            IconButton(
              tooltip: 'Supprimer le mur ${i + 1}',
              onPressed: r.walls.length <= 3
                  ? null
                  : () => edit(() {
                        r.walls.removeAt(i);
                        for (final o in r.openings) {
                          if (o.wallIndex == i) {
                            o.wallIndex = -1; // à rattacher : signalé dans les alertes
                          } else if (o.wallIndex > i) {
                            o.wallIndex--;
                          }
                        }
                      }),
              icon: const Icon(Icons.close),
            ),
          ]),
        ),
      TextButton.icon(
        onPressed: () => edit(() => r.walls.add(Wall(id: newId(), length: 0, lengthSource: MeasureSource.standard))),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un mur'),
      ),
    ]);
  }
}

class _OpeningRow extends StatelessWidget {
  const _OpeningRow({super.key, required this.room, required this.opening, required this.edit});
  final Room room;
  final Opening opening;
  final void Function(VoidCallback) edit;

  @override
  Widget build(BuildContext context) {
    final o = opening;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Row(children: [
            Expanded(child: Text(o.type == OpeningType.door ? 'Porte' : 'Fenêtre')),
            DropdownButton<int>(
              value: o.wallIndex >= 0 && o.wallIndex < room.walls.length ? o.wallIndex : null,
              hint: const Text('Mur ?'),
              items: [for (var i = 0; i < room.walls.length; i++) DropdownMenuItem(value: i, child: Text('Mur ${i + 1}'))],
              onChanged: (v) => edit(() => o.wallIndex = v ?? 0),
            ),
            IconButton(
              tooltip: 'Supprimer l\'ouverture',
              onPressed: () => edit(() => room.openings.removeWhere((x) => x.id == o.id)),
              icon: const Icon(Icons.close),
            ),
          ]),
          Row(children: [
            Expanded(
              child: _MeasureField(
                key: ValueKey('ow-${o.id}'),
                label: 'Largeur (m)',
                value: o.width,
                source: o.widthSource,
                onChanged: (v) => edit(() {
                  o.width = v;
                  o.widthSource = MeasureSource.manual;
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MeasureField(
                key: ValueKey('oh-${o.id}'),
                label: 'Hauteur (m)',
                value: o.height,
                source: o.heightSource,
                onChanged: (v) => edit(() {
                  o.height = v;
                  o.heightSource = MeasureSource.manual;
                }),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Aperçu à l'échelle du contour saisi (murs numérotés, écart de fermeture en rouge).
class _OutlinePreview extends StatelessWidget {
  const _OutlinePreview({required this.room});
  final Room room;

  @override
  Widget build(BuildContext context) {
    final shape = outline([for (final w in room.walls) w.length], [for (final w in room.walls) w.angle]);
    if (shape.vertices.length < 3 || shape.vertices.every((v) => v.length == 0)) return const SizedBox.shrink();
    return SizedBox(
      height: 180,
      child: CustomPaint(painter: OutlinePainter(shape, Theme.of(context).colorScheme), size: Size.infinite),
    );
  }
}

class OutlinePainter extends CustomPainter {
  OutlinePainter(this.shape, this.cs);
  final Outline shape;
  final ColorScheme cs;

  @override
  void paint(Canvas canvas, Size size) {
    final v = shape.vertices;
    final xs = v.map((p) => p.x), ys = v.map((p) => p.y);
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final w = math.max(maxX - minX, 0.1), h = math.max(maxY - minY, 0.1);
    final scale = math.min((size.width - 32) / w, (size.height - 32) / h);
    Offset at(Pt p) => Offset(16 + (p.x - minX) * scale, size.height - 16 - (p.y - minY) * scale);

    final path = Path()..moveTo(at(v.first).dx, at(v.first).dy);
    for (final p in v.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    canvas.drawPath(path, Paint()
      ..color = cs.onSurface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    // Dernier mur : relie le dernier sommet au départ ; en rouge si les cotes ne se referment pas.
    canvas.drawLine(at(v.last), at(v.first), Paint()
      ..color = shape.closes ? cs.onSurface : cs.error
      ..strokeWidth = shape.closes ? 2 : 3);
    for (var i = 0; i < v.length; i++) {
      final a = at(v[i]), b = at(v[(i + 1) % v.length]);
      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: TextStyle(fontSize: 11, color: cs.primary)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((a.dx + b.dx) / 2 - tp.width / 2, (a.dy + b.dy) / 2 - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant OutlinePainter old) => true;
}

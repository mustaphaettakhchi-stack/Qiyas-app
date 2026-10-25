import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../domain/calculations.dart';
import '../../domain/models.dart';
import '../../services/laser_meter_service.dart';
import '../widgets/common.dart';
import '../widgets/photos.dart';

enum _Dim { length, width, height }

const _dimLabels = {_Dim.length: 'Longueur', _Dim.width: 'Largeur', _Dim.height: 'Hauteur'};

/// E5 · Saisie d'une pièce.
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.projectId, required this.roomId});
  final String projectId;
  final String roomId;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late final Map<_Dim, TextEditingController> _ctrl;
  late final Map<_Dim, FocusNode> _focus;
  _Dim _active = _Dim.length;
  bool _measuring = false;

  Room? get _room {
    final p = context.read<AppState>().project(widget.projectId);
    if (p == null) return null;
    for (final r in p.rooms) {
      if (r.id == widget.roomId) return r;
    }
    return null;
  }

  double _get(Room r, _Dim d) => switch (d) {
        _Dim.length => r.length,
        _Dim.width => r.width,
        _Dim.height => r.height,
      };

  void _set(Room r, _Dim d, double v) {
    switch (d) {
      case _Dim.length:
        r.length = v;
      case _Dim.width:
        r.width = v;
      case _Dim.height:
        r.height = v;
    }
  }

  @override
  void initState() {
    super.initState();
    final r = _room;
    _ctrl = {for (final d in _Dim.values) d: TextEditingController(text: r == null ? '' : numInput(_get(r, d)))};
    _focus = {for (final d in _Dim.values) d: FocusNode()};
    for (final e in _focus.entries) {
      e.value.addListener(() {
        if (e.value.hasFocus) setState(() => _active = e.key);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _measure(AppState s, Project p, Room r) async {
    final laser = context.read<LaserMeterService>();
    setState(() => _measuring = true);
    final v = await laser.measure(hint: _get(r, _active));
    if (!mounted) return;
    s.mutate(() => _set(r, _active, v), touch: p);
    _ctrl[_active]!.text = numInput(v);
    setState(() => _measuring = false);
    showToast(context, '${laser.displayName} : ${fmt2(v)} m reçus dans « ${_dimLabels[_active]} ».');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.project(widget.projectId);
    final r = _room;
    if (p == null || r == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Pièce introuvable.')));
    }
    void edit(VoidCallback f) => s.mutate(f, touch: p);
    final m = roomMeasures(r);
    final warnings = roomWarnings(r);
    final laser = context.read<LaserMeterService>();
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(r.name), actions: const [SyncBadge()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in AppState.roomNames)
            ChoiceChip(label: Text(n), selected: r.name == n, onSelected: (_) => edit(() => r.name = n)),
        ]),
        EditField(key: ValueKey('name-${r.id}'), label: 'Nom de la pièce', value: r.name, onChanged: (v) => edit(() => r.name = v)),
        const SizedBox(height: 8),
        Row(children: [
          for (final d in _Dim.values) ...[
            if (d != _Dim.length) const SizedBox(width: 8),
            Expanded(
              child: NumField(
                label: '${_dimLabels[d]} (m)',
                value: _get(r, d),
                controller: _ctrl[d],
                focusNode: _focus[d],
                onChanged: (v) => edit(() => _set(r, d, v)),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _measuring ? null : () => _measure(s, p, r),
          icon: _measuring
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.straighten),
          label: Text('Mesurer « ${_dimLabels[_active]} » au télémètre${laser.isSimulated ? ' (simulé)' : ''}'),
        ),
        for (final w in warnings) ...[const SizedBox(height: 8), AlertBox(w, kind: AlertKind.warning)],
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 20, runSpacing: 6, children: [
              Text('Sol ${fmt2(m.floor)} m²'),
              Text('Murs nets ${fmt2(m.walls)} m²'),
              Text('Plinthes ${fmt2(m.skirting)} ml'),
              Text('Volume ${fmt2(m.volume)} m³'),
            ]),
          ),
        ),
        SectionHeader(
          'Ouvertures',
          trailing: Wrap(spacing: 4, children: [
            TextButton(onPressed: () => edit(() => r.openings.add(Opening.standard(s.newId(), OpeningType.door))), child: const Text('+ Porte')),
            TextButton(onPressed: () => edit(() => r.openings.add(Opening.standard(s.newId(), OpeningType.window))), child: const Text('+ Fenêtre')),
          ]),
        ),
        if (r.openings.isEmpty) Text('Aucune ouverture.', style: t.bodySmall),
        for (final o in r.openings)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 70, child: Text(o.type == OpeningType.door ? 'Porte' : 'Fenêtre')),
              Expanded(child: NumField(key: ValueKey('ow-${o.id}'), label: 'Largeur', value: o.width, onChanged: (v) => edit(() => o.width = v))),
              const SizedBox(width: 8),
              Expanded(child: NumField(key: ValueKey('oh-${o.id}'), label: 'Hauteur', value: o.height, onChanged: (v) => edit(() => o.height = v))),
              IconButton(
                tooltip: 'Supprimer l\'ouverture',
                onPressed: () => edit(() => r.openings.removeWhere((x) => x.id == o.id)),
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
        SectionHeader(
          'Photos de la pièce',
          trailing: TextButton.icon(
            onPressed: () async {
              final paths = await pickPhotos(context);
              if (paths.isNotEmpty) edit(() => r.photoPaths.addAll(paths));
            },
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Ajouter'),
          ),
        ),
        PhotoStrip(paths: r.photoPaths),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                final next = s.addRoom(p);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => RoomScreen(projectId: p.id, roomId: next.id)),
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
            if (await confirm(context, 'Supprimer cette pièce ?', 'Ses cotes et ses photos seront retirées du projet.', ok: 'Supprimer')) {
              s.deleteRoom(p, r);
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: const Text('Supprimer cette pièce'),
        ),
      ]),
    );
  }
}

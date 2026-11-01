// Validation du métré (lot 1.4, USER_FLOWS P4).
//
// Le métré validé est identifié par une empreinte SHA-256 des données qui déterminent les
// quantités (murs, angles, hauteurs, ouvertures, comptages). Toute modification ultérieure
// d'une de ces données rend la validation périmée : le métré est « à revalider ».

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'calculations.dart';
import 'models.dart';

String metreFingerprint(Project p) {
  final rooms = [...p.rooms]..sort((a, b) => a.id.compareTo(b.id));
  final canonical = [
    for (final r in rooms)
      {
        'id': r.id,
        'h': r.height,
        'walls': [for (final w in r.walls) [w.length, w.angle]],
        'openings': [for (final o in r.openings) [o.type.name, o.wallIndex, o.width, o.height]],
        'counts': {for (final k in (r.counts.keys.toList()..sort())) if (r.counts[k]! > 0) k: r.counts[k]},
      },
  ];
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

/// Cote encore à la valeur standard, à vérifier ou à accepter explicitement.
class UnverifiedMeasure {
  const UnverifiedMeasure(this.room, this.label);
  final String room;
  final String label;
}

List<UnverifiedMeasure> unverifiedMeasures(Project p) {
  final out = <UnverifiedMeasure>[];
  for (final r in p.rooms) {
    if (!MeasureSource.verified(r.heightSource)) out.add(UnverifiedMeasure(r.name, 'hauteur'));
    for (final (i, w) in r.walls.indexed) {
      if (!MeasureSource.verified(w.lengthSource)) out.add(UnverifiedMeasure(r.name, 'mur ${i + 1}'));
    }
    for (final o in r.openings) {
      final kind = o.type == OpeningType.door ? 'porte' : 'fenêtre';
      if (!MeasureSource.verified(o.widthSource)) out.add(UnverifiedMeasure(r.name, 'largeur de la $kind'));
      if (!MeasureSource.verified(o.heightSource)) out.add(UnverifiedMeasure(r.name, 'hauteur de la $kind'));
    }
  }
  return out;
}

enum MetreState { notValidated, validated, stale }

MetreState metreState(Project p) {
  final v = p.metreValidation;
  if (v == null) return MetreState.notValidated;
  return v['fingerprint'] == metreFingerprint(p) ? MetreState.validated : MetreState.stale;
}

/// Pièces qui empêchent la validation (contour non fermé, murs croisés, ouverture sans mur).
List<Room> blockingRooms(Project p) => p.rooms.where((r) => !roomGeometryValid(r)).toList();

Map<String, dynamic> buildValidation(Project p, {required String userId, required String userName}) => {
      'validated_at': DateTime.now().toUtc().toIso8601String(),
      'validated_by': userId,
      'validated_by_name': userName,
      'fingerprint': metreFingerprint(p),
      'rooms': p.rooms.length,
      'unverified_accepted': unverifiedMeasures(p).length,
    };

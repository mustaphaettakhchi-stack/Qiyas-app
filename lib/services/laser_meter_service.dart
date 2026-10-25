import 'dart:math' as math;

/// Télémètre laser Bluetooth (écran E5).
///
/// Question ouverte du cahier des charges : les modèles vendus au Maroc et l'accès
/// à leurs données ne sont pas encore validés. [SimulatedLaserMeter] permet de tester
/// le parcours ; une implémentation réelle utilisera par exemple flutter_blue_plus
/// avec le protocole du fabricant retenu.
abstract class LaserMeterService {
  String get displayName;
  bool get isSimulated;

  /// Renvoie une mesure en mètres. [hint] = valeur actuelle du champ, pour la simulation.
  Future<double> measure({double? hint});
}

class SimulatedLaserMeter implements LaserMeterService {
  SimulatedLaserMeter([math.Random? random]) : _random = random ?? math.Random();
  final math.Random _random;

  @override
  String get displayName => 'Télémètre simulé';

  @override
  bool get isSimulated => true;

  @override
  Future<double> measure({double? hint}) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final base = (hint == null || hint <= 0) ? 3.0 : hint;
    final v = base * (0.97 + _random.nextDouble() * 0.06);
    return (v * 100).roundToDouble() / 100;
  }
}

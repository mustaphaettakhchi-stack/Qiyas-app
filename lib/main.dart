import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/app_state.dart';
import 'data/local_store.dart';
import 'services/auth_service.dart';
import 'services/laser_meter_service.dart';
import 'services/sync_service.dart';

/// Point d'entrée. Les services sont injectés ici : pour brancher un vrai fournisseur
/// SMS, un backend de synchronisation ou un télémètre Bluetooth, il suffit de remplacer
/// l'implémentation correspondante.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(store: LocalStore(), sync: LocalOnlySyncService());
  await state.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        Provider<AuthService>.value(value: FakeSmsAuthService()),
        Provider<LaserMeterService>.value(value: SimulatedLaserMeter()),
      ],
      child: const QiyasApp(),
    ),
  );
}

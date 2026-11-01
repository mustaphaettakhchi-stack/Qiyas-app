import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/app_state.dart';
import 'data/local_store.dart';
import 'services/laser_meter_service.dart';
import 'services/sync_service.dart';
import 'session/api_client.dart';
import 'session/auth_service.dart';
import 'session/session_controller.dart';
import 'session/session_store.dart';

/// Point d'entrée : les services sont injectés ici.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(store: LocalStore(), sync: LocalOnlySyncService());
  final store = SecureSessionStore();
  final api = ApiClient(store: store);
  final session = SessionController(api: api, auth: AuthService(api), store: store);
  await state.init();
  // La vérification en ligne de la session se poursuit en arrière-plan.
  session.restore();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<SessionController>.value(value: session),
        Provider<LaserMeterService>.value(value: SimulatedLaserMeter()),
      ],
      child: const LamaalamApp(),
    ),
  );
}

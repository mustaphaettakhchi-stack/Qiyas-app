import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/app_state.dart';
import 'data/local_store.dart';
import 'services/laser_meter_service.dart';
import 'services/pdf_service.dart';
import 'session/api_client.dart';
import 'session/auth_service.dart';
import 'session/session_controller.dart';
import 'session/session_store.dart';
import 'sync/sync_engine.dart';

/// Point d'entrée : les services sont injectés ici.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(store: LocalStore());
  final store = SecureSessionStore();
  final api = ApiClient(store: store);
  final session = SessionController(api: api, auth: AuthService(api), store: store);
  await state.init();
  final sync = SyncEngine(
    state: state,
    session: session,
    pdfBuilder: (p, q) => PdfService.build(company: state.company, project: p, quote: q, client: state.clientOf(p)),
  );
  // La vérification en ligne de la session se poursuit en arrière-plan.
  session.restore();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<SessionController>.value(value: session),
        ChangeNotifierProvider<SyncEngine>.value(value: sync),
        Provider<LaserMeterService>.value(value: SimulatedLaserMeter()),
      ],
      child: const LamaalamApp(),
    ),
  );
}

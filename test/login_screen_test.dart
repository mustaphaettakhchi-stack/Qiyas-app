import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamaalam/app.dart';
import 'package:lamaalam/session/api_client.dart';
import 'package:lamaalam/session/auth_service.dart';
import 'package:lamaalam/session/session_controller.dart';
import 'package:lamaalam/session/session_store.dart';
import 'package:lamaalam/ui/screens/auth/login_screen.dart';
import 'package:provider/provider.dart';

Widget _wrap(SessionController session) => ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(theme: lamaalamTheme(), home: const LoginScreen()),
    );

void main() {
  late SessionController session;

  setUp(() {
    final store = MemorySessionStore();
    final api = ApiClient(store: store);
    session = SessionController(api: api, auth: AuthService(api), store: store);
  });

  testWidgets('Écran de connexion : logo, champs, aucune entrée de démonstration', (tester) async {
    await tester.pumpWidget(_wrap(session));
    expect(find.bySemanticsLabel('Logo Group LAMAALAM'), findsOneWidget);
    expect(find.text('Adresse e-mail'), findsOneWidget);
    expect(find.textContaining('J\'ai reçu un lien'), findsOneWidget);
    expect(find.text('Mot de passe'), findsOneWidget);
    expect(find.text('Continuer sans serveur'), findsNothing);
    expect(find.textContaining('482913'), findsNothing);
  });

  testWidgets('Champs vides : message clair, aucune requête', (tester) async {
    await tester.pumpWidget(_wrap(session));
    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    expect(find.text('Saisissez votre adresse e-mail et votre mot de passe.'), findsOneWidget);
  });

  testWidgets('Adresse de serveur non sécurisée refusée', (tester) async {
    await tester.pumpWidget(_wrap(session));
    await tester.enterText(find.widgetWithText(TextField, 'Adresse e-mail'), 'karim@exemple.ma');
    await tester.enterText(find.widgetWithText(TextField, 'Mot de passe'), 'un-mot-de-passe-long');
    await tester.enterText(find.widgetWithText(TextField, 'Adresse du serveur LAMAALAM'), 'ftp://serveur');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Se connecter'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Se connecter'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Adresse du serveur invalide'), findsOneWidget);
  });
}

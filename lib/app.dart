import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/app_state.dart';
import 'ui/home_shell.dart';
import 'session/session_controller.dart';
import 'ui/screens/auth/login_screen.dart';

/// Charte Groupe LAMAALAM (docs/ARCHITECTURE.md §8).
abstract final class Brand {
  static const black = Color(0xFF151515);
  static const blackSecondary = Color(0xFF222222);
  static const orange = Color(0xFFF28C00);
  static const orangeBright = Color(0xFFFF9D19);
  static const white = Color(0xFFFFFFFF);
  static const lightGrey = Color(0xFFF2F2F2);
  static const technicalGrey = Color(0xFF777777);

  /// Texte secondaire. Le gris technique #777777 n'atteint que 4,08:1 sur #151515
  /// (minimum WCAG AA : 4,5:1) : il est réservé aux bordures et éléments décoratifs.
  /// Écart à faire valider par Groupe LAMAALAM.
  static const secondaryText = Color(0xFFB3B3B3);
}

ThemeData lamaalamTheme() {
  // Texte noir sur orange (7,41:1) : le blanc sur orange n'atteint que 2,46:1.
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Brand.orange,
    onPrimary: Brand.black,
    primaryContainer: Brand.orangeBright,
    onPrimaryContainer: Brand.black,
    secondary: Brand.orangeBright,
    onSecondary: Brand.black,
    error: Color(0xFFFF6B5E),
    onError: Brand.black,
    surface: Brand.black,
    onSurface: Brand.white,
    surfaceContainerLowest: Brand.black,
    surfaceContainerLow: Brand.blackSecondary,
    surfaceContainer: Brand.blackSecondary,
    surfaceContainerHigh: Color(0xFF2A2A2A),
    surfaceContainerHighest: Color(0xFF333333),
    onSurfaceVariant: Brand.secondaryText,
    outline: Brand.technicalGrey,
    outlineVariant: Color(0xFF3A3A3A),
    inverseSurface: Brand.lightGrey,
    onInverseSurface: Brand.black,
    inversePrimary: Color(0xFFB36800),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: Brand.black,
    visualDensity: VisualDensity.standard,
    appBarTheme: const AppBarTheme(backgroundColor: Brand.black, foregroundColor: Brand.white),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.blackSecondary,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: false,
    ),
    // Boutons d'au moins 48 points de haut (usage à une main sur chantier).
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48, 52))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52))),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Brand.blackSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}

class LamaalamApp extends StatelessWidget {
  const LamaalamApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final session = context.watch<SessionController>();
    return MaterialApp(
      title: 'LAMAALAM',
      debugShowCheckedModeBanner: false,
      // Thème sombre unique pour l'instant : un thème clair à fort contraste (plein soleil)
      // est prévu, l'orange sur blanc (2,46:1) ne pouvant pas servir de couleur de texte.
      theme: lamaalamTheme(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: !s.loaded || !session.restored
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (session.isAuthenticated ? const HomeShell() : const LoginScreen()),
    );
  }
}

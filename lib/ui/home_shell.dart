import 'package:flutter/material.dart';

import 'screens/prices_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/projects_screen.dart';

/// Navigation principale : Projets (E3), Prix (E8), Profil (E2).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _index, children: const [ProjectsScreen(), PricesScreen(), ProfileScreen()]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Projets'),
            NavigationDestination(icon: Icon(Icons.sell_outlined), selectedIcon: Icon(Icons.sell), label: 'Prix'),
            NavigationDestination(icon: Icon(Icons.business_outlined), selectedIcon: Icon(Icons.business), label: 'Profil'),
          ],
        ),
      );
}

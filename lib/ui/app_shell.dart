import 'package:flutter/material.dart';

import 'package:combat_goblin_prime/ui/downloads/downloads_screen.dart';
import 'package:combat_goblin_prime/ui/home/home_screen.dart';
import 'package:combat_goblin_prime/ui/import/import_session_controller.dart';
import 'package:combat_goblin_prime/ui/import/import_session_provider.dart';

/// Global app shell with navigation drawer.
///
/// Hosts [HomeScreen] (search + slot status) and [DownloadsScreen]
/// (slot management + catalog picker). Shows an update badge on the
/// AppBar when [ImportSessionController.updateAvailable] is true.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  void _navigate(int index) {
    setState(() => _selectedIndex = index);
    Navigator.of(context).pop(); // close drawer
  }

  @override
  Widget build(BuildContext context) {
    final controller = ImportSessionProvider.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Combat Goblin'),
          actions: [
            if (controller.updateAvailable)
              IconButton(
                icon: const Badge(
                  smallSize: 8,
                  child: Icon(Icons.system_update),
                ),
                tooltip: 'Updates available',
                onPressed: () => setState(() => _selectedIndex = 1),
              ),
          ],
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(color: Colors.deepPurple),
                child: Text(
                  'Combat Goblin',
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Home'),
                selected: _selectedIndex == 0,
                onTap: () => _navigate(0),
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Downloads'),
                selected: _selectedIndex == 1,
                onTap: () => _navigate(1),
              ),
            ],
          ),
        ),
        body: _selectedIndex == 0
            ? HomeScreen(
                onNavigateToDownloads: () =>
                    setState(() => _selectedIndex = 1),
              )
            : const DownloadsScreen(),
      ),
    );
  }
}

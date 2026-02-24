import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'services/github_sync_state.dart';
import 'ui/app_shell.dart';
import 'ui/import/import_session_controller.dart';
import 'ui/import/import_session_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final appDataRoot = Directory(p.join(supportDir.path, 'combat_goblin'));
  runApp(CombatGoblinApp(appDataRoot: appDataRoot));
}

class CombatGoblinApp extends StatefulWidget {
  const CombatGoblinApp({super.key, required this.appDataRoot});

  final Directory appDataRoot;

  @override
  State<CombatGoblinApp> createState() => _CombatGoblinAppState();
}

class _CombatGoblinAppState extends State<CombatGoblinApp> {
  late final ImportSessionController _importController;

  @override
  void initState() {
    super.initState();
    _importController =
        ImportSessionController(appDataRoot: widget.appDataRoot);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final persistDir =
        Directory(p.join(widget.appDataRoot.path, 'session'));
    final persistService =
        SessionPersistenceService(storageRoot: persistDir.path);
    // Wire GitHubSyncStateService for SHA-based update detection.
    final syncService =
        GitHubSyncStateService(storageRoot: widget.appDataRoot.path);
    _importController.setGitHubSyncStateService(syncService);
    // Auto-restore last session on boot (fails silently)
    await _importController.initPersistenceAndRestore(persistService);
    // Non-blocking update check (fails silently)
    _importController.checkForUpdatesAsync();
  }

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ImportSessionProvider(
      controller: _importController,
      child: MaterialApp(
        title: 'Combat Goblin',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const AppShell(),
      ),
    );
  }
}

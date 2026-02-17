import 'package:flutter/material.dart';

import 'ui/import/import_session_controller.dart';
import 'ui/import/import_session_provider.dart';
import 'ui/import/import_wizard_screen.dart';
import 'ui/search/search_screen.dart';

void main() {
  runApp(const CombatGoblinApp());
}

class CombatGoblinApp extends StatefulWidget {
  const CombatGoblinApp({super.key});

  @override
  State<CombatGoblinApp> createState() => _CombatGoblinAppState();
}

class _CombatGoblinAppState extends State<CombatGoblinApp> {
  late final ImportSessionController _importController;

  @override
  void initState() {
    super.initState();
    _importController = ImportSessionController();
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
        home: const _AppNavigator(),
      ),
    );
  }
}

/// Handles navigation between Import and Search screens.
class _AppNavigator extends StatefulWidget {
  const _AppNavigator();

  @override
  State<_AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<_AppNavigator> {
  bool _showSearch = false;

  @override
  Widget build(BuildContext context) {
    final controller = ImportSessionProvider.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // Navigate to search when import succeeds
        if (controller.status == ImportStatus.success &&
            controller.indexBundles.isNotEmpty &&
            !_showSearch) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() => _showSearch = true);
          });
        }

        if (_showSearch && controller.indexBundles.isNotEmpty) {
          return SearchScreen.multi(
            indexBundles: controller.indexBundles,
          );
        }

        return ImportWizardScreen(
          onImportSuccess: () {
            if (controller.indexBundles.isNotEmpty) {
              setState(() => _showSearch = true);
            }
          },
        );
      },
    );
  }
}

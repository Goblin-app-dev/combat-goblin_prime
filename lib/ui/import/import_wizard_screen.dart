import 'package:flutter/material.dart';

import 'import_session_controller.dart';
import 'import_session_provider.dart';
import 'widgets/dependency_resolution_view.dart';
import 'widgets/file_picker_view.dart';
import 'widgets/import_progress_view.dart';

/// Import wizard screen for selecting files and building packs.
///
/// Shows different views based on ImportStatus:
/// - idle: File picker
/// - preparing/building: Progress indicator
/// - resolvingDeps: Dependency resolution
/// - success: Navigate to search (handled by parent)
/// - failed: Error with retry option
class ImportWizardScreen extends StatelessWidget {
  /// Callback when import succeeds.
  final VoidCallback? onImportSuccess;

  const ImportWizardScreen({
    super.key,
    this.onImportSuccess,
  });

  @override
  Widget build(BuildContext context) {
    final controller = ImportSessionProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Pack'),
        actions: [
          if (controller.status != ImportStatus.idle)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => controller.clear(),
              tooltip: 'Start over',
            ),
        ],
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          return _buildBody(context, controller);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, ImportSessionController controller) {
    switch (controller.status) {
      case ImportStatus.idle:
        return const GitHubCatalogPickerView();

      case ImportStatus.preparing:
      case ImportStatus.building:
        return ImportProgressView(
          statusMessage: controller.statusMessage ?? 'Working...',
        );

      case ImportStatus.resolvingDeps:
        return DependencyResolutionView(
          missingTargetIds: controller.missingTargetIds,
          resolvedCount: controller.resolvedCount,
          resolverError: controller.resolverError,
          hasAuthToken: controller.hasAuthToken,
          onResolveAutomatically: controller.sourceLocator != null
              ? () => controller.resolveDependencies()
              : null,
          onRetryBuild: controller.allDependenciesResolved
              ? () => controller.retryBuildWithResolvedDeps()
              : null,
          onSetAuthToken: (token) => controller.setAuthToken(token),
        );

      case ImportStatus.success:
        // Trigger callback and show success
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onImportSuccess?.call();
        });
        return _buildSuccessView(context, controller);

      case ImportStatus.failed:
        return _buildErrorView(context, controller);
    }
  }

  Widget _buildSuccessView(
    BuildContext context,
    ImportSessionController controller,
  ) {
    final bundles = controller.indexBundles;
    final packCount = bundles.length;

    // Aggregate stats across all bundles
    var totalUnits = 0;
    var totalWeapons = 0;
    var totalRules = 0;
    for (final bundle in bundles.values) {
      totalUnits += bundle.units.length;
      totalWeapons += bundle.weapons.length;
      totalRules += bundle.rules.length;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Colors.green,
            ),
            const SizedBox(height: 16),
            Text(
              packCount == 1
                  ? 'Import Complete'
                  : '$packCount Packs Imported',
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold),
            ),
            if (bundles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '$totalUnits units, '
                '$totalWeapons weapons, '
                '$totalRules rules',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onImportSuccess,
              icon: const Icon(Icons.search),
              label: const Text('Go to Search'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(
    BuildContext context,
    ImportSessionController controller,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            const Text(
              'Import Failed',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            if (controller.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                controller.errorMessage!,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => controller.attemptBuild(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => controller.clear(),
              child: const Text('Start Over'),
            ),
          ],
        ),
      ),
    );
  }
}

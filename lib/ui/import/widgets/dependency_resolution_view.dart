import 'package:flutter/material.dart';

/// View for resolving missing dependencies.
class DependencyResolutionView extends StatelessWidget {
  final List<String> missingTargetIds;
  final int resolvedCount;
  final VoidCallback? onResolveAutomatically;
  final VoidCallback? onRetryBuild;

  const DependencyResolutionView({
    super.key,
    required this.missingTargetIds,
    required this.resolvedCount,
    this.onResolveAutomatically,
    this.onRetryBuild,
  });

  @override
  Widget build(BuildContext context) {
    final allResolved = resolvedCount >= missingTargetIds.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Icon(
                allResolved ? Icons.check_circle : Icons.warning_amber,
                size: 32,
                color: allResolved ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      allResolved
                          ? 'Dependencies Resolved'
                          : 'Missing Dependencies',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Found $resolvedCount / ${missingTargetIds.length}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress indicator
          if (!allResolved)
            LinearProgressIndicator(
              value: missingTargetIds.isEmpty
                  ? 0
                  : resolvedCount / missingTargetIds.length,
            ),
          const SizedBox(height: 24),

          // Missing IDs list
          const Text(
            'Required Catalogs',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: missingTargetIds.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final targetId = missingTargetIds[index];
                final isResolved = index < resolvedCount;

                return ListTile(
                  leading: Icon(
                    isResolved ? Icons.check_circle : Icons.pending,
                    color: isResolved ? Colors.green : Colors.grey,
                  ),
                  title: Text(
                    targetId,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  subtitle: Text(isResolved ? 'Resolved' : 'Pending'),
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // Action buttons
          if (!allResolved && onResolveAutomatically != null) ...[
            FilledButton.icon(
              onPressed: onResolveAutomatically,
              icon: const Icon(Icons.cloud_download),
              label: const Text('Resolve from Repository'),
            ),
            const SizedBox(height: 8),
            Text(
              'Dependencies will be fetched from the configured BSData repository.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],

          if (!allResolved && onResolveAutomatically == null) ...[
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, size: 32),
                    SizedBox(height: 8),
                    Text(
                      'Manual Resolution Required',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'No repository configured. Please download the missing '
                      'catalog files manually and re-import.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (allResolved && onRetryBuild != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetryBuild,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Continue Import'),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:combat_goblin_prime/services/bsd_resolver_service.dart';

/// View for resolving missing dependencies.
class DependencyResolutionView extends StatefulWidget {
  final List<String> missingTargetIds;
  final int resolvedCount;
  final BsdResolverException? resolverError;
  final bool hasAuthToken;
  final VoidCallback? onResolveAutomatically;
  final VoidCallback? onRetryBuild;
  final void Function(String token)? onSetAuthToken;

  const DependencyResolutionView({
    super.key,
    required this.missingTargetIds,
    required this.resolvedCount,
    this.resolverError,
    this.hasAuthToken = false,
    this.onResolveAutomatically,
    this.onRetryBuild,
    this.onSetAuthToken,
  });

  @override
  State<DependencyResolutionView> createState() =>
      _DependencyResolutionViewState();
}

class _DependencyResolutionViewState extends State<DependencyResolutionView> {
  final _tokenController = TextEditingController();
  bool _showTokenField = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allResolved = widget.resolvedCount >= widget.missingTargetIds.length;
    final hasError = widget.resolverError != null;
    final isRateLimited =
        widget.resolverError?.code == BsdResolverErrorCode.rateLimitExceeded;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Icon(
                allResolved
                    ? Icons.check_circle
                    : (hasError ? Icons.error : Icons.warning_amber),
                size: 32,
                color: allResolved
                    ? Colors.green
                    : (hasError ? Colors.red : Colors.orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      allResolved
                          ? 'Dependencies Resolved'
                          : (hasError ? 'Resolution Error' : 'Missing Dependencies'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Found ${widget.resolvedCount} / ${widget.missingTargetIds.length}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Error message with actionable options
          if (hasError) ...[
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isRateLimited ? Icons.timer_off : Icons.error_outline,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.resolverError!.userMessage,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onErrorContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isRateLimited) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Options:',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '• Add a GitHub Personal Access Token below\n'
                        '• Manually download and add the missing catalogs\n'
                        '• Wait and try again later',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Progress indicator
          if (!allResolved && !hasError)
            LinearProgressIndicator(
              value: widget.missingTargetIds.isEmpty
                  ? 0
                  : widget.resolvedCount / widget.missingTargetIds.length,
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
              itemCount: widget.missingTargetIds.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final targetId = widget.missingTargetIds[index];
                final isResolved = index < widget.resolvedCount;

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

          // GitHub Token Section (shown on rate limit or when requested)
          if (isRateLimited || _showTokenField) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.key),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'GitHub Personal Access Token',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (widget.hasAuthToken)
                          const Chip(
                            label: Text('Configured'),
                            avatar: Icon(Icons.check, size: 16),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add a token to increase rate limits. '
                      'The token is stored in memory only.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tokenController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Token',
                        hintText: 'ghp_xxxx...',
                        prefixIcon: Icon(Icons.vpn_key),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _tokenController.text.isNotEmpty
                          ? () {
                              widget.onSetAuthToken?.call(_tokenController.text);
                              _tokenController.clear();
                            }
                          : null,
                      child: const Text('Set Token'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Action buttons
          if (!allResolved && widget.onResolveAutomatically != null && !hasError) ...[
            FilledButton.icon(
              onPressed: widget.onResolveAutomatically,
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

          // Retry button after error
          if (hasError && widget.onResolveAutomatically != null) ...[
            FilledButton.icon(
              onPressed: widget.onResolveAutomatically,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Resolution'),
            ),
            const SizedBox(height: 8),
          ],

          // Show token field toggle
          if (!isRateLimited && !_showTokenField && !allResolved) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => setState(() => _showTokenField = true),
              icon: const Icon(Icons.key),
              label: const Text('Add GitHub Token'),
            ),
          ],

          if (!allResolved && widget.onResolveAutomatically == null) ...[
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

          if (allResolved && widget.onRetryBuild != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: widget.onRetryBuild,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Continue Import'),
            ),
          ],
        ],
      ),
    );
  }
}

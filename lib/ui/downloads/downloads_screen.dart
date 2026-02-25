import 'package:flutter/material.dart';

import 'package:combat_goblin_prime/ui/downloads/faction_picker_screen.dart';
import 'package:combat_goblin_prime/ui/import/import_session_controller.dart';
import 'package:combat_goblin_prime/ui/import/import_session_provider.dart';

/// Default repository URL pre-loaded on first launch.
const _kDefaultRepoUrl = 'https://github.com/BSData/wh40k-10e';

/// Downloads screen for managing catalog slots.
///
/// Layout (top → bottom):
/// 1. Repo URL — read-only display + "Change" button. Auto-fetches tree on mount.
/// 2. "Load Game System Data" button — user-triggered; SHA-aware.
/// 3. Demo limitation banner.
/// 4. Slot panels — tappable → [FactionPickerScreen]; auto-load on faction pick.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final _urlController = TextEditingController(text: _kDefaultRepoUrl);

  // Tree browsing state
  RepoTreeResult? _repoTree;
  bool _fetchingTree = false;
  String? _treeFetchError;

  // URL edit mode
  bool _editingUrl = false;

  // Game system load state
  bool _fetchingGst = false;
  String? _gstPath; // which .gst path was loaded
  String? _gstLoadedBlobSha; // blob SHA at the time of last successful load

  @override
  void initState() {
    super.initState();
    // Auto-fetch the default repo tree on first mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchTree();
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  SourceLocator? _buildLocator() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != 'github.com') return null;
    final segments = uri.pathSegments;
    if (segments.length < 2) return null;
    return SourceLocator(
      sourceKey: '${segments[0]}_${segments[1]}',
      sourceUrl: 'https://github.com/${segments[0]}/${segments[1]}',
    );
  }

  Future<void> _fetchTree() async {
    final locator = _buildLocator();
    if (locator == null) {
      setState(() => _treeFetchError = 'Enter a valid GitHub repository URL.');
      return;
    }
    setState(() {
      _fetchingTree = true;
      _treeFetchError = null;
      _repoTree = null;
      _gstPath = null;
      _editingUrl = false;
    });

    final controller = ImportSessionProvider.of(context);
    final tree = await controller.loadRepoCatalogTree(locator);

    if (!mounted) return;
    setState(() {
      _fetchingTree = false;
      _repoTree = tree;
      if (tree == null) {
        _treeFetchError =
            controller.resolverError?.userMessage ?? 'Failed to fetch repository.';
      }
    });
  }

  /// Downloads the game system file (user-triggered).
  ///
  /// If the repo has exactly one `.gst`, uses it directly.
  /// If multiple `.gst` files exist, shows a picker dialog first.
  /// SHA-aware: stores [_gstLoadedBlobSha] for update detection.
  Future<void> _loadGameSystem() async {
    final locator = _buildLocator();
    final tree = _repoTree;
    if (locator == null || tree == null) return;

    final gstFiles = tree.gameSystemFiles;
    if (gstFiles.isEmpty) return;

    // Resolve which .gst to download.
    String? selectedPath;
    if (gstFiles.length == 1) {
      selectedPath = gstFiles.first.path;
    } else {
      selectedPath = await _showGstPickerDialog(gstFiles);
    }
    if (selectedPath == null || !mounted) return;

    final expectedSha = tree.pathToBlobSha[selectedPath];

    setState(() {
      _gstPath = selectedPath;
      _fetchingGst = true;
    });

    final controller = ImportSessionProvider.of(context);
    final success = await controller.fetchAndSetGameSystem(locator, selectedPath);

    if (!mounted) return;
    setState(() {
      _fetchingGst = false;
      if (success) _gstLoadedBlobSha = expectedSha;
    });
  }

  /// Shows a dialog for choosing among multiple `.gst` files.
  /// Returns the selected path, or null if dismissed.
  Future<String?> _showGstPickerDialog(List<RepoTreeEntry> gstFiles) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Game System'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: gstFiles.length,
            itemBuilder: (_, i) {
              final entry = gstFiles[i];
              final name = entry.path.split('/').last;
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(name),
                onTap: () => Navigator.of(ctx).pop(entry.path),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Navigates to [FactionPickerScreen] for the given slot.
  Future<void> _openFactionPicker(int slot) async {
    final locator = _buildLocator();
    if (locator == null) return;
    final tree = _repoTree;
    if (tree == null) return;

    final controller = ImportSessionProvider.of(context);
    final factions = controller.availableFactions(tree);
    final currentPath = controller.slotState(slot).catalogPath;

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FactionPickerScreen(
          slotIndex: slot,
          factions: factions,
          locator: locator,
          currentFactionPath: currentPath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ImportSessionProvider.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Determine game-system SHA state for button display.
        final currentSha = _gstPath != null
            ? _repoTree?.pathToBlobSha[_gstPath!]
            : null;
        final gstUpdateAvailable = controller.gameSystemFile != null &&
            _gstLoadedBlobSha != null &&
            currentSha != null &&
            _gstLoadedBlobSha != currentSha;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. Repo URL
            _RepoUrlSection(
              urlController: _urlController,
              fetching: _fetchingTree,
              error: _treeFetchError,
              editing: _editingUrl,
              onChangeRequested: () => setState(() => _editingUrl = true),
              onFetch: _fetchTree,
            ),
            const SizedBox(height: 12),

            // 2. Load Game System Data button
            _LoadGameSystemButton(
              treeAvailable: _repoTree != null,
              gameSystemLoaded: controller.gameSystemFile != null,
              gameSystemName: controller.gameSystemDisplayName,
              fetching: _fetchingGst,
              updateAvailable: gstUpdateAvailable,
              onLoad: _loadGameSystem,
            ),
            const SizedBox(height: 16),

            // 3. Demo limitation banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Demo: $kMaxSelectedCatalogs catalog slots. '
                      'More slots in a future release.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 4. Slot panels
            for (var i = 0; i < kMaxSelectedCatalogs; i++) ...[
              _SlotPanel(
                index: i,
                slotState: controller.slotState(i),
                hasGameSystem: controller.gameSystemFile != null,
                hasTree: _repoTree != null,
                onTap: (_repoTree != null && controller.gameSystemFile != null)
                    ? () => _openFactionPicker(i)
                    : null,
                onClear: () => controller.clearSlot(i),
                onRetry: () => controller.retrySlot(i),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _RepoUrlSection extends StatelessWidget {
  final TextEditingController urlController;
  final bool fetching;
  final String? error;
  final bool editing;
  final VoidCallback onChangeRequested;
  final VoidCallback onFetch;

  const _RepoUrlSection({
    required this.urlController,
    required this.fetching,
    this.error,
    required this.editing,
    required this.onChangeRequested,
    required this.onFetch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('GitHub Repository', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (editing)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: urlController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'https://github.com/BSData/wh40k-10e',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => onFetch(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: fetching ? null : onFetch,
                child: fetching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Fetch'),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: fetching
                      ? const Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Fetching…',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        )
                      : Text(
                          urlController.text,
                          style: Theme.of(context).textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: fetching ? null : onChangeRequested,
                child: const Text('Change'),
              ),
            ],
          ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: TextStyle(color: Colors.red.shade700, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// User-triggered "Load Game System Data" button.
///
/// States:
/// - No tree: disabled.
/// - Tree available, not loaded: primary filled button.
/// - Fetching: spinner.
/// - Loaded, up to date: outlined green chip (non-interactive).
/// - Loaded, update available: orange filled button.
class _LoadGameSystemButton extends StatelessWidget {
  final bool treeAvailable;
  final bool gameSystemLoaded;
  final String? gameSystemName;
  final bool fetching;
  final bool updateAvailable;
  final VoidCallback onLoad;

  const _LoadGameSystemButton({
    required this.treeAvailable,
    required this.gameSystemLoaded,
    this.gameSystemName,
    required this.fetching,
    required this.updateAvailable,
    required this.onLoad,
  });

  @override
  Widget build(BuildContext context) {
    if (fetching) {
      return const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Loading game system…'),
        ],
      );
    }

    if (gameSystemLoaded && !updateAvailable) {
      // Loaded and up to date — show confirmation, non-interactive.
      return Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              gameSystemName ?? 'Game System Loaded',
              style: const TextStyle(color: Colors.green),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    if (gameSystemLoaded && updateAvailable) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.orange,
        ),
        onPressed: onLoad,
        icon: const Icon(Icons.system_update),
        label: const Text('Update Available — Reload'),
      );
    }

    // Not loaded yet.
    return FilledButton.icon(
      onPressed: treeAvailable ? onLoad : null,
      icon: const Icon(Icons.download),
      label: const Text('Load Game System Data'),
    );
  }
}

class _SlotPanel extends StatelessWidget {
  final int index;
  final SlotState slotState;
  final bool hasGameSystem;
  final bool hasTree;

  /// Opens the faction picker. Null when not yet available.
  final VoidCallback? onTap;
  final VoidCallback onClear;

  /// Retries a failed slot that still has bytes. Null when not applicable.
  final VoidCallback? onRetry;

  const _SlotPanel({
    required this.index,
    required this.slotState,
    required this.hasGameSystem,
    required this.hasTree,
    this.onTap,
    required this.onClear,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final canTap = onTap != null &&
        slotState.status != SlotStatus.fetching &&
        slotState.status != SlotStatus.building;

    return Card(
      child: InkWell(
        onTap: canTap ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Text(
                    'Slot ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    status: slotState.status,
                    isBootRestoring: slotState.isBootRestoring,
                  ),
                  const Spacer(),
                  if (slotState.status != SlotStatus.empty &&
                      slotState.status != SlotStatus.fetching &&
                      slotState.status != SlotStatus.building)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: onClear,
                      tooltip: 'Clear slot',
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),

              // Body — status-dependent
              if (slotState.status == SlotStatus.empty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _buildEmptyBody(context),
                ),

              if (slotState.status == SlotStatus.fetching)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: slotState.isBootRestoring
                      ? Row(
                          children: [
                            Icon(Icons.restore,
                                size: 16,
                                color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'Restoring from snapshot…',
                              style: TextStyle(color: Colors.orange.shade700),
                            ),
                          ],
                        )
                      : const Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Downloading…'),
                          ],
                        ),
                ),

              if (slotState.status == SlotStatus.ready)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        slotState.catalogName ?? 'Ready',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      if (!hasGameSystem)
                        const Text(
                          'Load Game System Data first.',
                          style: TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                    ],
                  ),
                ),

              if (slotState.status == SlotStatus.building)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Building index…'),
                    ],
                  ),
                ),

              if (slotState.status == SlotStatus.loaded)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          slotState.catalogName ?? 'Loaded',
                          style: const TextStyle(color: Colors.green),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (canTap)
                        const Text(
                          'Tap to change',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                    ],
                  ),
                ),

              if (slotState.status == SlotStatus.error) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    slotState.errorMessage ?? 'An error occurred.',
                    style:
                        TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
                if (slotState.hasMissingDeps) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Missing dependencies '
                    '(${slotState.missingTargetIds.length}):',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  ...slotState.missingTargetIds.map(
                    (id) => Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        id,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.red.shade600,
                        ),
                      ),
                    ),
                  ),
                ],
                if (canTap || onRetry != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        if (canTap)
                          Text(
                            'Tap to try a different faction.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                          ),
                        if (onRetry != null && slotState.fetchedBytes != null) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: onRetry,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyBody(BuildContext context) {
    if (!hasTree) {
      return const Text(
        'Fetch a repository first.',
        style: TextStyle(color: Colors.grey),
      );
    }
    if (!hasGameSystem) {
      return const Text(
        'Load Game System Data first.',
        style: TextStyle(color: Colors.orange, fontSize: 12),
      );
    }
    return Row(
      children: [
        const Icon(Icons.touch_app, size: 16, color: Colors.grey),
        const SizedBox(width: 6),
        Text(
          'Tap to select a faction',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final SlotStatus status;

  /// When true and [status] == [SlotStatus.fetching], shows "Restoring"
  /// instead of "Fetching" to distinguish Phase-1 boot restore from a live
  /// network download.
  final bool isBootRestoring;

  const _StatusChip({required this.status, this.isBootRestoring = false});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      SlotStatus.empty => ('Empty', Colors.grey),
      SlotStatus.fetching =>
        isBootRestoring ? ('Restoring', Colors.orange) : ('Fetching', Colors.amber),
      SlotStatus.ready => ('Ready', Colors.blue),
      SlotStatus.building => ('Building', Colors.amber),
      SlotStatus.loaded => ('Loaded', Colors.green),
      SlotStatus.error => ('Error', Colors.red),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

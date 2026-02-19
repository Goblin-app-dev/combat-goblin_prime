import 'package:flutter/material.dart';

import 'package:combat_goblin_prime/ui/downloads/faction_picker_screen.dart';
import 'package:combat_goblin_prime/ui/import/import_session_controller.dart';
import 'package:combat_goblin_prime/ui/import/import_session_provider.dart';

/// Default repository URL pre-loaded on first launch.
const _kDefaultRepoUrl = 'https://github.com/BSData/wh40k-10e';

/// Downloads screen for managing catalog slots.
///
/// Layout:
/// - Repo URL (read-only display + "Change" button). Auto-fetches tree on mount.
/// - Game system selector (shown after tree fetch, hidden once loaded).
/// - Slot panels (tappable → [FactionPickerScreen]).
/// - Load All button (shown when any slot is in [SlotStatus.ready]).
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final _urlController = TextEditingController(text: _kDefaultRepoUrl);

  // View-local state for tree browsing
  RepoTreeResult? _repoTree;
  bool _fetchingTree = false;
  String? _treeFetchError;
  String? _selectedGstPath;
  bool _fetchingGst = false;

  /// When true, the URL field is editable; when false, it shows read-only.
  bool _editingUrl = false;

  @override
  void initState() {
    super.initState();
    // Auto-fetch the default repo on first load.
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
      _selectedGstPath = null;
      _editingUrl = false; // collapse URL editor after fetch
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

    // Auto-select game system if exactly one .gst exists.
    if (tree != null && tree.gameSystemFiles.length == 1) {
      await _selectGameSystem(tree.gameSystemFiles.first.path);
    }
  }

  Future<void> _selectGameSystem(String path) async {
    final locator = _buildLocator();
    if (locator == null) return;

    setState(() {
      _selectedGstPath = path;
      _fetchingGst = true;
    });

    final controller = ImportSessionProvider.of(context);
    await controller.fetchAndSetGameSystem(locator, path);

    if (!mounted) return;
    setState(() => _fetchingGst = false);
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
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- Repo URL ---
            _RepoUrlSection(
              urlController: _urlController,
              fetching: _fetchingTree,
              error: _treeFetchError,
              editing: _editingUrl,
              onChangeRequested: () => setState(() => _editingUrl = true),
              onFetch: _fetchTree,
            ),
            const SizedBox(height: 16),

            // --- Game System Selector ---
            if (_repoTree != null && controller.gameSystemFile == null) ...[
              _GameSystemSection(
                tree: _repoTree!,
                selectedPath: _selectedGstPath,
                fetching: _fetchingGst,
                onSelect: _selectGameSystem,
              ),
              const SizedBox(height: 16),
            ],

            // --- Game system loaded confirmation ---
            if (controller.gameSystemFile != null) ...[
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text(
                  controller.gameSystemDisplayName ??
                      controller.gameSystemFile!.fileName,
                ),
                subtitle: const Text('Game system loaded'),
                dense: true,
                tileColor: Colors.green.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // --- Demo limitation banner ---
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

            // --- Slot Panels ---
            for (var i = 0; i < kMaxSelectedCatalogs; i++) ...[
              _SlotPanel(
                index: i,
                slotState: controller.slotState(i),
                hasGameSystem: controller.gameSystemFile != null,
                hasTree: _repoTree != null,
                onTap: (_repoTree != null && controller.gameSystemFile != null)
                    ? () => _openFactionPicker(i)
                    : null,
                onLoad: () => controller.loadSlot(i),
                onClear: () => controller.clearSlot(i),
              ),
              const SizedBox(height: 12),
            ],

            // --- Load All Button ---
            if (controller.slots.any((s) => s.status == SlotStatus.ready)) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: controller.gameSystemFile != null
                    ? () => controller.loadAllReadySlots()
                    : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Load All Ready Slots'),
              ),
            ],
          ],
        );
      },
    );
  }
}

// --- Sub-widgets ---

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
          // Editable mode
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
          // Read-only mode
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                              'Fetching...',
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
          Text(error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
        ],
      ],
    );
  }
}

class _GameSystemSection extends StatelessWidget {
  final RepoTreeResult tree;
  final String? selectedPath;
  final bool fetching;
  final ValueChanged<String> onSelect;

  const _GameSystemSection({
    required this.tree,
    this.selectedPath,
    required this.fetching,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final gstFiles = tree.gameSystemFiles;
    if (gstFiles.isEmpty) {
      return const Text('No game system (.gst) files found in this repository.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Game System', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...gstFiles.map((entry) => ListTile(
              leading: fetching && selectedPath == entry.path
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.description_outlined),
              title: Text(entry.path.split('/').last),
              dense: true,
              onTap: fetching ? null : () => onSelect(entry.path),
            )),
      ],
    );
  }
}

class _SlotPanel extends StatelessWidget {
  final int index;
  final SlotState slotState;
  final bool hasGameSystem;
  final bool hasTree;

  /// Opens the faction picker. Null when picker is not available yet.
  final VoidCallback? onTap;
  final VoidCallback onLoad;
  final VoidCallback onClear;

  const _SlotPanel({
    required this.index,
    required this.slotState,
    required this.hasGameSystem,
    required this.hasTree,
    this.onTap,
    required this.onLoad,
    required this.onClear,
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
              // Header
              Row(
                children: [
                  Text(
                    'Slot ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: slotState.status),
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

              // Body: depends on status
              if (slotState.status == SlotStatus.empty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _buildEmptyBody(context),
                ),
              if (slotState.status == SlotStatus.fetching)
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
                      Text('Downloading…'),
                    ],
                  ),
                ),
              if (slotState.status == SlotStatus.ready)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          slotState.catalogName ?? 'Ready',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (!hasGameSystem)
                        const Text(
                          'Set game system to load.',
                          style: TextStyle(color: Colors.orange, fontSize: 12),
                        )
                      else
                        FilledButton(
                          onPressed: onLoad,
                          child: const Text('Load'),
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
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
                if (slotState.hasMissingDeps) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Missing dependencies (${slotState.missingTargetIds.length}):',
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
                if (canTap)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Tap to try a different faction.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
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
        'Select a game system first.',
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

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      SlotStatus.empty => ('Empty', Colors.grey),
      SlotStatus.fetching => ('Fetching', Colors.amber),
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
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

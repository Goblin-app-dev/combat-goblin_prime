import 'package:flutter/material.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/models/source_locator.dart';
import 'package:combat_goblin_prime/ui/import/import_session_controller.dart';
import 'package:combat_goblin_prime/ui/import/import_session_provider.dart';

/// Downloads screen for managing catalog slots.
///
/// Layout:
/// - GitHub repo URL input + Fetch button
/// - Game system selector (from fetched tree)
/// - Slot panels (one per [kMaxSelectedCatalogs])
/// - Load All button
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final _urlController = TextEditingController();

  // View-local state for tree browsing
  RepoTreeResult? _repoTree;
  bool _fetchingTree = false;
  String? _treeFetchError;
  String? _selectedGstPath;
  bool _fetchingGst = false;

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

  Future<void> _assignToSlot(int slot, String catPath) async {
    final locator = _buildLocator();
    if (locator == null) return;
    final controller = ImportSessionProvider.of(context);
    await controller.assignCatalogToSlot(slot, catPath, locator);
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
            // --- Repo URL Input ---
            _RepoUrlSection(
              urlController: _urlController,
              fetching: _fetchingTree,
              error: _treeFetchError,
              onFetch: _fetchTree,
            ),
            const SizedBox(height: 16),

            // --- Game System Selector ---
            if (_repoTree != null) ...[
              _GameSystemSection(
                tree: _repoTree!,
                selectedPath: _selectedGstPath,
                fetching: _fetchingGst,
                gameSystemFile: controller.gameSystemFile,
                onSelect: _selectGameSystem,
              ),
              const SizedBox(height: 16),
            ],

            // --- Slot Panels ---
            for (var i = 0; i < kMaxSelectedCatalogs; i++) ...[
              _SlotPanel(
                index: i,
                slotState: controller.slotState(i),
                catalogEntries: _repoTree?.catalogFiles ?? [],
                hasGameSystem: controller.gameSystemFile != null,
                onAssign: (path) => _assignToSlot(i, path),
                onLoad: () => controller.loadSlot(i),
                onClear: () => controller.clearSlot(i),
              ),
              const SizedBox(height: 12),
            ],

            // --- Load All Button ---
            if (controller.slots
                .any((s) => s.status == SlotStatus.ready)) ...[
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
  final VoidCallback onFetch;

  const _RepoUrlSection({
    required this.urlController,
    required this.fetching,
    this.error,
    required this.onFetch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('GitHub Repository', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: urlController,
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
  final SelectedFile? gameSystemFile;
  final ValueChanged<String> onSelect;

  const _GameSystemSection({
    required this.tree,
    this.selectedPath,
    required this.fetching,
    this.gameSystemFile,
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
        if (gameSystemFile != null)
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: Text(gameSystemFile!.fileName),
            subtitle: const Text('Loaded'),
            dense: true,
            tileColor: Colors.green.withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          )
        else
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
  final List<RepoTreeEntry> catalogEntries;
  final bool hasGameSystem;
  final ValueChanged<String> onAssign;
  final VoidCallback onLoad;
  final VoidCallback onClear;

  const _SlotPanel({
    required this.index,
    required this.slotState,
    required this.catalogEntries,
    required this.hasGameSystem,
    required this.onAssign,
    required this.onLoad,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
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
            if (slotState.status == SlotStatus.empty) ...[
              if (catalogEntries.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Fetch a repository to see available catalogs.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                _CatalogPicker(
                  entries: catalogEntries,
                  enabled: hasGameSystem,
                  onSelect: onAssign,
                ),
            ],
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
                    Text('Downloading...'),
                  ],
                ),
              ),
            if (slotState.status == SlotStatus.ready) ...[
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
                    FilledButton(
                      onPressed: hasGameSystem ? onLoad : null,
                      child: const Text('Load'),
                    ),
                  ],
                ),
              ),
              if (!hasGameSystem)
                const Text(
                  'Select a game system first.',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
            ],
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
                    Text('Building index...'),
                  ],
                ),
              ),
            if (slotState.status == SlotStatus.loaded)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${slotState.catalogName} - ready for search',
                  style: const TextStyle(color: Colors.green),
                ),
              ),
            if (slotState.status == SlotStatus.error)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  slotState.errorMessage ?? 'An error occurred.',
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
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

class _CatalogPicker extends StatelessWidget {
  final List<RepoTreeEntry> entries;
  final bool enabled;
  final ValueChanged<String> onSelect;

  const _CatalogPicker({
    required this.entries,
    required this.enabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Select a game system first.',
          style: TextStyle(color: Colors.orange, fontSize: 12),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final name = entry.path.split('/').last;
          return ListTile(
            leading: const Icon(Icons.description_outlined, size: 20),
            title: Text(name, style: const TextStyle(fontSize: 13)),
            dense: true,
            onTap: () => onSelect(entry.path),
          );
        },
      ),
    );
  }
}

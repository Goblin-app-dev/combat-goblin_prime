import 'package:flutter/material.dart';

import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';
import 'package:combat_goblin_prime/services/multi_pack_search_service.dart';
import 'package:combat_goblin_prime/ui/import/import_session_controller.dart';
import 'package:combat_goblin_prime/ui/import/import_session_provider.dart';

/// Home screen with 3-section vertical layout.
///
/// - **Top**: search bar (always visible)
/// - **Middle**: search results (expands)
/// - **Bottom**: slot status bar (fixed, shows loaded catalogs)
class HomeScreen extends StatefulWidget {
  /// Callback to navigate to the Downloads screen.
  final VoidCallback? onNavigateToDownloads;

  const HomeScreen({super.key, this.onNavigateToDownloads});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _multiPackService = MultiPackSearchService();

  MultiPackSearchResult? _result;
  List<String> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, IndexBundle> _activeBundles(ImportSessionController c) {
    // Combine slot-based and legacy indexBundles
    final bundles = <String, IndexBundle>{};
    bundles.addAll(c.slotIndexBundles);
    if (bundles.isEmpty) {
      bundles.addAll(c.indexBundles);
    }
    return bundles;
  }

  void _onChanged(String query) {
    final controller = ImportSessionProvider.of(context);
    final bundles = _activeBundles(controller);
    if (query.isEmpty || bundles.isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    final suggestions = _multiPackService.suggest(bundles, query, limit: 8);
    setState(() {
      _suggestions = suggestions;
      _showSuggestions = suggestions.isNotEmpty;
    });
  }

  void _search(String query) {
    final controller = ImportSessionProvider.of(context);
    final bundles = _activeBundles(controller);
    if (query.isEmpty || bundles.isEmpty) {
      setState(() {
        _result = null;
        _showSuggestions = false;
      });
      return;
    }
    final result = _multiPackService.search(
      bundles,
      SearchRequest(text: query, limit: 50, sort: SearchSort.relevance),
    );
    setState(() {
      _result = result;
      _showSuggestions = false;
    });
  }

  void _selectSuggestion(String suggestion) {
    _searchController.text = suggestion;
    _search(suggestion);
  }

  /// Returns display names of all loaded catalog slots (for stats view).
  List<String> _loadedFactionNames(ImportSessionController controller) {
    return [
      for (var i = 0; i < kMaxSelectedCatalogs; i++)
        if (controller.slotState(i).status == SlotStatus.loaded)
          controller.slotState(i).catalogName ?? 'Slot ${i + 1}',
    ];
  }

  void _showHitDetail(BuildContext context, MultiPackSearchHit hit) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hit.displayName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('Type: ${hit.docType.name}'),
            Text('ID: ${hit.docId}'),
            Text('Key: ${hit.canonicalKey}'),
            Text('Pack: ${hit.sourcePackKey}'),
            const SizedBox(height: 16),
            Text(
              'Match: ${hit.matchReasons.map((r) => r.name).join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
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
        return Column(
          children: [
            // --- Top: Search Bar ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: _activeBundles(controller).isEmpty
                          ? 'Load catalogs to search...'
                          : 'Search units, weapons, rules...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _onChanged('');
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      enabled: _activeBundles(controller).isNotEmpty,
                    ),
                    onChanged: _onChanged,
                    onSubmitted: _search,
                    textInputAction: TextInputAction.search,
                  ),
                  if (_showSuggestions && _suggestions.isNotEmpty)
                    Material(
                      elevation: 4,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _suggestions.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            leading: const Icon(Icons.history, size: 18),
                            title: Text(_suggestions[index]),
                            dense: true,
                            onTap: () =>
                                _selectSuggestion(_suggestions[index]),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

            // --- Middle: Results ---
            Expanded(child: _buildResults(controller)),

            // --- Bottom: Slot Status Bar ---
            _SlotStatusBar(
              controller: controller,
              onTap: widget.onNavigateToDownloads,
            ),
          ],
        );
      },
    );
  }

  Widget _buildResults(ImportSessionController controller) {
    final bundles = _activeBundles(controller);

    if (bundles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text('No catalogs loaded'),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: widget.onNavigateToDownloads,
              icon: const Icon(Icons.download),
              label: const Text('Go to Downloads'),
            ),
          ],
        ),
      );
    }

    if (_result == null) {
      // Show aggregate stats
      var totalUnits = 0;
      var totalWeapons = 0;
      var totalRules = 0;
      for (final bundle in bundles.values) {
        totalUnits += bundle.units.length;
        totalWeapons += bundle.weapons.length;
        totalRules += bundle.rules.length;
      }
      final packCount = bundles.length;
      final packLabel = packCount == 1 ? 'Pack' : 'Packs';
      final gameSystemName = controller.gameSystemDisplayName;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            if (gameSystemName != null) ...[
              Text(
                gameSystemName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              '$packCount $packLabel Loaded',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            // Show loaded faction names per slot
            ..._loadedFactionNames(controller).map(
              (name) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$totalUnits units · $totalWeapons weapons · $totalRules rules',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            const Text(
              'Start typing to search',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_result!.hits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No results found'),
            if (_result!.diagnostics.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _result!.diagnostics.first.message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _result!.hits.length,
      itemBuilder: (context, index) {
        final hit = _result!.hits[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: _buildTypeIcon(hit.docType),
            title: Text(hit.displayName),
            subtitle: Text(
              '${hit.docType.name} • ${hit.sourcePackKey}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showHitDetail(context, hit),
          ),
        );
      },
    );
  }

  Widget _buildTypeIcon(SearchDocType type) {
    final (icon, color) = switch (type) {
      SearchDocType.unit => (Icons.person, Colors.blue),
      SearchDocType.weapon => (Icons.gavel, Colors.orange),
      SearchDocType.rule => (Icons.menu_book, Colors.green),
    };
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.2),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

/// Bottom bar showing loaded slot status.
class _SlotStatusBar extends StatelessWidget {
  final ImportSessionController controller;
  final VoidCallback? onTap;

  const _SlotStatusBar({required this.controller, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              for (var i = 0; i < kMaxSelectedCatalogs; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _SlotChip(slot: controller.slotState(i), index: i)),
              ],
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  final SlotState slot;
  final int index;

  const _SlotChip({required this.slot, required this.index});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (slot.status) {
      SlotStatus.empty => ('Slot ${index + 1}: Empty', Colors.grey, Icons.add_circle_outline),
      SlotStatus.fetching => ('Fetching...', Colors.amber, Icons.downloading),
      SlotStatus.ready => (slot.catalogName ?? 'Ready', Colors.blue, Icons.check_circle_outline),
      SlotStatus.building => ('Building...', Colors.amber, Icons.build_circle),
      SlotStatus.loaded => (slot.catalogName ?? 'Loaded', Colors.green, Icons.check_circle),
      SlotStatus.error => ('Error', Colors.red, Icons.error_outline),
    };

    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: color),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

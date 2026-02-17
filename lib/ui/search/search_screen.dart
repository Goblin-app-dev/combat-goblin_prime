import 'package:flutter/material.dart';

import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';
import 'package:combat_goblin_prime/services/multi_pack_search_service.dart';

/// Search screen supporting multiple IndexBundles.
///
/// When multiple bundles are provided, results are merged deterministically
/// using [MultiPackSearchService].
class SearchScreen extends StatefulWidget {
  /// Single index bundle (legacy support).
  @Deprecated('Use indexBundles instead for multi-pack support')
  final IndexBundle? indexBundle;

  /// Multiple index bundles keyed by pack identifier.
  final Map<String, IndexBundle>? indexBundles;

  /// Order of bundle keys for deterministic merging.
  /// Defaults to alphabetical if not provided.
  final List<String>? bundleOrder;

  const SearchScreen({
    super.key,
    @Deprecated('Use indexBundles instead') this.indexBundle,
    this.indexBundles,
    this.bundleOrder,
  }) : assert(
          indexBundle != null || indexBundles != null,
          'Either indexBundle or indexBundles must be provided',
        );

  /// Creates a search screen for a single index bundle.
  factory SearchScreen.single({
    Key? key,
    required IndexBundle indexBundle,
  }) {
    return SearchScreen(
      key: key,
      indexBundles: {'default': indexBundle},
      bundleOrder: const ['default'],
    );
  }

  /// Creates a search screen for multiple index bundles.
  factory SearchScreen.multi({
    Key? key,
    required Map<String, IndexBundle> indexBundles,
    List<String>? bundleOrder,
  }) {
    return SearchScreen(
      key: key,
      indexBundles: indexBundles,
      bundleOrder: bundleOrder,
    );
  }

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _multiPackService = MultiPackSearchService();

  MultiPackSearchResult? _result;
  List<String> _suggestions = [];
  bool _showSuggestions = false;

  /// Resolved bundles map.
  Map<String, IndexBundle> get _bundles {
    if (widget.indexBundles != null) {
      return widget.indexBundles!;
    }
    // ignore: deprecated_member_use_from_same_package
    if (widget.indexBundle != null) {
      // ignore: deprecated_member_use_from_same_package
      return {'default': widget.indexBundle!};
    }
    return const {};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    // Get suggestions for autocomplete across all bundles
    final suggestions = _multiPackService.suggest(
      _bundles,
      query,
      limit: 8,
    );

    setState(() {
      _suggestions = suggestions;
      _showSuggestions = suggestions.isNotEmpty;
    });
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _result = null;
        _showSuggestions = false;
      });
      return;
    }

    final request = SearchRequest(
      text: query,
      limit: 50,
      sort: SearchSort.relevance,
    );

    final result = _multiPackService.search(
      _bundles,
      request,
      bundleOrder: widget.bundleOrder,
    );

    setState(() {
      _result = result;
      _showSuggestions = false;
    });
  }

  void _selectSuggestion(String suggestion) {
    _searchController.text = suggestion;
    _performSearch(suggestion);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search units, weapons, rules...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: _onSearchChanged,
                  onSubmitted: _performSearch,
                  textInputAction: TextInputAction.search,
                ),

                // Suggestions dropdown
                if (_showSuggestions && _suggestions.isNotEmpty)
                  Material(
                    elevation: 4,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _suggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(suggestion),
                          onTap: () => _selectSuggestion(suggestion),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Results
          Expanded(
            child: _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_result == null) {
      return _buildIndexSummary();
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
        return _MultiPackSearchResultCard(
          hit: hit,
          showPackInfo: _bundles.length > 1,
        );
      },
    );
  }

  Widget _buildIndexSummary() {
    // Aggregate stats across all bundles
    var totalUnits = 0;
    var totalWeapons = 0;
    var totalRules = 0;

    for (final bundle in _bundles.values) {
      totalUnits += bundle.units.length;
      totalWeapons += bundle.weapons.length;
      totalRules += bundle.rules.length;
    }

    final packCount = _bundles.length;
    final packLabel = packCount == 1 ? 'Pack' : 'Packs';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              '$packCount $packLabel Loaded',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '$totalUnits units, '
              '$totalWeapons weapons, '
              '$totalRules rules',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            const Text(
              'Start typing to search',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card displaying a multi-pack search result.
class _MultiPackSearchResultCard extends StatelessWidget {
  final MultiPackSearchHit hit;
  final bool showPackInfo;

  const _MultiPackSearchResultCard({
    required this.hit,
    this.showPackInfo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _buildTypeIcon(),
        title: Text(hit.displayName),
        subtitle: Text(
          _buildSubtitle(),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showDetail(context),
      ),
    );
  }

  String _buildSubtitle() {
    final parts = <String>[
      hit.docType.name,
      _formatMatchReasons(),
    ];
    if (showPackInfo) {
      parts.add(hit.sourcePackKey);
    }
    return parts.join(' • ');
  }

  Widget _buildTypeIcon() {
    IconData icon;
    Color color;

    switch (hit.docType) {
      case SearchDocType.unit:
        icon = Icons.person;
        color = Colors.blue;
      case SearchDocType.weapon:
        icon = Icons.gavel;
        color = Colors.orange;
      case SearchDocType.rule:
        icon = Icons.menu_book;
        color = Colors.green;
    }

    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.2),
      child: Icon(icon, color: color, size: 20),
    );
  }

  String _formatMatchReasons() {
    return hit.matchReasons.map((r) {
      switch (r) {
        case MatchReason.canonicalKeyMatch:
          return 'name';
        case MatchReason.keywordMatch:
          return 'keyword';
        case MatchReason.characteristicMatch:
          return 'stat';
        case MatchReason.fuzzyMatch:
          return 'fuzzy';
      }
    }).join(', ');
  }

  void _showDetail(BuildContext context) {
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
            if (showPackInfo) Text('Pack: ${hit.sourcePackKey}'),
            const SizedBox(height: 16),
            Text(
              'Match reasons: ${_formatMatchReasons()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

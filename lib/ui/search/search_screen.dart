import 'package:flutter/material.dart';

import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';

/// Search screen using M10 StructuredSearchService.
class SearchScreen extends StatefulWidget {
  final IndexBundle indexBundle;

  const SearchScreen({
    super.key,
    required this.indexBundle,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _searchService = StructuredSearchService();

  SearchResult? _result;
  List<String> _suggestions = [];
  bool _showSuggestions = false;

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

    // Get suggestions for autocomplete
    final suggestions = _searchService.suggest(
      widget.indexBundle,
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

    final result = _searchService.search(widget.indexBundle, request);

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
        return _SearchResultCard(hit: hit);
      },
    );
  }

  Widget _buildIndexSummary() {
    final index = widget.indexBundle;
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
              'Pack Loaded',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${index.units.length} units, '
              '${index.weapons.length} weapons, '
              '${index.rules.length} rules',
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

/// Card displaying a single search result.
class _SearchResultCard extends StatelessWidget {
  final SearchHit hit;

  const _SearchResultCard({required this.hit});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _buildTypeIcon(),
        title: Text(hit.displayName),
        subtitle: Text(
          '${hit.docType.name} • ${_formatMatchReasons()}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showDetail(context),
      ),
    );
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:combat_goblin_prime/features/github_repository_search/github_repository_search.dart';

/// A full-screen picker that lets the user search GitHub for BSData
/// (BattleScribe) game-catalog repositories and choose one.
///
/// Returns the GitHub URL string of the selected repository via
/// [Navigator.pop], or `null` if the user dismisses without picking.
///
/// Usage:
/// ```dart
/// final url = await Navigator.of(context).push<String>(
///   MaterialPageRoute(builder: (_) => const GitHubCatalogPickerScreen()),
/// );
/// ```
class GitHubCatalogPickerScreen extends StatefulWidget {
  const GitHubCatalogPickerScreen({super.key}) : _service = null;

  /// Constructor for testing — injects a pre-built [GitHubRepositorySearchService].
  const GitHubCatalogPickerScreen.withService(
    GitHubRepositorySearchService service, {
    super.key,
  }) : _service = service;

  final GitHubRepositorySearchService? _service;

  @override
  State<GitHubCatalogPickerScreen> createState() =>
      _GitHubCatalogPickerScreenState();
}

class _GitHubCatalogPickerScreenState
    extends State<GitHubCatalogPickerScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  late final GitHubRepositorySearchService _service;

  List<RepoSummary> _results = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _nextPageToken;
  bool _isLastPage = true;

  /// Debounce timer for the search-as-you-type field.
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _service = widget._service ??
        GitHubRepositorySearchServiceHttp(
          client: http.Client(),
          queryBuilder: GitHubQueryBuilder(),
        );
    _scrollController.addListener(_onScroll);
    // Kick off initial browse (no text filter).
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Search logic
  // ---------------------------------------------------------------------------

  void _onTextChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search(value.trim());
    });
  }

  Future<void> _search(String text) async {
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
      _nextPageToken = null;
      _isLastPage = true;
    });

    try {
      final page = await _service.search(
        query: RepoSearchQuery(
          text: text.isEmpty ? null : text,
          mode: RepoSearchMode.bsdataDiscovery,
          sort: RepoSearchSort.stars,
          order: SortOrder.desc,
        ),
      );

      if (!mounted) return;
      setState(() {
        _results = page.items;
        _nextPageToken = page.nextPageToken;
        _isLastPage = page.isLastPage;
        _loading = false;
      });
    } on RepoSearchException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _messageForError(e.error);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unexpected error — please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _isLastPage || _nextPageToken == null) return;
    setState(() => _loadingMore = true);

    try {
      final page = await _service.search(
        query: RepoSearchQuery(
          text: _searchController.text.trim().isEmpty
              ? null
              : _searchController.text.trim(),
          mode: RepoSearchMode.bsdataDiscovery,
          sort: RepoSearchSort.stars,
          order: SortOrder.desc,
        ),
        pageCursor: _nextPageToken,
      );

      if (!mounted) return;
      setState(() {
        _results = [..._results, ...page.items];
        _nextPageToken = page.nextPageToken;
        _isLastPage = page.isLastPage;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _pick(RepoSummary repo) {
    Navigator.of(context).pop(repo.htmlUrl.toString());
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Catalog Repository'),
      ),
      body: Column(
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              autofocus: false,
              decoration: const InputDecoration(
                hintText: 'Search BattleScribe catalogs on GitHub…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: _onTextChanged,
            ),
          ),

          // Loading indicator (initial load only)
          if (_loading) const LinearProgressIndicator(),

          // Body
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _search(_searchController.text.trim()),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text(
          'No repositories found.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: _results.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _results.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final repo = _results[index];
        return _RepoTile(repo: repo, onTap: () => _pick(repo));
      },
    );
  }

  String _messageForError(RepoSearchError error) => switch (error) {
        RepoSearchError.rateLimited =>
          'GitHub rate limit reached — please wait a moment and try again.',
        RepoSearchError.unauthorized =>
          'GitHub authentication failed.',
        RepoSearchError.forbidden =>
          'Access forbidden — check your GitHub credentials.',
        RepoSearchError.networkFailure =>
          'Network error — check your internet connection.',
        RepoSearchError.serverFailure =>
          'GitHub server error — please try again later.',
        RepoSearchError.invalidQuery =>
          'Invalid search query.',
        RepoSearchError.invalidResponse =>
          'Unexpected response from GitHub.',
      };
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _RepoTile extends StatelessWidget {
  final RepoSummary repo;
  final VoidCallback onTap;

  const _RepoTile({required this.repo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final updatedAgo = _relativeTime(repo.updatedAt);

    return ListTile(
      leading: const Icon(Icons.book_outlined),
      title: Text(
        repo.fullName,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (repo.description != null)
            Text(
              repo.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          const SizedBox(height: 2),
          Row(
            children: [
              const Icon(Icons.star_outline, size: 12),
              const SizedBox(width: 2),
              Text(
                '${repo.stargazersCount}',
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.update, size: 12),
              const SizedBox(width: 2),
              Text(
                updatedAgo,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
      isThreeLine: repo.description != null,
      onTap: onTap,
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inDays > 365) {
      return '${(diff.inDays / 365).floor()}y ago';
    }
    if (diff.inDays > 30) {
      return '${(diff.inDays / 30).floor()}mo ago';
    }
    if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    }
    if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    }
    return 'just now';
  }
}

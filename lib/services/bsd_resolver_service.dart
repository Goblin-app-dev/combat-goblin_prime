import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:combat_goblin_prime/modules/m1_acquire/models/source_locator.dart';

/// Result of indexing a BSData repository.
class RepoIndexResult {
  /// Maps targetId → repository file path (e.g., "Imperium - Space Marines.cat").
  final Map<String, String> targetIdToPath;

  /// Files that could not be parsed (for diagnostics).
  final List<String> unparsedFiles;

  const RepoIndexResult({
    required this.targetIdToPath,
    required this.unparsedFiles,
  });
}

/// Service for resolving missing dependencies from BSData GitHub repositories.
///
/// Implements a 2-tier resolution strategy:
/// - **Tier A**: Session cache for targetId → repoPath mapping
/// - **Tier B**: Build mapping using Trees API + Range header partial fetches
///
/// Rate limit aware: builds mapping efficiently using partial content fetches.
class BsdResolverService {
  /// Session cache: targetId → repoPath for each source.
  final Map<String, Map<String, String>> _repoIndexCache = {};

  /// HTTP client (injectable for testing).
  final http.Client _client;

  /// Bytes to fetch for id extraction (2KB is plenty for XML root element).
  static const int _rangeBytes = 2048;

  BsdResolverService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches catalog bytes for a given targetId from a BSData repo.
  ///
  /// Returns null if the targetId cannot be resolved.
  Future<Uint8List?> fetchCatalogBytes({
    required SourceLocator sourceLocator,
    required String targetId,
  }) async {
    if (sourceLocator.sourceUrl.isEmpty) {
      return null;
    }

    // Ensure we have the repo index
    final index = await _ensureRepoIndex(sourceLocator);
    if (index == null) return null;

    // Look up path for targetId
    final path = index[targetId];
    if (path == null) return null;

    // Fetch full file content
    return _fetchFileContent(sourceLocator, path);
  }

  /// Builds and caches the repository index for a source.
  ///
  /// Returns the targetId → path mapping, or null on failure.
  Future<Map<String, String>?> _ensureRepoIndex(
    SourceLocator sourceLocator,
  ) async {
    final cacheKey = sourceLocator.sourceKey;

    // Check cache first
    if (_repoIndexCache.containsKey(cacheKey)) {
      return _repoIndexCache[cacheKey];
    }

    // Build index from repo
    final result = await buildRepoIndex(sourceLocator);
    if (result == null) return null;

    _repoIndexCache[cacheKey] = result.targetIdToPath;
    return result.targetIdToPath;
  }

  /// Builds repository index by fetching Trees API and parsing catalog ids.
  ///
  /// Uses Range header to fetch only first N bytes of each .cat file,
  /// then parses the root element to extract the catalogue id.
  Future<RepoIndexResult?> buildRepoIndex(SourceLocator sourceLocator) async {
    if (sourceLocator.sourceUrl.isEmpty) return null;

    // Parse owner/repo from URL
    final repoInfo = _parseGitHubUrl(sourceLocator.sourceUrl);
    if (repoInfo == null) return null;

    final (owner, repo) = repoInfo;
    final branch = sourceLocator.branch ?? 'main';

    // Fetch tree using GitHub API
    final treeUrl = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/git/trees/$branch?recursive=1',
    );

    final treeResponse = await _client.get(treeUrl, headers: {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    });

    if (treeResponse.statusCode != 200) {
      return null;
    }

    final treeData = json.decode(treeResponse.body) as Map<String, dynamic>;
    final tree = treeData['tree'] as List<dynamic>? ?? [];

    // Find all .cat files
    final catFiles = <String>[];
    for (final item in tree) {
      final path = item['path'] as String? ?? '';
      final type = item['type'] as String? ?? '';
      if (type == 'blob' && path.endsWith('.cat')) {
        catFiles.add(path);
      }
    }

    // Build targetId → path mapping
    final targetIdToPath = <String, String>{};
    final unparsedFiles = <String>[];

    for (final path in catFiles) {
      final targetId = await _extractCatalogId(owner, repo, branch, path);
      if (targetId != null) {
        targetIdToPath[targetId] = path;
      } else {
        unparsedFiles.add(path);
      }
    }

    return RepoIndexResult(
      targetIdToPath: targetIdToPath,
      unparsedFiles: unparsedFiles,
    );
  }

  /// Extracts the catalogue id from a .cat file using partial fetch.
  ///
  /// Uses HTTP Range header to fetch only first N bytes,
  /// then parses the root element to extract id attribute.
  Future<String?> _extractCatalogId(
    String owner,
    String repo,
    String branch,
    String path,
  ) async {
    // Use raw.githubusercontent.com for direct file access
    final rawUrl = Uri.parse(
      'https://raw.githubusercontent.com/$owner/$repo/$branch/$path',
    );

    try {
      final response = await _client.get(rawUrl, headers: {
        'Range': 'bytes=0-${_rangeBytes - 1}',
      });

      // Server may return 200 (full content) or 206 (partial content)
      if (response.statusCode != 200 && response.statusCode != 206) {
        return null;
      }

      final content = response.body;
      return _parseIdFromXmlHead(content);
    } catch (e) {
      return null;
    }
  }

  /// Parses the catalogue id from XML content head.
  ///
  /// Uses simple string scanning for robustness with partial/truncated XML.
  /// Looks for: <catalogue id="..." or <gameSystem id="..."
  String? _parseIdFromXmlHead(String content) {
    // Pattern: <catalogue ... id="VALUE" or <gameSystem ... id="VALUE"
    // We look for id= after the opening tag

    final catalogueMatch = RegExp(r'<catalogue\s+[^>]*id="([^"]+)"')
        .firstMatch(content);
    if (catalogueMatch != null) {
      return catalogueMatch.group(1);
    }

    final gameSystemMatch = RegExp(r'<gameSystem\s+[^>]*id="([^"]+)"')
        .firstMatch(content);
    if (gameSystemMatch != null) {
      return gameSystemMatch.group(1);
    }

    return null;
  }

  /// Fetches full file content from the repository.
  Future<Uint8List?> _fetchFileContent(
    SourceLocator sourceLocator,
    String path,
  ) async {
    final repoInfo = _parseGitHubUrl(sourceLocator.sourceUrl);
    if (repoInfo == null) return null;

    final (owner, repo) = repoInfo;
    final branch = sourceLocator.branch ?? 'main';

    final rawUrl = Uri.parse(
      'https://raw.githubusercontent.com/$owner/$repo/$branch/$path',
    );

    try {
      final response = await _client.get(rawUrl);

      if (response.statusCode != 200) {
        return null;
      }

      return response.bodyBytes;
    } catch (e) {
      return null;
    }
  }

  /// Parses GitHub URL to extract owner and repo.
  ///
  /// Supports: https://github.com/owner/repo
  (String, String)? _parseGitHubUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    if (uri.host != 'github.com') return null;

    final segments = uri.pathSegments;
    if (segments.length < 2) return null;

    return (segments[0], segments[1]);
  }

  /// Clears the session cache.
  void clearCache() {
    _repoIndexCache.clear();
  }

  /// Gets cached index for a source (for debugging/testing).
  Map<String, String>? getCachedIndex(String sourceKey) {
    return _repoIndexCache[sourceKey];
  }

  /// Pre-populates the index for specific targetIds (early termination).
  ///
  /// Stops indexing once all needed targetIds are found.
  Future<Map<String, String>?> buildPartialIndex(
    SourceLocator sourceLocator,
    Set<String> neededTargetIds, {
    void Function(int found, int needed)? onProgress,
  }) async {
    if (sourceLocator.sourceUrl.isEmpty) return null;

    final repoInfo = _parseGitHubUrl(sourceLocator.sourceUrl);
    if (repoInfo == null) return null;

    final (owner, repo) = repoInfo;
    final branch = sourceLocator.branch ?? 'main';

    // Fetch tree
    final treeUrl = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/git/trees/$branch?recursive=1',
    );

    final treeResponse = await _client.get(treeUrl, headers: {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    });

    if (treeResponse.statusCode != 200) {
      return null;
    }

    final treeData = json.decode(treeResponse.body) as Map<String, dynamic>;
    final tree = treeData['tree'] as List<dynamic>? ?? [];

    final catFiles = <String>[];
    for (final item in tree) {
      final path = item['path'] as String? ?? '';
      final type = item['type'] as String? ?? '';
      if (type == 'blob' && path.endsWith('.cat')) {
        catFiles.add(path);
      }
    }

    final targetIdToPath = <String, String>{};
    final remaining = Set<String>.from(neededTargetIds);

    for (final path in catFiles) {
      if (remaining.isEmpty) break; // Early termination

      final targetId = await _extractCatalogId(owner, repo, branch, path);
      if (targetId != null) {
        targetIdToPath[targetId] = path;
        remaining.remove(targetId);
        onProgress?.call(
          neededTargetIds.length - remaining.length,
          neededTargetIds.length,
        );
      }
    }

    // Cache partial results
    final cacheKey = sourceLocator.sourceKey;
    _repoIndexCache[cacheKey] = {
      ...(_repoIndexCache[cacheKey] ?? {}),
      ...targetIdToPath,
    };

    return targetIdToPath;
  }
}

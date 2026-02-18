import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:combat_goblin_prime/modules/m1_acquire/models/source_locator.dart';

/// Entry in the repository tree with path and blob SHA.
class RepoTreeEntry {
  /// Repository file path (e.g., "Imperium - Space Marines.cat").
  final String path;

  /// GitHub blob SHA for this file.
  final String blobSha;

  /// File extension (.gst or .cat).
  final String extension;

  const RepoTreeEntry({
    required this.path,
    required this.blobSha,
    required this.extension,
  });

  /// Returns true if this is a game system file.
  bool get isGameSystem => extension == '.gst';

  /// Returns true if this is a catalog file.
  bool get isCatalog => extension == '.cat';
}

/// Result of fetching repository tree.
class RepoTreeResult {
  /// All .gst and .cat files in the repository.
  final List<RepoTreeEntry> entries;

  /// Timestamp when tree was fetched.
  final DateTime fetchedAt;

  const RepoTreeResult({
    required this.entries,
    required this.fetchedAt,
  });

  /// Returns only game system files.
  List<RepoTreeEntry> get gameSystemFiles =>
      entries.where((e) => e.isGameSystem).toList();

  /// Returns only catalog files.
  List<RepoTreeEntry> get catalogFiles =>
      entries.where((e) => e.isCatalog).toList();

  /// Returns a map of path → blobSha for all entries.
  Map<String, String> get pathToBlobSha =>
      {for (final e in entries) e.path: e.blobSha};
}

/// Result of indexing a BSData repository.
class RepoIndexResult {
  /// Maps targetId → repository file path (e.g., "Imperium - Space Marines.cat").
  final Map<String, String> targetIdToPath;

  /// Maps path → blobSha for update detection.
  final Map<String, String> pathToBlobSha;

  /// Maps targetId → blobSha for efficient lookup.
  final Map<String, String> targetIdToBlobSha;

  /// Files that could not be parsed (for diagnostics).
  final List<String> unparsedFiles;

  const RepoIndexResult({
    required this.targetIdToPath,
    required this.pathToBlobSha,
    required this.targetIdToBlobSha,
    required this.unparsedFiles,
  });
}

/// Error codes for BSD resolver failures.
enum BsdResolverErrorCode {
  /// GitHub rate limit exceeded (403/429).
  rateLimitExceeded,

  /// Resource not found (404).
  notFound,

  /// Network timeout.
  timeout,

  /// Other network error.
  networkError,
}

/// Exception thrown when BSD resolution fails.
class BsdResolverException implements Exception {
  final BsdResolverErrorCode code;
  final String message;
  final int? statusCode;

  const BsdResolverException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => 'BsdResolverException($code): $message';

  /// User-friendly message for UI display.
  String get userMessage {
    switch (code) {
      case BsdResolverErrorCode.rateLimitExceeded:
        return 'GitHub rate limit reached. Use manual add, or add a token.';
      case BsdResolverErrorCode.notFound:
        return 'Repository or branch not found.';
      case BsdResolverErrorCode.timeout:
        return 'Request timed out. Please try again.';
      case BsdResolverErrorCode.networkError:
        return 'Network error. Please check your connection.';
    }
  }
}

/// Service for resolving missing dependencies from BSData GitHub repositories.
///
/// Implements a 2-tier resolution strategy:
/// - **Tier A**: Session cache for targetId → repoPath mapping
/// - **Tier B**: Build mapping using Trees API + Range header partial fetches
///
/// Rate limit aware: builds mapping efficiently using partial content fetches.
/// Includes timeouts and retry policy for reliability.
class BsdResolverService {
  /// Session cache: targetId → repoPath for each source.
  final Map<String, Map<String, String>> _repoIndexCache = {};

  /// HTTP client (injectable for testing).
  final http.Client _client;

  /// Optional Personal Access Token for authenticated requests.
  String? _authToken;

  /// Bytes to fetch for id extraction (2KB is plenty for XML root element).
  static const int _rangeBytes = 2048;

  /// Timeout for GitHub Trees API requests.
  static const Duration _treesTimeout = Duration(seconds: 15);

  /// Timeout for Range/content fetch requests.
  static const Duration _fetchTimeout = Duration(seconds: 10);

  /// Maximum retries for transient network errors.
  static const int _maxRetries = 1;

  /// Last error encountered (for UI display).
  BsdResolverException? _lastError;

  BsdResolverService({http.Client? client}) : _client = client ?? http.Client();

  /// Gets the last error encountered during resolution.
  BsdResolverException? get lastError => _lastError;

  /// Sets the Personal Access Token for authenticated requests.
  ///
  /// Token is stored in memory only - not persisted.
  void setAuthToken(String? token) {
    _authToken = token?.trim().isEmpty == true ? null : token?.trim();
  }

  /// Returns true if an auth token is configured.
  bool get hasAuthToken => _authToken != null;

  /// Fetches catalog bytes for a given targetId from a BSData repo.
  ///
  /// Returns null if the targetId cannot be resolved.
  /// Throws [BsdResolverException] on rate limit or other errors.
  Future<Uint8List?> fetchCatalogBytes({
    required SourceLocator sourceLocator,
    required String targetId,
  }) async {
    _lastError = null;

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

  /// Fetches the repository tree with all .gst and .cat files.
  ///
  /// Returns tree entries with blob SHAs for update detection.
  /// Throws [BsdResolverException] on rate limit or network errors.
  Future<RepoTreeResult?> fetchRepoTree(SourceLocator sourceLocator) async {
    _lastError = null;

    if (sourceLocator.sourceUrl.isEmpty) return null;

    final repoInfo = _parseGitHubUrl(sourceLocator.sourceUrl);
    if (repoInfo == null) return null;

    final (owner, repo) = repoInfo;
    final branch = sourceLocator.branch ?? 'main';

    final treeUrl = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/git/trees/$branch?recursive=1',
    );

    final treeResponse = await _fetchWithRetry(
      treeUrl,
      headers: _buildApiHeaders(),
      timeout: _treesTimeout,
    );

    if (treeResponse == null) {
      return null;
    }

    if (treeResponse.statusCode != 200) {
      _handleErrorResponse(treeResponse.statusCode, 'Trees API');
      return null;
    }

    final treeData = json.decode(treeResponse.body) as Map<String, dynamic>;
    final tree = treeData['tree'] as List<dynamic>? ?? [];

    final entries = <RepoTreeEntry>[];
    for (final item in tree) {
      final path = item['path'] as String? ?? '';
      final type = item['type'] as String? ?? '';
      final sha = item['sha'] as String? ?? '';

      if (type == 'blob') {
        if (path.endsWith('.cat')) {
          entries.add(RepoTreeEntry(
            path: path,
            blobSha: sha,
            extension: '.cat',
          ));
        } else if (path.endsWith('.gst')) {
          entries.add(RepoTreeEntry(
            path: path,
            blobSha: sha,
            extension: '.gst',
          ));
        }
      }
    }

    return RepoTreeResult(
      entries: entries,
      fetchedAt: DateTime.now().toUtc(),
    );
  }

  /// Builds repository index by fetching Trees API and parsing catalog ids.
  ///
  /// Uses Range header to fetch only first N bytes of each .cat file,
  /// then parses the root element to extract the catalogue id.
  /// Also captures blob SHAs for update detection.
  ///
  /// Throws [BsdResolverException] on rate limit or network errors.
  Future<RepoIndexResult?> buildRepoIndex(SourceLocator sourceLocator) async {
    _lastError = null;

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

    final treeResponse = await _fetchWithRetry(
      treeUrl,
      headers: _buildApiHeaders(),
      timeout: _treesTimeout,
    );

    if (treeResponse == null) {
      return null;
    }

    if (treeResponse.statusCode != 200) {
      _handleErrorResponse(treeResponse.statusCode, 'Trees API');
      return null;
    }

    final treeData = json.decode(treeResponse.body) as Map<String, dynamic>;
    final tree = treeData['tree'] as List<dynamic>? ?? [];

    // Find all .cat files and capture blob SHAs
    final catFiles = <String, String>{}; // path → blobSha
    for (final item in tree) {
      final path = item['path'] as String? ?? '';
      final type = item['type'] as String? ?? '';
      final sha = item['sha'] as String? ?? '';
      if (type == 'blob' && path.endsWith('.cat')) {
        catFiles[path] = sha;
      }
    }

    // Build targetId → path mapping
    final targetIdToPath = <String, String>{};
    final targetIdToBlobSha = <String, String>{};
    final pathToBlobSha = <String, String>{};
    final unparsedFiles = <String>[];

    for (final entry in catFiles.entries) {
      final path = entry.key;
      final blobSha = entry.value;
      pathToBlobSha[path] = blobSha;

      final targetId = await _extractCatalogId(owner, repo, branch, path);
      if (targetId != null) {
        targetIdToPath[targetId] = path;
        targetIdToBlobSha[targetId] = blobSha;
      } else {
        unparsedFiles.add(path);
      }
    }

    return RepoIndexResult(
      targetIdToPath: targetIdToPath,
      pathToBlobSha: pathToBlobSha,
      targetIdToBlobSha: targetIdToBlobSha,
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
      final response = await _fetchWithRetry(
        rawUrl,
        headers: {
          'Range': 'bytes=0-${_rangeBytes - 1}',
          ..._buildRawHeaders(),
        },
        timeout: _fetchTimeout,
      );

      if (response == null) {
        return null;
      }

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
      final response = await _fetchWithRetry(
        rawUrl,
        headers: _buildRawHeaders(),
        timeout: _fetchTimeout,
      );

      if (response == null) {
        return null;
      }

      if (response.statusCode != 200) {
        _handleErrorResponse(response.statusCode, 'file fetch');
        return null;
      }

      return response.bodyBytes;
    } catch (e) {
      return null;
    }
  }

  /// Performs HTTP GET with retry policy.
  ///
  /// Retries once on transient network errors.
  /// Does NOT retry on 403, 404, or 429 responses.
  Future<http.Response?> _fetchWithRetry(
    Uri url, {
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    int attempts = 0;

    while (attempts <= _maxRetries) {
      attempts++;

      try {
        final response = await _client
            .get(url, headers: headers)
            .timeout(timeout);

        // Don't retry on rate limit or not found
        if (response.statusCode == 403 ||
            response.statusCode == 404 ||
            response.statusCode == 429) {
          return response;
        }

        // Success or other error - return response
        if (response.statusCode == 200 || response.statusCode == 206) {
          return response;
        }

        // Server error - might be transient, retry if attempts remain
        if (attempts > _maxRetries) {
          return response;
        }

        // Wait before retry (100ms backoff)
        await Future<void>.delayed(const Duration(milliseconds: 100));
      } on TimeoutException {
        if (attempts > _maxRetries) {
          _lastError = const BsdResolverException(
            code: BsdResolverErrorCode.timeout,
            message: 'Request timed out',
          );
          return null;
        }
        // Retry on timeout
        await Future<void>.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        if (attempts > _maxRetries) {
          _lastError = BsdResolverException(
            code: BsdResolverErrorCode.networkError,
            message: e.toString(),
          );
          return null;
        }
        // Retry on network error
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    return null;
  }

  /// Handles error responses and sets [_lastError].
  void _handleErrorResponse(int statusCode, String context) {
    if (statusCode == 403 || statusCode == 429) {
      _lastError = BsdResolverException(
        code: BsdResolverErrorCode.rateLimitExceeded,
        message: 'GitHub rate limit exceeded during $context',
        statusCode: statusCode,
      );
    } else if (statusCode == 404) {
      _lastError = BsdResolverException(
        code: BsdResolverErrorCode.notFound,
        message: 'Resource not found during $context',
        statusCode: statusCode,
      );
    } else {
      _lastError = BsdResolverException(
        code: BsdResolverErrorCode.networkError,
        message: 'HTTP $statusCode during $context',
        statusCode: statusCode,
      );
    }
  }

  /// Builds headers for GitHub API requests.
  Map<String, String> _buildApiHeaders() {
    return {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };
  }

  /// Builds headers for raw content requests.
  Map<String, String> _buildRawHeaders() {
    if (_authToken != null) {
      return {'Authorization': 'Bearer $_authToken'};
    }
    return {};
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

  /// Downloads the full content of a repository file by path.
  ///
  /// Returns raw bytes only. No storage side effects.
  /// Clears [lastError] before each call; sets it on failure.
  ///
  /// Used by [ImportSessionController.importFromGitHub] to download
  /// .gst and .cat files after the caller has already fetched the repo tree.
  Future<Uint8List?> fetchFileByPath(
    SourceLocator sourceLocator,
    String path,
  ) async {
    _lastError = null;
    return _fetchFileContent(sourceLocator, path);
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
  ///
  /// Throws [BsdResolverException] on rate limit or network errors.
  Future<Map<String, String>?> buildPartialIndex(
    SourceLocator sourceLocator,
    Set<String> neededTargetIds, {
    void Function(int found, int needed)? onProgress,
  }) async {
    _lastError = null;

    if (sourceLocator.sourceUrl.isEmpty) return null;

    final repoInfo = _parseGitHubUrl(sourceLocator.sourceUrl);
    if (repoInfo == null) return null;

    final (owner, repo) = repoInfo;
    final branch = sourceLocator.branch ?? 'main';

    // Fetch tree
    final treeUrl = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/git/trees/$branch?recursive=1',
    );

    final treeResponse = await _fetchWithRetry(
      treeUrl,
      headers: _buildApiHeaders(),
      timeout: _treesTimeout,
    );

    if (treeResponse == null) {
      return null;
    }

    if (treeResponse.statusCode != 200) {
      _handleErrorResponse(treeResponse.statusCode, 'Trees API');
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

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/services/bsd_resolver_service.dart';
import 'package:combat_goblin_prime/services/github_sync_state.dart';
import 'package:combat_goblin_prime/services/session_persistence_service.dart';

export 'package:combat_goblin_prime/services/bsd_resolver_service.dart'
    show BsdResolverException, BsdResolverErrorCode, RepoTreeEntry, RepoTreeResult;
export 'package:combat_goblin_prime/services/session_persistence_service.dart'
    show PersistedSession, SessionPersistenceService;

/// Build status for import workflow.
enum ImportStatus {
  /// Initial state, waiting for file selection.
  idle,

  /// Preparing pack storage (scanning files).
  preparing,

  /// Resolving missing dependencies from BSData.
  resolvingDeps,

  /// Running pipeline (M2-M9).
  building,

  /// Build succeeded, IndexBundle available.
  success,

  /// Build failed with error.
  failed,
}

/// Selected file for import.
class SelectedFile {
  final String fileName;
  final Uint8List bytes;

  /// Absolute file path (for session persistence).
  final String? filePath;

  /// Root ID extracted from the file (catalogue/gameSystem id attribute).
  final String? rootId;

  const SelectedFile({
    required this.fileName,
    required this.bytes,
    this.filePath,
    this.rootId,
  });

  /// Creates a copy with updated fields.
  SelectedFile copyWith({
    String? fileName,
    Uint8List? bytes,
    String? filePath,
    String? rootId,
  }) {
    return SelectedFile(
      fileName: fileName ?? this.fileName,
      bytes: bytes ?? this.bytes,
      filePath: filePath ?? this.filePath,
      rootId: rootId ?? this.rootId,
    );
  }
}

/// Maximum number of user-selected primary catalogs.
const int kMaxSelectedCatalogs = 3;

/// Controller for import session state.
///
/// Manages:
/// - Selected files (game system, up to 3 primary catalogs)
/// - Missing target IDs during dependency resolution
/// - Build status progression
/// - Cached BoundPackBundle and IndexBundle (per catalog)
/// - Repo mapping cache for BSData resolution
///
/// ## Multi-Catalog Support
///
/// Users may select up to [kMaxSelectedCatalogs] primary catalogs.
/// Each selected catalog runs the M1-M9 pipeline independently,
/// producing its own [IndexBundle]. Dependencies (library catalogs)
/// are auto-resolved and do NOT count toward the 3-catalog limit.
///
/// Uses ChangeNotifier for minimal state management without external deps.
class ImportSessionController extends ChangeNotifier {
  // --- File Selection ---

  SelectedFile? _gameSystemFile;
  SelectedFile? get gameSystemFile => _gameSystemFile;

  /// Selected primary catalogs (max [kMaxSelectedCatalogs]).
  List<SelectedFile> _selectedCatalogs = const [];
  List<SelectedFile> get selectedCatalogs => List.unmodifiable(_selectedCatalogs);

  /// Legacy accessor for single-catalog compatibility.
  /// Returns the first selected catalog, or null if none selected.
  @Deprecated('Use selectedCatalogs instead for multi-catalog support')
  SelectedFile? get primaryCatalogFile =>
      _selectedCatalogs.isNotEmpty ? _selectedCatalogs.first : null;

  // --- Build State ---

  ImportStatus _status = ImportStatus.idle;
  ImportStatus get status => _status;

  String? _statusMessage;
  String? get statusMessage => _statusMessage;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // --- Dependency Resolution ---

  List<String> _missingTargetIds = const [];
  List<String> get missingTargetIds => _missingTargetIds;

  /// Progress: found X / needed Y during dependency resolution.
  int _resolvedCount = 0;
  int get resolvedCount => _resolvedCount;

  // --- Cached Bundles ---

  /// Raw bundles per selected catalog (keyed by catalog rootId or index).
  final Map<String, RawPackBundle> _rawBundles = {};
  Map<String, RawPackBundle> get rawBundles => Map.unmodifiable(_rawBundles);

  /// Bound bundles per selected catalog.
  final Map<String, BoundPackBundle> _boundBundles = {};
  Map<String, BoundPackBundle> get boundBundles => Map.unmodifiable(_boundBundles);

  /// Index bundles per selected catalog.
  final Map<String, IndexBundle> _indexBundles = {};
  Map<String, IndexBundle> get indexBundles => Map.unmodifiable(_indexBundles);

  /// Legacy accessor for single-bundle compatibility.
  @Deprecated('Use rawBundles instead for multi-catalog support')
  RawPackBundle? get rawBundle =>
      _rawBundles.isNotEmpty ? _rawBundles.values.first : null;

  /// Legacy accessor for single-bundle compatibility.
  @Deprecated('Use boundBundles instead for multi-catalog support')
  BoundPackBundle? get boundBundle =>
      _boundBundles.isNotEmpty ? _boundBundles.values.first : null;

  /// Legacy accessor for single-bundle compatibility.
  @Deprecated('Use indexBundles instead for multi-catalog support')
  IndexBundle? get indexBundle =>
      _indexBundles.isNotEmpty ? _indexBundles.values.first : null;

  // --- Resolved Dependencies Cache ---

  /// Cached dependency bytes resolved during this session.
  /// Maps targetId → bytes.
  final Map<String, Uint8List> _resolvedDependencies = {};
  Map<String, Uint8List> get resolvedDependencies =>
      Map.unmodifiable(_resolvedDependencies);

  // --- Source Locator ---

  SourceLocator? _sourceLocator;
  SourceLocator? get sourceLocator => _sourceLocator;

  // --- Services ---

  final BsdResolverService _bsdResolver;
  SessionPersistenceService? _persistenceService;
  GitHubSyncStateService? _gitHubSyncStateService;

  // --- Rate Limit State ---

  /// Last resolver error encountered (for UI display).
  BsdResolverException? _resolverError;
  BsdResolverException? get resolverError => _resolverError;

  // --- Session Persistence ---

  /// Whether a previous session is available for reload.
  bool _hasPersistedSession = false;
  bool get hasPersistedSession => _hasPersistedSession;

  /// The persisted session (if loaded).
  PersistedSession? _persistedSession;
  PersistedSession? get persistedSession => _persistedSession;

  final Directory? _appDataRoot;

  ImportSessionController({
    Directory? appDataRoot,
    BsdResolverService? bsdResolver,
    SessionPersistenceService? persistenceService,
    GitHubSyncStateService? gitHubSyncStateService,
  })  : _appDataRoot = appDataRoot,
        _bsdResolver = bsdResolver ?? BsdResolverService(),
        _persistenceService = persistenceService,
        _gitHubSyncStateService = gitHubSyncStateService;

  /// Sets the persistence service and checks for existing session.
  Future<void> initPersistence(SessionPersistenceService service) async {
    _persistenceService = service;
    await _checkForPersistedSession();
  }

  Future<void> _checkForPersistedSession() async {
    if (_persistenceService == null) return;

    final session = await _persistenceService!.loadValidSession();
    _persistedSession = session;
    _hasPersistedSession = session != null;
    notifyListeners();
  }

  /// Sets the GitHub Personal Access Token for authenticated requests.
  ///
  /// Token is stored in memory only - not persisted.
  void setAuthToken(String? token) {
    _bsdResolver.setAuthToken(token);
    notifyListeners();
  }

  /// Returns true if an auth token is configured.
  bool get hasAuthToken => _bsdResolver.hasAuthToken;

  // --- GitHub Import Methods ---

  /// Fetches the repository tree for catalog browsing.
  ///
  /// Returns a [RepoTreeResult] with .gst and .cat entries sorted
  /// lexicographically by path. Returns null on failure.
  ///
  /// Does NOT change [ImportStatus]; tree browsing is view-local state.
  /// Sets [resolverError] on failure so the view can display it inline.
  /// Idempotent: re-calling with the same locator makes a new fetch but
  /// does not accumulate side effects.
  Future<RepoTreeResult?> loadRepoCatalogTree(
    SourceLocator sourceLocator,
  ) async {
    _resolverError = null;
    final result = await _bsdResolver.fetchRepoTree(sourceLocator);
    if (_bsdResolver.lastError != null) {
      _resolverError = _bsdResolver.lastError;
      notifyListeners();
      return null;
    }
    if (result == null) return null;
    // Return entries sorted lexicographically by path (determinism requirement).
    final sortedEntries = result.entries.toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return RepoTreeResult(
      entries: sortedEntries,
      fetchedAt: result.fetchedAt,
    );
  }

  /// Downloads selected .gst and .cat files from GitHub and runs the pipeline.
  ///
  /// Deterministic failure policy:
  /// - .gst download failure → [ImportStatus.failed], return immediately
  /// - Any .cat download failure → [ImportStatus.failed], return immediately
  /// - Dep resolution failure after pipeline → [ImportStatus.resolvingDeps]
  ///   with missing list stable-sorted; no partial index build
  ///
  /// Enforces [kMaxSelectedCatalogs]: throws [ArgumentError] if
  /// catPaths.length > kMaxSelectedCatalogs.
  ///
  /// Catalogs are sorted lexicographically by path before processing,
  /// ensuring deterministic order regardless of caller-provided ordering.
  Future<void> importFromGitHub({
    required SourceLocator sourceLocator,
    required String gstPath,
    required List<String> catPaths,
    required RepoTreeResult repoTree,
  }) async {
    if (catPaths.length > kMaxSelectedCatalogs) {
      throw ArgumentError(
        'Cannot import more than $kMaxSelectedCatalogs catalogs. '
        'Got ${catPaths.length}.',
      );
    }

    // Sort locally for deterministic processing regardless of input order.
    final sortedCatPaths = List<String>.of(catPaths)..sort();

    _sourceLocator = sourceLocator;
    _status = ImportStatus.preparing;
    _statusMessage = 'Downloading game system...';
    _errorMessage = null;
    _resolverError = null;
    notifyListeners();

    // Download .gst (failure = abort entire flow)
    final gstBytes =
        await _bsdResolver.fetchFileByPath(sourceLocator, gstPath);
    if (gstBytes == null) {
      _resolverError = _bsdResolver.lastError;
      _status = ImportStatus.failed;
      _errorMessage =
          _resolverError?.userMessage ?? 'Failed to download game system.';
      _statusMessage = null;
      notifyListeners();
      return;
    }

    // Download each .cat (any failure = abort entire flow)
    final catFiles = <SelectedFile>[];
    for (var i = 0; i < sortedCatPaths.length; i++) {
      final path = sortedCatPaths[i];
      _statusMessage =
          'Downloading catalog ${i + 1}/${sortedCatPaths.length}...';
      notifyListeners();

      final bytes =
          await _bsdResolver.fetchFileByPath(sourceLocator, path);
      if (bytes == null) {
        _resolverError = _bsdResolver.lastError;
        _status = ImportStatus.failed;
        _errorMessage = _resolverError?.userMessage ??
            'Failed to download: ${path.split('/').last}';
        _statusMessage = null;
        notifyListeners();
        return;
      }

      catFiles.add(SelectedFile(
        fileName: path.split('/').last,
        bytes: bytes,
      ));
    }

    // Install downloaded files into controller state
    _gameSystemFile = SelectedFile(
      fileName: gstPath.split('/').last,
      bytes: gstBytes,
    );
    _selectedCatalogs = List.unmodifiable(catFiles);
    _rawBundles.clear();
    _boundBundles.clear();
    _indexBundles.clear();
    _resolvedDependencies.clear();
    _missingTargetIds = const [];

    // Run M1-M9 pipeline for each catalog
    _statusMessage = 'Building catalogs...';
    notifyListeners();
    await attemptBuild();

    // Auto-resolve dependencies if pipeline flagged missing deps
    if (_status == ImportStatus.resolvingDeps) {
      await resolveDependencies();
    }

    // On success, persist sync state with blob SHAs from the provided tree
    if (_status == ImportStatus.success &&
        _gitHubSyncStateService != null) {
      await _persistGitHubSyncState(
        sourceLocator: sourceLocator,
        gstPath: gstPath,
        catPaths: sortedCatPaths,
        repoTree: repoTree,
      );
    }
  }

  /// Persists GitHub sync state after a successful import.
  Future<void> _persistGitHubSyncState({
    required SourceLocator sourceLocator,
    required String gstPath,
    required List<String> catPaths,
    required RepoTreeResult repoTree,
  }) async {
    final service = _gitHubSyncStateService;
    if (service == null) return;

    final now = DateTime.now().toUtc();
    final pathToBlobSha = repoTree.pathToBlobSha;

    // Ensure repo entry exists before updating individual files
    await service.updateRepoState(
      sourceLocator.sourceKey,
      RepoSyncState(
        repoUrl: sourceLocator.sourceUrl,
        branch: sourceLocator.branch ?? 'main',
        lastTreeFetchAt: repoTree.fetchedAt,
      ),
    );

    // Track .gst
    final gstSha = pathToBlobSha[gstPath];
    if (gstSha != null) {
      await service.updateTrackedFile(
        sourceLocator.sourceKey,
        TrackedFile(
          repoPath: gstPath,
          fileType: 'gst',
          blobSha: gstSha,
          lastCheckedAt: now,
        ),
      );
    }

    // Track each .cat
    for (final path in catPaths) {
      final sha = pathToBlobSha[path];
      if (sha != null) {
        await service.updateTrackedFile(
          sourceLocator.sourceKey,
          TrackedFile(
            repoPath: path,
            fileType: 'cat',
            blobSha: sha,
            lastCheckedAt: now,
          ),
        );
      }
    }

    // Persist session pack state
    final primaryRootIds = _selectedCatalogs
        .map((f) => f.rootId)
        .whereType<String>()
        .toList();
    await service.updateSessionPack(SessionPackState(
      selectedPrimaryRootIds: primaryRootIds,
      indexBuiltAt: now,
    ));
  }

  // --- File Selection Methods ---

  void setGameSystemFile(SelectedFile file) {
    _gameSystemFile = file;
    _reset();
    notifyListeners();
  }

  /// Sets selected catalogs (replaces all).
  ///
  /// Throws [ArgumentError] if more than [kMaxSelectedCatalogs] catalogs.
  void setSelectedCatalogs(List<SelectedFile> catalogs) {
    if (catalogs.length > kMaxSelectedCatalogs) {
      throw ArgumentError(
        'Cannot select more than $kMaxSelectedCatalogs catalogs. '
        'Got ${catalogs.length}.',
      );
    }
    _selectedCatalogs = List.unmodifiable(catalogs);
    _reset();
    notifyListeners();
  }

  /// Adds a catalog to the selection.
  ///
  /// Returns false if already at max capacity.
  bool addSelectedCatalog(SelectedFile catalog) {
    if (_selectedCatalogs.length >= kMaxSelectedCatalogs) {
      return false;
    }
    _selectedCatalogs = List.unmodifiable([..._selectedCatalogs, catalog]);
    _reset();
    notifyListeners();
    return true;
  }

  /// Removes a catalog from the selection by index.
  void removeSelectedCatalog(int index) {
    if (index < 0 || index >= _selectedCatalogs.length) return;
    final updated = List<SelectedFile>.from(_selectedCatalogs)..removeAt(index);
    _selectedCatalogs = List.unmodifiable(updated);
    _reset();
    notifyListeners();
  }

  /// Legacy single-catalog setter for compatibility.
  @Deprecated('Use setSelectedCatalogs instead for multi-catalog support')
  void setPrimaryCatalogFile(SelectedFile file) {
    setSelectedCatalogs([file]);
  }

  void setSourceLocator(SourceLocator locator) {
    _sourceLocator = locator;
    notifyListeners();
  }

  /// Clear all state and start fresh.
  void clear() {
    _gameSystemFile = null;
    _selectedCatalogs = const [];
    _sourceLocator = null;
    _reset();
    notifyListeners();
  }

  void _reset() {
    _status = ImportStatus.idle;
    _statusMessage = null;
    _errorMessage = null;
    _missingTargetIds = const [];
    _resolvedCount = 0;
    _rawBundles.clear();
    _boundBundles.clear();
    _indexBundles.clear();
    _resolvedDependencies.clear();
    _resolverError = null;
  }

  // --- Build Methods ---

  /// Attempts to build bundles for all selected catalogs.
  ///
  /// Each selected catalog runs the M1-M9 pipeline independently.
  /// On missing dependencies, transitions to [ImportStatus.resolvingDeps]
  /// and populates [missingTargetIds].
  ///
  /// On success, runs full pipeline for each catalog and caches IndexBundles.
  Future<void> attemptBuild() async {
    if (_gameSystemFile == null || _selectedCatalogs.isEmpty) {
      _errorMessage = 'Please select a game system and at least one catalog.';
      _status = ImportStatus.failed;
      notifyListeners();
      return;
    }

    _status = ImportStatus.preparing;
    _statusMessage = 'Preparing pack storage...';
    _errorMessage = null;
    notifyListeners();

    // Build each selected catalog independently
    final allMissingIds = <String>{};

    for (var i = 0; i < _selectedCatalogs.length; i++) {
      final catalog = _selectedCatalogs[i];
      final catalogKey = catalog.rootId ?? 'catalog_$i';

      // Skip if already built
      if (_indexBundles.containsKey(catalogKey)) continue;

      _statusMessage = 'Building catalog ${i + 1}/${_selectedCatalogs.length}...';
      notifyListeners();

      try {
        final acquireService = AcquireService(
          storage: AcquireStorage(appDataRoot: _appDataRoot),
        );

        final rawBundle = await acquireService.buildBundle(
          gameSystemBytes: _gameSystemFile!.bytes,
          gameSystemExternalFileName: _gameSystemFile!.fileName,
          primaryCatalogBytes: catalog.bytes,
          primaryCatalogExternalFileName: catalog.fileName,
          requestDependencyBytes: _requestDependencyBytes,
          source: _sourceLocator ?? _defaultSourceLocator(),
        );

        _rawBundles[catalogKey] = rawBundle;
        await _runPipeline(rawBundle, catalogKey);
      } on AcquireFailure catch (e) {
        if (e.missingTargetIds.isNotEmpty) {
          allMissingIds.addAll(e.missingTargetIds);
        } else {
          _status = ImportStatus.failed;
          _errorMessage = 'Catalog ${catalog.fileName}: ${e.message}';
          _statusMessage = null;
          notifyListeners();
          return;
        }
      } catch (e) {
        _status = ImportStatus.failed;
        _errorMessage = 'Catalog ${catalog.fileName}: $e';
        _statusMessage = null;
        notifyListeners();
        return;
      }
    }

    // If any missing dependencies, transition to resolution
    if (allMissingIds.isNotEmpty) {
      _missingTargetIds = List.unmodifiable(allMissingIds.toList()..sort());
      _status = ImportStatus.resolvingDeps;
      _statusMessage =
          'Finding dependencies... (0/${_missingTargetIds.length})';
      notifyListeners();
      return;
    }

    // All catalogs built successfully
    if (_indexBundles.length == _selectedCatalogs.length) {
      _status = ImportStatus.success;
      _statusMessage = null;
      notifyListeners();
      await _saveSession();
    }
  }

  /// Resolves missing dependencies using BSData resolver.
  ///
  /// After resolution, retries build.
  /// On rate limit errors, transitions to resolvingDeps with error info.
  Future<void> resolveDependencies() async {
    if (_missingTargetIds.isEmpty) return;
    if (_sourceLocator == null) {
      _errorMessage = 'No source locator configured for BSData resolution.';
      _status = ImportStatus.failed;
      notifyListeners();
      return;
    }

    _status = ImportStatus.resolvingDeps;
    _resolvedCount = 0;
    _resolverError = null;
    notifyListeners();

    try {
      for (final targetId in _missingTargetIds) {
        if (_resolvedDependencies.containsKey(targetId)) {
          _resolvedCount++;
          _statusMessage =
              'Finding dependencies... ($_resolvedCount/${_missingTargetIds.length})';
          notifyListeners();
          continue;
        }

        final bytes = await _bsdResolver.fetchCatalogBytes(
          sourceLocator: _sourceLocator!,
          targetId: targetId,
        );

        // Check for rate limit or other errors
        if (_bsdResolver.lastError != null) {
          _resolverError = _bsdResolver.lastError;
          _statusMessage = null;
          // Stay in resolvingDeps status so user can add token or manual deps
          notifyListeners();
          return;
        }

        if (bytes != null) {
          _resolvedDependencies[targetId] = bytes;
          _resolvedCount++;
          _statusMessage =
              'Finding dependencies... ($_resolvedCount/${_missingTargetIds.length})';
          notifyListeners();
        }
      }

      // Check if all dependencies were resolved
      if (allDependenciesResolved) {
        // Retry build with resolved dependencies
        _missingTargetIds = const [];
        await attemptBuild();
      } else {
        // Some dependencies couldn't be found
        _statusMessage = null;
        notifyListeners();
      }
    } catch (e) {
      _status = ImportStatus.failed;
      _errorMessage = 'Failed to resolve dependencies: $e';
      _statusMessage = null;
      notifyListeners();
    }
  }

  /// Manually provide bytes for a missing dependency.
  void provideManualDependency(String targetId, Uint8List bytes) {
    _resolvedDependencies[targetId] = bytes;
    _resolvedCount = _resolvedDependencies.length;
    _statusMessage =
        'Finding dependencies... ($_resolvedCount/${_missingTargetIds.length})';
    notifyListeners();
  }

  /// Check if all missing dependencies have been resolved.
  bool get allDependenciesResolved {
    return _missingTargetIds
        .every((id) => _resolvedDependencies.containsKey(id));
  }

  /// Retry build after manual dependency resolution.
  Future<void> retryBuildWithResolvedDeps() async {
    if (!allDependenciesResolved) {
      _errorMessage = 'Not all dependencies have been resolved.';
      notifyListeners();
      return;
    }

    _missingTargetIds = const [];
    await attemptBuild();
  }

  // --- Private Methods ---

  Future<List<int>?> _requestDependencyBytes(String targetId) async {
    // Check session cache first
    final cached = _resolvedDependencies[targetId];
    if (cached != null) {
      return cached;
    }

    // Not in cache, will be requested during resolution phase
    return null;
  }

  Future<void> _runPipeline(RawPackBundle rawBundle, String catalogKey) async {
    _status = ImportStatus.building;
    _statusMessage = 'Parsing files...';
    notifyListeners();

    // M2: Parse
    final parseService = ParseService();
    final parsedBundle = await parseService.parseBundle(rawBundle: rawBundle);

    _statusMessage = 'Wrapping nodes...';
    notifyListeners();

    // M3: Wrap
    final wrapService = WrapService();
    final wrappedBundle = await wrapService.wrapBundle(parsedBundle: parsedBundle);

    _statusMessage = 'Linking references...';
    notifyListeners();

    // M4: Link
    final linkService = LinkService();
    final linkedBundle = await linkService.linkBundle(wrappedBundle: wrappedBundle);

    _statusMessage = 'Binding entities...';
    notifyListeners();

    // M5: Bind
    final bindService = BindService();
    final boundBundle = await bindService.bindBundle(linkedBundle: linkedBundle);
    _boundBundles[catalogKey] = boundBundle;

    _statusMessage = 'Building search index...';
    notifyListeners();

    // M9: Index
    final indexService = IndexService();
    final indexBundle = indexService.buildIndex(boundBundle);
    _indexBundles[catalogKey] = indexBundle;

    // Note: Don't set success status here - let attemptBuild handle it
    // after all catalogs are built
  }

  SourceLocator _defaultSourceLocator() {
    return const SourceLocator(
      sourceKey: 'local_import',
      sourceUrl: '',
    );
  }

  // --- Session Persistence Methods ---

  /// Reloads the last persisted session.
  ///
  /// Reads files from their persisted paths and attempts build.
  Future<void> reloadLastSession() async {
    if (_persistedSession == null) {
      _errorMessage = 'No persisted session available.';
      _status = ImportStatus.failed;
      notifyListeners();
      return;
    }

    _status = ImportStatus.preparing;
    _statusMessage = 'Loading files from last session...';
    notifyListeners();

    try {
      // Read game system file
      final gsFile = File(_persistedSession!.gameSystemPath);
      if (!await gsFile.exists()) {
        throw Exception('Game system file no longer exists');
      }
      final gsBytes = await gsFile.readAsBytes();

      // Read all selected catalog files
      final loadedCatalogs = <SelectedFile>[];
      for (final persistedCatalog in _persistedSession!.selectedCatalogs) {
        final catFile = File(persistedCatalog.path);
        if (!await catFile.exists()) {
          throw Exception(
              'Catalog file no longer exists: ${persistedCatalog.path}');
        }
        final catBytes = await catFile.readAsBytes();
        loadedCatalogs.add(SelectedFile(
          fileName: catFile.uri.pathSegments.last,
          bytes: catBytes,
          filePath: persistedCatalog.path,
          rootId: persistedCatalog.rootId,
        ));
      }

      // Set files
      _gameSystemFile = SelectedFile(
        fileName: gsFile.uri.pathSegments.last,
        bytes: gsBytes,
        filePath: _persistedSession!.gameSystemPath,
      );
      _selectedCatalogs = List.unmodifiable(loadedCatalogs);

      // Set source locator if available
      if (_persistedSession!.repoUrl != null &&
          _persistedSession!.repoUrl!.isNotEmpty) {
        final uri = Uri.tryParse(_persistedSession!.repoUrl!);
        if (uri != null && uri.pathSegments.length >= 2) {
          final sourceKey = '${uri.pathSegments[0]}_${uri.pathSegments[1]}';
          _sourceLocator = SourceLocator(
            sourceKey: sourceKey,
            sourceUrl: _persistedSession!.repoUrl!,
            branch: _persistedSession!.branch,
          );
        }
      }

      // Pre-load dependency bytes from persisted paths
      for (final entry in _persistedSession!.dependencyPaths.entries) {
        final depFile = File(entry.value);
        if (await depFile.exists()) {
          _resolvedDependencies[entry.key] = await depFile.readAsBytes();
        }
      }

      // Clear persisted session flag since we're loading
      _hasPersistedSession = false;
      notifyListeners();

      // Attempt build
      await attemptBuild();
    } catch (e) {
      _status = ImportStatus.failed;
      _errorMessage = 'Failed to reload session: $e';
      _statusMessage = null;
      notifyListeners();
    }
  }

  /// Saves the current session for later reload.
  ///
  /// Called automatically on successful build if file paths are available.
  Future<void> _saveSession() async {
    if (_persistenceService == null) return;
    if (_gameSystemFile?.filePath == null) return;

    // Build list of persisted catalogs (only those with file paths)
    final persistedCatalogs = <PersistedCatalog>[];
    for (final catalog in _selectedCatalogs) {
      if (catalog.filePath != null) {
        persistedCatalogs.add(PersistedCatalog(
          path: catalog.filePath!,
          rootId: catalog.rootId,
        ));
      }
    }

    if (persistedCatalogs.isEmpty) return;

    final session = PersistedSession(
      gameSystemPath: _gameSystemFile!.filePath!,
      selectedCatalogs: persistedCatalogs,
      repoUrl: _sourceLocator?.sourceUrl,
      branch: _sourceLocator?.branch,
      dependencyPaths: {}, // TODO: Track dependency paths if needed
      savedAt: DateTime.now(),
    );

    await _persistenceService!.saveSession(session);
  }

  /// Clears any persisted session.
  Future<void> clearPersistedSession() async {
    if (_persistenceService != null) {
      await _persistenceService!.clearSession();
    }
    _hasPersistedSession = false;
    _persistedSession = null;
    notifyListeners();
  }
}

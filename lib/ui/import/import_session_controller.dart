import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/services/bsd_resolver_service.dart';
import 'package:combat_goblin_prime/services/session_persistence_service.dart';

export 'package:combat_goblin_prime/services/bsd_resolver_service.dart'
    show BsdResolverException, BsdResolverErrorCode;
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

  const SelectedFile({
    required this.fileName,
    required this.bytes,
    this.filePath,
  });
}

/// Controller for import session state.
///
/// Manages:
/// - Selected files (game system, primary catalog)
/// - Missing target IDs during dependency resolution
/// - Build status progression
/// - Cached BoundPackBundle and IndexBundle
/// - Repo mapping cache for BSData resolution
///
/// Uses ChangeNotifier for minimal state management without external deps.
class ImportSessionController extends ChangeNotifier {
  // --- File Selection ---

  SelectedFile? _gameSystemFile;
  SelectedFile? get gameSystemFile => _gameSystemFile;

  SelectedFile? _primaryCatalogFile;
  SelectedFile? get primaryCatalogFile => _primaryCatalogFile;

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

  RawPackBundle? _rawBundle;
  RawPackBundle? get rawBundle => _rawBundle;

  BoundPackBundle? _boundBundle;
  BoundPackBundle? get boundBundle => _boundBundle;

  IndexBundle? _indexBundle;
  IndexBundle? get indexBundle => _indexBundle;

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

  ImportSessionController({
    BsdResolverService? bsdResolver,
    SessionPersistenceService? persistenceService,
  })  : _bsdResolver = bsdResolver ?? BsdResolverService(),
        _persistenceService = persistenceService;

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

  // --- File Selection Methods ---

  void setGameSystemFile(SelectedFile file) {
    _gameSystemFile = file;
    _reset();
    notifyListeners();
  }

  void setPrimaryCatalogFile(SelectedFile file) {
    _primaryCatalogFile = file;
    _reset();
    notifyListeners();
  }

  void setSourceLocator(SourceLocator locator) {
    _sourceLocator = locator;
    notifyListeners();
  }

  /// Clear all state and start fresh.
  void clear() {
    _gameSystemFile = null;
    _primaryCatalogFile = null;
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
    _rawBundle = null;
    _boundBundle = null;
    _indexBundle = null;
    _resolvedDependencies.clear();
    _resolverError = null;
  }

  // --- Build Methods ---

  /// Attempts to build the bundle.
  ///
  /// On missing dependencies, transitions to [ImportStatus.resolvingDeps]
  /// and populates [missingTargetIds].
  ///
  /// On success, runs full pipeline and caches IndexBundle.
  Future<void> attemptBuild() async {
    if (_gameSystemFile == null || _primaryCatalogFile == null) {
      _errorMessage = 'Please select both game system and catalog files.';
      _status = ImportStatus.failed;
      notifyListeners();
      return;
    }

    _status = ImportStatus.preparing;
    _statusMessage = 'Preparing pack storage...';
    _errorMessage = null;
    notifyListeners();

    try {
      final acquireService = AcquireService();

      final rawBundle = await acquireService.buildBundle(
        gameSystemBytes: _gameSystemFile!.bytes,
        gameSystemExternalFileName: _gameSystemFile!.fileName,
        primaryCatalogBytes: _primaryCatalogFile!.bytes,
        primaryCatalogExternalFileName: _primaryCatalogFile!.fileName,
        requestDependencyBytes: _requestDependencyBytes,
        source: _sourceLocator ?? _defaultSourceLocator(),
      );

      _rawBundle = rawBundle;
      await _runPipeline(rawBundle);
    } on AcquireFailure catch (e) {
      if (e.missingTargetIds.isNotEmpty) {
        _missingTargetIds = List.unmodifiable(e.missingTargetIds);
        _status = ImportStatus.resolvingDeps;
        _statusMessage =
            'Finding dependencies... (0/${_missingTargetIds.length})';
        notifyListeners();
      } else {
        _status = ImportStatus.failed;
        _errorMessage = e.message;
        _statusMessage = null;
        notifyListeners();
      }
    } catch (e) {
      _status = ImportStatus.failed;
      _errorMessage = e.toString();
      _statusMessage = null;
      notifyListeners();
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

  Future<void> _runPipeline(RawPackBundle rawBundle) async {
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
    _boundBundle = boundBundle;

    _statusMessage = 'Building search index...';
    notifyListeners();

    // M9: Index
    final indexService = IndexService();
    final indexBundle = indexService.buildIndex(boundBundle);
    _indexBundle = indexBundle;

    _status = ImportStatus.success;
    _statusMessage = null;
    notifyListeners();

    // Save session for future reload
    await _saveSession();
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

      // Read primary catalog file
      final catFile = File(_persistedSession!.primaryCatalogPath);
      if (!await catFile.exists()) {
        throw Exception('Primary catalog file no longer exists');
      }
      final catBytes = await catFile.readAsBytes();

      // Set files
      _gameSystemFile = SelectedFile(
        fileName: gsFile.uri.pathSegments.last,
        bytes: gsBytes,
        filePath: _persistedSession!.gameSystemPath,
      );
      _primaryCatalogFile = SelectedFile(
        fileName: catFile.uri.pathSegments.last,
        bytes: catBytes,
        filePath: _persistedSession!.primaryCatalogPath,
      );

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
    if (_gameSystemFile?.filePath == null ||
        _primaryCatalogFile?.filePath == null) {
      return;
    }

    final session = PersistedSession(
      gameSystemPath: _gameSystemFile!.filePath!,
      primaryCatalogPath: _primaryCatalogFile!.filePath!,
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

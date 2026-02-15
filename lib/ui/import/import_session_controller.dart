import 'package:flutter/foundation.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/services/bsd_resolver_service.dart';

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

  const SelectedFile({required this.fileName, required this.bytes});
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

  ImportSessionController({BsdResolverService? bsdResolver})
      : _bsdResolver = bsdResolver ?? BsdResolverService();

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

        if (bytes != null) {
          _resolvedDependencies[targetId] = bytes;
          _resolvedCount++;
          _statusMessage =
              'Finding dependencies... ($_resolvedCount/${_missingTargetIds.length})';
          notifyListeners();
        }
      }

      // Retry build with resolved dependencies
      _missingTargetIds = const [];
      await attemptBuild();
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
  }

  SourceLocator _defaultSourceLocator() {
    return const SourceLocator(
      sourceKey: 'local_import',
      sourceUrl: '',
    );
  }
}

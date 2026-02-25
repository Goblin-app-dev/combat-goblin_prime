import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m1_acquire/services/preflight_scan_service.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/services/bsd_resolver_service.dart';
import 'package:combat_goblin_prime/services/github_sync_state.dart';
import 'package:combat_goblin_prime/services/session_persistence_service.dart';

export 'package:combat_goblin_prime/modules/m1_acquire/models/source_locator.dart'
    show SourceLocator;
export 'package:combat_goblin_prime/services/bsd_resolver_service.dart'
    show BsdResolverException, BsdResolverErrorCode, RepoTreeEntry, RepoTreeResult;
export 'package:combat_goblin_prime/services/session_persistence_service.dart'
    show PersistedSession, SessionPersistenceService;

// FactionOption is defined in this file and available to all importers.

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

/// A selectable faction in the faction picker.
///
/// Derived from [RepoTreeResult] via [ImportSessionController.availableFactions].
/// Represents one primary `.cat` file and its associated library catalogs.
/// Library catalogs (e.g. "Library - Tyranids.cat") are excluded from the
/// picker list and appear only in [libraryPaths] for informational display.
class FactionOption {
  /// User-facing display name (e.g. "Tyranids", "Space Marines").
  final String displayName;

  /// Repository path of the primary faction catalog (e.g. "Tyranids.cat").
  final String primaryPath;

  /// Repository paths of library catalogs associated with this faction.
  /// Populated by filename matching at tree-build time. Additional deps
  /// declared via `catalogueLinks` are also resolved during
  /// [ImportSessionController.loadFactionIntoSlot].
  final List<String> libraryPaths;

  const FactionOption({
    required this.displayName,
    required this.primaryPath,
    this.libraryPaths = const [],
  });
}

/// Status of an individual catalog slot.
enum SlotStatus {
  /// No catalog assigned.
  empty,

  /// Downloading catalog bytes from GitHub.
  fetching,

  /// Bytes in memory, awaiting pipeline.
  ready,

  /// Running M2-M9 pipeline.
  building,

  /// IndexBundle built and available for search.
  loaded,

  /// Download or pipeline failed.
  error,
}

/// Immutable state for a single catalog slot.
class SlotState {
  final SlotStatus status;

  /// GitHub repo path (e.g. "path/to/Foo.cat").
  final String? catalogPath;

  /// Display name (filename only).
  final String? catalogName;

  final SourceLocator? sourceLocator;

  /// Bytes fetched from GitHub (available after [SlotStatus.ready]).
  final Uint8List? fetchedBytes;

  final String? errorMessage;

  /// Missing dependency target IDs (sorted), populated when the pipeline
  /// encounters unresolved references. Non-empty only in [SlotStatus.error].
  final List<String> missingTargetIds;

  /// Built index, available after [SlotStatus.loaded].
  final IndexBundle? indexBundle;

  /// True only when [status] == [SlotStatus.fetching] during the Phase-1
  /// boot restore (label population from snapshot). Distinguishes the fast
  /// in-memory restore pass from a live network download so the UI can show
  /// "Restoring…" instead of "Downloading…".
  final bool isBootRestoring;

  const SlotState({
    this.status = SlotStatus.empty,
    this.catalogPath,
    this.catalogName,
    this.sourceLocator,
    this.fetchedBytes,
    this.errorMessage,
    this.missingTargetIds = const [],
    this.indexBundle,
    this.isBootRestoring = false,
  });

  SlotState copyWith({
    SlotStatus? status,
    String? catalogPath,
    String? catalogName,
    SourceLocator? sourceLocator,
    Uint8List? fetchedBytes,
    String? errorMessage,
    List<String>? missingTargetIds,
    IndexBundle? indexBundle,
    bool? isBootRestoring,
  }) {
    return SlotState(
      status: status ?? this.status,
      catalogPath: catalogPath ?? this.catalogPath,
      catalogName: catalogName ?? this.catalogName,
      sourceLocator: sourceLocator ?? this.sourceLocator,
      fetchedBytes: fetchedBytes ?? this.fetchedBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      missingTargetIds: missingTargetIds ?? this.missingTargetIds,
      indexBundle: indexBundle ?? this.indexBundle,
      isBootRestoring: isBootRestoring ?? this.isBootRestoring,
    );
  }

  /// Whether this slot has a searchable IndexBundle.
  bool get isSearchable => indexBundle != null;

  /// Whether this slot has unresolved dependencies.
  bool get hasMissingDeps => missingTargetIds.isNotEmpty;
}

/// Result of the non-blocking update check.
enum UpdateCheckStatus {
  /// Check has not run or is still in progress.
  unknown,

  /// Check completed and found no updates.
  upToDate,

  /// Check completed and found at least one changed blob SHA.
  updatesAvailable,

  /// Check failed (network error, no sync state, etc.).
  failed,
}

/// Maximum number of user-selected primary catalogs.
///
/// This is a **demo limitation**. The per-slot architecture supports
/// arbitrary N; the constant is intentionally low for the initial release
/// to keep memory and network usage bounded during testing.
const int kMaxSelectedCatalogs = 2;

/// Controller for import session state.
///
/// Manages:
/// - Selected files (game system, up to [kMaxSelectedCatalogs] primary catalogs)
/// - Per-slot download and pipeline state ([SlotState])
/// - Missing target IDs during dependency resolution
/// - Build status progression
/// - Cached BoundPackBundle and IndexBundle (per catalog)
/// - Repo mapping cache for BSData resolution
/// - Non-blocking update checks
///
/// ## Per-Slot Model
///
/// The controller manages [kMaxSelectedCatalogs] independent catalog slots.
/// Each slot follows a 1.5-step lifecycle:
/// 1. **Fetch-on-select** — assigning a catalog auto-fetches its bytes
/// 2. **Explicit Load** — user clicks Load to run the M2-M9 pipeline
///
/// Slots are independent: one slot can be loaded while another is fetching.
///
/// ## Legacy Multi-Catalog Support
///
/// The [selectedCatalogs]/[setSelectedCatalogs] API is preserved for
/// backward compatibility. Dependencies (library catalogs) are
/// auto-resolved and do NOT count toward the catalog limit.
///
/// Uses ChangeNotifier for minimal state management without external deps.
///
/// ## Public API surface
///
/// Types defined in this file:
/// - [ImportStatus] — global build lifecycle enum
/// - [SelectedFile] — file bytes + metadata for import
/// - [SlotStatus] — per-slot lifecycle enum
/// - [SlotState] — immutable snapshot of a single catalog slot
/// - [UpdateCheckStatus] — tri-state enum for background update check
/// - [kMaxSelectedCatalogs] — demo-limited slot count
///
/// Re-exported from other packages for consumer convenience:
/// - [SourceLocator] (from m1_acquire)
/// - [BsdResolverException], [BsdResolverErrorCode], [RepoTreeEntry],
///   [RepoTreeResult] (from bsd_resolver_service)
/// - [PersistedSession], [SessionPersistenceService]
///   (from session_persistence_service)
class ImportSessionController extends ChangeNotifier {
  // --- File Selection ---

  SelectedFile? _gameSystemFile;
  SelectedFile? get gameSystemFile => _gameSystemFile;

  /// Short display name for the loaded game system (strips `.gst` extension).
  ///
  /// Returns null if no game system file has been loaded yet.
  String? get gameSystemDisplayName {
    final name = _gameSystemFile?.fileName;
    if (name == null) return null;
    return name.endsWith('.gst') ? name.substring(0, name.length - 4) : name;
  }

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

  // --- Cached Repo Tree ---

  /// Most recent result from [loadRepoCatalogTree].
  ///
  /// Used by [FactionPickerScreen] and [DownloadsScreen] to derive faction
  /// lists without re-fetching. Null until first successful tree fetch.
  RepoTreeResult? _cachedRepoTree;
  RepoTreeResult? get cachedRepoTree => _cachedRepoTree;

  /// Sets [_sourceLocator] directly, for use in tests only.
  ///
  /// In production, [_sourceLocator] is always set via
  /// [importFromGitHub] or [fetchAndSetGameSystem].
  @visibleForTesting
  void setSourceLocatorForTesting(SourceLocator locator) {
    _sourceLocator = locator;
  }

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

  // --- Per-Slot State ---

  List<SlotState> _slots = const [SlotState(), SlotState()];

  /// Last RawPackBundle per slot, retained for _saveSession() to read M1 paths.
  /// Keyed by slot index. Cleared when slot is cleared.
  final Map<int, RawPackBundle> _slotBundles = {};

  /// Returns the state of the slot at [index].
  SlotState slotState(int index) => _slots[index];

  /// All slot states (read-only view).
  List<SlotState> get slots => List.unmodifiable(_slots);

  /// All loaded IndexBundles from slots, keyed by slot identifier.
  Map<String, IndexBundle> get slotIndexBundles {
    final result = <String, IndexBundle>{};
    for (var i = 0; i < _slots.length; i++) {
      final bundle = _slots[i].indexBundle;
      if (bundle != null) {
        result['slot_$i'] = bundle;
      }
    }
    return result;
  }

  /// Whether any slot has a loaded IndexBundle.
  bool get hasAnyLoaded => _slots.any((s) => s.status == SlotStatus.loaded);

  // --- Update Check State ---

  UpdateCheckStatus _updateCheckStatus = UpdateCheckStatus.unknown;

  /// Current status of the background update check.
  UpdateCheckStatus get updateCheckStatus => _updateCheckStatus;

  /// Convenience: true only when the check completed and found updates.
  bool get updateAvailable =>
      _updateCheckStatus == UpdateCheckStatus.updatesAvailable;

  /// Timestamp of the most recent completed update check (transient, not
  /// persisted). Null until the first check completes (success or failure).
  DateTime? _lastUpdateCheckAt;
  DateTime? get lastUpdateCheckAt => _lastUpdateCheckAt;

  /// Timestamp of the most recent successful repo tree fetch (transient).
  /// Sourced from [RepoTreeResult.fetchedAt] after [loadRepoCatalogTree].
  DateTime? _lastSyncAt;
  DateTime? get lastSyncAt => _lastSyncAt;

  // --- Boot Perf State ---

  /// Wall-clock origin for boot timing: set at [initPersistenceAndRestore]
  /// entry. Null on fresh installs where no session is restored.
  DateTime? _t0;

  /// Time at which slot labels became visible (Phase 1 complete).
  DateTime? _tLabelsVisible;

  /// Time at which the first slot reached [SlotStatus.loaded] (Phase 2
  /// partial-complete). Set once; subsequent loads do not overwrite.
  DateTime? _tSlot0Loaded;

  /// Optional factory for creating [AcquireService] instances.
  ///
  /// Defaults to the production implementation. Inject a custom factory in
  /// tests to simulate [AcquireFailure] without running the full pipeline.
  final AcquireService Function(Directory? appDataRoot)? _acquireServiceFactory;

  ImportSessionController({
    Directory? appDataRoot,
    BsdResolverService? bsdResolver,
    SessionPersistenceService? persistenceService,
    GitHubSyncStateService? gitHubSyncStateService,
    AcquireService Function(Directory? appDataRoot)? acquireServiceFactory,
  })  : _appDataRoot = appDataRoot,
        _bsdResolver = bsdResolver ?? BsdResolverService(),
        _persistenceService = persistenceService,
        _gitHubSyncStateService = gitHubSyncStateService,
        _acquireServiceFactory = acquireServiceFactory;

  /// Sets the [GitHubSyncStateService] for SHA-based update detection.
  ///
  /// Called from bootstrap before [initPersistenceAndRestore] so that the
  /// subsequent [checkForUpdatesAsync] has a service to query.
  void setGitHubSyncStateService(GitHubSyncStateService service) {
    _gitHubSyncStateService = service;
  }

  /// Sets the persistence service and checks for existing session.
  Future<void> initPersistence(SessionPersistenceService service) async {
    _persistenceService = service;
    await _checkForPersistedSession();
  }

  /// Sets the persistence service and auto-restores the last session on boot.
  ///
  /// Phase 11E two-phase restore:
  /// 1. **Instant labels** — synchronously populates slot display names and
  ///    game system label from persisted metadata (no file I/O).
  /// 2. **Background rebuild** — reads file bytes from M1 paths and runs the
  ///    pipeline. On success, slots transition to [SlotStatus.loaded].
  ///    On failure, slots fall back to [SlotStatus.error] but labels remain
  ///    visible so the user sees what was loaded last time.
  ///
  /// Fails silently if restoration fails.
  Future<void> initPersistenceAndRestore(
    SessionPersistenceService service,
  ) async {
    _t0 = DateTime.now();
    _persistenceService = service;
    await _checkForPersistedSession();
    if (!_hasPersistedSession || _persistedSession == null) return;

    final session = _persistedSession!;

    // Phase 1: Instant labels — populate display state from metadata only.
    _restoreLabelsFromSnapshot(session);

    // Phase 2: Background rebuild — read files + run pipeline.
    try {
      await _rebuildFromSnapshot(session);
    } catch (_) {
      // Fail silently on auto-restore; labels remain visible.
    }
  }

  /// Restores display labels from a persisted session without any file I/O.
  ///
  /// Sets [gameSystemDisplayName] via a lightweight [SelectedFile] (empty
  /// bytes), and populates slot names from [PersistedCatalog.factionDisplayName].
  /// Slots are set to [SlotStatus.fetching] to indicate "restoring…" state.
  void _restoreLabelsFromSnapshot(PersistedSession session) {
    // Set game system display name from persisted label.
    if (session.gameSystemDisplayName != null) {
      _gameSystemFile = SelectedFile(
        fileName: '${session.gameSystemDisplayName}.gst',
        bytes: Uint8List(0), // placeholder — replaced in Phase 2
      );
    }

    // Reconstruct source locator from persisted sourceKey + repoUrl.
    if (session.sourceKey != null &&
        session.repoUrl != null &&
        session.repoUrl!.isNotEmpty) {
      _sourceLocator = SourceLocator(
        sourceKey: session.sourceKey!,
        sourceUrl: session.repoUrl!,
        branch: session.branch,
      );
    }

    // Populate slot labels.
    final updated = List<SlotState>.of(_slots);
    for (var i = 0; i < session.selectedCatalogs.length && i < kMaxSelectedCatalogs; i++) {
      final pc = session.selectedCatalogs[i];
      updated[i] = SlotState(
        status: SlotStatus.fetching,
        catalogPath: pc.primaryCatRepoPath ?? pc.path,
        catalogName: pc.factionDisplayName,
        isBootRestoring: true, // disambiguates from live network download
      );
    }
    _slots = List.unmodifiable(updated);

    _hasPersistedSession = false;
    _tLabelsVisible = DateTime.now();
    notifyListeners();
  }

  /// Reads M1 files and rebuilds indices from a persisted session.
  ///
  /// Called as Phase 2 of [initPersistenceAndRestore]. On success each slot
  /// transitions to [SlotStatus.loaded]. On failure the slot transitions to
  /// [SlotStatus.error] but the display label from Phase 1 remains visible.
  Future<void> _rebuildFromSnapshot(PersistedSession session) async {
    // Read game system bytes.
    final gsFile = File(session.gameSystemPath);
    if (!await gsFile.exists()) {
      _setAllSlotsError('Game system file missing from storage');
      return;
    }
    final gsBytes = await gsFile.readAsBytes();
    _gameSystemFile = SelectedFile(
      fileName: gsFile.uri.pathSegments.last,
      bytes: gsBytes,
      filePath: session.gameSystemPath,
    );

    // Pre-load dependency bytes from persisted paths.
    for (final entry in session.dependencyPaths.entries) {
      final depFile = File(entry.value);
      if (await depFile.exists()) {
        _resolvedDependencies[entry.key] = await depFile.readAsBytes();
      }
    }
    // Also load per-catalog dependency paths.
    for (final pc in session.selectedCatalogs) {
      if (pc.dependencyStoredPaths != null) {
        for (final entry in pc.dependencyStoredPaths!.entries) {
          if (_resolvedDependencies.containsKey(entry.key)) continue;
          final depFile = File(entry.value);
          if (await depFile.exists()) {
            _resolvedDependencies[entry.key] = await depFile.readAsBytes();
          }
        }
      }
    }

    // Rebuild each slot.
    for (var i = 0; i < session.selectedCatalogs.length && i < kMaxSelectedCatalogs; i++) {
      final pc = session.selectedCatalogs[i];
      try {
        final catFile = File(pc.path);
        if (!await catFile.exists()) {
          _setSlot(i, _slots[i].copyWith(
            status: SlotStatus.error,
            errorMessage: 'Catalog file missing from storage',
          ));
          continue;
        }
        final catBytes = await catFile.readAsBytes();

        // Set slot to ready with bytes (clear boot flag), then load.
        _setSlot(i, _slots[i].copyWith(
          status: SlotStatus.ready,
          fetchedBytes: catBytes,
          sourceLocator: _sourceLocator,
          isBootRestoring: false,
        ));
        await loadSlot(i);
      } catch (e) {
        _setSlot(i, _slots[i].copyWith(
          status: SlotStatus.error,
          errorMessage: 'Restore failed: $e',
        ));
      }
    }
  }

  /// Sets all non-empty slots to error state.
  void _setAllSlotsError(String message) {
    final updated = _slots.map((s) {
      if (s.status == SlotStatus.empty) return s;
      return s.copyWith(
        status: SlotStatus.error,
        errorMessage: message,
        isBootRestoring: false,
      );
    }).toList();
    _slots = List.unmodifiable(updated);
    notifyListeners();
  }

  /// Runs the update check and returns when complete.
  ///
  /// Updates [updateCheckStatus] to [UpdateCheckStatus.upToDate],
  /// [UpdateCheckStatus.updatesAvailable], or [UpdateCheckStatus.failed].
  /// Never throws — all errors are converted to [UpdateCheckStatus.failed].
  ///
  /// Prefer [checkForUpdatesAsync] in production; use this in tests.
  Future<void> checkForUpdates() => _performUpdateCheck();

  /// Fires a non-blocking update check. Fails silently on any error.
  ///
  /// Equivalent to calling [checkForUpdates] without awaiting the result.
  /// Updates [updateCheckStatus] asynchronously.
  void checkForUpdatesAsync() {
    checkForUpdates(); // intentionally not awaited
  }

  Future<void> _performUpdateCheck() async {
    if (_sourceLocator == null) return;
    try {
      final tree = await _bsdResolver.fetchRepoTree(_sourceLocator!);
      if (tree == null) {
        _updateCheckStatus = UpdateCheckStatus.failed;
        _lastUpdateCheckAt = DateTime.now();
        notifyListeners();
        return;
      }
      final service = _gitHubSyncStateService;
      if (service == null) {
        _updateCheckStatus = UpdateCheckStatus.failed;
        _lastUpdateCheckAt = DateTime.now();
        notifyListeners();
        return;
      }
      final syncState = await service.loadState();
      final repoState = syncState.repos[_sourceLocator!.sourceKey];
      if (repoState == null) {
        _updateCheckStatus = UpdateCheckStatus.failed;
        _lastUpdateCheckAt = DateTime.now();
        notifyListeners();
        return;
      }
      // Compare SHAs from the fresh tree against persisted tracked files
      for (final entry in tree.entries) {
        final tracked = repoState.trackedFiles[entry.path];
        if (tracked != null && tracked.blobSha != entry.blobSha) {
          _updateCheckStatus = UpdateCheckStatus.updatesAvailable;
          _lastUpdateCheckAt = DateTime.now();
          notifyListeners();
          return;
        }
      }
      _updateCheckStatus = UpdateCheckStatus.upToDate;
      _lastUpdateCheckAt = DateTime.now();
      notifyListeners();
    } catch (_) {
      _updateCheckStatus = UpdateCheckStatus.failed;
      _lastUpdateCheckAt = DateTime.now();
      notifyListeners();
    }
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
    final sorted = RepoTreeResult(
      entries: sortedEntries,
      fetchedAt: result.fetchedAt,
    );
    // Cache tree, locator, and last-sync timestamp.
    _cachedRepoTree = sorted;
    _sourceLocator = sourceLocator;
    _lastSyncAt = sorted.fetchedAt;
    notifyListeners();
    return sorted;
  }

  // --- Faction Picker Helpers ---

  /// Returns true when a catalog stem (filename without `.cat`) is a library
  /// file.  The only criterion is whether the word "library" appears anywhere
  /// in the stem (case-insensitive).  No hardcoded prefix list is needed.
  static bool _isLibraryFile(String stem) =>
      stem.toLowerCase().contains('library');

  /// Normalised key used to pair a library catalog with its primary.
  ///
  /// Algorithm (deterministic, no hardcoded prefix list):
  /// 1. Lowercase the stem.
  /// 2. Remove every occurrence of the word "library".
  /// 3. Collapse runs of spaces to a single space.
  /// 4. Trim leading/trailing whitespace and hyphen/space fragments.
  /// 5. Strip one leading category segment (e.g. `"xenos - "`) if present —
  ///    this pairs `"Xenos - Tyranids"` with the key produced by
  ///    `"Library - Tyranids"` (which becomes `"tyranids"` after step 4).
  ///
  /// Examples:
  /// - `"Tyranids"`                        → `"tyranids"`
  /// - `"Library - Tyranids"`              → `"tyranids"`
  /// - `"Xenos - Tyranids"`               → `"tyranids"`
  /// - `"Chaos - Chaos Knights"`          → `"chaos knights"`
  /// - `"Chaos - Chaos Knights - Library"` → `"chaos knights"`
  /// - `"Library - Unaligned - Giants"`   → `"giants"`
  /// - `"Unaligned - Giants"`             → `"giants"`
  static String _pairKey(String stem) {
    var key = stem.toLowerCase().replaceAll('library', '');
    key = key.replaceAll(RegExp(r' {2,}'), ' ').trim();
    key = key.replaceAll(RegExp(r'^[\s\-]+|[\s\-]+$'), '').trim();
    // Strip one leading category-style segment (everything before the first
    // " - ") so that "Xenos - Tyranids" and "Tyranids" (post-library-removal
    // of "Library - Tyranids") produce the same key.
    final sep = key.indexOf(' - ');
    if (sep != -1) {
      key = key.substring(sep + 3).trim();
    }
    return key;
  }

  /// Removes the word "Library" from [stem], preserving original casing of
  /// the remainder and cleaning up leftover punctuation/spaces.
  ///
  /// Used to build a human-readable display name for orphan library files
  /// (library `.cat` files that have no paired primary).
  ///
  /// Example: `"Library - Astartes Heresy Legends"` → `"Astartes Heresy Legends"`
  static String _stripLibraryLabel(String stem) {
    var result = stem.replaceAll(RegExp(r'library', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r' {2,}'), ' ').trim();
    result = result.replaceAll(RegExp(r'^[\s\-]+|[\s\-]+$'), '').trim();
    return result;
  }

  /// Builds a sorted list of [FactionOption]s from [tree].
  ///
  /// **Group-by algorithm** — deterministic, filename-pair based:
  /// 1. Classify each `.cat` stem as library (`_isLibraryFile`) or primary.
  /// 2. Index library stems by `_pairKey`.
  /// 3. Emit one [FactionOption] per primary key:
  ///    - [FactionOption.displayName] = lex-smallest primary stem (exact, no
  ///      prefix stripping — filenames are never shown in the UI).
  ///    - [FactionOption.primaryPath] = path of that stem.
  ///    - [FactionOption.libraryPaths] = paths of all library stems whose
  ///      `_pairKey` matches, sorted.
  /// 4. Orphan libraries (no paired primary): emit one [FactionOption] per
  ///    unpaired library key, with display name = stem stripped of "Library".
  /// 5. Sort ascending by display name (case-insensitive), stable tie-break
  ///    by path.
  List<FactionOption> availableFactions(RepoTreeResult tree) {
    final stemToPath = <String, String>{};
    final primaryStems = <String>[];
    final libraryStems = <String>[];

    for (final entry in tree.catalogFiles) {
      final base = entry.path.split('/').last;
      final stem =
          base.endsWith('.cat') ? base.substring(0, base.length - 4) : base;
      stemToPath[stem] = entry.path;
      if (_isLibraryFile(stem)) {
        libraryStems.add(stem);
      } else {
        primaryStems.add(stem);
      }
    }

    // Index library stems by pair key.
    final libsByKey = <String, List<String>>{};
    for (final lib in libraryStems) {
      libsByKey.putIfAbsent(_pairKey(lib), () => []).add(lib);
    }

    // Group primaries by pair key; collapse to one entry (lex-smallest stem).
    final primaryByKey = <String, List<String>>{};
    for (final p in primaryStems) {
      primaryByKey.putIfAbsent(_pairKey(p), () => []).add(p);
    }

    final options = <FactionOption>[];

    // Step 3: one row per primary group.
    for (final kv in primaryByKey.entries) {
      final primaries = kv.value..sort();
      final canonical = primaries.first; // lex-smallest for determinism
      final libs = (libsByKey[kv.key] ?? [])..sort();
      options.add(FactionOption(
        displayName: canonical,
        primaryPath: stemToPath[canonical]!,
        libraryPaths: libs.map((s) => stemToPath[s]!).toList(),
      ));
    }

    // Step 4: orphan libraries — library stems whose pairKey has no primary.
    final pairedKeys = primaryByKey.keys.toSet();
    for (final kv in libsByKey.entries) {
      if (pairedKeys.contains(kv.key)) continue; // already paired
      final libs = kv.value..sort();
      final canonical = libs.first;
      options.add(FactionOption(
        displayName: _stripLibraryLabel(canonical),
        primaryPath: stemToPath[canonical]!,
      ));
    }

    options.sort((a, b) {
      final cmp =
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      return cmp != 0 ? cmp : a.primaryPath.compareTo(b.primaryPath);
    });
    return options;
  }

  /// Downloads a faction's primary catalog and dependencies, then runs the
  /// pipeline immediately (one-tap import).
  ///
  /// Flow:
  /// 1. Marks slot [SlotStatus.fetching] with [faction.displayName] as the name.
  /// 2. Downloads primary `.cat` bytes.
  /// 3. Pre-flight scans for `catalogueLinks` and fetches missing dep bytes.
  /// 4. Marks slot [SlotStatus.ready].
  /// 5. Immediately calls [loadSlot] (if [gameSystemFile] is set).
  ///
  /// If [gameSystemFile] is not yet set, the slot stays at [SlotStatus.ready]
  /// so the user can set it and then tap "Load".
  Future<void> loadFactionIntoSlot(
    int slot,
    FactionOption faction,
    SourceLocator locator,
  ) async {
    assert(slot >= 0 && slot < kMaxSelectedCatalogs, 'Invalid slot index');

    _setSlot(
      slot,
      SlotState(
        status: SlotStatus.fetching,
        catalogPath: faction.primaryPath,
        catalogName: faction.displayName,
        sourceLocator: locator,
      ),
    );

    final bytes = await _bsdResolver.fetchFileByPath(locator, faction.primaryPath);
    if (bytes == null) {
      _setSlot(
        slot,
        _slots[slot].copyWith(
          status: SlotStatus.error,
          errorMessage: _bsdResolver.lastError?.userMessage ?? 'Download failed',
        ),
      );
      return;
    }

    // Pre-flight scan for catalogueLink deps (targetId-based).
    try {
      final preflight = await PreflightScanService().scanBytes(
        bytes: bytes,
        fileType: SourceFileType.cat,
      );
      final missingIds = preflight.importDependencies
          .map((d) => d.targetId)
          .where((id) => !_resolvedDependencies.containsKey(id))
          .toList();
      for (final targetId in missingIds) {
        final depBytes = await _bsdResolver.fetchCatalogBytes(
          sourceLocator: locator,
          targetId: targetId,
        );
        if (depBytes != null) {
          _resolvedDependencies[targetId] = depBytes;
        }
      }
    } catch (_) {
      // Non-fatal; _autoResolveSlotDeps handles stragglers.
    }

    _setSlot(
      slot,
      _slots[slot].copyWith(
        status: SlotStatus.ready,
        fetchedBytes: bytes,
      ),
    );

    if (_gameSystemFile != null) {
      await loadSlot(slot);
    }
  }

  /// Fetches a .gst file from GitHub and sets it as the game system.
  ///
  /// Returns true on success. On failure, sets [resolverError] and
  /// transitions to [ImportStatus.failed].
  Future<bool> fetchAndSetGameSystem(
    SourceLocator locator,
    String gstPath,
  ) async {
    _status = ImportStatus.preparing;
    _statusMessage = 'Downloading game system...';
    _errorMessage = null;
    _resolverError = null;
    notifyListeners();

    final bytes = await _bsdResolver.fetchFileByPath(locator, gstPath);
    if (bytes == null) {
      _resolverError = _bsdResolver.lastError;
      _status = ImportStatus.failed;
      _errorMessage =
          _resolverError?.userMessage ?? 'Failed to download game system.';
      _statusMessage = null;
      notifyListeners();
      return false;
    }

    _gameSystemFile = SelectedFile(
      fileName: gstPath.split('/').last,
      bytes: bytes,
    );
    _sourceLocator = locator;
    _status = ImportStatus.idle;
    _statusMessage = null;
    // Demote any loaded slots back to ready (game system changed)
    _demoteSlotBuildState();
    notifyListeners();
    return true;
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

  // --- Per-Slot Methods ---

  /// Assigns a catalog to a slot and immediately fetches its bytes.
  ///
  /// Transitions: empty/error/ready → fetching → ready or error.
  Future<void> assignCatalogToSlot(
    int slot,
    String catPath,
    SourceLocator locator,
  ) async {
    assert(slot >= 0 && slot < kMaxSelectedCatalogs, 'Invalid slot index');
    _setSlot(
      slot,
      SlotState(
        status: SlotStatus.fetching,
        catalogPath: catPath,
        catalogName: catPath.split('/').last,
        sourceLocator: locator,
      ),
    );

    final bytes = await _bsdResolver.fetchFileByPath(locator, catPath);
    if (bytes == null) {
      _setSlot(
        slot,
        _slots[slot].copyWith(
          status: SlotStatus.error,
          errorMessage:
              _bsdResolver.lastError?.userMessage ?? 'Download failed',
        ),
      );
      return;
    }

    // Scan the catalog for declared catalogueLink dependencies and pre-fetch
    // any that are not already cached, so the pipeline succeeds on first run.
    try {
      final preflight = await PreflightScanService().scanBytes(
        bytes: bytes,
        fileType: SourceFileType.cat,
      );
      final missingIds = preflight.importDependencies
          .map((d) => d.targetId)
          .where((id) => !_resolvedDependencies.containsKey(id))
          .toList();
      for (final targetId in missingIds) {
        final depBytes = await _bsdResolver.fetchCatalogBytes(
          sourceLocator: locator,
          targetId: targetId,
        );
        if (depBytes != null) {
          _resolvedDependencies[targetId] = depBytes;
        }
        // If a dep can't be fetched, continue — the AcquireFailure +
        // _autoResolveSlotDeps path will surface and retry it.
      }
    } catch (_) {
      // Scan/fetch errors are non-fatal here; pipeline handles missing deps.
    }

    _setSlot(
      slot,
      _slots[slot].copyWith(
        status: SlotStatus.ready,
        fetchedBytes: bytes,
      ),
    );
  }

  /// Runs the M2-M9 pipeline for slot [slot].
  ///
  /// Slot must be in [SlotStatus.ready]. Requires [gameSystemFile] to be set.
  /// On success transitions to [SlotStatus.loaded] with an IndexBundle.
  Future<void> loadSlot(int slot) async {
    assert(slot >= 0 && slot < kMaxSelectedCatalogs, 'Invalid slot index');
    final s = _slots[slot];
    if (s.status != SlotStatus.ready) return;
    if (_gameSystemFile == null) {
      _setSlot(
        slot,
        s.copyWith(
          status: SlotStatus.error,
          errorMessage: 'Game system file not set.',
        ),
      );
      return;
    }

    _setSlot(slot, s.copyWith(status: SlotStatus.building));

    try {
      final acquireService = _acquireServiceFactory != null
          ? _acquireServiceFactory!(_appDataRoot)
          : AcquireService(storage: AcquireStorage(appDataRoot: _appDataRoot));

      final rawBundle = await acquireService.buildBundle(
        gameSystemBytes: _gameSystemFile!.bytes,
        gameSystemExternalFileName: _gameSystemFile!.fileName,
        primaryCatalogBytes: s.fetchedBytes!,
        primaryCatalogExternalFileName: s.catalogName!,
        requestDependencyBytes: _requestDependencyBytes,
        source: s.sourceLocator ?? _defaultSourceLocator(),
      );

      // Stash bundle so _saveSession() can read M1 storage paths.
      _slotBundles[slot] = rawBundle;

      final indexBundle = await _runPipelineForBundle(rawBundle);
      _indexBundles['slot_$slot'] = indexBundle;

      _setSlot(
        slot,
        _slots[slot].copyWith(
          status: SlotStatus.loaded,
          indexBundle: indexBundle,
        ),
      );
      await _saveSession();
    } on AcquireFailure catch (e) {
      if (e.missingTargetIds.isNotEmpty) {
        final sorted = List<String>.of(e.missingTargetIds)..sort();
        _setSlot(
          slot,
          _slots[slot].copyWith(
            status: SlotStatus.error,
            errorMessage:
                '${sorted.length} missing dependenc${sorted.length == 1 ? 'y' : 'ies'}',
            missingTargetIds: List.unmodifiable(sorted),
          ),
        );
        // Attempt auto-resolution via BsdResolver
        await _autoResolveSlotDeps(slot, sorted);
      } else {
        _setSlot(
          slot,
          _slots[slot].copyWith(
            status: SlotStatus.error,
            errorMessage: e.message,
          ),
        );
      }
    } catch (e) {
      _setSlot(
        slot,
        _slots[slot].copyWith(
          status: SlotStatus.error,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  /// Attempts to auto-resolve missing dependencies for a slot.
  ///
  /// On success, caches the resolved bytes and retries loading the slot.
  /// On partial/total failure, leaves the slot in error with the remaining
  /// missing list visible for the user.
  Future<void> _autoResolveSlotDeps(
    int slot,
    List<String> missingIds,
  ) async {
    final locator = _slots[slot].sourceLocator ?? _sourceLocator;
    if (locator == null) return; // can't resolve without a locator

    var resolved = 0;
    for (final targetId in missingIds) {
      if (_resolvedDependencies.containsKey(targetId)) {
        resolved++;
        continue;
      }
      final bytes = await _bsdResolver.fetchCatalogBytes(
        sourceLocator: locator,
        targetId: targetId,
      );
      if (_bsdResolver.lastError != null) {
        // Rate limit or network error — stop resolution, keep error visible
        _setSlot(
          slot,
          _slots[slot].copyWith(
            errorMessage:
                'Dependency resolution stopped: '
                '${_bsdResolver.lastError?.userMessage ?? 'network error'}. '
                '${missingIds.length - resolved} '
                'dependenc${(missingIds.length - resolved) == 1 ? 'y' : 'ies'} '
                'still missing.',
          ),
        );
        return;
      }
      if (bytes != null) {
        _resolvedDependencies[targetId] = bytes;
        resolved++;
      }
    }

    // If all resolved, retry loading the slot
    if (missingIds.every((id) => _resolvedDependencies.containsKey(id))) {
      // Transition back to ready so loadSlot can run again
      _setSlot(
        slot,
        _slots[slot].copyWith(
          status: SlotStatus.ready,
          errorMessage: null,
          missingTargetIds: const [],
        ),
      );
      await loadSlot(slot);
    }
  }

  /// Loads all slots that are in [SlotStatus.ready].
  Future<void> loadAllReadySlots() async {
    for (var i = 0; i < kMaxSelectedCatalogs; i++) {
      if (_slots[i].status == SlotStatus.ready) {
        await loadSlot(i);
      }
    }
  }

  /// Retries loading a slot that failed with bytes still available.
  ///
  /// If the slot is in [SlotStatus.error] and has [SlotState.fetchedBytes],
  /// transitions it back to [SlotStatus.ready] and re-runs [loadSlot].
  /// Does nothing if the slot has no bytes or is not in the error state.
  Future<void> retrySlot(int slot) async {
    assert(slot >= 0 && slot < kMaxSelectedCatalogs, 'Invalid slot index');
    final s = _slots[slot];
    if (s.status != SlotStatus.error || s.fetchedBytes == null) return;
    _setSlot(
      slot,
      s.copyWith(
        status: SlotStatus.ready,
        errorMessage: null,
        missingTargetIds: const [],
      ),
    );
    await loadSlot(slot);
  }

  /// Clears a slot back to [SlotStatus.empty].
  void clearSlot(int slot) {
    assert(slot >= 0 && slot < kMaxSelectedCatalogs, 'Invalid slot index');
    _indexBundles.remove('slot_$slot');
    _slotBundles.remove(slot);
    _setSlot(slot, const SlotState());
  }

  void _setSlot(int slot, SlotState state) {
    final updated = List<SlotState>.of(_slots);
    updated[slot] = state;
    _slots = List.unmodifiable(updated);

    // Boot perf: capture first-slot-loaded timestamp and emit timing log.
    if (state.status == SlotStatus.loaded &&
        _tSlot0Loaded == null &&
        _t0 != null) {
      _tSlot0Loaded = DateTime.now();
      _emitBootPerfLog();
    }

    notifyListeners();
  }

  /// Emits a single [debugPrint] line with cumulative boot timing.
  ///
  /// Only called once per boot, immediately after the first slot loads.
  /// Timing covers: controller init → labels visible → first slot loaded.
  void _emitBootPerfLog() {
    final t0 = _t0;
    final tLv = _tLabelsVisible;
    final tS0 = _tSlot0Loaded;
    if (t0 == null || tS0 == null) return;

    final totalMs = tS0.difference(t0).inMilliseconds;
    final labelsMs = tLv != null ? tLv.difference(t0).inMilliseconds : -1;
    final buildMs = tLv != null ? tS0.difference(tLv).inMilliseconds : -1;

    debugPrint(
      '[BOOT PERF] t0→labels: ${labelsMs}ms | '
      'labels→first-loaded: ${buildMs}ms | '
      'total: ${totalMs}ms',
    );
  }

  /// Demotes slot build state when the game system changes.
  ///
  /// Loaded/building/error slots with fetched bytes → ready.
  /// Slots without fetched bytes are unaffected.
  void _demoteSlotBuildState() {
    final updated = _slots.map((s) {
      if (s.fetchedBytes != null &&
          (s.status == SlotStatus.loaded ||
              s.status == SlotStatus.building ||
              s.status == SlotStatus.error)) {
        return SlotState(
          status: SlotStatus.ready,
          catalogPath: s.catalogPath,
          catalogName: s.catalogName,
          sourceLocator: s.sourceLocator,
          fetchedBytes: s.fetchedBytes,
        );
      }
      return s;
    }).toList();
    _slots = List.unmodifiable(updated);
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
    _demoteSlotBuildState();
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

  /// Runs the M2-M9 pipeline on a raw bundle and returns the IndexBundle.
  ///
  /// Does not update global status; used by per-slot loading.
  Future<IndexBundle> _runPipelineForBundle(RawPackBundle rawBundle) async {
    final parseService = ParseService();
    final parsedBundle = await parseService.parseBundle(rawBundle: rawBundle);

    final wrapService = WrapService();
    final wrappedBundle =
        await wrapService.wrapBundle(parsedBundle: parsedBundle);

    final linkService = LinkService();
    final linkedBundle =
        await linkService.linkBundle(wrappedBundle: wrappedBundle);

    final bindService = BindService();
    final boundBundle =
        await bindService.bindBundle(linkedBundle: linkedBundle);

    final indexService = IndexService();
    return indexService.buildIndex(boundBundle);
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

      // Set source locator if available. Prefer persisted sourceKey (Phase
      // 11E) over URL-derived key (legacy).
      if (_persistedSession!.repoUrl != null &&
          _persistedSession!.repoUrl!.isNotEmpty) {
        final persistedKey = _persistedSession!.sourceKey;
        final String sourceKey;
        if (persistedKey != null && persistedKey.isNotEmpty) {
          sourceKey = persistedKey;
        } else {
          final uri = Uri.tryParse(_persistedSession!.repoUrl!);
          sourceKey = (uri != null && uri.pathSegments.length >= 2)
              ? '${uri.pathSegments[0]}_${uri.pathSegments[1]}'
              : 'unknown';
        }
        _sourceLocator = SourceLocator(
          sourceKey: sourceKey,
          sourceUrl: _persistedSession!.repoUrl!,
          branch: _persistedSession!.branch,
        );
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
  /// Called automatically on successful build. Uses M1 storage paths from
  /// stashed [RawPackBundle]s (per-slot flow) or [SelectedFile.filePath]
  /// (legacy flow) for file location. Phase 11E fields enable instant label
  /// restore on cold boot without loading file bytes.
  Future<void> _saveSession() async {
    if (_persistenceService == null) return;

    // Determine game system M1 path: prefer stashed bundle, fall back to
    // SelectedFile.filePath (legacy/reload path).
    String? gsPath = _gameSystemFile?.filePath;
    if (_slotBundles.isNotEmpty) {
      gsPath ??= _slotBundles.values.first.gameSystemMetadata.storedPath;
    }
    if (gsPath == null) return;

    // Build list of persisted catalogs from per-slot bundles.
    final persistedCatalogs = <PersistedCatalog>[];
    final allDepPaths = <String, String>{};

    for (var i = 0; i < _slots.length; i++) {
      final slot = _slots[i];
      if (slot.status != SlotStatus.loaded) continue;

      final bundle = _slotBundles[i];
      if (bundle != null) {
        // Per-slot flow: M1 paths from RawPackBundle metadata.
        final depPaths = <String, String>{};
        for (var j = 0; j < bundle.dependencyCatalogMetadatas.length; j++) {
          final depMeta = bundle.dependencyCatalogMetadatas[j];
          final depPreflight = bundle.dependencyCatalogPreflights[j];
          depPaths[depPreflight.rootId] = depMeta.storedPath;
        }
        allDepPaths.addAll(depPaths);

        persistedCatalogs.add(PersistedCatalog(
          path: bundle.primaryCatalogMetadata.storedPath,
          rootId: bundle.primaryCatalogPreflight.rootId,
          factionDisplayName: slot.catalogName,
          primaryCatRepoPath: slot.catalogPath,
          dependencyStoredPaths: depPaths.isNotEmpty ? depPaths : null,
        ));
      } else if (slot.catalogPath != null) {
        // Reload flow: use whatever path we already have.
        persistedCatalogs.add(PersistedCatalog(
          path: slot.catalogPath!,
          factionDisplayName: slot.catalogName,
          primaryCatRepoPath: slot.catalogPath,
        ));
      }
    }

    // Fall back to legacy _selectedCatalogs if no per-slot data.
    if (persistedCatalogs.isEmpty) {
      for (final catalog in _selectedCatalogs) {
        if (catalog.filePath != null) {
          persistedCatalogs.add(PersistedCatalog(
            path: catalog.filePath!,
            rootId: catalog.rootId,
          ));
        }
      }
    }

    if (persistedCatalogs.isEmpty) return;

    final session = PersistedSession(
      gameSystemPath: gsPath,
      gameSystemDisplayName: gameSystemDisplayName,
      selectedCatalogs: persistedCatalogs,
      repoUrl: _sourceLocator?.sourceUrl,
      branch: _sourceLocator?.branch,
      sourceKey: _sourceLocator?.sourceKey,
      dependencyPaths: allDepPaths,
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

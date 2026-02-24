import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Persisted catalog entry for multi-catalog sessions.
///
/// Phase 11E additions: [factionDisplayName], [primaryCatRepoPath],
/// [dependencyStoredPaths] enable instant boot label restore and
/// offline dependency reload.
class PersistedCatalog {
  /// Absolute path to the catalog file (M1 storage path).
  final String path;

  /// Root ID extracted from the catalog (optional).
  final String? rootId;

  /// Human-readable faction label (e.g. "Tyranids") for instant boot display.
  final String? factionDisplayName;

  /// Repo-relative path of the primary .cat file (e.g. "Tyranids.cat").
  /// Used for re-download fallback when M1 local files are missing.
  final String? primaryCatRepoPath;

  /// Maps targetId → M1 local storage path for dependency catalog files.
  /// Enables offline session reload by reading dependency bytes from disk.
  final Map<String, String>? dependencyStoredPaths;

  const PersistedCatalog({
    required this.path,
    this.rootId,
    this.factionDisplayName,
    this.primaryCatRepoPath,
    this.dependencyStoredPaths,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'rootId': rootId,
        if (factionDisplayName != null)
          'factionDisplayName': factionDisplayName,
        if (primaryCatRepoPath != null)
          'primaryCatRepoPath': primaryCatRepoPath,
        if (dependencyStoredPaths != null &&
            dependencyStoredPaths!.isNotEmpty)
          'dependencyStoredPaths': dependencyStoredPaths,
      };

  factory PersistedCatalog.fromJson(Map<String, dynamic> json) {
    return PersistedCatalog(
      path: json['path'] as String,
      rootId: json['rootId'] as String?,
      factionDisplayName: json['factionDisplayName'] as String?,
      primaryCatRepoPath: json['primaryCatRepoPath'] as String?,
      dependencyStoredPaths:
          (json['dependencyStoredPaths'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)),
    );
  }
}

/// Persisted session state for reload functionality.
///
/// Phase 11E evolves this from v1 (last_session.json) to v2
/// (app_snapshot.json) with [schemaVersion], [gameSystemDisplayName],
/// and [sourceKey] for instant label restore on cold boot.
class PersistedSession {
  /// Format version. Legacy sessions without this field are version 1.
  /// Phase 11E snapshots use version 2.
  final int schemaVersion;

  /// Absolute path to the game system file (M1 storage path).
  final String gameSystemPath;

  /// Human-readable game system label (e.g. "Warhammer 40,000") for
  /// instant boot display without loading file bytes.
  final String? gameSystemDisplayName;

  /// Selected primary catalogs (up to [kMaxSelectedCatalogs]).
  final List<PersistedCatalog> selectedCatalogs;

  /// Legacy: absolute path to primary catalog (for backwards compat).
  @Deprecated('Use selectedCatalogs instead')
  String get primaryCatalogPath =>
      selectedCatalogs.isNotEmpty ? selectedCatalogs.first.path : '';

  /// Repository URL for BSData auto-resolution (optional).
  final String? repoUrl;

  /// Branch name (optional).
  final String? branch;

  /// Stable SourceLocator.sourceKey for boot-time reconstruction
  /// and GitHubSyncStateService lookup.
  final String? sourceKey;

  /// Cached {targetId → localPath} mapping for dependencies.
  final Map<String, String> dependencyPaths;

  /// Timestamp when the session was saved.
  final DateTime savedAt;

  const PersistedSession({
    this.schemaVersion = 2,
    required this.gameSystemPath,
    this.gameSystemDisplayName,
    required this.selectedCatalogs,
    this.repoUrl,
    this.branch,
    this.sourceKey,
    this.dependencyPaths = const {},
    required this.savedAt,
  });

  /// Legacy constructor for backwards compatibility.
  factory PersistedSession.legacy({
    required String gameSystemPath,
    required String primaryCatalogPath,
    String? repoUrl,
    String? branch,
    Map<String, String> dependencyPaths = const {},
    required DateTime savedAt,
  }) {
    return PersistedSession(
      schemaVersion: 1,
      gameSystemPath: gameSystemPath,
      selectedCatalogs: [PersistedCatalog(path: primaryCatalogPath)],
      repoUrl: repoUrl,
      branch: branch,
      dependencyPaths: dependencyPaths,
      savedAt: savedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'gameSystemPath': gameSystemPath,
        if (gameSystemDisplayName != null)
          'gameSystemDisplayName': gameSystemDisplayName,
        'selectedCatalogs':
            selectedCatalogs.map((c) => c.toJson()).toList(),
        'repoUrl': repoUrl,
        'branch': branch,
        if (sourceKey != null) 'sourceKey': sourceKey,
        'dependencyPaths': dependencyPaths,
        'savedAt': savedAt.toIso8601String(),
        // Legacy field for backwards compat
        'primaryCatalogPath': selectedCatalogs.isNotEmpty
            ? selectedCatalogs.first.path
            : null,
      };

  factory PersistedSession.fromJson(Map<String, dynamic> json) {
    // Handle legacy format (single primaryCatalogPath)
    List<PersistedCatalog> catalogs;
    if (json.containsKey('selectedCatalogs')) {
      final catalogsList = json['selectedCatalogs'] as List<dynamic>;
      catalogs = catalogsList
          .map((c) => PersistedCatalog.fromJson(c as Map<String, dynamic>))
          .toList();
    } else if (json.containsKey('primaryCatalogPath')) {
      // Legacy format
      catalogs = [
        PersistedCatalog(path: json['primaryCatalogPath'] as String),
      ];
    } else {
      catalogs = const [];
    }

    return PersistedSession(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      gameSystemPath: json['gameSystemPath'] as String,
      gameSystemDisplayName: json['gameSystemDisplayName'] as String?,
      selectedCatalogs: catalogs,
      repoUrl: json['repoUrl'] as String?,
      branch: json['branch'] as String?,
      sourceKey: json['sourceKey'] as String?,
      dependencyPaths: (json['dependencyPaths'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          {},
      savedAt: DateTime.parse(json['savedAt'] as String),
    );
  }

  /// Checks if the persisted files still exist.
  Future<bool> validatePaths() async {
    final gsExists = await File(gameSystemPath).exists();
    if (!gsExists) return false;

    for (final catalog in selectedCatalogs) {
      final catExists = await File(catalog.path).exists();
      if (!catExists) return false;
    }
    return true;
  }
}

/// Service for persisting and restoring import sessions.
///
/// Stores minimal data needed to reload the last session:
/// - File paths (not content - files are re-read on reload)
/// - Repository configuration
/// - Dependency path mapping
/// - Display labels for instant boot restore (Phase 11E)
///
/// Phase 11E: storage file renamed from `last_session.json` to
/// `app_snapshot.json`. Reads `last_session.json` as migration fallback.
class SessionPersistenceService {
  static const _snapshotFileName = 'app_snapshot.json';
  static const _legacyFileName = 'last_session.json';

  final String _storageRoot;

  SessionPersistenceService({required String storageRoot})
      : _storageRoot = storageRoot;

  /// Gets the snapshot file path.
  String get _snapshotFilePath => p.join(_storageRoot, _snapshotFileName);

  /// Gets the legacy session file path (migration fallback).
  String get _legacyFilePath => p.join(_storageRoot, _legacyFileName);

  /// Saves the current session state.
  ///
  /// Writes atomically: write to temp file, then rename.
  Future<void> saveSession(PersistedSession session) async {
    final file = File(_snapshotFilePath);
    await file.parent.create(recursive: true);
    final tempFile = File('$_snapshotFilePath.tmp');
    await tempFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(session.toJson()),
      flush: true,
    );
    await tempFile.rename(_snapshotFilePath);
  }

  /// Loads the last saved session, if any.
  ///
  /// Tries `app_snapshot.json` first, then falls back to legacy
  /// `last_session.json` for migration. Returns null if no session
  /// exists or if loading fails.
  Future<PersistedSession?> loadSession() async {
    // Try the new snapshot file first
    final session = await _loadFromFile(_snapshotFilePath);
    if (session != null) return session;

    // Fall back to legacy file for migration
    final legacySession = await _loadFromFile(_legacyFilePath);
    if (legacySession != null) {
      // Migrate: save to new location, delete legacy
      await saveSession(legacySession);
      final legacyFile = File(_legacyFilePath);
      if (await legacyFile.exists()) {
        await legacyFile.delete();
      }
    }
    return legacySession;
  }

  Future<PersistedSession?> _loadFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return PersistedSession.fromJson(json);
    } catch (e) {
      // Corrupted or invalid session file
      return null;
    }
  }

  /// Checks if a saved session exists (either new or legacy file).
  Future<bool> hasSession() async {
    final file = File(_snapshotFilePath);
    if (await file.exists()) return true;
    final legacyFile = File(_legacyFilePath);
    return await legacyFile.exists();
  }

  /// Clears the saved session (both new and legacy files).
  Future<void> clearSession() async {
    final file = File(_snapshotFilePath);
    if (await file.exists()) {
      await file.delete();
    }
    final legacyFile = File(_legacyFilePath);
    if (await legacyFile.exists()) {
      await legacyFile.delete();
    }
  }

  /// Loads and validates a session in one call.
  ///
  /// Returns null if no session exists or files no longer exist.
  Future<PersistedSession?> loadValidSession() async {
    final session = await loadSession();
    if (session == null) return null;

    if (!await session.validatePaths()) {
      // Files no longer exist, clear the stale session
      await clearSession();
      return null;
    }

    return session;
  }
}

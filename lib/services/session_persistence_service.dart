import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Persisted catalog entry for multi-catalog sessions.
class PersistedCatalog {
  /// Absolute path to the catalog file.
  final String path;

  /// Root ID extracted from the catalog (optional).
  final String? rootId;

  const PersistedCatalog({
    required this.path,
    this.rootId,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'rootId': rootId,
      };

  factory PersistedCatalog.fromJson(Map<String, dynamic> json) {
    return PersistedCatalog(
      path: json['path'] as String,
      rootId: json['rootId'] as String?,
    );
  }
}

/// Persisted session state for reload functionality.
class PersistedSession {
  /// Absolute path to the game system file.
  final String gameSystemPath;

  /// Selected primary catalogs (up to 3).
  final List<PersistedCatalog> selectedCatalogs;

  /// Legacy: absolute path to primary catalog (for backwards compat).
  @Deprecated('Use selectedCatalogs instead')
  String get primaryCatalogPath =>
      selectedCatalogs.isNotEmpty ? selectedCatalogs.first.path : '';

  /// Repository URL for BSData auto-resolution (optional).
  final String? repoUrl;

  /// Branch name (optional).
  final String? branch;

  /// Cached {targetId → localPath} mapping for dependencies.
  final Map<String, String> dependencyPaths;

  /// Timestamp when the session was saved.
  final DateTime savedAt;

  const PersistedSession({
    required this.gameSystemPath,
    required this.selectedCatalogs,
    this.repoUrl,
    this.branch,
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
      gameSystemPath: gameSystemPath,
      selectedCatalogs: [PersistedCatalog(path: primaryCatalogPath)],
      repoUrl: repoUrl,
      branch: branch,
      dependencyPaths: dependencyPaths,
      savedAt: savedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'gameSystemPath': gameSystemPath,
        'selectedCatalogs':
            selectedCatalogs.map((c) => c.toJson()).toList(),
        'repoUrl': repoUrl,
        'branch': branch,
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
      gameSystemPath: json['gameSystemPath'] as String,
      selectedCatalogs: catalogs,
      repoUrl: json['repoUrl'] as String?,
      branch: json['branch'] as String?,
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
class SessionPersistenceService {
  static const _sessionFileName = 'last_session.json';

  final String _storageRoot;

  SessionPersistenceService({required String storageRoot})
      : _storageRoot = storageRoot;

  /// Gets the session file path.
  String get _sessionFilePath => p.join(_storageRoot, _sessionFileName);

  /// Saves the current session state.
  Future<void> saveSession(PersistedSession session) async {
    final file = File(_sessionFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(session.toJson()),
    );
  }

  /// Loads the last saved session, if any.
  ///
  /// Returns null if no session exists or if loading fails.
  Future<PersistedSession?> loadSession() async {
    try {
      final file = File(_sessionFilePath);
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

  /// Checks if a saved session exists.
  Future<bool> hasSession() async {
    final file = File(_sessionFilePath);
    return await file.exists();
  }

  /// Clears the saved session.
  Future<void> clearSession() async {
    final file = File(_sessionFilePath);
    if (await file.exists()) {
      await file.delete();
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

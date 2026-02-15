import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Persisted session state for reload functionality.
class PersistedSession {
  /// Absolute path to the game system file.
  final String gameSystemPath;

  /// Absolute path to the primary catalog file.
  final String primaryCatalogPath;

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
    required this.primaryCatalogPath,
    this.repoUrl,
    this.branch,
    this.dependencyPaths = const {},
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'gameSystemPath': gameSystemPath,
        'primaryCatalogPath': primaryCatalogPath,
        'repoUrl': repoUrl,
        'branch': branch,
        'dependencyPaths': dependencyPaths,
        'savedAt': savedAt.toIso8601String(),
      };

  factory PersistedSession.fromJson(Map<String, dynamic> json) {
    return PersistedSession(
      gameSystemPath: json['gameSystemPath'] as String,
      primaryCatalogPath: json['primaryCatalogPath'] as String,
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
    final catExists = await File(primaryCatalogPath).exists();
    return gsExists && catExists;
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

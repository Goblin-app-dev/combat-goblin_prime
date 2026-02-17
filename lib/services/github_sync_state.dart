import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Tracked file entry in GitHub sync state.
///
/// Stores both GitHub blob SHA (for update detection) and
/// local storage metadata.
class TrackedFile {
  /// Repository file path (e.g., "Imperium - Space Marines.cat").
  final String repoPath;

  /// File type: 'gst' for game system, 'cat' for catalog.
  final String fileType;

  /// Root ID extracted from the file (catalogue/gameSystem id attribute).
  final String? rootId;

  /// GitHub blob SHA for update detection.
  final String blobSha;

  /// Local storage path (absolute).
  final String? localStoredPath;

  /// Local file ID (SHA-256 of content) for integrity.
  final String? localFileId;

  /// Last time this file was checked for updates.
  final DateTime lastCheckedAt;

  const TrackedFile({
    required this.repoPath,
    required this.fileType,
    this.rootId,
    required this.blobSha,
    this.localStoredPath,
    this.localFileId,
    required this.lastCheckedAt,
  });

  /// Returns true if this file has been downloaded.
  bool get isDownloaded => localStoredPath != null && localFileId != null;

  Map<String, dynamic> toJson() => {
        'repoPath': repoPath,
        'fileType': fileType,
        'rootId': rootId,
        'blobSha': blobSha,
        'localStoredPath': localStoredPath,
        'localFileId': localFileId,
        'lastCheckedAt': lastCheckedAt.toIso8601String(),
      };

  factory TrackedFile.fromJson(Map<String, dynamic> json) {
    return TrackedFile(
      repoPath: json['repoPath'] as String,
      fileType: json['fileType'] as String,
      rootId: json['rootId'] as String?,
      blobSha: json['blobSha'] as String,
      localStoredPath: json['localStoredPath'] as String?,
      localFileId: json['localFileId'] as String?,
      lastCheckedAt: DateTime.parse(json['lastCheckedAt'] as String),
    );
  }

  /// Creates a copy with updated fields.
  TrackedFile copyWith({
    String? repoPath,
    String? fileType,
    String? rootId,
    String? blobSha,
    String? localStoredPath,
    String? localFileId,
    DateTime? lastCheckedAt,
  }) {
    return TrackedFile(
      repoPath: repoPath ?? this.repoPath,
      fileType: fileType ?? this.fileType,
      rootId: rootId ?? this.rootId,
      blobSha: blobSha ?? this.blobSha,
      localStoredPath: localStoredPath ?? this.localStoredPath,
      localFileId: localFileId ?? this.localFileId,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }
}

/// Session pack state tracking selected primaries and dependencies.
class SessionPackState {
  /// Selected primary catalog rootIds (max 3).
  final List<String> selectedPrimaryRootIds;

  /// Auto-resolved dependency rootIds.
  final List<String> dependencyRootIds;

  /// Timestamp when index was last built for this pack.
  final DateTime? indexBuiltAt;

  const SessionPackState({
    required this.selectedPrimaryRootIds,
    this.dependencyRootIds = const [],
    this.indexBuiltAt,
  });

  Map<String, dynamic> toJson() => {
        'selectedPrimaryRootIds': selectedPrimaryRootIds,
        'dependencyRootIds': dependencyRootIds,
        'indexBuiltAt': indexBuiltAt?.toIso8601String(),
      };

  factory SessionPackState.fromJson(Map<String, dynamic> json) {
    return SessionPackState(
      selectedPrimaryRootIds: (json['selectedPrimaryRootIds'] as List<dynamic>)
          .cast<String>()
          .toList(),
      dependencyRootIds: (json['dependencyRootIds'] as List<dynamic>?)
              ?.cast<String>()
              .toList() ??
          const [],
      indexBuiltAt: json['indexBuiltAt'] != null
          ? DateTime.parse(json['indexBuiltAt'] as String)
          : null,
    );
  }
}

/// GitHub sync state for a repository.
///
/// Tracks blob SHAs for update detection separately from M1 storage metadata.
/// This is UI-feature metadata, not engine storage metadata.
class RepoSyncState {
  /// Repository URL (e.g., "https://github.com/BSData/wh40k-10e").
  final String repoUrl;

  /// Branch name.
  final String branch;

  /// Tracked files keyed by repoPath.
  final Map<String, TrackedFile> trackedFiles;

  /// Last time the tree was fetched from GitHub.
  final DateTime? lastTreeFetchAt;

  const RepoSyncState({
    required this.repoUrl,
    required this.branch,
    this.trackedFiles = const {},
    this.lastTreeFetchAt,
  });

  Map<String, dynamic> toJson() => {
        'repoUrl': repoUrl,
        'branch': branch,
        'trackedFiles':
            trackedFiles.map((k, v) => MapEntry(k, v.toJson())),
        'lastTreeFetchAt': lastTreeFetchAt?.toIso8601String(),
      };

  factory RepoSyncState.fromJson(Map<String, dynamic> json) {
    final trackedFilesJson =
        json['trackedFiles'] as Map<String, dynamic>? ?? {};
    return RepoSyncState(
      repoUrl: json['repoUrl'] as String,
      branch: json['branch'] as String,
      trackedFiles: trackedFilesJson.map(
        (k, v) => MapEntry(k, TrackedFile.fromJson(v as Map<String, dynamic>)),
      ),
      lastTreeFetchAt: json['lastTreeFetchAt'] != null
          ? DateTime.parse(json['lastTreeFetchAt'] as String)
          : null,
    );
  }

  /// Creates a copy with updated fields.
  RepoSyncState copyWith({
    String? repoUrl,
    String? branch,
    Map<String, TrackedFile>? trackedFiles,
    DateTime? lastTreeFetchAt,
  }) {
    return RepoSyncState(
      repoUrl: repoUrl ?? this.repoUrl,
      branch: branch ?? this.branch,
      trackedFiles: trackedFiles ?? this.trackedFiles,
      lastTreeFetchAt: lastTreeFetchAt ?? this.lastTreeFetchAt,
    );
  }

  /// Returns files that have different blobSha compared to provided map.
  List<TrackedFile> findUpdatedFiles(Map<String, String> currentBlobShas) {
    final updated = <TrackedFile>[];
    for (final entry in trackedFiles.entries) {
      final currentSha = currentBlobShas[entry.key];
      if (currentSha != null && currentSha != entry.value.blobSha) {
        updated.add(entry.value);
      }
    }
    return updated;
  }
}

/// Complete GitHub sync state across all repositories.
class GitHubSyncState {
  /// Sync state per repository, keyed by sourceKey.
  final Map<String, RepoSyncState> repos;

  /// Current session pack state (selected primaries + dependencies).
  final SessionPackState? sessionPack;

  const GitHubSyncState({
    this.repos = const {},
    this.sessionPack,
  });

  Map<String, dynamic> toJson() => {
        'repos': repos.map((k, v) => MapEntry(k, v.toJson())),
        'sessionPack': sessionPack?.toJson(),
      };

  factory GitHubSyncState.fromJson(Map<String, dynamic> json) {
    final reposJson = json['repos'] as Map<String, dynamic>? ?? {};
    return GitHubSyncState(
      repos: reposJson.map(
        (k, v) => MapEntry(k, RepoSyncState.fromJson(v as Map<String, dynamic>)),
      ),
      sessionPack: json['sessionPack'] != null
          ? SessionPackState.fromJson(json['sessionPack'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Creates a copy with updated fields.
  GitHubSyncState copyWith({
    Map<String, RepoSyncState>? repos,
    SessionPackState? sessionPack,
  }) {
    return GitHubSyncState(
      repos: repos ?? this.repos,
      sessionPack: sessionPack ?? this.sessionPack,
    );
  }
}

/// Service for persisting GitHub sync state.
///
/// Stores sync metadata in appDataRoot/github_sync_state.json.
/// This is separate from M1 engine storage metadata.
class GitHubSyncStateService {
  static const _stateFileName = 'github_sync_state.json';

  final String _storageRoot;

  GitHubSyncStateService({required String storageRoot})
      : _storageRoot = storageRoot;

  String get _stateFilePath => p.join(_storageRoot, _stateFileName);

  /// Loads the current sync state.
  ///
  /// Returns empty state if file doesn't exist or is invalid.
  Future<GitHubSyncState> loadState() async {
    try {
      final file = File(_stateFilePath);
      if (!await file.exists()) {
        return const GitHubSyncState();
      }

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return GitHubSyncState.fromJson(json);
    } catch (e) {
      // Corrupted or invalid state file - return empty state
      return const GitHubSyncState();
    }
  }

  /// Saves the sync state.
  Future<void> saveState(GitHubSyncState state) async {
    final file = File(_stateFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
      flush: true,
    );
  }

  /// Updates a single repository's sync state.
  Future<void> updateRepoState(String sourceKey, RepoSyncState repoState) async {
    final state = await loadState();
    final updatedRepos = Map<String, RepoSyncState>.from(state.repos);
    updatedRepos[sourceKey] = repoState;
    await saveState(state.copyWith(repos: updatedRepos));
  }

  /// Updates tracked file within a repository.
  Future<void> updateTrackedFile(
    String sourceKey,
    TrackedFile trackedFile,
  ) async {
    final state = await loadState();
    final repoState = state.repos[sourceKey];
    if (repoState == null) return;

    final updatedFiles = Map<String, TrackedFile>.from(repoState.trackedFiles);
    updatedFiles[trackedFile.repoPath] = trackedFile;
    await updateRepoState(
      sourceKey,
      repoState.copyWith(trackedFiles: updatedFiles),
    );
  }

  /// Updates the session pack state.
  Future<void> updateSessionPack(SessionPackState packState) async {
    final state = await loadState();
    await saveState(state.copyWith(sessionPack: packState));
  }

  /// Clears the sync state.
  Future<void> clearState() async {
    final file = File(_stateFilePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Gets files that need updating for a repository.
  ///
  /// Compares stored blobShas against current tree.
  Future<List<TrackedFile>> getFilesNeedingUpdate(
    String sourceKey,
    Map<String, String> currentBlobShas,
  ) async {
    final state = await loadState();
    final repoState = state.repos[sourceKey];
    if (repoState == null) return const [];

    return repoState.findUpdatedFiles(currentBlobShas);
  }
}

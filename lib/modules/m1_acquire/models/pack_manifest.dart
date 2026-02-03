import 'dependency_record.dart';
import 'source_locator.dart';

/// Persisted record of an installed pack for update checking.
/// Survives dependency deletion.
class PackManifest {
  /// Deterministic pack identifier.
  final String packId;

  /// Installation timestamp.
  final DateTime installedAt;

  /// Game system rootId.
  final String gameSystemRootId;

  /// Game system SHA-256 hash.
  final String gameSystemFileId;

  /// Game system revision.
  final String? gameSystemRevision;

  /// Game system git blob SHA for update checking.
  final String? gameSystemGitBlobSha;

  /// Primary catalog rootId.
  final String primaryCatalogRootId;

  /// Primary catalog SHA-256 hash.
  final String primaryCatalogFileId;

  /// Primary catalog revision.
  final String? primaryCatalogRevision;

  /// Primary catalog git blob SHA for update checking.
  final String? primaryCatalogGitBlobSha;

  /// Dependency version records.
  final List<DependencyRecord> dependencies;

  /// Upstream source information.
  final SourceLocator source;

  const PackManifest({
    required this.packId,
    required this.installedAt,
    required this.gameSystemRootId,
    required this.gameSystemFileId,
    this.gameSystemRevision,
    this.gameSystemGitBlobSha,
    required this.primaryCatalogRootId,
    required this.primaryCatalogFileId,
    this.primaryCatalogRevision,
    this.primaryCatalogGitBlobSha,
    required this.dependencies,
    required this.source,
  });
}

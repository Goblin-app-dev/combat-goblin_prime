/// Version information for a single dependency catalog.
/// Survives raw file deletion for update checking.
class DependencyRecord {
  /// Catalog's internal identifier.
  final String rootId;

  /// SHA-256 hash of bytes (local identity).
  final String fileId;

  /// XML revision attribute (for display).
  final String? revision;

  /// Git blob SHA for cheap update checking.
  final String? gitBlobSha;

  const DependencyRecord({
    required this.rootId,
    required this.fileId,
    this.revision,
    this.gitBlobSha,
  });
}

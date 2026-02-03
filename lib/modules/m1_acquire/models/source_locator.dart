/// Identifies the upstream source for update checking.
class SourceLocator {
  /// Stable internal identifier (e.g., "bsdata_wh40k_10e").
  final String sourceKey;

  /// Repository URL (e.g., "https://github.com/BSData/wh40k-10e").
  final String sourceUrl;

  /// Branch name (defaults to default branch if null).
  final String? branch;

  /// Optional: pin to specific commit.
  final String? commitSha;

  const SourceLocator({
    required this.sourceKey,
    required this.sourceUrl,
    this.branch,
    this.commitSha,
  });
}

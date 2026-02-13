/// Immutable configuration for [StructuredSearchService].
///
/// Pure data only — limits, thresholds, toggles.
/// Default values produce identical behavior to an unconfigured service.
class SearchConfig {
  /// Maximum number of results returned when [SearchRequest.limit] is not set.
  final int defaultLimit;

  /// Whether fuzzy matching is enabled by default.
  final bool fuzzyEnabled;

  /// Maximum edit distance for fuzzy matching (ignored if [fuzzyEnabled] is
  /// false).
  final int fuzzyMaxEditDistance;

  const SearchConfig({
    this.defaultLimit = 20,
    this.fuzzyEnabled = false,
    this.fuzzyMaxEditDistance = 2,
  });
}

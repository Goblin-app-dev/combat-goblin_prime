/// Sort strategy for M10 search results.
///
/// All sort strategies must produce deterministic, stable ordering.
enum SearchSort {
  /// Sort by match relevance score. Deterministic: ties broken by
  /// docType → canonicalKey → docId.
  relevance,

  /// Sort alphabetically by displayName.
  alphabetical,

  /// Group by docType first, then alphabetical within each group.
  docTypeThenAlphabetical,
}

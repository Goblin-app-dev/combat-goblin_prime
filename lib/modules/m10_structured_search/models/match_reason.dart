/// Reason a document matched a search request.
///
/// Values describe index-level match mechanics only.
/// Must not imply evaluation, applicability, or modifier output.
enum MatchReason {
  /// Exact or prefix match on canonicalKey.
  canonicalKeyMatch,

  /// Match on one or more indexed keyword tokens.
  keywordMatch,

  /// Match on an indexed characteristic name or value.
  characteristicMatch,

  /// Bounded fuzzy match (edit-distance or trigram).
  fuzzyMatch,
}

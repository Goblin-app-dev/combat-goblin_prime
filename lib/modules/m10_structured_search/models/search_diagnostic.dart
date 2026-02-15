/// Closed set of M10-only diagnostic codes.
///
/// These are distinct from M9 [IndexDiagnosticCode] and must not be
/// conflated with indexing diagnostics.
///
/// ## Uniqueness contract
///
/// Diagnostics emitted by [StructuredSearchService] are:
///   - **Unique**: at most one diagnostic per unsupported dimension per request
///     (e.g. one [invalidFilter] for "keyword filter unsupported for rule docs",
///     not one per keyword).
///   - **Stable order**: sorted by [SearchDiagnosticCode] enum index, then by
///     message (lexicographic). Identical requests produce identical diagnostic
///     lists.
enum SearchDiagnosticCode {
  /// A filter dimension is unsupported for the target document type, or a
  /// filter field references an invalid/unknown value.
  ///
  /// Emitted at most once per unsupported dimension per request. For example,
  /// keyword filtering on rule docs emits a single diagnostic regardless of
  /// how many keywords were requested.
  invalidFilter,

  /// The query contains no actionable search criteria.
  emptyQuery,

  /// Results were truncated to the request limit.
  resultLimitApplied,

  /// The requested [SearchMode] is not yet supported.
  unsupportedMode,
}

/// A diagnostic emitted during M10 query resolution.
///
/// Diagnostics are informational — they do not prevent result delivery.
class SearchDiagnostic {
  /// Diagnostic code from the closed set.
  final SearchDiagnosticCode code;

  /// Human-readable description.
  final String message;

  /// Optional structured context for tooling (deterministic-friendly).
  final Map<String, String>? context;

  const SearchDiagnostic({
    required this.code,
    required this.message,
    this.context,
  });
}

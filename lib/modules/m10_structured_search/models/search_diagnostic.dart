/// Closed set of M10-only diagnostic codes.
///
/// These are distinct from M9 [IndexDiagnosticCode] and must not be
/// conflated with indexing diagnostics.
enum SearchDiagnosticCode {
  /// A filter field references an invalid or unknown value.
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

import 'search_diagnostic.dart';
import 'search_hit.dart';

/// Result of an M10 structured search.
///
/// ## STATUS: FROZEN (2026-02-14)
///
/// ## Frozen Invariants — Ordering Semantics
///
/// [hits] are deterministically ordered by the service using explicit
/// tie-break rules that vary by [SearchSort] strategy:
///
/// - **alphabetical**: canonicalKey → docType → docId
/// - **docTypeThenAlphabetical**: docType → canonicalKey → docId
/// - **relevance**: matchReasons.length (desc) → docType → canonicalKey → docId
///
/// All chains terminate at docId for total ordering. When
/// [SortDirection.descending] is set, the entire comparator is inverted.
///
/// Callers may rely on this ordering being stable across runs with
/// identical input. Same [IndexBundle] + same [SearchRequest] → identical
/// [SearchResult] (including [diagnostics] order).
///
/// [diagnostics] are sorted by [SearchDiagnosticCode] enum index, then by
/// message (lexicographic). At most one diagnostic per unsupported dimension.
class SearchResult {
  /// Matched documents in deterministic order.
  final List<SearchHit> hits;

  /// M10-only diagnostics emitted during query resolution.
  final List<SearchDiagnostic> diagnostics;

  const SearchResult({
    required this.hits,
    this.diagnostics = const [],
  });

  /// Convenience: empty result with no diagnostics.
  static const empty = SearchResult(hits: []);
}

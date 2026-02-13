import 'search_diagnostic.dart';
import 'search_hit.dart';

/// Result of an M10 structured search.
///
/// [hits] are deterministically ordered by the service using explicit
/// tie-break rules:
///   1. Score (if applicable)
///   2. docType (enum index)
///   3. canonicalKey (lexicographic)
///   4. docId (lexicographic)
///
/// Callers may rely on this ordering being stable across runs with
/// identical input.
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

import 'search_doc_type.dart';
import 'search_mode.dart';
import 'search_sort.dart';
import 'sort_direction.dart';

/// A deterministic query over an M9 [IndexBundle].
///
/// ## STATUS: FROZEN (2026-02-14)
///
/// This is a pure request container — no parsing logic, no tokenization.
/// All filtering and matching is performed by [StructuredSearchService].
///
/// ## Frozen Invariants — Ordering Semantics
///
/// The [sort] field selects a deterministic comparator chain. All chains
/// terminate at [SearchHit.docId] to guarantee total ordering. The [limit]
/// field truncates after sorting; if truncation occurs, a
/// [SearchDiagnosticCode.resultLimitApplied] diagnostic is emitted.
///
/// A request must include at least one search driver ([text], [keywords],
/// or [characteristicFilters]) to produce results. [docTypes] alone is
/// not a driver.
class SearchRequest {
  /// Free-text query string. Interpretation depends on [mode].
  final String? text;

  /// Restrict results to these document types. Null means all types.
  final Set<SearchDocType>? docTypes;

  /// Filter by keyword tokens present in the document's keyword index.
  final Set<String>? keywords;

  /// Filter by indexed characteristic name/value pairs.
  /// Key = characteristic name (e.g. "T"), value = query string (e.g. "4").
  final Map<String, String>? characteristicFilters;

  /// Query execution mode.
  final SearchMode mode;

  /// Maximum number of results to return.
  final int limit;

  /// Sort strategy for results.
  final SearchSort sort;

  /// Sort direction.
  final SortDirection sortDirection;

  const SearchRequest({
    this.text,
    this.docTypes,
    this.keywords,
    this.characteristicFilters,
    this.mode = SearchMode.structured,
    this.limit = 20,
    this.sort = SearchSort.relevance,
    this.sortDirection = SortDirection.ascending,
  });
}

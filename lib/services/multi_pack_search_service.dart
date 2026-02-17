import 'dart:collection';

import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';

/// Extended search hit that includes source pack information.
class MultiPackSearchHit {
  /// The original search hit from M10.
  final SearchHit hit;

  /// Source pack key (e.g., catalog rootId) for deterministic tie-breaking.
  final String sourcePackKey;

  /// Index of the source pack in the session (for display ordering).
  final int sourcePackIndex;

  const MultiPackSearchHit({
    required this.hit,
    required this.sourcePackKey,
    required this.sourcePackIndex,
  });

  // Delegate to underlying hit
  String get docId => hit.docId;
  SearchDocType get docType => hit.docType;
  String get canonicalKey => hit.canonicalKey;
  String get displayName => hit.displayName;
  List<MatchReason> get matchReasons => hit.matchReasons;
}

/// Result of a multi-pack search.
class MultiPackSearchResult {
  /// Merged hits in deterministic order.
  final List<MultiPackSearchHit> hits;

  /// Merged diagnostics from all packs.
  final List<SearchDiagnostic> diagnostics;

  /// Whether the result limit was applied after merging.
  final bool resultLimitApplied;

  /// Total hits before limit was applied.
  final int totalHitsBeforeLimit;

  const MultiPackSearchResult({
    required this.hits,
    this.diagnostics = const [],
    this.resultLimitApplied = false,
    this.totalHitsBeforeLimit = 0,
  });

  static const empty = MultiPackSearchResult(hits: []);
}

/// Service for searching across multiple IndexBundles.
///
/// Implements the deterministic multi-IndexBundle search merge strategy:
/// 1. Run M10 search on each bundle
/// 2. Merge hits into one list
/// 3. Stable sort with tie-breaks: docType → canonicalKey → docId → sourcePackKey
/// 4. Deduplicate by docId (prefer earlier pack order)
/// 5. Apply limit after merge
///
/// This service is stateless - IndexBundles are passed per-call.
class MultiPackSearchService {
  final StructuredSearchService _searchService;

  MultiPackSearchService({StructuredSearchService? searchService})
      : _searchService = searchService ?? StructuredSearchService();

  /// Searches across multiple IndexBundles and merges results.
  ///
  /// [bundles] is a map of packKey → IndexBundle.
  /// [bundleOrder] defines the deterministic ordering for tie-breaks
  /// (typically the user's selection order).
  ///
  /// Returns merged results with deterministic ordering.
  MultiPackSearchResult search(
    Map<String, IndexBundle> bundles,
    SearchRequest request, {
    List<String>? bundleOrder,
  }) {
    if (bundles.isEmpty) {
      return const MultiPackSearchResult(hits: []);
    }

    // Use provided order or sort keys alphabetically for determinism
    final orderedKeys = bundleOrder ?? (bundles.keys.toList()..sort());
    final allHits = <MultiPackSearchHit>[];
    final allDiagnostics = <SearchDiagnostic>[];
    final seenDocIds = <String>{};

    // Run search on each bundle
    for (var i = 0; i < orderedKeys.length; i++) {
      final packKey = orderedKeys[i];
      final bundle = bundles[packKey];
      if (bundle == null) continue;

      final result = _searchService.search(bundle, request);

      // Collect hits with pack context
      for (final hit in result.hits) {
        allHits.add(MultiPackSearchHit(
          hit: hit,
          sourcePackKey: packKey,
          sourcePackIndex: i,
        ));
      }

      // Collect diagnostics (except resultLimitApplied - we'll handle that)
      for (final diag in result.diagnostics) {
        if (diag.code != SearchDiagnosticCode.resultLimitApplied) {
          allDiagnostics.add(diag);
        }
      }
    }

    // Sort with deterministic tie-breaks
    _sortHits(allHits, request.sort, request.sortDirection);

    // Deduplicate by docId (prefer earlier pack order due to stable sort)
    final deduplicatedHits = <MultiPackSearchHit>[];
    for (final hit in allHits) {
      if (!seenDocIds.contains(hit.docId)) {
        seenDocIds.add(hit.docId);
        deduplicatedHits.add(hit);
      }
    }

    // Apply limit after merge
    final totalBeforeLimit = deduplicatedHits.length;
    final limitApplied = totalBeforeLimit > request.limit;
    final limitedHits = limitApplied
        ? deduplicatedHits.sublist(0, request.limit)
        : deduplicatedHits;

    if (limitApplied) {
      allDiagnostics.add(SearchDiagnostic(
        code: SearchDiagnosticCode.resultLimitApplied,
        message: 'Results truncated from $totalBeforeLimit to ${request.limit} '
            'after merging ${bundles.length} packs.',
      ));
    }

    // Deduplicate diagnostics
    final uniqueDiagnostics = _deduplicateDiagnostics(allDiagnostics);

    return MultiPackSearchResult(
      hits: limitedHits,
      diagnostics: uniqueDiagnostics,
      resultLimitApplied: limitApplied,
      totalHitsBeforeLimit: totalBeforeLimit,
    );
  }

  /// Suggests completions across multiple IndexBundles.
  ///
  /// Merges, deduplicates, and sorts suggestions from all bundles.
  List<String> suggest(
    Map<String, IndexBundle> bundles,
    String prefix, {
    int limit = 10,
  }) {
    if (bundles.isEmpty || prefix.isEmpty) {
      return const [];
    }

    // Collect suggestions from all bundles
    final merged = SplayTreeSet<String>();
    for (final bundle in bundles.values) {
      final suggestions = _searchService.suggest(bundle, prefix, limit: limit);
      merged.addAll(suggestions);
    }

    return merged.take(limit).toList();
  }

  /// Resolves a docId across multiple bundles.
  ///
  /// Returns the first match found in bundle order.
  MultiPackSearchHit? resolveByDocId(
    Map<String, IndexBundle> bundles,
    String docId, {
    List<String>? bundleOrder,
  }) {
    if (bundles.isEmpty) return null;

    final orderedKeys = bundleOrder ?? (bundles.keys.toList()..sort());

    for (var i = 0; i < orderedKeys.length; i++) {
      final packKey = orderedKeys[i];
      final bundle = bundles[packKey];
      if (bundle == null) continue;

      final hit = _searchService.resolveByDocId(bundle, docId);
      if (hit != null) {
        return MultiPackSearchHit(
          hit: hit,
          sourcePackKey: packKey,
          sourcePackIndex: i,
        );
      }
    }

    return null;
  }

  /// Sorts hits with deterministic tie-breaks.
  ///
  /// Chain: sort strategy → docType → canonicalKey → docId → sourcePackKey
  void _sortHits(
    List<MultiPackSearchHit> hits,
    SearchSort sort,
    SortDirection direction,
  ) {
    int Function(MultiPackSearchHit, MultiPackSearchHit) comparator;

    switch (sort) {
      case SearchSort.alphabetical:
        comparator = (a, b) {
          var cmp = a.canonicalKey.compareTo(b.canonicalKey);
          if (cmp != 0) return cmp;
          cmp = a.docType.index.compareTo(b.docType.index);
          if (cmp != 0) return cmp;
          cmp = a.docId.compareTo(b.docId);
          if (cmp != 0) return cmp;
          return a.sourcePackKey.compareTo(b.sourcePackKey);
        };

      case SearchSort.docTypeThenAlphabetical:
        comparator = (a, b) {
          var cmp = a.docType.index.compareTo(b.docType.index);
          if (cmp != 0) return cmp;
          cmp = a.canonicalKey.compareTo(b.canonicalKey);
          if (cmp != 0) return cmp;
          cmp = a.docId.compareTo(b.docId);
          if (cmp != 0) return cmp;
          return a.sourcePackKey.compareTo(b.sourcePackKey);
        };

      case SearchSort.relevance:
        comparator = (a, b) {
          // Higher relevance first
          var cmp = b.matchReasons.length.compareTo(a.matchReasons.length);
          if (cmp != 0) return cmp;
          cmp = a.docType.index.compareTo(b.docType.index);
          if (cmp != 0) return cmp;
          cmp = a.canonicalKey.compareTo(b.canonicalKey);
          if (cmp != 0) return cmp;
          cmp = a.docId.compareTo(b.docId);
          if (cmp != 0) return cmp;
          return a.sourcePackKey.compareTo(b.sourcePackKey);
        };
    }

    // Apply direction
    if (direction == SortDirection.descending) {
      final original = comparator;
      comparator = (a, b) => original(b, a);
    }

    hits.sort(comparator);
  }

  /// Deduplicates diagnostics by code + message.
  List<SearchDiagnostic> _deduplicateDiagnostics(
    List<SearchDiagnostic> diagnostics,
  ) {
    final seen = <String>{};
    final unique = <SearchDiagnostic>[];

    for (final diag in diagnostics) {
      final key = '${diag.code.index}:${diag.message}';
      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(diag);
      }
    }

    // Sort by code index then message
    unique.sort((a, b) {
      final codeCompare = a.code.index.compareTo(b.code.index);
      if (codeCompare != 0) return codeCompare;
      return a.message.compareTo(b.message);
    });

    return unique;
  }
}

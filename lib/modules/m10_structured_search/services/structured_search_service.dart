import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';

import '../models/search_config.dart';
import '../models/search_diagnostic.dart';
import '../models/search_hit.dart';
import '../models/search_request.dart';
import '../models/search_result.dart';

/// Deterministic structured search over an M9 [IndexBundle].
///
/// This service is stateless with respect to index data — the [IndexBundle]
/// is passed per-call so the service holds no mutable references.
///
/// ## Determinism guarantees
///
/// All results are deterministically ordered using explicit tie-break rules:
///   1. Score (if applicable, higher first)
///   2. docType (enum index, ascending)
///   3. canonicalKey (lexicographic, ascending)
///   4. docId (lexicographic, ascending)
///
/// No iteration over unordered maps. No time-based or random scoring.
///
/// ## M9 usage policy
///
/// Uses M9 lookup methods ([IndexBundle.unitByDocId], etc.) for direct
/// resolution. Search and filter logic operates on raw indexed structures
/// (sorted lists, SplayTreeMap indices) to avoid coupling to M9's
/// convenience query surface.
class StructuredSearchService {
  /// Optional configuration for search behavior.
  final SearchConfig config;

  StructuredSearchService({this.config = const SearchConfig()});

  /// Execute a structured search against [index].
  ///
  /// Returns a [SearchResult] with deterministically ordered hits.
  /// Emits [SearchDiagnostic]s for empty queries or applied limits.
  SearchResult search(IndexBundle index, SearchRequest request) {
    final diagnostics = <SearchDiagnostic>[];

    final hasText = request.text != null && request.text!.isNotEmpty;
    final hasKeywords = request.keywords != null && request.keywords!.isNotEmpty;
    final hasCharFilters =
        request.characteristicFilters != null &&
        request.characteristicFilters!.isNotEmpty;
    final hasDocTypeFilter =
        request.docTypes != null && request.docTypes!.isNotEmpty;

    if (!hasText && !hasKeywords && !hasCharFilters && !hasDocTypeFilter) {
      diagnostics.add(
        const SearchDiagnostic(
          code: SearchDiagnosticCode.emptyQuery,
          message: 'No search criteria provided.',
        ),
      );
      return SearchResult(hits: const [], diagnostics: diagnostics);
    }

    // TODO(m10): Implement search logic over IndexBundle raw indices.
    return SearchResult(hits: const [], diagnostics: diagnostics);
  }

  /// Suggest canonical keys matching [prefix] for autocomplete.
  ///
  /// Returns up to [limit] suggestions in deterministic lexicographic order.
  List<String> suggest(IndexBundle index, String prefix, {int limit = 10}) {
    // TODO(m10): Implement prefix matching over IndexBundle canonical keys.
    return const [];
  }

  /// Resolve a single document by its exact [docId].
  ///
  /// Returns null if no document with [docId] exists in [index].
  SearchHit? resolveByDocId(IndexBundle index, String docId) {
    // TODO(m10): Implement direct lookup via IndexBundle.unitByDocId /
    //           weaponByDocId / ruleByDocId.
    return null;
  }
}

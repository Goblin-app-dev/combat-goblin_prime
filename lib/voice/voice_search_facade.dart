import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';
import 'package:combat_goblin_prime/services/multi_pack_search_service.dart';

import 'models/spoken_entity.dart';
import 'models/voice_search_response.dart';
import 'services/search_result_grouper.dart';

/// App-layer voice search entrypoint.
///
/// Calls M10 [StructuredSearchService] per slot bundle directly —
/// bypasses [MultiPackSearchService] to preserve duplicate variants that
/// would otherwise be deduplicated by docId.
///
/// Slot bundles are iterated in lexicographic key order for determinism
/// (e.g. 'slot_0' before 'slot_1').
///
/// Returns a [VoiceSearchResponse] with deterministically grouped and
/// ordered [SpokenEntity] results.
class VoiceSearchFacade {
  final _search = StructuredSearchService();
  final _multiPackService = MultiPackSearchService();
  final _grouper = const SearchResultGrouper();

  /// Search [slotBundles] for [query], grouping results by canonicalKey
  /// per slot.
  ///
  /// [slotBundles] is keyed by slot id ('slot_0', 'slot_1', ...).
  /// Returns [VoiceSearchResponse.empty] for empty query or empty bundles.
  VoiceSearchResponse searchText(
    Map<String, IndexBundle> slotBundles,
    String query, {
    int limit = 50,
  }) {
    if (query.isEmpty || slotBundles.isEmpty) {
      return VoiceSearchResponse.empty;
    }

    final allEntities = <SpokenEntity>[];
    final allDiagnostics = <SearchDiagnostic>[];

    // Lexicographic order ensures slot_0 always processed before slot_1.
    final sortedKeys = slotBundles.keys.toList()..sort();

    for (final slotId in sortedKeys) {
      final bundle = slotBundles[slotId]!;
      final result = _search.search(
        bundle,
        SearchRequest(text: query, limit: limit, sort: SearchSort.relevance),
      );
      allDiagnostics.addAll(result.diagnostics);
      allEntities.addAll(_grouper.group(slotId, result.hits));
    }

    // Final cross-slot sort: slotId → groupKey → first variant tieBreakKey.
    allEntities.sort((a, b) {
      final sc = a.slotId.compareTo(b.slotId);
      if (sc != 0) return sc;
      final gc = a.groupKey.compareTo(b.groupKey);
      if (gc != 0) return gc;
      return a.variants.first.tieBreakKey
          .compareTo(b.variants.first.tieBreakKey);
    });

    return VoiceSearchResponse(
      entities: List.unmodifiable(allEntities),
      diagnostics: List.unmodifiable(allDiagnostics),
      spokenSummary: _buildSummary(allEntities, query),
    );
  }

  /// Typeahead suggestions. Delegates to [MultiPackSearchService.suggest].
  List<String> suggest(
    Map<String, IndexBundle> slotBundles,
    String prefix, {
    int limit = 8,
  }) {
    return _multiPackService.suggest(slotBundles, prefix, limit: limit);
  }

  /// Pure function — no timestamps, no randomness.
  String _buildSummary(List<SpokenEntity> entities, String query) {
    if (entities.isEmpty) return 'No results for "$query".';
    final totalVariants =
        entities.fold<int>(0, (s, e) => s + e.variants.length);
    if (entities.length == 1) {
      final e = entities.first;
      if (e.variants.length > 1) {
        return 'Found ${e.variants.length} variants of "${e.displayName}". Say "next" to cycle.';
      }
      return 'Found "${e.displayName}".';
    }
    return 'Found $totalVariants results across ${entities.length} groups for "$query".';
  }
}

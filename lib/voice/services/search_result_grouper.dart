import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';

import '../models/spoken_entity.dart';
import '../models/spoken_variant.dart';

/// Groups [SearchHit] results from a single slot into [SpokenEntity] groups.
///
/// Grouping key: (slotId, canonicalKey) — slot-local only.
/// Phase 12A: no cross-slot grouping.
///
/// Pure function helper — no state, no side effects.
class SearchResultGrouper {
  const SearchResultGrouper();

  /// Group [hits] from [slotId] into a deterministically sorted
  /// [SpokenEntity] list.
  ///
  /// Variant ordering within each entity: [SpokenVariant.tieBreakKey] ascending.
  /// Entity ordering: groupKey → first variant tieBreakKey.
  List<SpokenEntity> group(String slotId, List<SearchHit> hits) {
    if (hits.isEmpty) return const [];

    // Build groupKey → List<SpokenVariant> map.
    // Also track first-seen displayName per groupKey for the entity label.
    final groups = <String, List<SpokenVariant>>{};
    final displayNames = <String, String>{};

    for (final hit in hits) {
      final groupKey = hit.canonicalKey;
      final variant = SpokenVariant.fromHit(hit, slotId);
      groups.putIfAbsent(groupKey, () => []).add(variant);
      displayNames.putIfAbsent(groupKey, () => hit.displayName);
    }

    final entities = <SpokenEntity>[];

    for (final entry in groups.entries) {
      final groupKey = entry.key;
      // Sort variants by tieBreakKey ascending.
      final variants = entry.value
        ..sort((a, b) => a.tieBreakKey.compareTo(b.tieBreakKey));

      entities.add(SpokenEntity(
        slotId: slotId,
        groupKey: groupKey,
        displayName: displayNames[groupKey]!,
        variants: List.unmodifiable(variants),
      ));
    }

    // Sort entities: groupKey ascending, then first variant tieBreakKey.
    entities.sort((a, b) {
      final gk = a.groupKey.compareTo(b.groupKey);
      if (gk != 0) return gk;
      return a.variants.first.tieBreakKey
          .compareTo(b.variants.first.tieBreakKey);
    });

    return entities;
  }
}

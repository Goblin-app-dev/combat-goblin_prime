import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';

/// A single underlying search hit in a specific catalog slot.
///
/// Invariants:
/// - [sourceSlotId] is always a concrete slot id ('slot_0', 'slot_1', etc.);
///   never null, never 'multi-slot'.
/// - [tieBreakKey] is always '$canonicalKey\x00$docId' (null-byte separator).
class SpokenVariant {
  /// Concrete slot id where this hit was found ('slot_0', 'slot_1', etc.).
  final String sourceSlotId;

  final SearchDocType docType;
  final String docId;
  final String canonicalKey;
  final String displayName;
  final List<MatchReason> matchReasons;

  /// Stable sort key: '$canonicalKey\x00$docId'.
  final String tieBreakKey;

  const SpokenVariant({
    required this.sourceSlotId,
    required this.docType,
    required this.docId,
    required this.canonicalKey,
    required this.displayName,
    required this.matchReasons,
    required this.tieBreakKey,
  });

  factory SpokenVariant.fromHit(SearchHit hit, String slotId) {
    return SpokenVariant(
      sourceSlotId: slotId,
      docType: hit.docType,
      docId: hit.docId,
      canonicalKey: hit.canonicalKey,
      displayName: hit.displayName,
      matchReasons: hit.matchReasons,
      tieBreakKey: '${hit.canonicalKey}\x00${hit.docId}',
    );
  }
}

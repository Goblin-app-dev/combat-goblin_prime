import 'spoken_variant.dart';

/// A grouped voice entity: all [SpokenVariant]s sharing the same
/// [canonicalKey] within the same catalog slot.
///
/// Invariants:
/// - [slotId] is always a concrete slot id ('slot_0', 'slot_1', etc.).
///   Cross-slot grouping is deferred to a future phase.
/// - [variants] is non-empty and sorted by [SpokenVariant.tieBreakKey]
///   ascending.
/// - [primaryVariant] is always [variants.first] (deterministic auto-pick).
class SpokenEntity {
  /// Concrete slot id for this group ('slot_0', 'slot_1', etc.).
  final String slotId;

  /// Normalized group key derived from [SpokenVariant.canonicalKey].
  final String groupKey;

  /// Human-readable label for display and speech.
  final String displayName;

  /// Non-empty list of variants, sorted by [SpokenVariant.tieBreakKey].
  final List<SpokenVariant> variants;

  const SpokenEntity({
    required this.slotId,
    required this.groupKey,
    required this.displayName,
    required this.variants,
  });

  /// Deterministic auto-pick: always [variants.first].
  SpokenVariant get primaryVariant => variants.first;
}

import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

import 'indexed_characteristic.dart';
import 'indexed_cost.dart';

/// Unit/datasheet document for search indexing.
///
/// Identity vs Search:
/// - docId: Globally unique stable identifier (unit:{entryId})
/// - canonicalKey: Normalized name for search grouping (normalize(name))
///
/// Unit names are mostly unique, but using entryId ensures stability
/// across variants, punctuation changes, and localization.
///
/// Part of M9 Index-Core (Search).
class UnitDoc {
  /// Globally unique document ID (format: "unit:{entryId}").
  final String docId;

  /// Canonical search key (normalized name for grouping).
  final String canonicalKey;

  /// Original entry ID from M5 (for provenance).
  final String entryId;

  /// Display name of the unit.
  final String name;

  /// Unit statistics (M, T, SV, W, LD, OC, etc.).
  final List<IndexedCharacteristic> characteristics;

  /// Keyword tokens (lowercase, normalized).
  final List<String> keywordTokens;

  /// Category tokens (lowercase, normalized).
  final List<String> categoryTokens;

  /// References to WeaponDoc docIds.
  final List<String> weaponDocRefs;

  /// References to RuleDoc docIds (abilities, special rules).
  final List<String> ruleDocRefs;

  /// Point costs and other resource costs.
  final List<IndexedCost> costs;

  /// Source file ID (for provenance).
  final String sourceFileId;

  /// Source node reference (for provenance).
  final NodeRef sourceNode;

  const UnitDoc({
    required this.docId,
    required this.canonicalKey,
    required this.entryId,
    required this.name,
    required this.characteristics,
    required this.keywordTokens,
    required this.categoryTokens,
    required this.weaponDocRefs,
    required this.ruleDocRefs,
    required this.costs,
    required this.sourceFileId,
    required this.sourceNode,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnitDoc &&
          runtimeType == other.runtimeType &&
          docId == other.docId;

  @override
  int get hashCode => docId.hashCode;

  @override
  String toString() => 'UnitDoc($docId: "$name")';
}

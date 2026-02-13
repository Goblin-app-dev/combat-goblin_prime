import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

import 'indexed_characteristic.dart';
import 'indexed_cost.dart';

/// Unit/datasheet document for search indexing.
///
/// Represents a player-facing unit flattened for lookup by name,
/// keyword filtering, and voice-ready stat retrieval.
///
/// Part of M9 Index-Core (Search).
class UnitDoc {
  /// Canonical document ID (stable, deterministic).
  final String docId;

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
          docId == other.docId &&
          entryId == other.entryId &&
          name == other.name &&
          _listEquals(characteristics, other.characteristics) &&
          _listEquals(keywordTokens, other.keywordTokens) &&
          _listEquals(categoryTokens, other.categoryTokens) &&
          _listEquals(weaponDocRefs, other.weaponDocRefs) &&
          _listEquals(ruleDocRefs, other.ruleDocRefs) &&
          _listEquals(costs, other.costs) &&
          sourceFileId == other.sourceFileId &&
          sourceNode == other.sourceNode;

  @override
  int get hashCode =>
      docId.hashCode ^
      entryId.hashCode ^
      name.hashCode ^
      Object.hashAll(characteristics) ^
      Object.hashAll(keywordTokens) ^
      Object.hashAll(categoryTokens) ^
      Object.hashAll(weaponDocRefs) ^
      Object.hashAll(ruleDocRefs) ^
      Object.hashAll(costs) ^
      sourceFileId.hashCode ^
      sourceNode.hashCode;

  @override
  String toString() => 'UnitDoc($docId: "$name")';

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

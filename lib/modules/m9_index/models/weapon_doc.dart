import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

import 'indexed_characteristic.dart';

/// Weapon document for search indexing.
///
/// Represents a weapon profile (Ranged or Melee) flattened for
/// player-facing lookup and voice retrieval.
///
/// Part of M9 Index-Core (Search).
class WeaponDoc {
  /// Canonical document ID (stable, deterministic).
  final String docId;

  /// Original profile ID from M5 (for provenance).
  final String profileId;

  /// Display name of the weapon.
  final String name;

  /// Weapon statistics (Range, A, BS/WS, S, AP, D, etc.).
  final List<IndexedCharacteristic> characteristics;

  /// Keyword tokens (e.g., "assault", "heavy", "pistol").
  final List<String> keywordTokens;

  /// References to RuleDoc docIds (for linked rules like Assault, Heavy).
  final List<String> ruleDocRefs;

  /// Source file ID (for provenance).
  final String sourceFileId;

  /// Source node reference (for provenance).
  final NodeRef sourceNode;

  const WeaponDoc({
    required this.docId,
    required this.profileId,
    required this.name,
    required this.characteristics,
    required this.keywordTokens,
    required this.ruleDocRefs,
    required this.sourceFileId,
    required this.sourceNode,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeaponDoc &&
          runtimeType == other.runtimeType &&
          docId == other.docId &&
          profileId == other.profileId &&
          name == other.name &&
          _listEquals(characteristics, other.characteristics) &&
          _listEquals(keywordTokens, other.keywordTokens) &&
          _listEquals(ruleDocRefs, other.ruleDocRefs) &&
          sourceFileId == other.sourceFileId &&
          sourceNode == other.sourceNode;

  @override
  int get hashCode =>
      docId.hashCode ^
      profileId.hashCode ^
      name.hashCode ^
      Object.hashAll(characteristics) ^
      Object.hashAll(keywordTokens) ^
      Object.hashAll(ruleDocRefs) ^
      sourceFileId.hashCode ^
      sourceNode.hashCode;

  @override
  String toString() => 'WeaponDoc($docId: "$name")';

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

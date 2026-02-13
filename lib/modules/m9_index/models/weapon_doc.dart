import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

import 'indexed_characteristic.dart';

/// Weapon document for search indexing.
///
/// Identity vs Search:
/// - docId: Globally unique stable identifier (weapon:{profileId})
/// - canonicalKey: Normalized name for search grouping (normalize(name))
///
/// Multiple weapons may share the same canonicalKey (e.g., "Bolt Rifle"
/// on many units). Use canonicalKey for search, docId for identity.
///
/// Part of M9 Index-Core (Search).
class WeaponDoc {
  /// Globally unique document ID (format: "weapon:{profileId}").
  final String docId;

  /// Canonical search key (normalized name for grouping).
  final String canonicalKey;

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
    required this.canonicalKey,
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
          docId == other.docId;

  @override
  int get hashCode => docId.hashCode;

  @override
  String toString() => 'WeaponDoc($docId: "$name")';
}

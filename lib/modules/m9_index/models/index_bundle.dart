import 'dart:collection';

import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';

import 'index_diagnostic.dart';
import 'rule_doc.dart';
import 'unit_doc.dart';
import 'weapon_doc.dart';

/// Complete M9 output with indexed documents and query surface.
///
/// IndexBundle provides deterministic, canonical search documents
/// built from M5 BoundPackBundle. All lists are sorted by docId
/// for deterministic iteration.
///
/// Query Semantics:
/// - *ByKey(key): Returns null if canonical key not found
/// - *ByDocId(docId): Returns null if docId not found
/// - unitsByKeyword(keyword): Returns empty list if keyword not found
/// - unitsByCharacteristic(name): Returns empty list if name not found
///
/// Deterministic Ordering:
/// - All document lists sorted by docId (canonical key)
/// - All lookup map values are sorted lists
/// - Diagnostics sorted by (sourceFileId, sourceNode.nodeIndex)
///
/// Part of M9 Index-Core (Search).
class IndexBundle {
  /// Pack identifier (from M5 input).
  final String packId;

  /// Timestamp when index was built.
  final DateTime indexedAt;

  /// All unit documents (sorted by docId).
  final List<UnitDoc> units;

  /// All weapon documents (sorted by docId).
  final List<WeaponDoc> weapons;

  /// All rule documents (sorted by docId).
  final List<RuleDoc> rules;

  /// Canonical key → UnitDoc docId lookup.
  final SplayTreeMap<String, String> unitKeyToDocId;

  /// Canonical key → WeaponDoc docId lookup.
  final SplayTreeMap<String, String> weaponKeyToDocId;

  /// Canonical key → RuleDoc docId lookup.
  final SplayTreeMap<String, String> ruleKeyToDocId;

  /// Keyword → list of UnitDoc docIds (sorted).
  final SplayTreeMap<String, List<String>> keywordToUnitDocIds;

  /// Characteristic name → list of doc IDs (sorted).
  final SplayTreeMap<String, List<String>> characteristicNameToDocIds;

  /// Issues detected during indexing.
  final List<IndexDiagnostic> diagnostics;

  /// Reference to M5 input (immutable).
  final BoundPackBundle boundBundle;

  // Internal lookup indices (built on construction)
  final Map<String, UnitDoc> _unitByDocId;
  final Map<String, WeaponDoc> _weaponByDocId;
  final Map<String, RuleDoc> _ruleByDocId;

  IndexBundle({
    required this.packId,
    required this.indexedAt,
    required this.units,
    required this.weapons,
    required this.rules,
    required this.unitKeyToDocId,
    required this.weaponKeyToDocId,
    required this.ruleKeyToDocId,
    required this.keywordToUnitDocIds,
    required this.characteristicNameToDocIds,
    required this.diagnostics,
    required this.boundBundle,
  })  : _unitByDocId = {for (final u in units) u.docId: u},
        _weaponByDocId = {for (final w in weapons) w.docId: w},
        _ruleByDocId = {for (final r in rules) r.docId: r};

  // --- Lookup by canonical key ---

  /// Returns UnitDoc for the given canonical key, or null if not found.
  UnitDoc? unitByKey(String key) {
    final docId = unitKeyToDocId[key];
    return docId != null ? _unitByDocId[docId] : null;
  }

  /// Returns WeaponDoc for the given canonical key, or null if not found.
  WeaponDoc? weaponByKey(String key) {
    final docId = weaponKeyToDocId[key];
    return docId != null ? _weaponByDocId[docId] : null;
  }

  /// Returns RuleDoc for the given canonical key, or null if not found.
  RuleDoc? ruleByKey(String key) {
    final docId = ruleKeyToDocId[key];
    return docId != null ? _ruleByDocId[docId] : null;
  }

  // --- Lookup by docId ---

  /// Returns UnitDoc for the given docId, or null if not found.
  UnitDoc? unitByDocId(String docId) => _unitByDocId[docId];

  /// Returns WeaponDoc for the given docId, or null if not found.
  WeaponDoc? weaponByDocId(String docId) => _weaponByDocId[docId];

  /// Returns RuleDoc for the given docId, or null if not found.
  RuleDoc? ruleByDocId(String docId) => _ruleByDocId[docId];

  // --- Inverted index queries ---

  /// Returns UnitDocs that have the given keyword (sorted by docId).
  Iterable<UnitDoc> unitsByKeyword(String keyword) {
    final docIds = keywordToUnitDocIds[keyword.toLowerCase()];
    if (docIds == null) return const [];
    return docIds.map((id) => _unitByDocId[id]).whereType<UnitDoc>();
  }

  /// Returns docIds of documents that have the given characteristic name.
  Iterable<String> docIdsByCharacteristic(String characteristicName) {
    return characteristicNameToDocIds[characteristicName.toLowerCase()] ??
        const [];
  }

  // --- Diagnostic helpers ---

  int get missingNameCount => diagnostics
      .where((d) => d.code == IndexDiagnosticCode.missingName)
      .length;

  int get duplicateDocKeyCount => diagnostics
      .where((d) => d.code == IndexDiagnosticCode.duplicateDocKey)
      .length;

  int get duplicateRuleCanonicalKeyCount => diagnostics
      .where((d) => d.code == IndexDiagnosticCode.duplicateRuleCanonicalKey)
      .length;

  int get unknownProfileTypeCount => diagnostics
      .where((d) => d.code == IndexDiagnosticCode.unknownProfileType)
      .length;

  int get linkTargetMissingCount => diagnostics
      .where((d) => d.code == IndexDiagnosticCode.linkTargetMissing)
      .length;

  @override
  String toString() =>
      'IndexBundle(pack=$packId, units=${units.length}, weapons=${weapons.length}, rules=${rules.length}, diags=${diagnostics.length})';
}

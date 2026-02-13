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
/// Identity vs Search:
/// - docId: Globally unique stable identifier (type:{id})
/// - canonicalKey: Normalized name for search grouping
///
/// Query Semantics:
/// - *ByDocId(docId): Returns single doc or null (identity lookup)
/// - *ByCanonicalKey(key): Returns list of docs (search lookup)
/// - unitsByKeyword(keyword): Returns list of units with that keyword
///
/// Deterministic Ordering:
/// - All document lists sorted by docId
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

  /// Canonical key → list of UnitDoc docIds (for search grouping).
  final SplayTreeMap<String, List<String>> unitKeyToDocIds;

  /// Canonical key → list of WeaponDoc docIds (for search grouping).
  final SplayTreeMap<String, List<String>> weaponKeyToDocIds;

  /// Canonical key → list of RuleDoc docIds (for search grouping).
  final SplayTreeMap<String, List<String>> ruleKeyToDocIds;

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
    required this.unitKeyToDocIds,
    required this.weaponKeyToDocIds,
    required this.ruleKeyToDocIds,
    required this.keywordToUnitDocIds,
    required this.characteristicNameToDocIds,
    required this.diagnostics,
    required this.boundBundle,
  })  : _unitByDocId = {for (final u in units) u.docId: u},
        _weaponByDocId = {for (final w in weapons) w.docId: w},
        _ruleByDocId = {for (final r in rules) r.docId: r};

  // --- Lookup by docId (identity) ---

  /// Returns UnitDoc for the given docId, or null if not found.
  UnitDoc? unitByDocId(String docId) => _unitByDocId[docId];

  /// Returns WeaponDoc for the given docId, or null if not found.
  WeaponDoc? weaponByDocId(String docId) => _weaponByDocId[docId];

  /// Returns RuleDoc for the given docId, or null if not found.
  RuleDoc? ruleByDocId(String docId) => _ruleByDocId[docId];

  // --- Lookup by canonical key (search) ---

  /// Returns all UnitDocs matching the canonical key (sorted by docId).
  Iterable<UnitDoc> unitsByCanonicalKey(String key) {
    final docIds = unitKeyToDocIds[key];
    if (docIds == null) return const [];
    return docIds.map((id) => _unitByDocId[id]).whereType<UnitDoc>();
  }

  /// Returns all WeaponDocs matching the canonical key (sorted by docId).
  Iterable<WeaponDoc> weaponsByCanonicalKey(String key) {
    final docIds = weaponKeyToDocIds[key];
    if (docIds == null) return const [];
    return docIds.map((id) => _weaponByDocId[id]).whereType<WeaponDoc>();
  }

  /// Returns all RuleDocs matching the canonical key (sorted by docId).
  Iterable<RuleDoc> rulesByCanonicalKey(String key) {
    final docIds = ruleKeyToDocIds[key];
    if (docIds == null) return const [];
    return docIds.map((id) => _ruleByDocId[id]).whereType<RuleDoc>();
  }

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

  int get duplicateDocIdCount => diagnostics
      .where((d) => d.code == IndexDiagnosticCode.duplicateDocId)
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

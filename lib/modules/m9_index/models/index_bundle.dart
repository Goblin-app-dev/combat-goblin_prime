import 'dart:collection';

import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';

import 'index_diagnostic.dart';
import 'rule_doc.dart';
import 'unit_doc.dart';
import 'weapon_doc.dart';

/// Complete M9 output with indexed documents and query surface.
///
/// **STATUS: FROZEN** (2026-02-13)
///
/// IndexBundle provides deterministic, canonical search documents
/// built from M5 BoundPackBundle. All lists are sorted by docId
/// for deterministic iteration.
///
/// ## Identity vs Search
/// - docId: Globally unique stable identifier (type:{id})
/// - canonicalKey: Normalized name for search grouping
///
/// ## Query Semantics (Frozen)
/// - `*ByDocId(docId)`: Returns single doc or null (identity lookup)
/// - `*ByCanonicalKey(key)`: Returns list of docs (search lookup)
/// - `unitsByKeyword(keyword)`: Returns list of units with that keyword
/// - `findUnitsByName(query)`: Exact canonical key match
/// - `findUnitsContaining(query)`: Substring match on canonical key
/// - `autocompleteUnitKeys(prefix)`: Sorted prefix completions
///
/// ## Deterministic Ordering (Frozen)
/// - All document lists sorted by docId
/// - All lookup map values are sorted lists
/// - Diagnostics sorted by (sourceFileId, sourceNode.nodeIndex)
/// - Query results are stable-sorted and deterministic across builds
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

  // --- Name-based search (query surface) ---

  /// Finds units whose canonicalKey matches exactly.
  ///
  /// Returns stable-sorted list by docId. Query is normalized before lookup.
  /// For substring/contains matching, use [findUnitsContaining].
  List<UnitDoc> findUnitsByName(String query) {
    final key = _normalize(query);
    return unitsByCanonicalKey(key).toList();
  }

  /// Finds weapons whose canonicalKey matches exactly.
  ///
  /// Returns stable-sorted list by docId. Query is normalized before lookup.
  List<WeaponDoc> findWeaponsByName(String query) {
    final key = _normalize(query);
    return weaponsByCanonicalKey(key).toList();
  }

  /// Finds rules whose canonicalKey matches exactly.
  ///
  /// Returns stable-sorted list by docId. Query is normalized before lookup.
  List<RuleDoc> findRulesByName(String query) {
    final key = _normalize(query);
    return rulesByCanonicalKey(key).toList();
  }

  /// Finds units whose canonicalKey contains the normalized query.
  ///
  /// Returns stable-sorted list by docId. More expensive than exact match.
  List<UnitDoc> findUnitsContaining(String query) {
    final key = _normalize(query);
    if (key.isEmpty) return const [];
    final results = <UnitDoc>[];
    for (final entry in unitKeyToDocIds.entries) {
      if (entry.key.contains(key)) {
        for (final docId in entry.value) {
          final doc = _unitByDocId[docId];
          if (doc != null) results.add(doc);
        }
      }
    }
    return results;
  }

  /// Finds weapons whose canonicalKey contains the normalized query.
  ///
  /// Returns stable-sorted list by docId. More expensive than exact match.
  List<WeaponDoc> findWeaponsContaining(String query) {
    final key = _normalize(query);
    if (key.isEmpty) return const [];
    final results = <WeaponDoc>[];
    for (final entry in weaponKeyToDocIds.entries) {
      if (entry.key.contains(key)) {
        for (final docId in entry.value) {
          final doc = _weaponByDocId[docId];
          if (doc != null) results.add(doc);
        }
      }
    }
    return results;
  }

  /// Finds rules whose canonicalKey contains the normalized query.
  ///
  /// Returns stable-sorted list by docId. More expensive than exact match.
  List<RuleDoc> findRulesContaining(String query) {
    final key = _normalize(query);
    if (key.isEmpty) return const [];
    final results = <RuleDoc>[];
    for (final entry in ruleKeyToDocIds.entries) {
      if (entry.key.contains(key)) {
        for (final docId in entry.value) {
          final doc = _ruleByDocId[docId];
          if (doc != null) results.add(doc);
        }
      }
    }
    return results;
  }

  /// Returns unit canonical keys that start with the given prefix.
  ///
  /// Sorted lexicographically. Useful for autocomplete/typeahead.
  List<String> autocompleteUnitKeys(String prefix, {int limit = 10}) {
    final key = _normalize(prefix);
    if (key.isEmpty) return const [];
    final results = <String>[];
    for (final k in unitKeyToDocIds.keys) {
      if (k.startsWith(key)) {
        results.add(k);
        if (results.length >= limit) break;
      }
    }
    return results;
  }

  /// Returns weapon canonical keys that start with the given prefix.
  ///
  /// Sorted lexicographically. Useful for autocomplete/typeahead.
  List<String> autocompleteWeaponKeys(String prefix, {int limit = 10}) {
    final key = _normalize(prefix);
    if (key.isEmpty) return const [];
    final results = <String>[];
    for (final k in weaponKeyToDocIds.keys) {
      if (k.startsWith(key)) {
        results.add(k);
        if (results.length >= limit) break;
      }
    }
    return results;
  }

  /// Returns rule canonical keys that start with the given prefix.
  ///
  /// Sorted lexicographically. Useful for autocomplete/typeahead.
  List<String> autocompleteRuleKeys(String prefix, {int limit = 10}) {
    final key = _normalize(prefix);
    if (key.isEmpty) return const [];
    final results = <String>[];
    for (final k in ruleKeyToDocIds.keys) {
      if (k.startsWith(key)) {
        results.add(k);
        if (results.length >= limit) break;
      }
    }
    return results;
  }

  /// Normalize query string (same rules as IndexService.normalize).
  static String _normalize(String name) {
    var result = name.toLowerCase();
    result = result.replaceAll(RegExp(r'[^a-z0-9\s]'), '');
    result = result.replaceAll(RegExp(r'\s+'), ' ');
    return result.trim();
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

  int get duplicateSourceProfileSkippedCount => diagnostics
      .where(
          (d) => d.code == IndexDiagnosticCode.duplicateSourceProfileSkipped)
      .length;

  @override
  String toString() =>
      'IndexBundle(pack=$packId, units=${units.length}, weapons=${weapons.length}, rules=${rules.length}, diags=${diagnostics.length})';
}

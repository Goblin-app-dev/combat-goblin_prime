import 'dart:collection';

import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';

import '../models/index_bundle.dart';
import '../models/index_diagnostic.dart';
import '../models/indexed_characteristic.dart';
import '../models/indexed_cost.dart';
import '../models/rule_doc.dart';
import '../models/unit_doc.dart';
import '../models/weapon_doc.dart';

/// Service for building deterministic search indices from M5 output.
///
/// v2 Key Strategy:
/// - docId: Globally unique stable identifier (type:{stableId})
/// - canonicalKey: Normalized name for search grouping
///
/// Multiple docs may share the same canonicalKey (e.g., "Bolt Rifle" on
/// many units). Use canonicalKey for search, docId for identity.
///
/// Contract: IndexBundle buildIndex(BoundPackBundle boundPack)
///
/// Pure function:
/// - No IO
/// - No mutation of input
/// - Deterministic output (same input → identical output)
///
/// Part of M9 Index-Core (Search).
class IndexService {
  /// Profile type names that indicate unit profiles (case-insensitive).
  static const _unitTypeNames = {'unit'};

  /// Profile type names that indicate weapon profiles (case-insensitive).
  static const _weaponTypePatterns = {'ranged weapons', 'melee weapons'};

  /// Profile type names that indicate ability/rule profiles (case-insensitive).
  static const _abilityTypeNames = {'abilities'};

  /// Characteristic names that typically contain rule descriptions.
  static const _descriptionCharNames = {'description', 'effect', 'ability'};

  /// Builds a deterministic search index from M5 BoundPackBundle.
  ///
  /// Processing order (for determinism):
  /// 1. Build RuleDocs (from ability profiles, sorted by profileId)
  /// 2. Build WeaponDocs (sorted by profileId)
  /// 3. Build UnitDocs (sorted by entryId)
  /// 4. Build canonical key → docIds maps (search grouping)
  /// 5. Build inverted indices (keywords, characteristics)
  /// 6. Sort all outputs
  IndexBundle buildIndex(BoundPackBundle boundPack) {
    final diagnostics = <IndexDiagnostic>[];

    // Step 1: Build RuleDocs (all ability profiles with descriptions)
    final ruleDocList = _buildRuleDocs(boundPack, diagnostics);

    // Step 2: Build WeaponDocs (all weapon profiles)
    final weaponDocList = _buildWeaponDocs(boundPack, ruleDocList, diagnostics);

    // Step 3: Build UnitDocs (all entries with unit profiles)
    final unitDocList =
        _buildUnitDocs(boundPack, weaponDocList, ruleDocList, diagnostics);

    // Step 4: Sort lists by docId
    ruleDocList.sort((a, b) => a.docId.compareTo(b.docId));
    weaponDocList.sort((a, b) => a.docId.compareTo(b.docId));
    unitDocList.sort((a, b) => a.docId.compareTo(b.docId));

    // Step 5: Build canonical key → docIds maps (search grouping)
    final unitKeyToDocIds = _buildCanonicalKeyIndex(unitDocList);
    final weaponKeyToDocIds = _buildCanonicalKeyIndex(weaponDocList);
    final ruleKeyToDocIds = _buildCanonicalKeyIndex(ruleDocList);

    // Step 6: Build inverted indices
    final keywordToUnitDocIds = _buildKeywordIndex(unitDocList);
    final characteristicNameToDocIds =
        _buildCharacteristicIndex(unitDocList, weaponDocList);

    // Step 7: Sort diagnostics deterministically
    diagnostics.sort((a, b) {
      final fileCompare =
          (a.sourceFileId ?? '').compareTo(b.sourceFileId ?? '');
      if (fileCompare != 0) return fileCompare;
      final aIndex = a.sourceNode?.nodeIndex ?? 0;
      final bIndex = b.sourceNode?.nodeIndex ?? 0;
      return aIndex.compareTo(bIndex);
    });

    return IndexBundle(
      packId: boundPack.packId,
      indexedAt: DateTime.now(),
      units: unitDocList,
      weapons: weaponDocList,
      rules: ruleDocList,
      unitKeyToDocIds: unitKeyToDocIds,
      weaponKeyToDocIds: weaponKeyToDocIds,
      ruleKeyToDocIds: ruleKeyToDocIds,
      keywordToUnitDocIds: keywordToUnitDocIds,
      characteristicNameToDocIds: characteristicNameToDocIds,
      diagnostics: diagnostics,
      boundBundle: boundPack,
    );
  }

  // --- Normalization & Tokenization ---

  /// Normalizes a name to a canonical key.
  ///
  /// Rules:
  /// 1. Lowercase
  /// 2. Strip punctuation (keep alphanumeric and spaces)
  /// 3. Collapse multiple spaces to single space
  /// 4. Trim leading/trailing whitespace
  ///
  /// Deterministic: same input → same output.
  static String normalize(String name) {
    // Lowercase
    var result = name.toLowerCase();

    // Strip non-alphanumeric except space
    result = result.replaceAll(RegExp(r'[^a-z0-9\s]'), '');

    // Collapse whitespace
    result = result.replaceAll(RegExp(r'\s+'), ' ');

    // Trim
    result = result.trim();

    return result;
  }

  /// Tokenizes text into search tokens.
  ///
  /// Rules:
  /// 1. Lowercase
  /// 2. Strip punctuation
  /// 3. Split on whitespace
  /// 4. Filter empty tokens
  /// 5. No stemming (v1)
  /// 6. Sort for determinism
  ///
  /// Returns sorted list of unique tokens.
  static List<String> tokenize(String text) {
    final normalized = normalize(text);
    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toSet();
    return tokens.toList()..sort();
  }

  // --- Private: Build RuleDocs ---

  /// Builds RuleDocs from ability-type profiles.
  ///
  /// Every ability profile with a description becomes a RuleDoc.
  /// docId format: "rule:{profileId}"
  List<RuleDoc> _buildRuleDocs(
    BoundPackBundle boundPack,
    List<IndexDiagnostic> diagnostics,
  ) {
    final ruleDocs = <RuleDoc>[];
    final seenDocIds = <String>{};
    var skippedCount = 0;

    // Sort profiles by ID for stable iteration order
    final sortedProfiles = boundPack.profiles.toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    for (final profile in sortedProfiles) {
      if (!_isAbilityProfile(profile)) continue;

      // Check for name
      if (profile.name.isEmpty) {
        diagnostics.add(IndexDiagnostic(
          code: IndexDiagnosticCode.missingName,
          message: 'Ability profile missing name',
          sourceFileId: profile.sourceFileId,
          sourceNode: profile.sourceNode,
          targetId: profile.id,
        ));
        continue;
      }

      // Extract description from characteristics
      final description = _extractDescription(profile);
      if (description == null || description.isEmpty) {
        // No description = not a meaningful rule, skip
        continue;
      }

      final canonicalKey = normalize(profile.name);
      if (canonicalKey.isEmpty) {
        diagnostics.add(IndexDiagnostic(
          code: IndexDiagnosticCode.missingName,
          message:
              'Ability profile name normalizes to empty: "${profile.name}"',
          sourceFileId: profile.sourceFileId,
          sourceNode: profile.sourceNode,
          targetId: profile.id,
        ));
        continue;
      }

      // Generate unique docId
      final docId = 'rule:${profile.id}';

      // Skip duplicate profile IDs (same profile appears on multiple entries)
      if (!seenDocIds.add(docId)) {
        skippedCount++;
        continue;
      }

      // Create RuleDoc
      ruleDocs.add(RuleDoc(
        docId: docId,
        canonicalKey: canonicalKey,
        ruleId: profile.id,
        name: profile.name,
        description: description,
        page: null, // Page info not available in M5
        sourceFileId: profile.sourceFileId,
        sourceNode: profile.sourceNode,
      ));
    }

    if (skippedCount > 0) {
      diagnostics.add(IndexDiagnostic(
        code: IndexDiagnosticCode.duplicateSourceProfileSkipped,
        message:
            'Skipped $skippedCount duplicate rule profile(s) (same profileId on multiple entries)',
      ));
    }

    return ruleDocs;
  }

  // --- Private: Build WeaponDocs ---

  /// Builds WeaponDocs from weapon-type profiles.
  ///
  /// Every weapon profile becomes a WeaponDoc.
  /// docId format: "weapon:{profileId}"
  List<WeaponDoc> _buildWeaponDocs(
    BoundPackBundle boundPack,
    List<RuleDoc> ruleDocs,
    List<IndexDiagnostic> diagnostics,
  ) {
    final weaponDocs = <WeaponDoc>[];
    final seenDocIds = <String>{};
    var skippedCount = 0;

    // Build canonical key → docIds lookup for rules (for linking)
    final ruleKeyToDocIds = <String, List<String>>{};
    for (final rule in ruleDocs) {
      ruleKeyToDocIds.putIfAbsent(rule.canonicalKey, () => []).add(rule.docId);
    }

    // Sort profiles by ID for stable iteration order
    final sortedProfiles = boundPack.profiles.toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    for (final profile in sortedProfiles) {
      if (!_isWeaponProfile(profile)) continue;

      // Check for name
      if (profile.name.isEmpty) {
        diagnostics.add(IndexDiagnostic(
          code: IndexDiagnosticCode.missingName,
          message: 'Weapon profile missing name',
          sourceFileId: profile.sourceFileId,
          sourceNode: profile.sourceNode,
          targetId: profile.id,
        ));
        continue;
      }

      // Check for characteristics
      if (profile.characteristics.isEmpty) {
        diagnostics.add(IndexDiagnostic(
          code: IndexDiagnosticCode.emptyCharacteristics,
          message: 'Weapon profile "${profile.name}" has no characteristics',
          sourceFileId: profile.sourceFileId,
          sourceNode: profile.sourceNode,
          targetId: profile.id,
        ));
      }

      final canonicalKey = normalize(profile.name);
      if (canonicalKey.isEmpty) {
        diagnostics.add(IndexDiagnostic(
          code: IndexDiagnosticCode.missingName,
          message:
              'Weapon profile name normalizes to empty: "${profile.name}"',
          sourceFileId: profile.sourceFileId,
          sourceNode: profile.sourceNode,
          targetId: profile.id,
        ));
        continue;
      }

      // Generate unique docId
      final docId = 'weapon:${profile.id}';

      // Skip duplicate profile IDs (same profile appears on multiple entries)
      if (!seenDocIds.add(docId)) {
        skippedCount++;
        continue;
      }

      // Build characteristics
      final characteristics = profile.characteristics
          .map((c) => IndexedCharacteristic(
                name: c.name,
                typeId: profile.typeId ?? '',
                valueText: c.value,
              ))
          .toList();

      // Extract keyword tokens from weapon name
      final keywordTokens = tokenize(profile.name);

      // Link to rules by canonical key match (take first if multiple)
      final ruleDocRefs = <String>[];
      for (final token in keywordTokens) {
        final matchingRules = ruleKeyToDocIds[token];
        if (matchingRules != null && matchingRules.isNotEmpty) {
          ruleDocRefs.add(matchingRules.first);
        }
      }
      ruleDocRefs.sort();

      // Create WeaponDoc
      weaponDocs.add(WeaponDoc(
        docId: docId,
        canonicalKey: canonicalKey,
        profileId: profile.id,
        name: profile.name,
        characteristics: characteristics,
        keywordTokens: keywordTokens,
        ruleDocRefs: ruleDocRefs,
        sourceFileId: profile.sourceFileId,
        sourceNode: profile.sourceNode,
      ));
    }

    if (skippedCount > 0) {
      diagnostics.add(IndexDiagnostic(
        code: IndexDiagnosticCode.duplicateSourceProfileSkipped,
        message:
            'Skipped $skippedCount duplicate weapon profile(s) (same profileId on multiple entries)',
      ));
    }

    return weaponDocs;
  }

  // --- Private: Build UnitDocs ---

  /// Builds UnitDocs from entries with unit-type profiles.
  ///
  /// Every entry with a unit profile becomes a UnitDoc.
  /// docId format: "unit:{entryId}"
  List<UnitDoc> _buildUnitDocs(
    BoundPackBundle boundPack,
    List<WeaponDoc> weaponDocs,
    List<RuleDoc> ruleDocs,
    List<IndexDiagnostic> diagnostics,
  ) {
    final unitDocs = <UnitDoc>[];
    final seenDocIds = <String>{};

    // Build profileId → weaponDoc lookup
    final weaponByProfileId = <String, WeaponDoc>{};
    for (final weapon in weaponDocs) {
      weaponByProfileId[weapon.profileId] = weapon;
    }

    // Build profileId → ruleDoc lookup
    final ruleByProfileId = <String, RuleDoc>{};
    for (final rule in ruleDocs) {
      ruleByProfileId[rule.ruleId] = rule;
    }

    // Sort entries by ID for stable iteration order
    final sortedEntries = boundPack.entries.toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    for (final entry in sortedEntries) {
      // Skip groups and hidden entries for unit indexing
      if (entry.isGroup) continue;
      if (entry.isHidden) continue;

      // Find unit profile
      final unitProfile = _findUnitProfile(entry);
      if (unitProfile == null) continue;

      // Check for name
      if (entry.name.isEmpty) {
        diagnostics.add(IndexDiagnostic(
          code: IndexDiagnosticCode.missingName,
          message: 'Entry missing name',
          sourceFileId: entry.sourceFileId,
          sourceNode: entry.sourceNode,
          targetId: entry.id,
        ));
        continue;
      }

      final canonicalKey = normalize(entry.name);
      if (canonicalKey.isEmpty) {
        diagnostics.add(IndexDiagnostic(
          code: IndexDiagnosticCode.missingName,
          message: 'Entry name normalizes to empty: "${entry.name}"',
          sourceFileId: entry.sourceFileId,
          sourceNode: entry.sourceNode,
          targetId: entry.id,
        ));
        continue;
      }

      // Generate unique docId
      final docId = 'unit:${entry.id}';

      // Skip duplicate entry IDs (shouldn't happen, but be safe)
      if (!seenDocIds.add(docId)) continue;

      // Build characteristics from unit profile
      final characteristics = unitProfile.characteristics
          .map((c) => IndexedCharacteristic(
                name: c.name,
                typeId: unitProfile.typeId ?? '',
                valueText: c.value,
              ))
          .toList();

      // Build keyword tokens from categories
      final keywordTokens = <String>{};
      for (final category in entry.categories) {
        keywordTokens.addAll(tokenize(category.name));
      }
      final sortedKeywords = keywordTokens.toList()..sort();

      // Build category tokens
      final categoryTokens = entry.categories
          .map((c) => normalize(c.name))
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      // Collect weapon refs from nested profiles
      final weaponDocRefs = <String>{};
      _collectWeaponRefs(entry, weaponByProfileId, weaponDocRefs);
      final sortedWeaponRefs = weaponDocRefs.toList()..sort();

      // Collect rule refs from nested ability profiles
      final ruleDocRefs = <String>{};
      _collectRuleRefs(entry, ruleByProfileId, ruleDocRefs);
      final sortedRuleRefs = ruleDocRefs.toList()..sort();

      // Build costs (sorted by typeId for determinism)
      final costs = entry.costs
          .map((c) => IndexedCost(
                typeId: c.typeId,
                typeName: c.typeName ?? c.typeId,
                value: c.value,
              ))
          .toList()
        ..sort((a, b) => a.typeId.compareTo(b.typeId));

      // Create UnitDoc
      unitDocs.add(UnitDoc(
        docId: docId,
        canonicalKey: canonicalKey,
        entryId: entry.id,
        name: entry.name,
        characteristics: characteristics,
        keywordTokens: sortedKeywords,
        categoryTokens: categoryTokens,
        weaponDocRefs: sortedWeaponRefs,
        ruleDocRefs: sortedRuleRefs,
        costs: costs,
        sourceFileId: entry.sourceFileId,
        sourceNode: entry.sourceNode,
      ));
    }

    return unitDocs;
  }

  // --- Private: Build Canonical Key Index ---

  /// Builds canonical key → docIds map from docs with canonicalKey field.
  SplayTreeMap<String, List<String>> _buildCanonicalKeyIndex<T>(
    List<T> docs,
  ) {
    final index = SplayTreeMap<String, List<String>>();

    for (final doc in docs) {
      final String canonicalKey;
      final String docId;

      if (doc is UnitDoc) {
        canonicalKey = doc.canonicalKey;
        docId = doc.docId;
      } else if (doc is WeaponDoc) {
        canonicalKey = doc.canonicalKey;
        docId = doc.docId;
      } else if (doc is RuleDoc) {
        canonicalKey = doc.canonicalKey;
        docId = doc.docId;
      } else {
        continue;
      }

      index.putIfAbsent(canonicalKey, () => []).add(docId);
    }

    // Sort value lists for determinism
    for (final entry in index.entries) {
      entry.value.sort();
    }

    return index;
  }

  // --- Private: Inverted Index Builders ---

  /// Builds keyword → unit docIds inverted index.
  SplayTreeMap<String, List<String>> _buildKeywordIndex(List<UnitDoc> units) {
    final index = SplayTreeMap<String, List<String>>();

    for (final unit in units) {
      for (final keyword in unit.keywordTokens) {
        index.putIfAbsent(keyword, () => []).add(unit.docId);
      }
    }

    // Sort value lists for determinism
    for (final entry in index.entries) {
      entry.value.sort();
    }

    return index;
  }

  /// Builds characteristic name → docIds inverted index.
  SplayTreeMap<String, List<String>> _buildCharacteristicIndex(
    List<UnitDoc> units,
    List<WeaponDoc> weapons,
  ) {
    final index = SplayTreeMap<String, List<String>>();

    for (final unit in units) {
      for (final char in unit.characteristics) {
        final key = char.name.toLowerCase();
        index.putIfAbsent(key, () => []).add(unit.docId);
      }
    }

    for (final weapon in weapons) {
      for (final char in weapon.characteristics) {
        final key = char.name.toLowerCase();
        index.putIfAbsent(key, () => []).add(weapon.docId);
      }
    }

    // Sort value lists for determinism
    for (final entry in index.entries) {
      entry.value.sort();
    }

    return index;
  }

  // --- Private: Profile Classification ---

  bool _isUnitProfile(BoundProfile profile) {
    final typeName = (profile.typeName ?? '').toLowerCase();
    return _unitTypeNames.contains(typeName);
  }

  bool _isWeaponProfile(BoundProfile profile) {
    final typeName = (profile.typeName ?? '').toLowerCase();
    return _weaponTypePatterns.contains(typeName);
  }

  bool _isAbilityProfile(BoundProfile profile) {
    final typeName = (profile.typeName ?? '').toLowerCase();
    return _abilityTypeNames.contains(typeName);
  }

  /// Finds the first unit-type profile in an entry.
  BoundProfile? _findUnitProfile(BoundEntry entry) {
    for (final profile in entry.profiles) {
      if (_isUnitProfile(profile)) {
        return profile;
      }
    }
    return null;
  }

  /// Extracts description text from ability profile characteristics.
  String? _extractDescription(BoundProfile profile) {
    for (final char in profile.characteristics) {
      if (_descriptionCharNames.contains(char.name.toLowerCase())) {
        return char.value;
      }
    }
    // If no explicit description field, use first characteristic value
    if (profile.characteristics.isNotEmpty) {
      return profile.characteristics.first.value;
    }
    return null;
  }

  // --- Private: Ref Collection ---

  /// Recursively collects weapon refs from entry and children.
  void _collectWeaponRefs(
    BoundEntry entry,
    Map<String, WeaponDoc> weaponByProfileId,
    Set<String> weaponDocRefs,
  ) {
    for (final profile in entry.profiles) {
      if (_isWeaponProfile(profile)) {
        final weapon = weaponByProfileId[profile.id];
        if (weapon != null) {
          weaponDocRefs.add(weapon.docId);
        }
      }
    }

    // Recurse into children
    for (final child in entry.children) {
      _collectWeaponRefs(child, weaponByProfileId, weaponDocRefs);
    }
  }

  /// Recursively collects rule refs from entry and children.
  void _collectRuleRefs(
    BoundEntry entry,
    Map<String, RuleDoc> ruleByProfileId,
    Set<String> ruleDocRefs,
  ) {
    for (final profile in entry.profiles) {
      if (_isAbilityProfile(profile)) {
        final rule = ruleByProfileId[profile.id];
        if (rule != null) {
          ruleDocRefs.add(rule.docId);
        }
      }
    }

    // Recurse into children
    for (final child in entry.children) {
      _collectRuleRefs(child, ruleByProfileId, ruleDocRefs);
    }
  }
}

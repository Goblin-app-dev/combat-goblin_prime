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
  /// 1. Build RuleDoc dedupe map (from ability profiles, sorted by profileId)
  /// 2. Build WeaponDocs (sorted by profileId, link to rules)
  /// 3. Build UnitDocs (sorted by entryId, link to weapons and rules)
  /// 4. Build inverted indices
  /// 5. Sort all outputs by canonical key
  IndexBundle buildIndex(BoundPackBundle boundPack) {
    final diagnostics = <IndexDiagnostic>[];

    // Step 1: Build RuleDoc dedupe map (abilities → rules)
    final ruleDocMap = _buildRuleDocMap(boundPack, diagnostics);

    // Step 2: Build WeaponDoc map
    final weaponDocMap = _buildWeaponDocMap(boundPack, ruleDocMap, diagnostics);

    // Step 3: Build UnitDoc map
    final unitDocMap =
        _buildUnitDocMap(boundPack, weaponDocMap, ruleDocMap, diagnostics);

    // Step 4: Extract sorted lists
    final rules = ruleDocMap.values.toList()
      ..sort((a, b) => a.docId.compareTo(b.docId));
    final weapons = weaponDocMap.values.toList()
      ..sort((a, b) => a.docId.compareTo(b.docId));
    final units = unitDocMap.values.toList()
      ..sort((a, b) => a.docId.compareTo(b.docId));

    // Step 5: Build lookup maps (canonical key → docId)
    final unitKeyToDocId = SplayTreeMap<String, String>();
    for (final unit in units) {
      unitKeyToDocId[unit.docId] = unit.docId;
    }

    final weaponKeyToDocId = SplayTreeMap<String, String>();
    for (final weapon in weapons) {
      weaponKeyToDocId[weapon.docId] = weapon.docId;
    }

    final ruleKeyToDocId = SplayTreeMap<String, String>();
    for (final rule in rules) {
      ruleKeyToDocId[rule.docId] = rule.docId;
    }

    // Step 6: Build inverted indices
    final keywordToUnitDocIds = _buildKeywordIndex(units);
    final characteristicNameToDocIds = _buildCharacteristicIndex(units, weapons);

    // Step 7: Sort diagnostics deterministically
    diagnostics.sort((a, b) {
      final fileCompare = (a.sourceFileId ?? '').compareTo(b.sourceFileId ?? '');
      if (fileCompare != 0) return fileCompare;
      final aIndex = a.sourceNode?.nodeIndex ?? 0;
      final bIndex = b.sourceNode?.nodeIndex ?? 0;
      return aIndex.compareTo(bIndex);
    });

    return IndexBundle(
      packId: boundPack.packId,
      indexedAt: DateTime.now(),
      units: units,
      weapons: weapons,
      rules: rules,
      unitKeyToDocId: unitKeyToDocId,
      weaponKeyToDocId: weaponKeyToDocId,
      ruleKeyToDocId: ruleKeyToDocId,
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

  // --- Private: Build RuleDoc Map ---

  /// Builds RuleDoc map from ability-type profiles.
  ///
  /// Iteration order: profiles sorted by profileId for stability.
  /// Deduplication: by canonical key (normalized name).
  Map<String, RuleDoc> _buildRuleDocMap(
    BoundPackBundle boundPack,
    List<IndexDiagnostic> diagnostics,
  ) {
    final ruleDocMap = <String, RuleDoc>{};
    final seenKeys = <String, RuleDoc>{};

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
          message: 'Ability profile name normalizes to empty: "${profile.name}"',
          sourceFileId: profile.sourceFileId,
          sourceNode: profile.sourceNode,
          targetId: profile.id,
        ));
        continue;
      }

      // Check for duplicate canonical key
      if (seenKeys.containsKey(canonicalKey)) {
        final existing = seenKeys[canonicalKey]!;
        // Check if descriptions differ
        if (existing.description != description) {
          diagnostics.add(IndexDiagnostic(
            code: IndexDiagnosticCode.duplicateRuleCanonicalKey,
            message:
                'Rule "$canonicalKey" has conflicting descriptions; using first encountered (${existing.ruleId})',
            sourceFileId: profile.sourceFileId,
            sourceNode: profile.sourceNode,
            targetId: profile.id,
          ));
        } else {
          diagnostics.add(IndexDiagnostic(
            code: IndexDiagnosticCode.duplicateDocKey,
            message:
                'Rule "$canonicalKey" already indexed as ${existing.docId}; skipping duplicate',
            sourceFileId: profile.sourceFileId,
            sourceNode: profile.sourceNode,
            targetId: profile.id,
          ));
        }
        continue;
      }

      // Create RuleDoc
      final ruleDoc = RuleDoc(
        docId: canonicalKey,
        ruleId: profile.id,
        name: profile.name,
        description: description,
        page: null, // Page info not available in M5
        sourceFileId: profile.sourceFileId,
        sourceNode: profile.sourceNode,
      );

      ruleDocMap[profile.id] = ruleDoc;
      seenKeys[canonicalKey] = ruleDoc;
    }

    return ruleDocMap;
  }

  // --- Private: Build WeaponDoc Map ---

  /// Builds WeaponDoc map from weapon-type profiles.
  ///
  /// Iteration order: profiles sorted by profileId for stability.
  Map<String, WeaponDoc> _buildWeaponDocMap(
    BoundPackBundle boundPack,
    Map<String, RuleDoc> ruleDocMap,
    List<IndexDiagnostic> diagnostics,
  ) {
    final weaponDocMap = <String, WeaponDoc>{};
    final seenKeys = <String, WeaponDoc>{};

    // Build canonical key → docId lookup for rules
    final ruleKeyToDocId = <String, String>{};
    for (final rule in ruleDocMap.values) {
      ruleKeyToDocId[rule.docId] = rule.docId;
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
          message: 'Weapon profile name normalizes to empty: "${profile.name}"',
          sourceFileId: profile.sourceFileId,
          sourceNode: profile.sourceNode,
          targetId: profile.id,
        ));
        continue;
      }

      // Check for duplicate canonical key
      if (seenKeys.containsKey(canonicalKey)) {
        final existing = seenKeys[canonicalKey]!;
        diagnostics.add(IndexDiagnostic(
          code: IndexDiagnosticCode.duplicateDocKey,
          message:
              'Weapon "$canonicalKey" already indexed as ${existing.docId}; skipping duplicate',
          sourceFileId: profile.sourceFileId,
          sourceNode: profile.sourceNode,
          targetId: profile.id,
        ));
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

      // Extract keyword tokens from weapon name and type
      final keywordTokens = tokenize(profile.name);

      // Link to rules (by canonical key match)
      // For v1, we don't invent rules from keywords; we only link if rule exists
      final ruleDocRefs = <String>[];
      for (final token in keywordTokens) {
        if (ruleKeyToDocId.containsKey(token)) {
          ruleDocRefs.add(ruleKeyToDocId[token]!);
        }
      }
      ruleDocRefs.sort();

      // Create WeaponDoc
      final weaponDoc = WeaponDoc(
        docId: canonicalKey,
        profileId: profile.id,
        name: profile.name,
        characteristics: characteristics,
        keywordTokens: keywordTokens,
        ruleDocRefs: ruleDocRefs,
        sourceFileId: profile.sourceFileId,
        sourceNode: profile.sourceNode,
      );

      weaponDocMap[profile.id] = weaponDoc;
      seenKeys[canonicalKey] = weaponDoc;
    }

    return weaponDocMap;
  }

  // --- Private: Build UnitDoc Map ---

  /// Builds UnitDoc map from entries with unit-type profiles.
  ///
  /// Iteration order: entries sorted by entryId for stability.
  Map<String, UnitDoc> _buildUnitDocMap(
    BoundPackBundle boundPack,
    Map<String, WeaponDoc> weaponDocMap,
    Map<String, RuleDoc> ruleDocMap,
    List<IndexDiagnostic> diagnostics,
  ) {
    final unitDocMap = <String, UnitDoc>{};
    final seenKeys = <String, UnitDoc>{};

    // Build profileId → weaponDoc lookup
    final weaponByProfileId = <String, WeaponDoc>{};
    for (final weapon in weaponDocMap.values) {
      weaponByProfileId[weapon.profileId] = weapon;
    }

    // Build profileId → ruleDoc lookup
    final ruleByProfileId = <String, RuleDoc>{};
    for (final rule in ruleDocMap.values) {
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

      // Check for duplicate canonical key
      if (seenKeys.containsKey(canonicalKey)) {
        final existing = seenKeys[canonicalKey]!;
        diagnostics.add(IndexDiagnostic(
          code: IndexDiagnosticCode.duplicateDocKey,
          message:
              'Unit "$canonicalKey" already indexed as ${existing.docId}; skipping duplicate',
          sourceFileId: entry.sourceFileId,
          sourceNode: entry.sourceNode,
          targetId: entry.id,
        ));
        continue;
      }

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
      _collectWeaponRefs(entry, weaponByProfileId, weaponDocRefs, diagnostics);
      final sortedWeaponRefs = weaponDocRefs.toList()..sort();

      // Collect rule refs from nested ability profiles
      final ruleDocRefs = <String>{};
      _collectRuleRefs(entry, ruleByProfileId, ruleDocRefs);
      final sortedRuleRefs = ruleDocRefs.toList()..sort();

      // Build costs
      final costs = entry.costs
          .map((c) => IndexedCost(
                typeId: c.typeId,
                typeName: c.typeName ?? c.typeId,
                value: c.value,
              ))
          .toList();

      // Create UnitDoc
      final unitDoc = UnitDoc(
        docId: canonicalKey,
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
      );

      unitDocMap[entry.id] = unitDoc;
      seenKeys[canonicalKey] = unitDoc;
    }

    return unitDocMap;
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
    List<IndexDiagnostic> diagnostics,
  ) {
    for (final profile in entry.profiles) {
      if (_isWeaponProfile(profile)) {
        final weapon = weaponByProfileId[profile.id];
        if (weapon != null) {
          weaponDocRefs.add(weapon.docId);
        }
        // No LINK_TARGET_MISSING here; weapon profiles create their own docs
      }
    }

    // Recurse into children
    for (final child in entry.children) {
      _collectWeaponRefs(child, weaponByProfileId, weaponDocRefs, diagnostics);
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
        // Duplicate abilities link to canonical; no diagnostic needed
      }
    }

    // Recurse into children
    for (final child in entry.children) {
      _collectRuleRefs(child, ruleByProfileId, ruleDocRefs);
    }
  }
}

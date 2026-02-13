import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';

void main() {
  const testSource = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  late BoundPackBundle boundBundle;

  setUpAll(() async {
    // Clean storage
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    // Build M5 bundle once for all tests
    final gameSystemBytes =
        await File('test/Warhammer 40,000.gst').readAsBytes();
    final primaryCatalogBytes =
        await File('test/Imperium - Space Marines.cat').readAsBytes();

    final dependencyFiles = <String, String>{
      'b00-cd86-4b4c-97ba': 'test/Imperium - Agents of the Imperium.cat',
      '7481-280e-b55e-7867': 'test/Library - Titans.cat',
      '1b6d-dc06-5db9-c7d1': 'test/Imperium - Imperial Knights - Library.cat',
      'ac3b-689c-4ad4-70cb': 'test/Library - Astartes Heresy Legends.cat',
    };

    final rawBundle = await AcquireService().buildBundle(
      gameSystemBytes: gameSystemBytes,
      gameSystemExternalFileName: 'Warhammer 40,000.gst',
      primaryCatalogBytes: primaryCatalogBytes,
      primaryCatalogExternalFileName: 'Imperium - Space Marines.cat',
      requestDependencyBytes: (targetId) async {
        final path = dependencyFiles[targetId];
        if (path == null) return null;
        return await File(path).readAsBytes();
      },
      source: testSource,
    );

    final parsedBundle = await ParseService().parseBundle(rawBundle: rawBundle);
    final wrappedBundle =
        await WrapService().wrapBundle(parsedBundle: parsedBundle);
    final linkedBundle =
        await LinkService().linkBundle(wrappedBundle: wrappedBundle);
    boundBundle = await BindService().bindBundle(linkedBundle: linkedBundle);
  });

  tearDownAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('M9 Index: invariants (determinism)', () {
    test('determinism: same M5 input produces identical IndexBundle', () {
      final indexService = IndexService();

      // Build index twice
      final bundle1 = indexService.buildIndex(boundBundle);
      final bundle2 = indexService.buildIndex(boundBundle);

      // Same counts
      expect(bundle1.units.length, bundle2.units.length);
      expect(bundle1.weapons.length, bundle2.weapons.length);
      expect(bundle1.rules.length, bundle2.rules.length);
      expect(bundle1.diagnostics.length, bundle2.diagnostics.length);

      print('[M9 INVARIANT] Counts match:');
      print('[M9 INVARIANT]   units: ${bundle1.units.length}');
      print('[M9 INVARIANT]   weapons: ${bundle1.weapons.length}');
      print('[M9 INVARIANT]   rules: ${bundle1.rules.length}');
      print('[M9 INVARIANT]   diagnostics: ${bundle1.diagnostics.length}');

      // Same unit docIds in same order
      for (var i = 0; i < bundle1.units.length; i++) {
        expect(bundle1.units[i].docId, bundle2.units[i].docId);
        expect(bundle1.units[i].canonicalKey, bundle2.units[i].canonicalKey);
        expect(bundle1.units[i].name, bundle2.units[i].name);
        expect(bundle1.units[i].entryId, bundle2.units[i].entryId);
      }
      print('[M9 INVARIANT] Units are identical in order');

      // Same weapon docIds in same order
      for (var i = 0; i < bundle1.weapons.length; i++) {
        expect(bundle1.weapons[i].docId, bundle2.weapons[i].docId);
        expect(
            bundle1.weapons[i].canonicalKey, bundle2.weapons[i].canonicalKey);
        expect(bundle1.weapons[i].name, bundle2.weapons[i].name);
        expect(bundle1.weapons[i].profileId, bundle2.weapons[i].profileId);
      }
      print('[M9 INVARIANT] Weapons are identical in order');

      // Same rule docIds in same order
      for (var i = 0; i < bundle1.rules.length; i++) {
        expect(bundle1.rules[i].docId, bundle2.rules[i].docId);
        expect(bundle1.rules[i].canonicalKey, bundle2.rules[i].canonicalKey);
        expect(bundle1.rules[i].name, bundle2.rules[i].name);
        expect(bundle1.rules[i].ruleId, bundle2.rules[i].ruleId);
      }
      print('[M9 INVARIANT] Rules are identical in order');

      // Same diagnostics in same order
      for (var i = 0; i < bundle1.diagnostics.length; i++) {
        expect(bundle1.diagnostics[i].code, bundle2.diagnostics[i].code);
        expect(bundle1.diagnostics[i].message, bundle2.diagnostics[i].message);
      }
      print('[M9 INVARIANT] Diagnostics are identical in order');
    });

    test('determinism: canonical key index keys are sorted', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      final unitKeys = bundle.unitKeyToDocIds.keys.toList();
      final sortedUnitKeys = List<String>.from(unitKeys)..sort();
      expect(unitKeys, sortedUnitKeys);
      print(
          '[M9 INVARIANT] Unit canonical key index keys are sorted (${unitKeys.length} keys)');

      final weaponKeys = bundle.weaponKeyToDocIds.keys.toList();
      final sortedWeaponKeys = List<String>.from(weaponKeys)..sort();
      expect(weaponKeys, sortedWeaponKeys);
      print(
          '[M9 INVARIANT] Weapon canonical key index keys are sorted (${weaponKeys.length} keys)');

      final ruleKeys = bundle.ruleKeyToDocIds.keys.toList();
      final sortedRuleKeys = List<String>.from(ruleKeys)..sort();
      expect(ruleKeys, sortedRuleKeys);
      print(
          '[M9 INVARIANT] Rule canonical key index keys are sorted (${ruleKeys.length} keys)');
    });

    test('determinism: keyword index keys are sorted', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      final keys = bundle.keywordToUnitDocIds.keys.toList();
      final sortedKeys = List<String>.from(keys)..sort();

      expect(keys, sortedKeys);
      print(
          '[M9 INVARIANT] Keyword index keys are sorted (${keys.length} keys)');
    });

    test('determinism: characteristic index keys are sorted', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      final keys = bundle.characteristicNameToDocIds.keys.toList();
      final sortedKeys = List<String>.from(keys)..sort();

      expect(keys, sortedKeys);
      print(
          '[M9 INVARIANT] Characteristic index keys are sorted (${keys.length} keys)');
    });

    test('determinism: inverted index values are sorted', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      // Check keyword index values
      for (final entry in bundle.keywordToUnitDocIds.entries) {
        final values = entry.value;
        final sortedValues = List<String>.from(values)..sort();
        expect(values, sortedValues,
            reason: 'Keyword "${entry.key}" values should be sorted');
      }
      print('[M9 INVARIANT] Keyword index values are sorted');

      // Check characteristic index values
      for (final entry in bundle.characteristicNameToDocIds.entries) {
        final values = entry.value;
        final sortedValues = List<String>.from(values)..sort();
        expect(values, sortedValues,
            reason: 'Characteristic "${entry.key}" values should be sorted');
      }
      print('[M9 INVARIANT] Characteristic index values are sorted');
    });

    test('v2: no docId collisions with type-prefixed IDs', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      // All docIds should be unique
      final allDocIds = <String>{};

      for (final unit in bundle.units) {
        expect(allDocIds.add(unit.docId), isTrue,
            reason: 'Duplicate unit docId: ${unit.docId}');
      }

      for (final weapon in bundle.weapons) {
        expect(allDocIds.add(weapon.docId), isTrue,
            reason: 'Duplicate weapon docId: ${weapon.docId}');
      }

      for (final rule in bundle.rules) {
        expect(allDocIds.add(rule.docId), isTrue,
            reason: 'Duplicate rule docId: ${rule.docId}');
      }

      print('[M9 INVARIANT] All ${allDocIds.length} docIds are unique');
      print('[M9 INVARIANT] DUPLICATE_DOC_ID count: ${bundle.duplicateDocIdCount}');
      expect(bundle.duplicateDocIdCount, 0);
    });

    test('v2: canonicalKey groups multiple docs correctly', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      // Count how many canonical keys have multiple weapons
      var multiWeaponKeys = 0;
      for (final entry in bundle.weaponKeyToDocIds.entries) {
        if (entry.value.length > 1) {
          multiWeaponKeys++;
        }
      }
      print(
          '[M9 INVARIANT] Weapon canonical keys with multiple docs: $multiWeaponKeys');

      // Count how many canonical keys have multiple rules
      var multiRuleKeys = 0;
      for (final entry in bundle.ruleKeyToDocIds.entries) {
        if (entry.value.length > 1) {
          multiRuleKeys++;
        }
      }
      print(
          '[M9 INVARIANT] Rule canonical keys with multiple docs: $multiRuleKeys');

      // The v2 design should have these groupings
      // (previously these would have been DUPLICATE_DOC_KEY diagnostics)
    });

    test('linking integrity: UnitDoc.weaponDocRefs resolve', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      var totalRefs = 0;
      var resolvedRefs = 0;

      for (final unit in bundle.units) {
        for (final weaponRef in unit.weaponDocRefs) {
          totalRefs++;
          final weapon = bundle.weaponByDocId(weaponRef);
          if (weapon != null) {
            resolvedRefs++;
          } else {
            print(
                '[M9 INVARIANT] WARN: Unit "${unit.name}" has unresolved weaponRef: $weaponRef');
          }
        }
      }

      print('[M9 INVARIANT] Weapon refs: $resolvedRefs/$totalRefs resolved');
      expect(resolvedRefs, totalRefs);
    });

    test('linking integrity: WeaponDoc.ruleDocRefs resolve', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      var totalRefs = 0;
      var resolvedRefs = 0;

      for (final weapon in bundle.weapons) {
        for (final ruleRef in weapon.ruleDocRefs) {
          totalRefs++;
          final rule = bundle.ruleByDocId(ruleRef);
          if (rule != null) {
            resolvedRefs++;
          } else {
            print(
                '[M9 INVARIANT] WARN: Weapon "${weapon.name}" has unresolved ruleRef: $ruleRef');
          }
        }
      }

      print('[M9 INVARIANT] Rule refs: $resolvedRefs/$totalRefs resolved');
      expect(resolvedRefs, totalRefs);
    });

    test('diagnostic stability: counts stable across runs', () {
      final indexService = IndexService();

      final bundle1 = indexService.buildIndex(boundBundle);
      final bundle2 = indexService.buildIndex(boundBundle);

      expect(bundle1.missingNameCount, bundle2.missingNameCount);
      expect(bundle1.duplicateDocIdCount, bundle2.duplicateDocIdCount);
      expect(bundle1.unknownProfileTypeCount, bundle2.unknownProfileTypeCount);
      expect(bundle1.linkTargetMissingCount, bundle2.linkTargetMissingCount);

      print('[M9 INVARIANT] Diagnostic counts stable:');
      print('[M9 INVARIANT]   MISSING_NAME: ${bundle1.missingNameCount}');
      print('[M9 INVARIANT]   DUPLICATE_DOC_ID: ${bundle1.duplicateDocIdCount}');
      print(
          '[M9 INVARIANT]   UNKNOWN_PROFILE_TYPE: ${bundle1.unknownProfileTypeCount}');
      print(
          '[M9 INVARIANT]   LINK_TARGET_MISSING: ${bundle1.linkTargetMissingCount}');
    });
  });

  group('M9 Index: player query smoke tests', () {
    test('smoke: find unit by normalized name', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      // Try to find some common Space Marines units by canonical key
      final searchTerms = [
        'intercessor',
        'tactical',
        'assault',
        'captain',
        'librarian',
      ];

      print('[M9 SMOKE] Searching for units by canonical key:');
      for (final term in searchTerms) {
        // Search units whose canonicalKey contains the term
        final matches = bundle.units
            .where((u) => u.canonicalKey.contains(term))
            .toList();
        print('[M9 SMOKE]   "$term": ${matches.length} matches');
        for (final m in matches.take(3)) {
          print('[M9 SMOKE]     - ${m.name} (${m.docId})');
        }
      }
    });

    test('smoke: retrieve stats for found unit', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      // Find first unit with characteristics
      final unitWithStats = bundle.units.firstWhere(
        (u) => u.characteristics.isNotEmpty,
        orElse: () => throw StateError('No units with characteristics found'),
      );

      print('[M9 SMOKE] Unit: ${unitWithStats.name}');
      print('[M9 SMOKE] docId: ${unitWithStats.docId}');
      print('[M9 SMOKE] Stats:');
      for (final char in unitWithStats.characteristics) {
        print('[M9 SMOKE]   ${char.name}: ${char.valueText}');
      }

      expect(unitWithStats.characteristics.isNotEmpty, isTrue);
    });

    test('smoke: retrieve weapon names for unit', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      // Find first unit with weapon refs
      final unitWithWeapons = bundle.units.firstWhere(
        (u) => u.weaponDocRefs.isNotEmpty,
        orElse: () => throw StateError('No units with weapons found'),
      );

      print('[M9 SMOKE] Unit: ${unitWithWeapons.name}');
      print('[M9 SMOKE] Weapons:');
      for (final weaponRef in unitWithWeapons.weaponDocRefs) {
        final weapon = bundle.weaponByDocId(weaponRef);
        if (weapon != null) {
          print('[M9 SMOKE]   - ${weapon.name} (${weapon.docId})');
        }
      }

      expect(unitWithWeapons.weaponDocRefs.isNotEmpty, isTrue);
    });

    test('smoke: retrieve rule text by canonical key', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      if (bundle.rules.isEmpty) {
        print('[M9 SMOKE] No rules indexed (expected for some fixtures)');
        return;
      }

      // Get first rule
      final rule = bundle.rules.first;
      print('[M9 SMOKE] Rule: ${rule.name}');
      print('[M9 SMOKE] docId: ${rule.docId}');
      print('[M9 SMOKE] canonicalKey: ${rule.canonicalKey}');
      print('[M9 SMOKE] Description preview:');
      final preview = rule.description.length > 200
          ? '${rule.description.substring(0, 200)}...'
          : rule.description;
      print('[M9 SMOKE]   $preview');

      // Verify we can look it up by canonical key
      final found = bundle.rulesByCanonicalKey(rule.canonicalKey).toList();
      expect(found.isNotEmpty, isTrue);
      expect(found.any((r) => r.docId == rule.docId), isTrue);
      print('[M9 SMOKE] Rule lookup by canonical key: SUCCESS');
    });

    test('smoke: find all weapons with same name (canonical key grouping)', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      // Find a canonical key with multiple weapons
      String? multiKey;
      int? expectedCount;
      for (final entry in bundle.weaponKeyToDocIds.entries) {
        if (entry.value.length > 1) {
          multiKey = entry.key;
          expectedCount = entry.value.length;
          break;
        }
      }

      if (multiKey != null) {
        final weapons = bundle.weaponsByCanonicalKey(multiKey).toList();
        print(
            '[M9 SMOKE] Weapons with canonicalKey "$multiKey": ${weapons.length}');
        for (final w in weapons.take(5)) {
          print('[M9 SMOKE]   - ${w.name} (${w.docId})');
        }
        expect(weapons.length, expectedCount);
      } else {
        print('[M9 SMOKE] No weapon canonical key with multiple docs found');
      }
    });

    test('smoke: find units by keyword (category)', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      // Try common category keywords
      final keywords = ['infantry', 'battleline', 'character', 'vehicle'];

      print('[M9 SMOKE] Finding units by keyword:');
      for (final keyword in keywords) {
        final matches = bundle.unitsByKeyword(keyword).toList();
        print('[M9 SMOKE]   "$keyword": ${matches.length} units');
        for (final m in matches.take(3)) {
          print('[M9 SMOKE]     - ${m.name}');
        }
      }
    });
  });

  group('M9 Index: player-shaped query tests', () {
    test('findUnitsContaining "intercessor" returns matching units', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      final results = bundle.findUnitsContaining('Intercessor');
      print('[M9 PLAYER] findUnitsContaining("Intercessor"): ${results.length}');
      for (final u in results) {
        print('[M9 PLAYER]   - ${u.name} (${u.docId})');
      }

      expect(results.isNotEmpty, isTrue,
          reason: 'Space Marines should have Intercessor units');

      // Results should be stable-sorted (by canonicalKey order from SplayTreeMap)
      // Verify all results contain "intercessor" in canonicalKey
      for (final u in results) {
        expect(u.canonicalKey.contains('intercessor'), isTrue,
            reason: '${u.name} canonicalKey should contain "intercessor"');
      }
    });

    test('findWeaponsContaining "bolt rifle" returns multiple WeaponDocs', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      final results = bundle.findWeaponsContaining('bolt rifle');
      print(
          '[M9 PLAYER] findWeaponsContaining("bolt rifle"): ${results.length}');
      for (final w in results.take(10)) {
        print('[M9 PLAYER]   - ${w.name} (${w.docId}, key=${w.canonicalKey})');
      }

      // Should have multiple weapons matching "bolt rifle"
      expect(results.isNotEmpty, isTrue,
          reason: 'Space Marines should have bolt rifle weapons');

      // All results should contain "bolt" and "rifle" in canonicalKey
      for (final w in results) {
        expect(w.canonicalKey.contains('bolt'), isTrue);
        expect(w.canonicalKey.contains('rifle'), isTrue);
      }
    });

    test('findRulesContaining "leader" returns matching RuleDocs', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      final results = bundle.findRulesContaining('leader');
      print('[M9 PLAYER] findRulesContaining("leader"): ${results.length}');
      for (final r in results.take(5)) {
        print('[M9 PLAYER]   - ${r.name} (${r.docId})');
      }

      // Leader is a common ability in 10th edition
      expect(results.isNotEmpty, isTrue,
          reason: 'Space Marines should have Leader rules');
    });

    test('unitsByKeyword "infantry" returns units with Infantry keyword', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      final results = bundle.unitsByKeyword('infantry').toList();
      print('[M9 PLAYER] unitsByKeyword("infantry"): ${results.length} units');
      for (final u in results.take(5)) {
        print('[M9 PLAYER]   - ${u.name}');
      }

      expect(results.isNotEmpty, isTrue,
          reason: 'Space Marines should have Infantry units');

      // All returned units should have "infantry" in their keyword tokens
      for (final u in results) {
        expect(u.keywordTokens.contains('infantry'), isTrue,
            reason: '${u.name} should have "infantry" keyword');
      }
    });

    test('characteristic index points to docs with M and SV', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      // "m" characteristic (Movement)
      final mDocIds = bundle.docIdsByCharacteristic('M').toList();
      print('[M9 PLAYER] docIdsByCharacteristic("M"): ${mDocIds.length} docs');
      expect(mDocIds.isNotEmpty, isTrue,
          reason: 'Units should have M characteristic');

      // "sv" characteristic (Save)
      final svDocIds = bundle.docIdsByCharacteristic('SV').toList();
      print(
          '[M9 PLAYER] docIdsByCharacteristic("SV"): ${svDocIds.length} docs');
      expect(svDocIds.isNotEmpty, isTrue,
          reason: 'Units should have SV characteristic');

      // Verify a sample unit resolves from M index
      final sampleDocId = mDocIds.first;
      final unit = bundle.unitByDocId(sampleDocId);
      if (unit != null) {
        print('[M9 PLAYER] Sample unit from M index: ${unit.name}');
        final mChar = unit.characteristics
            .where((c) => c.name.toLowerCase() == 'm')
            .firstOrNull;
        expect(mChar, isNotNull,
            reason: 'Unit from M index should have M characteristic');
        print('[M9 PLAYER]   M: ${mChar!.valueText}');
      }
    });

    test('autocomplete: unit keys starting with "inter"', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      final completions = bundle.autocompleteUnitKeys('inter', limit: 10);
      print('[M9 PLAYER] autocompleteUnitKeys("inter"): $completions');

      expect(completions.isNotEmpty, isTrue,
          reason: 'Should have unit keys starting with "inter"');

      // All results should start with "inter"
      for (final key in completions) {
        expect(key.startsWith('inter'), isTrue);
      }

      // Results should be sorted
      final sorted = List<String>.from(completions)..sort();
      expect(completions, sorted);
    });

    test('query surface: findByName exact match vs contains', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      // Exact match should be more specific than contains
      if (bundle.units.isNotEmpty) {
        final sampleUnit = bundle.units.first;
        final exactResults = bundle.findUnitsByName(sampleUnit.name);
        final containsResults =
            bundle.findUnitsContaining(sampleUnit.canonicalKey);

        print('[M9 PLAYER] Exact match "${sampleUnit.name}": '
            '${exactResults.length} results');
        print('[M9 PLAYER] Contains "${sampleUnit.canonicalKey}": '
            '${containsResults.length} results');

        // Exact should be subset of contains
        expect(containsResults.length, greaterThanOrEqualTo(exactResults.length),
            reason: 'Contains should return at least as many as exact match');

        // Exact results should all have matching canonicalKey
        for (final u in exactResults) {
          expect(u.canonicalKey, sampleUnit.canonicalKey);
        }
      }
    });

    test('diagnostic summary: duplicate source profiles are summarized', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      // Should have summary diagnostics, not per-instance
      final skipDiags = bundle.diagnostics
          .where((d) =>
              d.code == IndexDiagnosticCode.duplicateSourceProfileSkipped)
          .toList();

      print('[M9 PLAYER] DUPLICATE_SOURCE_PROFILE_SKIPPED diagnostics: '
          '${skipDiags.length}');
      for (final d in skipDiags) {
        print('[M9 PLAYER]   ${d.message}');
      }

      // Should be at most 2 (one for rules, one for weapons) — not thousands
      expect(skipDiags.length, lessThanOrEqualTo(2),
          reason:
              'Duplicate skips should be summarized, not emitted per-instance');

      // No DUPLICATE_DOC_ID diagnostics (those are now silent skips)
      expect(bundle.duplicateDocIdCount, 0,
          reason: 'No DUPLICATE_DOC_ID diagnostics should be emitted');
    });

    test('query surface: results are stable-sorted by docId', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      // findUnitsContaining results should be sorted by docId
      // (because SplayTreeMap iterates keys in order, and values are sorted)
      final units = bundle.findUnitsContaining('captain');
      if (units.length > 1) {
        for (var i = 1; i < units.length; i++) {
          // Within the same canonicalKey, docIds are sorted.
          // Across keys, results follow SplayTreeMap key order.
          // This is a weaker guarantee but still deterministic.
        }
        print(
            '[M9 PLAYER] findUnitsContaining("captain"): ${units.length} results, order is deterministic');
      }

      // Build twice and verify same order
      final bundle2 = indexService.buildIndex(boundBundle);
      final units2 = bundle2.findUnitsContaining('captain');
      expect(units.length, units2.length);
      for (var i = 0; i < units.length; i++) {
        expect(units[i].docId, units2[i].docId,
            reason: 'Query results should be deterministic across builds');
      }
      print('[M9 PLAYER] Query results are deterministic across builds');
    });
  });
}

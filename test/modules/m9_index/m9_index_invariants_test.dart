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
        expect(bundle1.units[i].name, bundle2.units[i].name);
        expect(bundle1.units[i].entryId, bundle2.units[i].entryId);
      }
      print('[M9 INVARIANT] Units are identical in order');

      // Same weapon docIds in same order
      for (var i = 0; i < bundle1.weapons.length; i++) {
        expect(bundle1.weapons[i].docId, bundle2.weapons[i].docId);
        expect(bundle1.weapons[i].name, bundle2.weapons[i].name);
        expect(bundle1.weapons[i].profileId, bundle2.weapons[i].profileId);
      }
      print('[M9 INVARIANT] Weapons are identical in order');

      // Same rule docIds in same order
      for (var i = 0; i < bundle1.rules.length; i++) {
        expect(bundle1.rules[i].docId, bundle2.rules[i].docId);
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

    test('determinism: keyword index keys are sorted', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      final keys = bundle.keywordToUnitDocIds.keys.toList();
      final sortedKeys = List<String>.from(keys)..sort();

      expect(keys, sortedKeys);
      print('[M9 INVARIANT] Keyword index keys are sorted (${keys.length} keys)');
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

    test('rule deduplication: repeated rule creates exactly one RuleDoc', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      // Check for duplicate docIds (should be none)
      final docIds = bundle.rules.map((r) => r.docId).toSet();
      expect(docIds.length, bundle.rules.length,
          reason: 'All RuleDocs should have unique docIds');
      print('[M9 INVARIANT] All ${bundle.rules.length} rules have unique docIds');

      // Count DUPLICATE_RULE_CANONICAL_KEY diagnostics
      final dupRuleDiags = bundle.diagnostics
          .where(
              (d) => d.code == IndexDiagnosticCode.duplicateRuleCanonicalKey)
          .length;
      print(
          '[M9 INVARIANT] DUPLICATE_RULE_CANONICAL_KEY diagnostics: $dupRuleDiags');
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

      print(
          '[M9 INVARIANT] Weapon refs: $resolvedRefs/$totalRefs resolved');
      // All should resolve (we only add refs for weapons we indexed)
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
      // All should resolve (we only add refs for rules we indexed)
      expect(resolvedRefs, totalRefs);
    });

    test('diagnostic stability: counts stable across runs', () {
      final indexService = IndexService();

      final bundle1 = indexService.buildIndex(boundBundle);
      final bundle2 = indexService.buildIndex(boundBundle);

      expect(bundle1.missingNameCount, bundle2.missingNameCount);
      expect(bundle1.duplicateDocKeyCount, bundle2.duplicateDocKeyCount);
      expect(bundle1.duplicateRuleCanonicalKeyCount,
          bundle2.duplicateRuleCanonicalKeyCount);
      expect(bundle1.unknownProfileTypeCount, bundle2.unknownProfileTypeCount);
      expect(bundle1.linkTargetMissingCount, bundle2.linkTargetMissingCount);

      print('[M9 INVARIANT] Diagnostic counts stable:');
      print('[M9 INVARIANT]   MISSING_NAME: ${bundle1.missingNameCount}');
      print('[M9 INVARIANT]   DUPLICATE_DOC_KEY: ${bundle1.duplicateDocKeyCount}');
      print(
          '[M9 INVARIANT]   DUPLICATE_RULE_CANONICAL_KEY: ${bundle1.duplicateRuleCanonicalKeyCount}');
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

      // Try to find some common Space Marines units
      final searchTerms = [
        'intercessor',
        'tactical',
        'assault',
        'captain',
        'librarian',
      ];

      print('[M9 SMOKE] Searching for units:');
      for (final term in searchTerms) {
        // Search in unit names (partial match)
        final matches = bundle.units
            .where((u) => u.docId.contains(term))
            .toList();
        print('[M9 SMOKE]   "$term": ${matches.length} matches');
        for (final m in matches.take(3)) {
          print('[M9 SMOKE]     - ${m.name}');
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
          print('[M9 SMOKE]   - ${weapon.name}');
        }
      }

      expect(unitWithWeapons.weaponDocRefs.isNotEmpty, isTrue);
    });

    test('smoke: retrieve rule text by name', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      if (bundle.rules.isEmpty) {
        print('[M9 SMOKE] No rules indexed (expected for some fixtures)');
        return;
      }

      // Get first rule
      final rule = bundle.rules.first;
      print('[M9 SMOKE] Rule: ${rule.name}');
      print('[M9 SMOKE] Description preview:');
      final preview = rule.description.length > 200
          ? '${rule.description.substring(0, 200)}...'
          : rule.description;
      print('[M9 SMOKE]   $preview');

      // Verify we can look it up by key
      final found = bundle.ruleByKey(rule.docId);
      expect(found, isNotNull);
      expect(found!.name, rule.name);
      print('[M9 SMOKE] Rule lookup by key: SUCCESS');
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
}

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

    // Acquire, parse, wrap, link, bind bundle once for all tests
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

  group('M9 Index: flow harness (fixtures)', () {
    test('buildIndex: creates IndexBundle from BoundPackBundle', () {
      final indexService = IndexService();
      final indexBundle = indexService.buildIndex(boundBundle);

      print('[M9 TEST] M9 Index succeeded');
      print('[M9 TEST] Index packId: ${indexBundle.packId}');
      print('[M9 TEST] Indexed at: ${indexBundle.indexedAt}');

      // packId must match
      expect(indexBundle.packId, boundBundle.packId);

      // Document counts
      print('[M9 TEST] UnitDocs: ${indexBundle.units.length}');
      print('[M9 TEST] WeaponDocs: ${indexBundle.weapons.length}');
      print('[M9 TEST] RuleDocs: ${indexBundle.rules.length}');

      // Diagnostics (should be low with v2 key strategy)
      print('[M9 TEST] Diagnostics: ${indexBundle.diagnostics.length}');
      print('[M9 TEST]   MISSING_NAME: ${indexBundle.missingNameCount}');
      print('[M9 TEST]   DUPLICATE_DOC_ID: ${indexBundle.duplicateDocIdCount}');
      print(
          '[M9 TEST]   UNKNOWN_PROFILE_TYPE: ${indexBundle.unknownProfileTypeCount}');
      print(
          '[M9 TEST]   LINK_TARGET_MISSING: ${indexBundle.linkTargetMissingCount}');

      // Print first 10 diagnostics for debugging
      for (final d in indexBundle.diagnostics.take(10)) {
        print('[M9 TEST] Diagnostic: ${d.codeString} - ${d.message}');
      }
      if (indexBundle.diagnostics.length > 10) {
        print(
            '[M9 TEST]   ... and ${indexBundle.diagnostics.length - 10} more');
      }

      // v2: DUPLICATE_DOC_ID should be near-zero
      expect(indexBundle.duplicateDocIdCount, 0,
          reason: 'With stable IDs, docId collisions should not occur');

      // boundBundle reference preserved
      expect(indexBundle.boundBundle, same(boundBundle));

      print('[M9 TEST] All flow validations passed');
    });

    test('units: sample unit documents have expected structure', () {
      final indexService = IndexService();
      final indexBundle = indexService.buildIndex(boundBundle);

      // Print sample units
      for (final unit in indexBundle.units.take(5)) {
        print('[M9 TEST] Unit: ${unit.name} (docId=${unit.docId})');
        print('[M9 TEST]   canonicalKey: ${unit.canonicalKey}');
        print('[M9 TEST]   entryId: ${unit.entryId}');
        print('[M9 TEST]   characteristics: ${unit.characteristics.length}');
        for (final c in unit.characteristics.take(6)) {
          print('[M9 TEST]     ${c.name}: ${c.valueText}');
        }
        print('[M9 TEST]   keywords: ${unit.keywordTokens.take(5).toList()}');
        print(
            '[M9 TEST]   categories: ${unit.categoryTokens.take(5).toList()}');
        print('[M9 TEST]   weaponRefs: ${unit.weaponDocRefs.length}');
        print('[M9 TEST]   ruleRefs: ${unit.ruleDocRefs.length}');
        print(
            '[M9 TEST]   costs: ${unit.costs.map((c) => '${c.typeName}=${c.value}').toList()}');
      }

      // Units should have characteristics (from unit profiles)
      final unitsWithChars =
          indexBundle.units.where((u) => u.characteristics.isNotEmpty).toList();
      print('[M9 TEST] Units with characteristics: ${unitsWithChars.length}');

      // docId should be prefixed with "unit:"
      for (final unit in indexBundle.units.take(10)) {
        expect(unit.docId.startsWith('unit:'), isTrue,
            reason: 'UnitDoc docId should start with "unit:"');
      }
    });

    test('weapons: sample weapon documents have expected structure', () {
      final indexService = IndexService();
      final indexBundle = indexService.buildIndex(boundBundle);

      // Print sample weapons
      for (final weapon in indexBundle.weapons.take(5)) {
        print('[M9 TEST] Weapon: ${weapon.name} (docId=${weapon.docId})');
        print('[M9 TEST]   canonicalKey: ${weapon.canonicalKey}');
        print('[M9 TEST]   profileId: ${weapon.profileId}');
        print('[M9 TEST]   characteristics: ${weapon.characteristics.length}');
        for (final c in weapon.characteristics) {
          print('[M9 TEST]     ${c.name}: ${c.valueText}');
        }
        print('[M9 TEST]   keywords: ${weapon.keywordTokens}');
        print('[M9 TEST]   ruleRefs: ${weapon.ruleDocRefs}');
      }

      // docId should be prefixed with "weapon:"
      for (final weapon in indexBundle.weapons.take(10)) {
        expect(weapon.docId.startsWith('weapon:'), isTrue,
            reason: 'WeaponDoc docId should start with "weapon:"');
      }
    });

    test('rules: sample rule documents have expected structure', () {
      final indexService = IndexService();
      final indexBundle = indexService.buildIndex(boundBundle);

      // Print sample rules
      for (final rule in indexBundle.rules.take(5)) {
        print('[M9 TEST] Rule: ${rule.name} (docId=${rule.docId})');
        print('[M9 TEST]   canonicalKey: ${rule.canonicalKey}');
        print('[M9 TEST]   ruleId: ${rule.ruleId}');
        final descPreview = rule.description.length > 80
            ? '${rule.description.substring(0, 80)}...'
            : rule.description;
        print('[M9 TEST]   description: $descPreview');
      }

      // All RuleDocs should have unique docIds
      final docIds = indexBundle.rules.map((r) => r.docId).toSet();
      expect(docIds.length, indexBundle.rules.length,
          reason: 'RuleDocs should have unique docIds');
      print('[M9 TEST] All RuleDocs have unique docIds');

      // docId should be prefixed with "rule:"
      for (final rule in indexBundle.rules.take(10)) {
        expect(rule.docId.startsWith('rule:'), isTrue,
            reason: 'RuleDoc docId should start with "rule:"');
      }
    });

    test('query surface: unitByDocId returns correct unit or null', () {
      final indexService = IndexService();
      final indexBundle = indexService.buildIndex(boundBundle);

      if (indexBundle.units.isNotEmpty) {
        final firstUnit = indexBundle.units.first;
        final found = indexBundle.unitByDocId(firstUnit.docId);
        expect(found, isNotNull);
        expect(found!.docId, firstUnit.docId);
        expect(found.name, firstUnit.name);
        print('[M9 TEST] unitByDocId found: ${found.name}');
      }

      // Non-existent docId returns null
      final notFound = indexBundle.unitByDocId('unit:this-id-does-not-exist');
      expect(notFound, isNull);
      print('[M9 TEST] unitByDocId returns null for non-existent docId');
    });

    test('query surface: unitsByCanonicalKey returns matching units', () {
      final indexService = IndexService();
      final indexBundle = indexService.buildIndex(boundBundle);

      if (indexBundle.units.isNotEmpty) {
        final firstUnit = indexBundle.units.first;
        final matches =
            indexBundle.unitsByCanonicalKey(firstUnit.canonicalKey).toList();
        expect(matches.isNotEmpty, isTrue);
        expect(matches.any((u) => u.docId == firstUnit.docId), isTrue);
        print(
            '[M9 TEST] unitsByCanonicalKey("${firstUnit.canonicalKey}"): ${matches.length} units');
      }

      // Non-existent key returns empty
      final empty =
          indexBundle.unitsByCanonicalKey('xyznonexistentcanonicalkey');
      expect(empty.isEmpty, isTrue);
      print(
          '[M9 TEST] unitsByCanonicalKey returns empty for non-existent key');
    });

    test('query surface: weaponsByCanonicalKey returns all matching weapons',
        () {
      final indexService = IndexService();
      final indexBundle = indexService.buildIndex(boundBundle);

      // Find a weapon name that appears multiple times
      final keyCount = <String, int>{};
      for (final weapon in indexBundle.weapons) {
        keyCount[weapon.canonicalKey] =
            (keyCount[weapon.canonicalKey] ?? 0) + 1;
      }

      // Find a key with multiple weapons
      final multiKey =
          keyCount.entries.where((e) => e.value > 1).take(1).firstOrNull;
      if (multiKey != null) {
        final matches =
            indexBundle.weaponsByCanonicalKey(multiKey.key).toList();
        expect(matches.length, multiKey.value);
        print(
            '[M9 TEST] weaponsByCanonicalKey("${multiKey.key}"): ${matches.length} weapons (expected ${multiKey.value})');
      } else {
        print('[M9 TEST] No weapon canonical key with multiple matches found');
      }
    });

    test('query surface: unitsByKeyword returns matching units', () {
      final indexService = IndexService();
      final indexBundle = indexService.buildIndex(boundBundle);

      // Find a keyword used by at least one unit
      for (final unit in indexBundle.units) {
        if (unit.keywordTokens.isNotEmpty) {
          final keyword = unit.keywordTokens.first;
          final matches = indexBundle.unitsByKeyword(keyword).toList();
          expect(matches.isNotEmpty, isTrue);
          expect(matches.any((u) => u.docId == unit.docId), isTrue);
          print('[M9 TEST] unitsByKeyword("$keyword"): ${matches.length} units');
          break;
        }
      }

      // Non-existent keyword returns empty
      final empty = indexBundle.unitsByKeyword('xyznonexistentkeyword');
      expect(empty.isEmpty, isTrue);
      print('[M9 TEST] unitsByKeyword returns empty for non-existent keyword');
    });

    test('inverted index: keywordToUnitDocIds is populated', () {
      final indexService = IndexService();
      final indexBundle = indexService.buildIndex(boundBundle);

      print(
          '[M9 TEST] Keyword index entries: ${indexBundle.keywordToUnitDocIds.length}');

      // Print sample keywords
      var count = 0;
      for (final entry in indexBundle.keywordToUnitDocIds.entries) {
        if (count++ >= 10) break;
        print('[M9 TEST]   "${entry.key}": ${entry.value.length} units');
      }

      // Should have some keywords indexed
      expect(indexBundle.keywordToUnitDocIds.isNotEmpty, isTrue,
          reason: 'Should have indexed keywords from categories');
    });

    test('inverted index: characteristicNameToDocIds is populated', () {
      final indexService = IndexService();
      final indexBundle = indexService.buildIndex(boundBundle);

      print(
          '[M9 TEST] Characteristic index entries: ${indexBundle.characteristicNameToDocIds.length}');

      // Print sample characteristics
      var count = 0;
      for (final entry in indexBundle.characteristicNameToDocIds.entries) {
        if (count++ >= 10) break;
        print('[M9 TEST]   "${entry.key}": ${entry.value.length} docs');
      }

      // Should have some characteristics indexed
      expect(indexBundle.characteristicNameToDocIds.isNotEmpty, isTrue,
          reason: 'Should have indexed characteristic names');
    });

    test('deterministic lists: all lists are sorted by docId', () {
      final indexService = IndexService();
      final indexBundle = indexService.buildIndex(boundBundle);

      // Units sorted
      for (var i = 1; i < indexBundle.units.length; i++) {
        expect(
          indexBundle.units[i - 1].docId.compareTo(indexBundle.units[i].docId),
          lessThanOrEqualTo(0),
          reason: 'Units should be sorted by docId',
        );
      }
      print('[M9 TEST] Units are sorted by docId');

      // Weapons sorted
      for (var i = 1; i < indexBundle.weapons.length; i++) {
        expect(
          indexBundle.weapons[i - 1]
              .docId
              .compareTo(indexBundle.weapons[i].docId),
          lessThanOrEqualTo(0),
          reason: 'Weapons should be sorted by docId',
        );
      }
      print('[M9 TEST] Weapons are sorted by docId');

      // Rules sorted
      for (var i = 1; i < indexBundle.rules.length; i++) {
        expect(
          indexBundle.rules[i - 1].docId.compareTo(indexBundle.rules[i].docId),
          lessThanOrEqualTo(0),
          reason: 'Rules should be sorted by docId',
        );
      }
      print('[M9 TEST] Rules are sorted by docId');
    });
  });

  group('M9 Index: normalize and tokenize', () {
    test('normalize: lowercase', () {
      expect(IndexService.normalize('ASSAULT'), 'assault');
      expect(IndexService.normalize('Heavy'), 'heavy');
    });

    test('normalize: strip punctuation', () {
      expect(IndexService.normalize('bolt rifle'), 'bolt rifle');
      expect(IndexService.normalize("Captain's Sword"), 'captains sword');
      expect(IndexService.normalize('Master-crafted'), 'mastercrafted');
    });

    test('normalize: collapse whitespace', () {
      expect(IndexService.normalize('bolt  rifle'), 'bolt rifle');
      expect(IndexService.normalize('  spaced  out  '), 'spaced out');
    });

    test('normalize: complex case', () {
      expect(
        IndexService.normalize('Heavy Bolt Rifle (Assault)'),
        'heavy bolt rifle assault',
      );
    });

    test('tokenize: returns sorted unique tokens', () {
      final tokens = IndexService.tokenize('Heavy Bolt Rifle');
      expect(tokens, ['bolt', 'heavy', 'rifle']);
    });

    test('tokenize: handles duplicates', () {
      final tokens = IndexService.tokenize('bolt bolt bolt');
      expect(tokens, ['bolt']);
    });

    test('tokenize: empty string returns empty list', () {
      final tokens = IndexService.tokenize('');
      expect(tokens, isEmpty);
    });

    test('tokenize: punctuation only returns empty list', () {
      final tokens = IndexService.tokenize('---');
      expect(tokens, isEmpty);
    });
  });
}

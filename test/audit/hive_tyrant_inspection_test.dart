/// Hive Tyrant Targeted Inspection
///
/// PURPOSE
/// -------
/// Pass 1 inspection: verify Hive Tyrant target resolution and rule source.
///
/// Two questions this test answers — deliberately — without touching M5 or M9:
///
///   Task 1 — Target Resolution
///   ──────────────────────────
///   Which UnitDoc does exportByName("Hive Tyrant") select?
///   Are there multiple UnitDocs whose canonicalKey contains "hive tyrant"?
///   Do their stats match the walking variant, winged variant, or neither?
///
///   Task 2 — Rule Source Verification
///   ───────────────────────────────────
///   Why does the Hive Tyrant dump show ruleDocRefCount=236 while
///   the expected rules (Onslaught, Shadow in the Warp, etc.) are absent?
///   Is the rule collection sourcing from unit-specific profiles or from
///   the entire BoundEntry subtree including shared army options?
///
/// FINDINGS (from static analysis of existing dump + code, 2026-03-09)
/// --------------------------------------------------------------------
///
/// Task 1 — Target Resolution:
///   Selected unit: docId=unit:3e96-8098-3401-77af, name="Hive Tyrant"
///   Selected stats: M=8", T=10, SV=2+, W=10, LD=7+, OC=3
///   Expected stats: M=10", T=10, SV=2+, W=14, LD=6+, OC=3
///
///   The docId for the selected unit is the FIRST (alphabetically smallest)
///   match for canonicalKey="hive tyrant" in unitKeyToDocIds. Whether there
///   are other UnitDocs with this same canonical key is what Task 1 verifies.
///
///   The stat mismatch (M, W, LD all wrong) is consistent with either:
///     a) A catalog version difference (BattleScribe data vs Wahapedia)
///     b) Multiple "Hive Tyrant" entries and the wrong one is selected first
///   This test determines which.
///
/// Task 2 — Rule Source:
///   ruleDocRefCount=236, but NONE of the 5 expected Hive Tyrant rules
///   (Onslaught, Shadow in the Warp, Synaptic Imperative, Warlord, Leader)
///   appear by exact name in the 236-rule set.
///
///   Root cause: _collectRuleRefs in IndexService recursively walks the ENTIRE
///   BoundEntry subtree, including children that represent shared catalog options
///   (weapon upgrades, Crusade options, army-wide special rules). This pulls in
///   ALL ability profiles from the entire entry tree, not just the unit's own.
///
///   The exporter IS using unit.ruleDocRefs correctly — but the refs themselves
///   are wrong because _collectRuleRefs over-collects. This is an M9 scoping bug.
///
/// NEXT STEPS (do not modify M5/M9 until these checks complete)
/// ─────────────────────────────────────────────────────────────
///   After running this test:
///   1. Inspect "All 'hive tyrant' UnitDocs" output — if only one exists, the
///      stat mismatch is a catalog version difference. If multiple exist, decide
///      which should be the audit target.
///   2. Inspect "Rule collection breakdown" output — it will confirm how many
///      rules come from the top-level entry vs. recursive children, and whether
///      the expected rules exist anywhere in the index.
///
/// RUNNING
/// -------
///   flutter test test/audit/hive_tyrant_inspection_test.dart --reporter expanded

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:flutter_test/flutter_test.dart';

import 'unit_dump_exporter.dart';

// ---------------------------------------------------------------------------
// Pipeline helper (same as unit_audit_test.dart)
// ---------------------------------------------------------------------------

Future<({IndexBundle index, BoundPackBundle bound})> _buildIndexAndBound({
  required String gameSystemPath,
  required String primaryCatalogPath,
  Map<String, String> dependencyPaths = const {},
  required Directory testDir,
}) async {
  const testSource = SourceLocator(
    sourceKey: 'audit_fixture',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  final gameSystemBytes = await File(gameSystemPath).readAsBytes();
  final primaryCatalogBytes = await File(primaryCatalogPath).readAsBytes();

  final rawBundle = await AcquireService(storage: AcquireStorage(appDataRoot: testDir)).buildBundle(
    gameSystemBytes: gameSystemBytes,
    gameSystemExternalFileName: gameSystemPath.split('/').last,
    primaryCatalogBytes: primaryCatalogBytes,
    primaryCatalogExternalFileName: primaryCatalogPath.split('/').last,
    requestDependencyBytes: (targetId) async {
      final path = dependencyPaths[targetId];
      if (path == null) return null;
      return File(path).readAsBytes();
    },
    source: testSource,
  );

  final parsedBundle = await ParseService().parseBundle(rawBundle: rawBundle);
  final wrappedBundle = await WrapService().wrapBundle(parsedBundle: parsedBundle);
  final linkedBundle = await LinkService().linkBundle(wrappedBundle: wrappedBundle);
  final boundBundle = await BindService().bindBundle(linkedBundle: linkedBundle);
  final index = IndexService().buildIndex(boundBundle);

  return (index: index, bound: boundBundle);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Counts how many ability profiles exist at the TOP LEVEL of an entry
/// (not recursing into children). Used to compare against total recursive count.
int _topLevelAbilityProfileCount(BoundEntry entry) {
  var count = 0;
  for (final profile in entry.profiles) {
    final typeName = (profile.typeName ?? '').trim().toLowerCase();
    if (typeName == 'abilities' || typeName == 'ability') count++;
  }
  return count;
}

/// Recursively counts all ability profiles in the entry subtree.
int _recursiveAbilityProfileCount(BoundEntry entry) {
  var count = _topLevelAbilityProfileCount(entry);
  for (final child in entry.children) {
    count += _recursiveAbilityProfileCount(child);
  }
  return count;
}

/// Recursively counts children at each level (breadth of subtree).
int _recursiveChildCount(BoundEntry entry) {
  var count = entry.children.length;
  for (final child in entry.children) {
    count += _recursiveChildCount(child);
  }
  return count;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Hive Tyrant Targeted Inspection', () {
    const tyranidCatalogPath = 'test/Xenos - Tyranids.cat';
    const libTyranidPath = 'test/Library - Tyranids.cat';
    const unalignedPath = 'test/Unaligned Forces.cat';

    late Directory _testDir;
    late IndexBundle index;
    late BoundPackBundle bound;
    bool _fixturePresent = false;

    setUpAll(() async {
      _testDir = await Directory.systemTemp.createTemp('cgp_test_');

      _fixturePresent = File(tyranidCatalogPath).existsSync() &&
          File(libTyranidPath).existsSync() &&
          File(unalignedPath).existsSync();

      if (!_fixturePresent) {
        print('\n[INSPECT] SKIPPED: Tyranid catalog fixture(s) not present.');
        return;
      }

      final result = await _buildIndexAndBound(
        gameSystemPath: 'test/Warhammer 40,000.gst',
        primaryCatalogPath: tyranidCatalogPath,
        dependencyPaths: {
          '581a-46b9-5b86-44b7': unalignedPath,
          '374d-45f0-5832-001e': libTyranidPath,
        },
        testDir: _testDir,
      );
      index = result.index;
      bound = result.bound;

      print('[INSPECT] Index built: ${index.units.length} units, '
          '${index.weapons.length} weapons, ${index.rules.length} rules');
    });

    tearDownAll(() async {
      if (await _testDir.exists()) await _testDir.delete(recursive: true);
    });

    // ── Task 1: Target Resolution ─────────────────────────────────────────

    test('Task 1 — All UnitDocs whose canonicalKey contains "hive tyrant"', () {
      if (!_fixturePresent) return;

      print('\n' + '═' * 80);
      print('TASK 1: HIVE TYRANT TARGET RESOLUTION AUDIT');
      print('═' * 80);

      // Find ALL units containing "hive tyrant" in their canonical key
      final allHiveTyrantUnits = index.findUnitsContaining('Hive Tyrant');

      print('\nAll UnitDocs with canonicalKey containing "hive tyrant":');
      print('  Count: ${allHiveTyrantUnits.length}');
      print('');

      for (final unit in allHiveTyrantUnits) {
        final charMap = {for (final c in unit.characteristics) c.name: c.valueText};
        print('  ── ${unit.name} ──');
        print('     docId       : ${unit.docId}');
        print('     entryId     : ${unit.entryId}');
        print('     canonicalKey: ${unit.canonicalKey}');
        print('     M           : ${charMap['M'] ?? 'N/A'}');
        print('     T           : ${charMap['T'] ?? 'N/A'}');
        print('     W           : ${charMap['W'] ?? 'N/A'}');
        print('     LD          : ${charMap['LD'] ?? 'N/A'}');
        print('     OC          : ${charMap['OC'] ?? 'N/A'}');
        print('     SV          : ${charMap['SV'] ?? 'N/A'}');
        print('     pts         : ${unit.costs.where((c) => c.typeName.toLowerCase() == 'pts').firstOrNull?.value ?? 'N/A'}');
        print('     categoryTokens: ${unit.categoryTokens.join(', ')}');
        print('     weapons     : ${unit.weaponDocRefs.length}');
        print('     rules       : ${unit.ruleDocRefs.length}');
        print('');
      }

      // Verify what exportByName selects
      print('What exportByName("Hive Tyrant") selects:');
      final exactMatches = index.findUnitsByName('Hive Tyrant');
      print('  findUnitsByName exact matches: ${exactMatches.length}');
      if (exactMatches.isNotEmpty) {
        final selected = exactMatches.first;
        print('  → Selected docId: ${selected.docId}  (first by docId sort)');
        print('  → Name: ${selected.name}');
        final charMap = {for (final c in selected.characteristics) c.name: c.valueText};
        print('  → M=${charMap['M']}, W=${charMap['W']}, LD=${charMap['LD']}');
      }

      if (allHiveTyrantUnits.length > exactMatches.length) {
        print('\n  Contains-search found more units than exact match:');
        final extra = allHiveTyrantUnits
            .where((u) => !exactMatches.any((m) => m.docId == u.docId))
            .toList();
        for (final u in extra) {
          print('    "${u.name}" (canonicalKey="${u.canonicalKey}") would NOT be selected by exportByName');
        }
      }

      print('');
      print('Comparison against ground truth (Wahapedia datasheet):');
      print('  M : expected=10"  observed=${allHiveTyrantUnits.isEmpty ? "N/A" : ({for (final c in allHiveTyrantUnits.first.characteristics) c.name: c.valueText}['M'] ?? 'N/A')}');
      print('  W : expected=14   observed=${allHiveTyrantUnits.isEmpty ? "N/A" : ({for (final c in allHiveTyrantUnits.first.characteristics) c.name: c.valueText}['W'] ?? 'N/A')}');
      print('  LD: expected=6+   observed=${allHiveTyrantUnits.isEmpty ? "N/A" : ({for (final c in allHiveTyrantUnits.first.characteristics) c.name: c.valueText}['LD'] ?? 'N/A')}');
      print('  pts: expected=210  observed=${allHiveTyrantUnits.isEmpty ? "N/A" : allHiveTyrantUnits.first.costs.where((c) => c.typeName.toLowerCase() == 'pts').firstOrNull?.value ?? 'N/A'}');

      print('\n[VERDICT-T1] See output above to determine:');
      print('  - How many distinct UnitDocs share canonical key "hive tyrant"');
      print('  - Whether stat mismatch is due to wrong target or catalog version drift');

      // Test always passes — findings are informational
      expect(allHiveTyrantUnits, isNotEmpty,
          reason: 'Hive Tyrant must exist in the Tyranid index');
    });

    // ── Task 2: Rule Source Verification ─────────────────────────────────

    test('Task 2 — Rule source: why ruleDocRefCount=236, expected rules absent', () {
      if (!_fixturePresent) return;

      print('\n' + '═' * 80);
      print('TASK 2: RULE SOURCE VERIFICATION');
      print('═' * 80);

      // Find the Hive Tyrant UnitDoc
      final matches = index.findUnitsByName('Hive Tyrant');
      if (matches.isEmpty) {
        print('[INSPECT] Hive Tyrant not found — cannot inspect rules.');
        return;
      }
      final hiveTyrant = matches.first;

      print('\nSelected unit: ${hiveTyrant.name} (${hiveTyrant.docId})');
      print('ruleDocRefs count (from UnitDoc): ${hiveTyrant.ruleDocRefs.length}');

      // Find the BoundEntry for this unit
      final entry = bound.entries
          .where((e) => e.id == hiveTyrant.entryId)
          .firstOrNull;

      if (entry == null) {
        print('[INSPECT] BoundEntry for Hive Tyrant not found in BoundPackBundle.');
        return;
      }

      print('\nBoundEntry structure for "${entry.name}" (id=${entry.id}):');
      print('  Direct profiles count      : ${entry.profiles.length}');
      print('  Direct ability profiles    : ${_topLevelAbilityProfileCount(entry)}');
      print('  Direct children count      : ${entry.children.length}');
      print('  Total recursive children   : ${_recursiveChildCount(entry)}');
      print('  Total recursive ability profiles: ${_recursiveAbilityProfileCount(entry)}');

      print('\nDirect ability profiles on the entry (not children):');
      var directAbilityCount = 0;
      for (final profile in entry.profiles) {
        final typeName = (profile.typeName ?? '').trim().toLowerCase();
        if (typeName == 'abilities' || typeName == 'ability') {
          directAbilityCount++;
          print('  [DIRECT] "${profile.name}" (id=${profile.id}, type=${profile.typeName})');
        }
      }
      if (directAbilityCount == 0) {
        print('  (none — all ability profiles come from children)');
      }

      // Check whether expected rules exist anywhere in the index
      print('\nExpected Hive Tyrant rules (from Wahapedia ground truth):');
      const expectedRuleNames = [
        'Onslaught',
        'Shadow in the Warp',
        'Synaptic Imperative',
        'Warlord',
        'Leader',
      ];
      for (final ruleName in expectedRuleNames) {
        final exactMatches = index.findRulesByName(ruleName);
        final containsMatches = index.findRulesContaining(ruleName);
        print('  "$ruleName":');
        print('    Exact matches in index       : ${exactMatches.length}');
        print('    Contains-matches in index    : ${containsMatches.length}');
        if (containsMatches.isNotEmpty) {
          for (final r in containsMatches.take(3)) {
            print('      → "${r.name}" (${r.docId})');
          }
        }
        // Is it in the unit's ruleDocRefs?
        final inUnitRefs = exactMatches.any((r) => hiveTyrant.ruleDocRefs.contains(r.docId)) ||
            containsMatches.any((r) => hiveTyrant.ruleDocRefs.contains(r.docId));
        print('    In Hive Tyrant ruleDocRefs   : $inUnitRefs');
      }

      // Sample the first few and last few rules attached to the Hive Tyrant
      print('\nFirst 10 rules in Hive Tyrant ruleDocRefs:');
      for (final ref in hiveTyrant.ruleDocRefs.take(10)) {
        final r = index.ruleByDocId(ref);
        if (r != null) {
          print('  "${r.name}" (${r.docId})');
        }
      }

      print('\nLast 10 rules in Hive Tyrant ruleDocRefs:');
      for (final ref in hiveTyrant.ruleDocRefs.skip(hiveTyrant.ruleDocRefs.length > 10
          ? hiveTyrant.ruleDocRefs.length - 10
          : 0)) {
        final r = index.ruleByDocId(ref);
        if (r != null) {
          print('  "${r.name}" (${r.docId})');
        }
      }

      // Compare ruleDocRefCount to total rules in index
      print('\nIndex-wide context:');
      print('  Total rules in index            : ${index.rules.length}');
      print('  Hive Tyrant ruleDocRefs          : ${hiveTyrant.ruleDocRefs.length}');
      print('  Ratio (unit rules / index rules) : ${(hiveTyrant.ruleDocRefs.length / index.rules.length * 100).toStringAsFixed(1)}%');

      print('\n[VERDICT-T2]');
      print('  If "Direct ability profiles" above is 0 and "Total recursive ability profiles"');
      print('  is ≈${hiveTyrant.ruleDocRefs.length}, then _collectRuleRefs is collecting rules');
      print('  exclusively from the recursive subtree (children), NOT from the unit entry itself.');
      print('  This confirms the rule collection scope is too broad — M9 _collectRuleRefs');
      print('  must be scoped to exclude shared army-option children.');
      print('');
      print('  If the expected rules (Onslaught, Shadow in the Warp, etc.) are NOT in the');
      print('  Hive Tyrant ruleDocRefs, they may be stored under a different profile structure');
      print('  or under a parent entry, not under the selected BoundEntry directly.');

      // Test always passes — findings are informational
      expect(hiveTyrant.ruleDocRefs.length, greaterThan(0),
          reason: 'Hive Tyrant has rule refs (may be over-collecting)');
    });

    // ── Summary ───────────────────────────────────────────────────────────

    test('Summary dump: full exporter output for comparison', () {
      if (!_fixturePresent) return;

      final exporter = UnitDumpExporter();
      final dump = exporter.exportByName(index, 'Hive Tyrant');
      if (dump == null) {
        print('[INSPECT] Hive Tyrant not found by exporter.');
        return;
      }

      print('\n' + '═' * 80);
      print('EXPORTER OUTPUT SUMMARY');
      print('═' * 80);
      print('name        : ${dump.name}');
      print('docId       : ${dump.docId}');
      print('entryId     : ${dump.entryId}');
      print('weapons     : ${dump.weapons.length} (weaponDocRefCount=${dump.weaponDocRefCount})');
      print('rules       : ${dump.rules.length} (ruleDocRefCount=${dump.ruleDocRefCount})');
      print('keywords    : ${dump.keywordTokenCount} tokens, ${dump.categoryTokenCount} category tokens');
      print('');
      print('Stats:');
      for (final e in dump.characteristics.entries) {
        print('  ${e.key}: ${e.value}');
      }
      print('');
      print('Weapons (${dump.weapons.length}):');
      for (final w in dump.weapons) {
        print('  ${w.name}');
      }
      print('');
      print('First 10 rules (of ${dump.rules.length}):');
      for (final r in dump.rules.take(10)) {
        print('  "${r.name}"');
      }
      if (dump.rules.length > 10) {
        print('  ... and ${dump.rules.length - 10} more');
      }
    });
  });
}

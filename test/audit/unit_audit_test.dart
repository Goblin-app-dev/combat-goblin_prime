/// Unit Audit Test
///
/// PURPOSE
/// -------
/// Deterministic audit of Combat Goblin's unit reference output versus
/// Wahapedia ground truth. Exports a structured dump for each benchmark unit,
/// classifies every mismatch by error class, and prints a pattern summary so
/// systemic bugs can be fixed in batches rather than unit-by-unit.
///
/// BENCHMARK SET (add more as catalogs become available)
/// -------------------------------------------------------
/// Catalog: Imperium - Space Marines (loaded from fixture)
///   - Intercessor Squad     → basic infantry, validates stat/keyword/weapon pipeline
///
/// Catalog: Xenos - Tyranids  (NEEDS FIXTURE – see note below)
///   - Hive Tyrant           → monster/character, many weapons, known keyword bugs
///
/// TO ADD TYRANID FIXTURE
/// ----------------------
///   1. Download "Xenos - Tyranids.cat" from https://github.com/BSData/wh40k-10e
///   2. Place it in test/
///   3. Uncomment the tyranid section below
///
/// RUNNING
/// -------
///   flutter test test/audit/unit_audit_test.dart --reporter expanded
///
/// OUTPUT
/// ------
///   Prints audit dumps (text + JSON) and mismatch tables to stdout.
///   Zero failures expected when ground truth matches perfectly.
///   Each mismatch is printed but does not fail the test — the test records
///   findings as informational until they are deliberately verified and pinned.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_comparator.dart';
import 'unit_dump_exporter.dart';

// ---------------------------------------------------------------------------
// Pipeline helper
// ---------------------------------------------------------------------------

/// Runs the full M1→M9 pipeline for a given catalog + dependencies.
Future<IndexBundle> _buildIndex({
  required String gameSystemPath,
  required String primaryCatalogPath,
  Map<String, String> dependencyPaths = const {},
}) async {
  const testSource = SourceLocator(
    sourceKey: 'audit_fixture',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  final gameSystemBytes = await File(gameSystemPath).readAsBytes();
  final primaryCatalogBytes = await File(primaryCatalogPath).readAsBytes();

  final rawBundle = await AcquireService().buildBundle(
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
  return IndexService().buildIndex(boundBundle);
}

// ---------------------------------------------------------------------------
// Audit runner helper
// ---------------------------------------------------------------------------

void _runAudit({
  required IndexBundle index,
  required String unitName,
  required String? groundTruthPath,
}) {
  final exporter = UnitDumpExporter();
  final comparator = AuditComparator();

  // Export dump
  final dump = exporter.exportByName(index, unitName);

  if (dump == null) {
    print('\n[AUDIT] ⚠ Unit "$unitName" NOT FOUND in index.');
    print('[AUDIT]   Available units (first 20):');
    for (final u in index.units.take(20)) {
      print('[AUDIT]     ${u.name}');
    }
    return;
  }

  print('\n' + '─' * 80);
  print(dump.toAuditText());

  // Write JSON dump to file for inspection
  final jsonOutPath = 'test/audit/output/${dump.name.toLowerCase().replaceAll(' ', '_')}_dump.json';
  try {
    Directory('test/audit/output').createSync(recursive: true);
    File(jsonOutPath).writeAsStringSync(dump.toPrettyJson());
    print('[AUDIT] Dump written to $jsonOutPath');
  } catch (_) {
    // Non-fatal: output dir may not be writable in all environments
  }

  // Compare against ground truth (if available)
  if (groundTruthPath == null) {
    print('[AUDIT] No ground truth path provided — skipping comparison.');
    return;
  }

  final truth = UnitGroundTruth.loadFromFile(groundTruthPath);
  if (truth == null) {
    print('[AUDIT] ⚠ Ground truth file not found: $groundTruthPath');
    print('[AUDIT]   Dump exported above — fill in ground truth to enable comparison.');
    return;
  }

  final mismatches = comparator.compare(dump, truth);
  print('[AUDIT] Ground truth source: ${truth.source}');
  print('[AUDIT] Mismatches found: ${mismatches.length}');
  print('');
  print(comparator.renderTable(mismatches));
  print('');
  print(comparator.renderPatternSummary(mismatches));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Clean up stale appDataRoot between test runs
  setUp(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  tearDown(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  // ── Space Marines fixture (always available) ─────────────────────────────

  group('Audit: Imperium - Space Marines', () {
    late IndexBundle smIndex;

    setUpAll(() async {
      smIndex = await _buildIndex(
        gameSystemPath: 'test/Warhammer 40,000.gst',
        primaryCatalogPath: 'test/Imperium - Space Marines.cat',
        dependencyPaths: {
          'b00-cd86-4b4c-97ba': 'test/Imperium - Agents of the Imperium.cat',
          '7481-280e-b55e-7867': 'test/Library - Titans.cat',
          '1b6d-dc06-5db9-c7d1': 'test/Imperium - Imperial Knights - Library.cat',
          'ac3b-689c-4ad4-70cb': 'test/Library - Astartes Heresy Legends.cat',
        },
      );
      print('[AUDIT] Space Marines index built: '
          '${smIndex.units.length} units, '
          '${smIndex.weapons.length} weapons, '
          '${smIndex.rules.length} rules');
    });

    tearDownAll(() async {
      final dir = Directory('appDataRoot');
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('index health: non-empty, low duplicate count', () {
      expect(smIndex.units, isNotEmpty, reason: 'Index must contain units');
      expect(smIndex.weapons, isNotEmpty, reason: 'Index must contain weapons');
      expect(smIndex.duplicateDocIdCount, 0,
          reason: 'No duplicate docIds expected');
    });

    test('audit: Intercessor — basic infantry model benchmark', () {
      // NOTE: BattleScribe stores individual model entries (Intercessor,
      // Intercessor Sergeant), NOT squad-level entries. Wahapedia shows the
      // full squad datasheet. This structural difference is logged as a
      // unit-identity finding — not a data extraction bug.
      _runAudit(
        index: smIndex,
        unitName: 'Intercessor',
        groundTruthPath: 'test/audit/ground_truth/intercessor_squad.json',
      );
      // Test always passes — mismatches are logged, not asserted.
      // Once the dump is verified correct, add explicit pin assertions below.
    });

    test('keyword fragmentation regression: multi-word categories must not fragment into tokens', () {
      // Regression test for the E-class keyword fragmentation bug (now fixed).
      //
      // Previously, _collectCategoryKeywords called tokenize(category.name),
      // which split multi-word names into individual word fragments:
      //   e.g. "Adeptus Astartes" → ["adeptus", "astartes"] in keywordTokens
      //        "Hive Tyrant"      → ["hive", "tyrant"]
      //
      // Fix applied in index_service.dart _collectCategoryKeywords:
      //   Now calls normalize(name), preserving multi-word names as phrases.
      //
      // categoryTokens was always unaffected (used normalize() throughout).
      //
      // This test enforces the fix. A failure here means the fragmentation
      // bug has regressed in _collectCategoryKeywords.

      final fragmentedUnits = <String>[];
      final exampleFragments = <String, List<String>>{};

      for (final unit in smIndex.units) {
        // Find any categoryToken that is multi-word (space-separated)
        final multiWordCategories =
            unit.categoryTokens.where((t) => t.contains(' ')).toList();

        if (multiWordCategories.isEmpty) continue;

        // Check each multi-word category: its component words should NOT
        // appear as separate tokens in keywordTokens if they represent a
        // single concept (the fragmentation bug).
        for (final phrase in multiWordCategories) {
          final words = phrase.split(' ').where((w) => w.isNotEmpty).toList();
          final fragmentsPresent =
              words.where((w) => unit.keywordTokens.contains(w)).toList();

          if (fragmentsPresent.length == words.length) {
            // Phrase is fully fragmented: all words appear as individual tokens
            fragmentedUnits.add(unit.name);
            exampleFragments[unit.name] = words;
            break;
          }
        }
      }

      print('\n[KEYWORD FRAGMENTATION AUDIT]');
      print('Units with multi-word category names fragmented in keywordTokens:');
      print('  Count: ${fragmentedUnits.length}');
      for (final name in fragmentedUnits.take(10)) {
        final frags = exampleFragments[name]!;
        print('  "$name": phrase words ${frags.map((w) => '"$w"').join(', ')} appear as separate keywordTokens');
      }
      if (fragmentedUnits.length > 10) {
        print('  ... and ${fragmentedUnits.length - 10} more');
      }
      print('');
      print('[KEYWORD FRAGMENTATION] Regression check (bug is fixed — count should be 0).');
      print('[KEYWORD FRAGMENTATION] ${fragmentedUnits.length} units affected.');

      // Bug is fixed: enforce that no fragmentation occurs.
      expect(fragmentedUnits, isEmpty,
          reason: 'No multi-word category name should be fragmented '
              'into individual word tokens in keywordTokens. '
              '_collectCategoryKeywords in index_service.dart must use normalize(name).');
    });

    test('audit: sample bulk dump — first 5 units', () {
      // Useful for discovering what units are in the fixture and their data shape.
      final exporter = UnitDumpExporter();
      for (final unit in smIndex.units.take(5)) {
        final dump = exporter.exportByName(smIndex, unit.name);
        if (dump != null) {
          print(dump.toAuditText());
        }
      }
    });
  });

  // ── Tyranids fixture ──────────────────────────────────────────────────────
  //
  // Catalog:  test/Xenos - Tyranids.cat        (id: b984-7317-81cc-20f)
  // Deps:
  //   581a-46b9-5b86-44b7  Unaligned Forces.cat
  //   374d-45f0-5832-001e  Library - Tyranids.cat
  //
  // If the catalog files are absent the group is skipped cleanly.

  group('Audit: Xenos - Tyranids', () {
    const tyranidCatalogPath = 'test/Xenos - Tyranids.cat';
    const libTyranidPath = 'test/Library - Tyranids.cat';
    const unalignedPath = 'test/Unaligned Forces.cat';

    late IndexBundle tyranidIndex;
    bool _fixturePresent = false;

    setUpAll(() async {
      _fixturePresent = File(tyranidCatalogPath).existsSync() &&
          File(libTyranidPath).existsSync() &&
          File(unalignedPath).existsSync();

      if (!_fixturePresent) {
        print('\n[AUDIT] SKIPPED: Tyranid catalog fixture(s) not present.');
        print('[AUDIT]   Missing one or more of:');
        print('[AUDIT]     $tyranidCatalogPath');
        print('[AUDIT]     $libTyranidPath');
        print('[AUDIT]     $unalignedPath');
        print('[AUDIT]   Download from https://github.com/BSData/wh40k-10e');
        return;
      }

      tyranidIndex = await _buildIndex(
        gameSystemPath: 'test/Warhammer 40,000.gst',
        primaryCatalogPath: tyranidCatalogPath,
        dependencyPaths: {
          '581a-46b9-5b86-44b7': unalignedPath,
          '374d-45f0-5832-001e': libTyranidPath,
        },
      );
      print('[AUDIT] Tyranid index built: '
          '${tyranidIndex.units.length} units, '
          '${tyranidIndex.weapons.length} weapons, '
          '${tyranidIndex.rules.length} rules');
    });

    tearDownAll(() async {
      final dir = Directory('appDataRoot');
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('index health: non-empty, low duplicate count', () {
      if (!_fixturePresent) return; // skip
      expect(tyranidIndex.units, isNotEmpty,
          reason: 'Tyranid index must contain units');
      expect(tyranidIndex.weapons, isNotEmpty,
          reason: 'Tyranid index must contain weapons');
      expect(tyranidIndex.duplicateDocIdCount, 0,
          reason: 'No duplicate docIds expected');
    });

    test('audit: Hive Tyrant — monster/character benchmark', () {
      if (!_fixturePresent) return; // skip
      _runAudit(
        index: tyranidIndex,
        unitName: 'Hive Tyrant',
        groundTruthPath: 'test/audit/ground_truth/hive_tyrant.json',
      );
    });
  });
}

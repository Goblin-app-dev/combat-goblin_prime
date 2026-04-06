// ignore_for_file: avoid_print
/// Faction Sweep Validation Test
///
/// Sequential validation of all untested factions from the BSData wh40k-10e repo.
/// Already-tested factions excluded: Space Marines, Tyranids, Leagues of Votann,
/// Agents of the Imperium.
///
/// Run with:
///   flutter test test/faction_sweep_test.dart --concurrency=1 --timeout=300s
///
/// Each faction is validated through phases:
///   P1 — Acquire / dependency check / ingestion sanity
///   P2 — Representative unit inspection (char / infantry / multi-model / special)
///   P3 — V1 query validation (stat, rules, keyword, text search)
///   P4 — Structural difference detection

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Faction config
// ─────────────────────────────────────────────────────────────────────────────

class _FactionConfig {
  final String label;
  final String catPath;
  final String identityKeyword; // expected category/keyword token

  const _FactionConfig({
    required this.label,
    required this.catPath,
    required this.identityKeyword,
  });
}

// Global catalog-ID → file-path resolution map (all available catalog files).
const _depMap = <String, String>{
  // test/ root fixtures
  'e0af-67df-9d63-8fb7': 'test/Imperium - Space Marines.cat',
  'b00-cd86-4b4c-97ba': 'test/Imperium - Agents of the Imperium.cat',
  '7481-280e-b55e-7867': 'test/Library - Titans.cat',
  '1b6d-dc06-5db9-c7d1': 'test/Imperium - Imperial Knights - Library.cat',
  'ac3b-689c-4ad4-70cb': 'test/Library - Astartes Heresy Legends.cat',
  '581a-46b9-5b86-44b7': 'test/Unaligned Forces.cat',
  '374d-45f0-5832-001e': 'test/Library - Tyranids.cat',
  // downloaded
  'dfcf-1214-b57-2205': 'test/downloaded/Aeldari - Aeldari Library.cat',
  '5a44-f048-114b-e3ff':
      'test/downloaded/Imperium - Astra Militarum - Library.cat',
  '8106-aad2-918a-9ac': 'test/downloaded/Chaos - Chaos Knights Library.cat',
  'b45c-af22-788a-dfd6': 'test/downloaded/Chaos - Chaos Daemons Library.cat',
  'c8da-e875-58f7-f6d6': 'test/downloaded/Chaos - Chaos Space Marines.cat',
};

const _factions = <_FactionConfig>[
  // ── Aeldari ────────────────────────────────────────────────────────────────
  _FactionConfig(
    label: 'Aeldari - Craftworlds',
    catPath: 'test/downloaded/Aeldari - Craftworlds.cat',
    identityKeyword: 'aeldari',
  ),
  _FactionConfig(
    label: 'Aeldari - Drukhari',
    catPath: 'test/downloaded/Aeldari - Drukhari.cat',
    identityKeyword: 'drukhari',
  ),
  _FactionConfig(
    label: 'Aeldari - Ynnari',
    catPath: 'test/downloaded/Aeldari - Ynnari.cat',
    identityKeyword: 'ynnari',
  ),
  // ── Chaos ──────────────────────────────────────────────────────────────────
  _FactionConfig(
    label: 'Chaos - Chaos Daemons',
    catPath: 'test/downloaded/Chaos - Chaos Daemons.cat',
    identityKeyword: 'chaos daemons',
  ),
  _FactionConfig(
    label: 'Chaos - Chaos Knights',
    catPath: 'test/downloaded/Chaos - Chaos Knights.cat',
    identityKeyword: 'chaos knights',
  ),
  _FactionConfig(
    label: 'Chaos - Chaos Space Marines',
    catPath: 'test/downloaded/Chaos - Chaos Space Marines.cat',
    identityKeyword: 'heretic astartes',
  ),
  _FactionConfig(
    label: 'Chaos - Death Guard',
    catPath: 'test/downloaded/Chaos - Death Guard.cat',
    identityKeyword: 'death guard',
  ),
  _FactionConfig(
    label: 'Chaos - Emperors Children',
    catPath: "test/downloaded/Chaos - Emperor's Children.cat",
    identityKeyword: 'emperors children',
  ),
  _FactionConfig(
    label: 'Chaos - Thousand Sons',
    catPath: 'test/downloaded/Chaos - Thousand Sons.cat',
    identityKeyword: 'thousand sons',
  ),
  _FactionConfig(
    label: 'Chaos - World Eaters',
    catPath: 'test/downloaded/Chaos - World Eaters.cat',
    identityKeyword: 'world eaters',
  ),
  // ── Genestealer Cults ──────────────────────────────────────────────────────
  _FactionConfig(
    label: 'Genestealer Cults',
    catPath: 'test/downloaded/Genestealer Cults.cat',
    identityKeyword: 'genestealer cults',
  ),
  // ── Imperium ───────────────────────────────────────────────────────────────
  _FactionConfig(
    label: 'Imperium - Adepta Sororitas',
    catPath: 'test/downloaded/Imperium - Adepta Sororitas.cat',
    identityKeyword: 'adepta sororitas',
  ),
  _FactionConfig(
    label: 'Imperium - Adeptus Custodes',
    catPath: 'test/downloaded/Imperium - Adeptus Custodes.cat',
    identityKeyword: 'adeptus custodes',
  ),
  _FactionConfig(
    label: 'Imperium - Adeptus Mechanicus',
    catPath: 'test/downloaded/Imperium - Adeptus Mechanicus.cat',
    identityKeyword: 'adeptus mechanicus',
  ),
  _FactionConfig(
    label: 'Imperium - Astra Militarum',
    catPath: 'test/downloaded/Imperium - Astra Militarum.cat',
    identityKeyword: 'astra militarum',
  ),
  _FactionConfig(
    label: 'Imperium - Black Templars',
    catPath: 'test/downloaded/Imperium - Black Templars.cat',
    identityKeyword: 'black templars',
  ),
  _FactionConfig(
    label: 'Imperium - Blood Angels',
    catPath: 'test/downloaded/Imperium - Blood Angels.cat',
    identityKeyword: 'blood angels',
  ),
  _FactionConfig(
    label: 'Imperium - Dark Angels',
    catPath: 'test/downloaded/Imperium - Dark Angels.cat',
    identityKeyword: 'dark angels',
  ),
  _FactionConfig(
    label: 'Imperium - Deathwatch',
    catPath: 'test/downloaded/Imperium - Deathwatch.cat',
    identityKeyword: 'deathwatch',
  ),
  _FactionConfig(
    label: 'Imperium - Grey Knights',
    catPath: 'test/downloaded/Imperium - Grey Knights.cat',
    identityKeyword: 'grey knights',
  ),
  _FactionConfig(
    label: 'Imperium - Imperial Fists',
    catPath: 'test/downloaded/Imperium - Imperial Fists.cat',
    identityKeyword: 'imperial fists',
  ),
  _FactionConfig(
    label: 'Imperium - Iron Hands',
    catPath: 'test/downloaded/Imperium - Iron Hands.cat',
    identityKeyword: 'iron hands',
  ),
  _FactionConfig(
    label: 'Imperium - Raven Guard',
    catPath: 'test/downloaded/Imperium - Raven Guard.cat',
    identityKeyword: 'raven guard',
  ),
  _FactionConfig(
    label: 'Imperium - Salamanders',
    catPath: 'test/downloaded/Imperium - Salamanders.cat',
    identityKeyword: 'salamanders',
  ),
  _FactionConfig(
    label: 'Imperium - Space Wolves',
    catPath: 'test/downloaded/Imperium - Space Wolves.cat',
    identityKeyword: 'space wolves',
  ),
  _FactionConfig(
    label: 'Imperium - Ultramarines',
    catPath: 'test/downloaded/Imperium - Ultramarines.cat',
    identityKeyword: 'ultramarines',
  ),
  _FactionConfig(
    label: 'Imperium - White Scars',
    catPath: 'test/downloaded/Imperium - White Scars.cat',
    identityKeyword: 'white scars',
  ),
  // ── Xenos ─────────────────────────────────────────────────────────────────
  _FactionConfig(
    label: 'Necrons',
    catPath: 'test/downloaded/Necrons.cat',
    identityKeyword: 'necrons',
  ),
  _FactionConfig(
    label: 'Orks',
    catPath: 'test/downloaded/Orks.cat',
    identityKeyword: 'orks',
  ),
  _FactionConfig(
    label: "T'au Empire",
    catPath: "test/downloaded/T'au Empire.cat",
    identityKeyword: 'tau empire',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String? _stat(UnitDoc u, String name) {
  final n = name.toLowerCase();
  for (final c in u.characteristics) {
    if (c.name.toLowerCase() == n) return c.valueText;
  }
  return null;
}

List<RuleDoc> _rulesFor(IndexBundle idx, UnitDoc u) {
  final byId = {for (final r in idx.rules) r.docId: r};
  return u.ruleDocRefs.map((ref) => byId[ref]).whereType<RuleDoc>().toList();
}

UnitDoc? _pickByCategory(IndexBundle idx, String categoryToken) {
  final tok = categoryToken.toLowerCase();
  for (final u in idx.units) {
    if (u.categoryTokens.contains(tok) || u.keywordTokens.contains(tok)) {
      return u;
    }
  }
  return null;
}

/// Inspect a unit and return a multi-line summary string.
String _inspectUnit(IndexBundle idx, UnitDoc u) {
  final sb = StringBuffer();
  sb.writeln('    Unit: ${u.name}  [${u.docId}]');
  // Stats
  final statNames = ['M', 'T', 'SV', 'W', 'LD', 'OC'];
  final stats = statNames
      .map((s) => '$s=${_stat(u, s) ?? "-"}')
      .join('  ');
  sb.writeln('      stats: $stats');
  // Weapons
  sb.writeln('      weapons: ${u.weaponDocRefs.length} refs');
  // Rules
  final rules = _rulesFor(idx, u);
  sb.writeln('      rules: ${rules.map((r) => r.name).join(", ")}');
  // Categories / keywords
  sb.writeln('      categories: ${u.categoryTokens.take(6).join(", ")}');
  sb.writeln('      keywords: ${u.keywordTokens.take(6).join(", ")}');
  return sb.toString().trimRight();
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  const testSource = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  late List<int> _gstBytes;

  // Accumulate findings across all factions.
  final _sweepLog = <String>[];
  void emit(String line) {
    _sweepLog.add(line);
    print(line);
  }

  setUpAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) await dir.delete(recursive: true);
    _gstBytes = await File('test/Warhammer 40,000.gst').readAsBytes();
  });

  tearDownAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) await dir.delete(recursive: true);
    print('');
    print('══════════════════════════════════════════════════════════════');
    print('  FACTION SWEEP — complete');
    print('══════════════════════════════════════════════════════════════');
  });

  // ── Per-faction tests ─────────────────────────────────────────────────────

  for (final config in _factions) {
    test(
      'Faction: ${config.label}',
      () async {
        emit('');
        emit('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        emit('FACTION: ${config.label}');
        emit('  primary: ${config.catPath}');

        // ── P1 — Acquire ────────────────────────────────────────────────────
        emit('  [P1] Acquire');
        final catBytes = await File(config.catPath).readAsBytes();

        IndexBundle idx;
        try {
          final raw = await AcquireService().buildBundle(
            gameSystemBytes: _gstBytes,
            gameSystemExternalFileName: 'Warhammer 40,000.gst',
            primaryCatalogBytes: catBytes,
            primaryCatalogExternalFileName: config.catPath.split('/').last,
            requestDependencyBytes: (id) async {
              final path = _depMap[id];
              if (path == null) return null;
              return File(path).readAsBytes();
            },
            source: testSource,
          );

          emit('  [P1] deps loaded: ${raw.dependencyCatalogMetadatas.length}');
          for (final m in raw.dependencyCatalogMetadatas) {
            emit('    dep: ${m.externalFileName}');
          }

          // ── P2 — Pipeline ────────────────────────────────────────────────
          emit('  [P2] Pipeline M2→M9');
          idx = IndexService().buildIndex(
            await BindService().bindBundle(
              linkedBundle: await LinkService().linkBundle(
                wrappedBundle: await WrapService().wrapBundle(
                  parsedBundle:
                      await ParseService().parseBundle(rawBundle: raw),
                ),
              ),
            ),
          );
        } catch (e) {
          emit('  [P1/P2] INGESTION FAILED: $e');
          emit('  Classification: Pipeline bug or missing dependency');
          fail('${config.label}: ingestion failed — $e');
        }

        // ── Index sizes ──────────────────────────────────────────────────────
        emit('  [P2] index: ${idx.units.length} units, '
            '${idx.weapons.length} weapons, ${idx.rules.length} rules');
        emit('  [P2] diags: ${idx.diagnostics.length} total '
            '(unknownProfileType=${idx.unknownProfileTypeCount}, '
            'linkTargetMissing=${idx.linkTargetMissingCount}, '
            'duplicateDocId=${idx.duplicateDocIdCount})');

        expect(idx.units, isNotEmpty,
            reason: '${config.label}: unit index must be non-empty');
        expect(idx.weapons, isNotEmpty,
            reason: '${config.label}: weapon index must be non-empty');

        // ── P3 — Representative unit inspection ──────────────────────────────
        emit('  [P3] Representative units');

        // Character
        final charUnit = _pickByCategory(idx, 'character');
        if (charUnit != null) {
          emit('  char:');
          emit(_inspectUnit(idx, charUnit));
        } else {
          emit('  char: none found with "character" category token');
        }

        // Infantry
        final infUnit = _pickByCategory(idx, 'infantry');
        if (infUnit != null) {
          emit('  infantry:');
          emit(_inspectUnit(idx, infUnit));
        } else {
          emit('  infantry: none found with "infantry" category token');
        }

        // Multi-weapon (pick unit with most weapon refs)
        final multiUnit = idx.units.isEmpty
            ? null
            : idx.units.reduce((a, b) =>
                a.weaponDocRefs.length >= b.weaponDocRefs.length ? a : b);
        if (multiUnit != null && multiUnit.weaponDocRefs.length >= 2) {
          emit('  multi-weapon:');
          emit(_inspectUnit(idx, multiUnit));
        } else {
          emit('  multi-weapon: no unit with 2+ weapon refs found');
        }

        // "Special" — pick highest rule count
        final specialUnit = idx.units.isEmpty
            ? null
            : idx.units.reduce((a, b) =>
                a.ruleDocRefs.length >= b.ruleDocRefs.length ? a : b);
        if (specialUnit != null &&
            specialUnit != charUnit &&
            specialUnit != multiUnit) {
          emit('  special (most rules):');
          emit(_inspectUnit(idx, specialUnit));
        }

        // ── Stat completeness spot-check ──────────────────────────────────
        int unitsWithT = 0;
        int unitsWithM = 0;
        int unitsWithW = 0;
        for (final u in idx.units) {
          if (_stat(u, 'T') != null) unitsWithT++;
          if (_stat(u, 'M') != null) unitsWithM++;
          if (_stat(u, 'W') != null) unitsWithW++;
        }
        emit('  [P3] stat coverage out of ${idx.units.length} units: '
            'T=$unitsWithT  M=$unitsWithM  W=$unitsWithW');

        // ── P3 — Rule resolution spot-check ───────────────────────────────
        int unitsWithRules = 0;
        for (final u in idx.units) {
          if (_rulesFor(idx, u).isNotEmpty) unitsWithRules++;
        }
        emit('  [P3] units with ≥1 resolved rule: $unitsWithRules '
            '/ ${idx.units.length}');

        // ── Dangling weapon refs ───────────────────────────────────────────
        int danglingWeaponRefs = 0;
        for (final u in idx.units) {
          for (final wRef in u.weaponDocRefs) {
            if (idx.weaponByDocId(wRef) == null) danglingWeaponRefs++;
          }
        }
        if (danglingWeaponRefs > 0) {
          emit('  [P3] WARNING: $danglingWeaponRefs dangling weapon refs');
        }

        // ── Duplicate docIds ──────────────────────────────────────────────
        if (idx.duplicateDocIdCount > 0) {
          emit('  [P3] WARNING: ${idx.duplicateDocIdCount} duplicate docIds');
        }

        // ── P4 — V1 queries ──────────────────────────────────────────────────
        emit('  [P4] V1 queries');
        final svc = StructuredSearchService();

        // Stat lookup: Toughness of char unit (or first unit)
        final statTarget = charUnit ?? idx.units.first;
        final toughness = _stat(statTarget, 'T');
        emit('  stat(T of "${statTarget.name}"): ${toughness ?? "(not found)"}');

        // Movement of infantry (or first unit)
        final moveTarget = infUnit ?? idx.units.first;
        final movement = _stat(moveTarget, 'M');
        emit('  stat(M of "${moveTarget.name}"): ${movement ?? "(not found)"}');

        // Rule listing: rules of char unit
        if (charUnit != null) {
          final charRules = _rulesFor(idx, charUnit);
          emit('  rules("${charUnit.name}"): ${charRules.isEmpty ? "(none)" : charRules.map((r) => r.name).join(", ")}');
        }

        // Keyword search: identity keyword
        final kwNorm = config.identityKeyword.toLowerCase();
        final kwResult = svc.search(
          idx,
          SearchRequest(
            keywords: {kwNorm},
            docTypes: const {SearchDocType.unit},
            limit: 100,
          ),
        );
        emit('  keyword("$kwNorm"): ${kwResult.hits.length} hits');
        if (kwResult.hits.isEmpty) {
          emit('  WARNING: identity keyword returned 0 hits — '
              'may indicate category naming variation');
        }

        // Text search: first word of faction identity keyword
        final firstWord = kwNorm.split(' ').first;
        final textResult = svc.search(
          idx,
          SearchRequest(
            text: firstWord,
            docTypes: const {SearchDocType.unit},
            limit: 10,
          ),
        );
        emit('  text("$firstWord"): ${textResult.hits.length} hits'
            '${textResult.hits.isNotEmpty ? " — top: ${textResult.hits.first.displayName}" : ""}');

        // ── P4 — Leakage check ─────────────────────────────────────────────
        // Detect units with "tyranids" or "space marines" (should only appear
        // if those catalogs are direct deps).
        final tyranidUnits = idx.units
            .where((u) =>
                u.categoryTokens.contains('tyranids') ||
                u.keywordTokens.contains('tyranids'))
            .length;
        final smUnits = idx.units
            .where((u) =>
                u.categoryTokens.contains('adeptus astartes') ||
                u.keywordTokens.contains('adeptus astartes'))
            .length;

        // Leakage is only unexpected if those factions aren't declared deps.
        final catName = config.catPath.split('/').last;
        final isSmSupplement = catName.contains('Black Templars') ||
            catName.contains('Blood Angels') ||
            catName.contains('Dark Angels') ||
            catName.contains('Deathwatch') ||
            catName.contains('Imperial Fists') ||
            catName.contains('Iron Hands') ||
            catName.contains('Raven Guard') ||
            catName.contains('Salamanders') ||
            catName.contains('Space Wolves') ||
            catName.contains('Ultramarines') ||
            catName.contains('White Scars');
        if (tyranidUnits > 0) {
          emit('  LEAKAGE CHECK: $tyranidUnits units with "tyranids" token — '
              'investigate if unexpected');
        }
        if (smUnits > 0 && !isSmSupplement) {
          emit('  LEAKAGE CHECK: $smUnits units with "adeptus astartes" token '
              '— investigate if unexpected');
        }

        // ── P5 — Structural notes ─────────────────────────────────────────────
        emit('  [P5] Structural notes');

        // Unknown profile types
        if (idx.unknownProfileTypeCount > 0) {
          final unknownDiags = idx.diagnostics
              .where((d) =>
                  d.code == IndexDiagnosticCode.unknownProfileType)
              .take(5)
              .map((d) => d.message)
              .toList();
          emit('  unknownProfileType diags (first 5): $unknownDiags');
          emit('  Classification: BSData structural variation — '
              'new profile type names may need policy update');
        }

        // Units with multiple characteristics sets (check for multi-profile)
        final multiProfileUnits = idx.units
            .where((u) => u.characteristics.length > 10)
            .length;
        if (multiProfileUnits > 0) {
          emit('  units with >10 characteristics: $multiProfileUnits '
              '(possible multi-profile units)');
        }

        // Keyword-less units
        final noKeywordUnits =
            idx.units.where((u) => u.keywordTokens.isEmpty).length;
        if (noKeywordUnits > 0) {
          emit('  units with 0 keyword tokens: $noKeywordUnits');
        }

        // Category-less units
        final noCategoryUnits =
            idx.units.where((u) => u.categoryTokens.isEmpty).length;
        if (noCategoryUnits > 0) {
          emit('  units with 0 category tokens: $noCategoryUnits');
        }

        emit('  STATUS: PASS (ingestion OK, non-empty index)');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }

  // ── Summary test ──────────────────────────────────────────────────────────
  test('sweep summary', () {
    emit('');
    emit('══════════════════════════════════════════════════════════════');
    emit('FACTION SWEEP SUMMARY');
    emit('  Total factions tested: ${_factions.length}');
    emit('  Excluded (already tested): Space Marines, Tyranids, '
        'Leagues of Votann, Imperial Agents');
    emit('══════════════════════════════════════════════════════════════');
  });
}

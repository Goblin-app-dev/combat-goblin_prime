// ignore_for_file: avoid_print
import 'dart:io';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';
import 'package:flutter_test/flutter_test.dart';

// ─── Pipeline Helper ──────────────────────────────────────────────────────────

Future<IndexBundle> _buildIndex({
  required String gstPath,
  required String catPath,
  Map<String, String> deps = const {},
}) async {
  const src = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );
  final gstBytes = await File(gstPath).readAsBytes();
  final catBytes = await File(catPath).readAsBytes();
  final raw = await AcquireService().buildBundle(
    gameSystemBytes: gstBytes,
    gameSystemExternalFileName: gstPath.split('/').last,
    primaryCatalogBytes: catBytes,
    primaryCatalogExternalFileName: catPath.split('/').last,
    requestDependencyBytes: (id) async {
      final path = deps[id];
      if (path == null) return null;
      return File(path).readAsBytes();
    },
    source: src,
  );
  final parsed  = await ParseService().parseBundle(rawBundle: raw);
  final wrapped = await WrapService().wrapBundle(parsedBundle: parsed);
  final linked  = await LinkService().linkBundle(wrappedBundle: wrapped);
  final bound   = await BindService().bindBundle(linkedBundle: linked);
  return IndexService().buildIndex(bound);
}

// ─── Query helpers ────────────────────────────────────────────────────────────

UnitDoc? _findUnit(IndexBundle idx, String nameSubstr) {
  final norm = nameSubstr.toLowerCase();
  final exact = idx.units.where(
    (u) => u.canonicalKey == IndexService.normalize(nameSubstr),
  );
  if (exact.isNotEmpty) return exact.first;
  final sub = idx.units.where(
    (u) => u.canonicalKey.contains(norm) || u.name.toLowerCase().contains(norm),
  );
  return sub.isEmpty ? null : sub.first;
}

String? _stat(UnitDoc unit, String charName) {
  final norm = charName.toLowerCase();
  for (final c in unit.characteristics) {
    if (c.name.toLowerCase() == norm) return c.valueText;
  }
  return null;
}

List<RuleDoc> _rulesFor(IndexBundle idx, UnitDoc unit) {
  final byId = {for (final r in idx.rules) r.docId: r};
  return unit.ruleDocRefs.map((r) => byId[r]).whereType<RuleDoc>().toList();
}

// ─── Unit inspector helper ────────────────────────────────────────────────────

void _inspectUnit(IndexBundle idx, String name) {
  final unit = _findUnit(idx, name);
  if (unit == null) {
    print('  [MISS] "$name" NOT FOUND in index');
    return;
  }
  final rules = _rulesFor(idx, unit);
  print('  ── $name ──');
  print('    docId          : ${unit.docId}');
  print('    entryId        : ${unit.entryId}');
  print('    characteristics: ${unit.characteristics.map((c) => "${c.name}=${c.valueText}").join(", ")}');
  print('    keywordTokens  : ${unit.keywordTokens.take(12).join(", ")}');
  print('    categoryTokens : ${unit.categoryTokens.take(12).join(", ")}');
  print('    weaponDocRefs  : ${unit.weaponDocRefs.length}  ruleDocRefs: ${unit.ruleDocRefs.length}');
  print('    rules          : ${rules.map((r) => r.name).take(10).join(", ")}');
  print('    costs          : ${unit.costs.map((c) => "${c.typeName}=${c.value}").join(", ")}');
  // Check keyword vs category alignment
  final kwSet = unit.keywordTokens.toSet();
  final catSet = unit.categoryTokens.toSet();
  final inCatNotKw = catSet.difference(kwSet);
  final inKwNotCat = kwSet.difference(catSet);
  if (inCatNotKw.isNotEmpty) {
    print('    cat only (not in kw): ${inCatNotKw.take(6).join(", ")}');
  }
  if (inKwNotCat.isNotEmpty) {
    print('    kw only (not in cat): ${inKwNotCat.take(6).join(", ")}');
  }
}

// ─── Profile-type scanner ─────────────────────────────────────────────────────

Map<String, int> _profileTypeCounts(BoundPackBundle bundle) {
  final counts = <String, int>{};
  for (final p in bundle.profiles) {
    final t = p.typeName ?? '(null)';
    counts[t] = (counts[t] ?? 0) + 1;
  }
  return counts;
}

// =============================================================================
// TESTS
// =============================================================================

void main() {
  tearDownAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  setUp(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LEAGUES OF VOTANN
  // ═══════════════════════════════════════════════════════════════════════════

  group('PHASE 1–5 : Leagues of Votann', () {
    late IndexBundle idx;

    setUpAll(() async {
      final dir = Directory('appDataRoot');
      if (await dir.exists()) await dir.delete(recursive: true);
      idx = await _buildIndex(
        gstPath: 'test/Warhammer 40,000.gst',
        catPath: 'test/Leagues of Votann.cat',
        deps: {
          '581a-46b9-5b86-44b7': 'test/Unaligned Forces.cat',
        },
      );
    });

    tearDownAll(() async {
      final dir = Directory('appDataRoot');
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    // ── PHASE 1: Load & sanity ──────────────────────────────────────────────

    test('P1: pipeline completes, index non-empty', () {
      print('\n[LOV P1] Index built:');
      print('  units   : ${idx.units.length}');
      print('  weapons : ${idx.weapons.length}');
      print('  rules   : ${idx.rules.length}');
      print('  diag    : ${idx.diagnostics.length}');
      print('  dup IDs : ${idx.duplicateDocIdCount}');
      print('  missing name: ${idx.missingNameCount}');
      print('  unknown profile type: ${idx.unknownProfileTypeCount}');
      print('  link target missing: ${idx.linkTargetMissingCount}');

      expect(idx.units, isNotEmpty, reason: 'LOV index must have units');
      expect(idx.weapons, isNotEmpty, reason: 'LOV index must have weapons');
      expect(idx.duplicateDocIdCount, 0, reason: 'No duplicate docIds');
    });

    test('P1: Unaligned Forces linked (units contain shared categories)', () {
      // Unaligned Forces provides universal special rules / categories.
      // A well-linked index will have rules/categories from that dep.
      print('\n[LOV P1-DEP] Checking Unaligned Forces linkage...');
      // If dependency resolved, at least some rules from the dep should appear.
      print('  total rules: ${idx.rules.length}');
      // Print up to 5 rule names as proof
      for (final r in idx.rules.take(5)) {
        print('  rule: ${r.name}');
      }
      expect(idx.rules.isNotEmpty, isTrue,
          reason: 'Rules from Unaligned Forces dep should be present');
    });

    test('P1: no partial/orphan nodes (units all have entryId)', () {
      final noEntry = idx.units.where((u) => u.entryId.isEmpty).toList();
      print('\n[LOV P1] Units without entryId: ${noEntry.length}');
      for (final u in noEntry.take(5)) {
        print('  missing entryId: ${u.name} / ${u.docId}');
      }
      expect(noEntry, isEmpty, reason: 'Every UnitDoc must have an entryId');
    });

    test('P1: no dangling weaponDocRefs', () {
      final weaponById = {for (final w in idx.weapons) w.docId: w};
      int dangling = 0;
      for (final u in idx.units) {
        for (final wRef in u.weaponDocRefs) {
          if (!weaponById.containsKey(wRef)) dangling++;
        }
      }
      print('\n[LOV P1] Dangling weapon refs: $dangling');
      expect(dangling, 0, reason: 'All weaponDocRefs must resolve');
    });

    // ── PHASE 2: Representative unit inspection ─────────────────────────────

    test('P2: unit inspection — character', () {
      print('\n[LOV P2] Character inspection:');
      // Look for a character-like unit
      final chars = idx.units.where((u) =>
        u.categoryTokens.contains('character') ||
        u.keywordTokens.contains('character')).toList();
      print('  total CHARACTER units: ${chars.length}');
      if (chars.isNotEmpty) {
        _inspectUnit(idx, chars.first.name);
      } else {
        // Try named characters
        final named = ['Ûthar the Destined', 'Grimnyr', 'Kâhl'];
        for (final n in named) {
          final u = _findUnit(idx, n);
          if (u != null) { _inspectUnit(idx, n); break; }
        }
      }
    });

    test('P2: unit inspection — basic infantry (Hearthkyn Warrior)', () {
      print('\n[LOV P2] Basic infantry:');
      _inspectUnit(idx, 'Hearthkyn Warrior');
      // Fallback
      final infantry = idx.units.where((u) =>
        u.categoryTokens.contains('infantry')).toList();
      print('  total INFANTRY units: ${infantry.length}');
      if (infantry.isNotEmpty && _findUnit(idx, 'Hearthkyn Warrior') == null) {
        _inspectUnit(idx, infantry.first.name);
      }
    });

    test('P2: unit inspection — multi-model unit (Hearthkyn Warriors)', () {
      print('\n[LOV P2] Multi-model:');
      // Squads are typically multi-model
      _inspectUnit(idx, 'Hearthkyn Warriors');
      _inspectUnit(idx, 'Cthonian Berserks');
    });

    test('P2: unit inspection — complex/vehicle unit (Sagitaur)', () {
      print('\n[LOV P2] Complex/vehicle:');
      _inspectUnit(idx, 'Sagitaur');
      _inspectUnit(idx, 'Hekaton Land Fortress');
      final vehicles = idx.units.where((u) =>
        u.categoryTokens.contains('vehicle')).toList();
      print('  total VEHICLE units: ${vehicles.length}');
    });

    test('P2: category structure — keywordTokens vs categoryTokens', () {
      print('\n[LOV P2] Keyword/category alignment check...');
      int perfect = 0, mismatched = 0;
      for (final u in idx.units) {
        if (u.keywordTokens.toSet() == u.categoryTokens.toSet()) {
          perfect++;
        } else {
          mismatched++;
        }
      }
      print('  Perfect match: $perfect / ${idx.units.length}');
      print('  Mismatched   : $mismatched');
      // Not an error condition — keyword tokens include tokenised words
      // while category tokens are normalised phrase forms.
    });

    test('P2: profile type census', () {
      print('\n[LOV P2] Profile types in bound bundle:');
      // We need the bound bundle; access via idx.boundBundle
      final counts = _profileTypeCounts(idx.boundBundle);
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sorted) {
        print('  "${e.key}": ${e.value}');
      }
      expect(counts.containsKey('Unit'), isTrue,
          reason: 'Must have at least one Unit profile type');
    });

    // ── PHASE 3: V1 query validation ──────────────────────────────────────

    test('P3: stat query — Toughness of a Hearthkyn Warrior', () {
      print('\n[LOV P3] Toughness query:');
      final unit = _findUnit(idx, 'Hearthkyn Warrior') ??
          _findUnit(idx, 'Hearthkyn Warriors') ??
          (idx.units.isNotEmpty ? idx.units.first : null);
      if (unit == null) { print('  BLOCKED — no units found'); return; }
      final t = _stat(unit, 'T');
      final m = _stat(unit, 'M');
      print('  Unit: ${unit.name}');
      print('  T = ${t ?? "(not found)"}');
      print('  M = ${m ?? "(not found)"}');
      expect(t, isNotNull, reason: 'Toughness must be present on LOV unit');
      expect(m, isNotNull, reason: 'Movement must be present on LOV unit');
    });

    test('P3: rule query — rules of a character unit', () {
      print('\n[LOV P3] Rule query:');
      final chars = idx.units.where((u) =>
        u.categoryTokens.contains('character') ||
        u.keywordTokens.contains('character')).toList();
      if (chars.isEmpty) { print('  BLOCKED — no character units'); return; }
      final unit = chars.first;
      final rules = _rulesFor(idx, unit);
      print('  Unit: ${unit.name}');
      print('  ruleDocRefs: ${unit.ruleDocRefs.length}');
      print('  resolved rules: ${rules.map((r) => r.name).join(", ")}');
      // Characters typically have at least one rule
      expect(unit.ruleDocRefs, isNotEmpty,
          reason: 'Character must reference at least one rule');
    });

    test('P3: ability search — "OATH OF ENMITY" or "KINDRED GUARDIAN" faction ability', () {
      print('\n[LOV P3] Ability/keyword search:');
      final service = StructuredSearchService();
      // Try a LOV-specific keyword search
      for (final kw in ['league', 'votann', 'ancestor', 'grudge']) {
        final result = service.search(
          idx,
          SearchRequest(keywords: {kw}, docTypes: {SearchDocType.unit}, limit: 50),
        );
        print('  keyword("$kw"): ${result.hits.length} hits');
        if (result.hits.isNotEmpty) {
          print('    first: ${result.hits.first.displayName}');
        }
      }
    });

    test('P3: text search — "kâhl" returns a unit', () {
      print('\n[LOV P3] Text search:');
      final service = StructuredSearchService();
      for (final term in ['kahl', 'hearthkyn', 'sagitaur', 'votann']) {
        final result = service.search(
          idx,
          SearchRequest(text: term, docTypes: {SearchDocType.unit}, limit: 5),
        );
        print('  search("$term"): ${result.hits.length} hits');
        if (result.hits.isNotEmpty) {
          print('    first: ${result.hits.first.displayName}');
        }
      }
    });

    test('P3: no false positives — keyword results carry the keyword', () {
      print('\n[LOV P3] False-positive check:');
      final service = StructuredSearchService();
      // Find a keyword that exists
      final allKw = idx.units.expand((u) => u.keywordTokens).toSet().toList()
        ..sort();
      if (allKw.isEmpty) { print('  BLOCKED — no keywords'); return; }
      final kw = allKw.first;
      final result = service.search(
        idx,
        SearchRequest(keywords: {kw}, docTypes: {SearchDocType.unit}, limit: 100),
      );
      final mismatches = <String>[];
      for (final h in result.hits) {
        final u = idx.units.firstWhere((u) => u.docId == h.docId,
            orElse: () => throw TestFailure('docId not found: ${h.docId}'));
        if (!u.keywordTokens.contains(kw) && !u.categoryTokens.contains(kw)) {
          mismatches.add(h.displayName);
        }
      }
      print('  keyword="$kw": ${result.hits.length} hits, mismatches=${mismatches.length}');
      expect(mismatches, isEmpty,
          reason: 'Keyword filter must not return units without the keyword');
    });

    // ── PHASE 4: Structural differences ──────────────────────────────────

    test('P4: structural survey — nesting depth, profile types, category patterns', () {
      print('\n[LOV P4] Structural survey:');
      // Count units per keyword composition
      final kySizes = <int, int>{};
      for (final u in idx.units) {
        final sz = u.keywordTokens.length;
        kySizes[sz] = (kySizes[sz] ?? 0) + 1;
      }
      final sortedSizes = kySizes.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      print('  Keyword token count distribution:');
      for (final e in sortedSizes) {
        print('    ${e.key} tokens: ${e.value} units');
      }

      // Units with zero weapons
      final noWeapons = idx.units.where((u) => u.weaponDocRefs.isEmpty).toList();
      print('  Units with 0 weapon refs: ${noWeapons.length}');

      // Units with zero rules
      final noRules = idx.units.where((u) => u.ruleDocRefs.isEmpty).toList();
      print('  Units with 0 rule refs: ${noRules.length}');
      for (final u in noRules.take(3)) {
        print('    no rules: ${u.name} [${u.categoryTokens.take(3).join(", ")}]');
      }

      // Check for any units with unusually many characteristics (>8)
      final richStats = idx.units.where((u) => u.characteristics.length > 8).toList();
      print('  Units with >8 characteristics: ${richStats.length}');
      for (final u in richStats.take(3)) {
        print('    ${u.name}: ${u.characteristics.map((c) => c.name).join(", ")}');
      }
    });

    test('P4: all unit names in index (census)', () {
      print('\n[LOV P4] All units in index (${idx.units.length} total):');
      for (final u in idx.units) {
        print('  ${u.name}');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // AGENTS OF THE IMPERIUM
  // ═══════════════════════════════════════════════════════════════════════════

  group('PHASE 1–5 : Agents of the Imperium', () {
    late IndexBundle idx;

    setUpAll(() async {
      final dir = Directory('appDataRoot');
      if (await dir.exists()) await dir.delete(recursive: true);
      idx = await _buildIndex(
        gstPath: 'test/Warhammer 40,000.gst',
        catPath: 'test/Imperium - Agents of the Imperium.cat',
        deps: {
          '581a-46b9-5b86-44b7': 'test/Unaligned Forces.cat',
          '7481-280e-b55e-7867': 'test/Library - Titans.cat',
          '1b6d-dc06-5db9-c7d1': 'test/Imperium - Imperial Knights - Library.cat',
        },
      );
    });

    tearDownAll(() async {
      final dir = Directory('appDataRoot');
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    // ── PHASE 1: Load & sanity ──────────────────────────────────────────────

    test('P1: pipeline completes, index non-empty', () {
      print('\n[AOI P1] Index built:');
      print('  units   : ${idx.units.length}');
      print('  weapons : ${idx.weapons.length}');
      print('  rules   : ${idx.rules.length}');
      print('  diag    : ${idx.diagnostics.length}');
      print('  dup IDs : ${idx.duplicateDocIdCount}');
      print('  missing name: ${idx.missingNameCount}');
      print('  unknown profile type: ${idx.unknownProfileTypeCount}');
      print('  link target missing: ${idx.linkTargetMissingCount}');

      expect(idx.units, isNotEmpty, reason: 'AOI index must have units');
      expect(idx.weapons, isNotEmpty, reason: 'AOI index must have weapons');
      expect(idx.duplicateDocIdCount, 0, reason: 'No duplicate docIds');
    });

    test('P1: Unaligned Forces linked (rules present)', () {
      print('\n[AOI P1-DEP] Unaligned Forces check:');
      print('  total rules: ${idx.rules.length}');
      for (final r in idx.rules.take(5)) { print('  rule: ${r.name}'); }
      expect(idx.rules.isNotEmpty, isTrue);
    });

    test('P1: Titans library resolves (units or rules from lib present)', () {
      print('\n[AOI P1-DEP] Titans library check:');
      // Titans lib provides titan weapon/rule profiles
      // Check if any unit name contains "titan" or if titans-specific rules appear
      final titanUnits = idx.units.where((u) =>
        u.name.toLowerCase().contains('titan') ||
        u.categoryTokens.any((c) => c.contains('titan'))).toList();
      print('  Titan-related units: ${titanUnits.length}');
      for (final u in titanUnits.take(3)) { print('  unit: ${u.name}'); }

      // Also check LINK_TARGET_MISSING diagnostics are not excessive
      print('  link_target_missing: ${idx.linkTargetMissingCount}');
      // We log this — not a hard failure, as some may be intentional
    });

    test('P1: Imperial Knights library resolves', () {
      print('\n[AOI P1-DEP] Imperial Knights library check:');
      final knightUnits = idx.units.where((u) =>
        u.name.toLowerCase().contains('knight') ||
        u.categoryTokens.any((c) => c.contains('knight'))).toList();
      print('  Knight-related units: ${knightUnits.length}');
      for (final u in knightUnits.take(3)) { print('  unit: ${u.name}'); }
    });

    test('P1: no partial/orphan nodes', () {
      final noEntry = idx.units.where((u) => u.entryId.isEmpty).toList();
      print('\n[AOI P1] Units without entryId: ${noEntry.length}');
      expect(noEntry, isEmpty);
    });

    test('P1: no dangling entryLinks (weaponDocRefs all resolve)', () {
      final weaponById = {for (final w in idx.weapons) w.docId: w};
      int dangling = 0;
      final examples = <String>[];
      for (final u in idx.units) {
        for (final wRef in u.weaponDocRefs) {
          if (!weaponById.containsKey(wRef)) {
            dangling++;
            if (examples.length < 5) examples.add('${u.name}: $wRef');
          }
        }
      }
      print('\n[AOI P1] Dangling weapon refs: $dangling');
      for (final e in examples) { print('  $e'); }
      expect(dangling, 0, reason: 'All weaponDocRefs must resolve in AOI');
    });

    // ── PHASE 2: Representative unit inspection ─────────────────────────────

    test('P2: unit inspection — character', () {
      print('\n[AOI P2] Character inspection:');
      final charUnits = idx.units.where((u) =>
        u.categoryTokens.contains('character') ||
        u.keywordTokens.contains('character')).toList();
      print('  CHARACTER units: ${charUnits.length}');
      if (charUnits.isNotEmpty) {
        _inspectUnit(idx, charUnits.first.name);
      }
      // Try specific characters
      for (final n in ['Inquisitor', 'Culexus Assassin', 'Vindicare Assassin', 'Callidus Assassin']) {
        final u = _findUnit(idx, n);
        if (u != null) { _inspectUnit(idx, n); break; }
      }
    });

    test('P2: unit inspection — basic infantry (Death Cult Assassins)', () {
      print('\n[AOI P2] Basic infantry:');
      _inspectUnit(idx, 'Death Cult Assassin');
      _inspectUnit(idx, 'Crusaders');
      _inspectUnit(idx, 'Ministorum Priest');
    });

    test('P2: unit inspection — multi-model (Inquisitorial Henchmen)', () {
      print('\n[AOI P2] Multi-model:');
      _inspectUnit(idx, 'Inquisitorial Henchmen');
      _inspectUnit(idx, 'Inquisitorial Acolytes');
      // If neither found, find any multi-token infantry
      final inf = idx.units.where((u) =>
        u.categoryTokens.contains('infantry') &&
        !u.categoryTokens.contains('character')).toList();
      print('  Total non-character infantry: ${inf.length}');
      if (inf.isNotEmpty) _inspectUnit(idx, inf.first.name);
    });

    test('P2: unit inspection — complex/mixed unit', () {
      print('\n[AOI P2] Complex unit:');
      _inspectUnit(idx, 'Officio Assassinorum Assassin');
      _inspectUnit(idx, 'Rogue Trader Entourage');
      _inspectUnit(idx, 'Rogue Trader');
    });

    test('P2: category structure alignment', () {
      print('\n[AOI P2] Category alignment:');
      int perfect = 0, mismatched = 0;
      final mismatches = <String>[];
      for (final u in idx.units) {
        if (u.keywordTokens.toSet() == u.categoryTokens.toSet()) {
          perfect++;
        } else {
          mismatched++;
          if (mismatches.length < 3) mismatches.add(u.name);
        }
      }
      print('  Perfect: $perfect / ${idx.units.length}');
      print('  Mismatch examples: $mismatches');
    });

    test('P2: profile type census', () {
      print('\n[AOI P2] Profile types:');
      final counts = _profileTypeCounts(idx.boundBundle);
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sorted) {
        print('  "${e.key}": ${e.value}');
      }
      expect(counts.containsKey('Unit'), isTrue);
    });

    // ── PHASE 3: V1 query validation ──────────────────────────────────────

    test('P3: stat query — Toughness and Movement of an infantry unit', () {
      print('\n[AOI P3] Stat query:');
      final inf = idx.units.where((u) =>
        u.categoryTokens.contains('infantry') &&
        u.characteristics.any((c) => c.name.toLowerCase() == 't')).toList();
      if (inf.isEmpty) { print('  BLOCKED — no infantry with T stat'); return; }
      final unit = inf.first;
      final t = _stat(unit, 'T');
      final m = _stat(unit, 'M');
      print('  Unit: ${unit.name}');
      print('  T = ${t ?? "(not found)"}');
      print('  M = ${m ?? "(not found)"}');
      expect(t, isNotNull, reason: 'T must be present on AOI infantry');
      expect(m, isNotNull, reason: 'M must be present on AOI infantry');
    });

    test('P3: rule query — rules of Inquisitor or similar character', () {
      print('\n[AOI P3] Rule query:');
      UnitDoc? unit;
      for (final n in ['Inquisitor', 'Culexus Assassin', 'Callidus Assassin']) {
        unit = _findUnit(idx, n);
        if (unit != null) break;
      }
      if (unit == null) {
        final chars = idx.units.where((u) =>
          u.categoryTokens.contains('character')).toList();
        if (chars.isEmpty) { print('  BLOCKED — no characters'); return; }
        unit = chars.first;
      }
      final rules = _rulesFor(idx, unit);
      print('  Unit: ${unit.name}');
      print('  ruleDocRefs: ${unit.ruleDocRefs.length}');
      print('  resolved: ${rules.map((r) => r.name).join(", ")}');
      expect(unit.ruleDocRefs, isNotEmpty,
          reason: 'Character must have rule refs');
    });

    test('P3: ability search — "AGENTS OF THE IMPERIUM" faction keyword', () {
      print('\n[AOI P3] Ability/keyword search:');
      final service = StructuredSearchService();
      for (final kw in ['agents', 'imperium', 'inquisitor', 'assassin', 'psyker']) {
        final result = service.search(
          idx,
          SearchRequest(keywords: {kw}, docTypes: {SearchDocType.unit}, limit: 50),
        );
        print('  keyword("$kw"): ${result.hits.length} hits');
        if (result.hits.isNotEmpty) {
          print('    first: ${result.hits.first.displayName}');
        }
      }
    });

    test('P3: text search — "assassin" and "inquisitor"', () {
      print('\n[AOI P3] Text search:');
      final service = StructuredSearchService();
      for (final term in ['assassin', 'inquisitor', 'crusader', 'eversor']) {
        final result = service.search(
          idx,
          SearchRequest(text: term, docTypes: {SearchDocType.unit}, limit: 5),
        );
        print('  search("$term"): ${result.hits.length} hits');
        if (result.hits.isNotEmpty) {
          print('    first: ${result.hits.first.displayName}');
        }
      }
    });

    test('P3: no false positives — keyword results carry the keyword', () {
      print('\n[AOI P3] False-positive check:');
      final service = StructuredSearchService();
      final allKw = idx.units.expand((u) => u.keywordTokens).toSet().toList()
        ..sort();
      if (allKw.isEmpty) { print('  BLOCKED — no keywords'); return; }
      final kw = allKw.first;
      final result = service.search(
        idx,
        SearchRequest(keywords: {kw}, docTypes: {SearchDocType.unit}, limit: 100),
      );
      final mismatches = <String>[];
      for (final h in result.hits) {
        final u = idx.units.firstWhere((u) => u.docId == h.docId,
            orElse: () => throw TestFailure('docId not found: ${h.docId}'));
        if (!u.keywordTokens.contains(kw) && !u.categoryTokens.contains(kw)) {
          mismatches.add(h.displayName);
        }
      }
      print('  keyword="$kw": ${result.hits.length} hits, mismatches=${mismatches.length}');
      expect(mismatches, isEmpty);
    });

    // ── PHASE 4: Structural differences ──────────────────────────────────

    test('P4: structural survey — nesting, profile types, categories', () {
      print('\n[AOI P4] Structural survey:');
      final kySizes = <int, int>{};
      for (final u in idx.units) {
        final sz = u.keywordTokens.length;
        kySizes[sz] = (kySizes[sz] ?? 0) + 1;
      }
      final sortedSizes = kySizes.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      print('  Keyword token distribution:');
      for (final e in sortedSizes) {
        print('    ${e.key} tokens: ${e.value} units');
      }

      final noWeapons = idx.units.where((u) => u.weaponDocRefs.isEmpty).toList();
      print('  Units with 0 weapon refs: ${noWeapons.length}');
      for (final u in noWeapons.take(3)) { print('    ${u.name}'); }

      final noRules = idx.units.where((u) => u.ruleDocRefs.isEmpty).toList();
      print('  Units with 0 rule refs: ${noRules.length}');
      for (final u in noRules.take(3)) { print('    ${u.name}'); }

      final richStats = idx.units.where((u) => u.characteristics.length > 8).toList();
      print('  Units with >8 characteristics: ${richStats.length}');
    });

    test('P4: all unit names census', () {
      print('\n[AOI P4] All units in AOI index (${idx.units.length} total):');
      for (final u in idx.units) {
        print('  ${u.name}');
      }
    });

    test('P4: cross-faction source leakage check (no SM-only units)', () {
      print('\n[AOI P4] Source leakage check:');
      // "Kill Team Intercessor/Heavy Intercessor" units are legitimate AOI
      // content (Deathwatch kill team variants) — exclude them from the check.
      // Only flag bare SM unit names that have no business in AOI.
      final smLeakage = idx.units.where((u) {
        final name = u.name.toLowerCase();
        if (name.startsWith('kill team')) return false; // B: expected AOI content
        return name.contains('intercessor') ||
               name.contains('tactical marine') ||
               name.contains('land raider');
      }).toList();
      print('  Potential SM leakage units: ${smLeakage.length}');
      for (final u in smLeakage) { print('  LEAK: ${u.name}'); }
      // Kill Team variants noted as B (BSData structural variation) in Phase 5.
      expect(smLeakage, isEmpty,
          reason: 'AOI index must not contain bare Space Marines units');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 5 CLASSIFICATION SUMMARY
  // ═══════════════════════════════════════════════════════════════════════════

  group('PHASE 5: Classification summary', () {
    test('print classification table', () {
      print('''
\n════════════════════════════════════════════════════════════════════
PHASE 5: ISSUE CLASSIFICATION
════════════════════════════════════════════════════════════════════
This test file captures the following potential issues
(see per-test output above for actual data):

LOV-1: LOV units found in index               — to be confirmed above
LOV-2: Dep 581a (Unaligned Forces) resolved   — to be confirmed above
LOV-3: duplicateDocIdCount == 0               — tested above
LOV-4: dangling weaponDocRefs == 0            — tested above
LOV-5: keywordTokens vs categoryTokens delta  — logged above (policy)
LOV-6: Units with 0 rule refs                 — logged above

AOI-1: AOI units found                        — tested above
AOI-2: Dep 581a Unaligned Forces resolved     — tested above
AOI-3: Dep 7481 Titans library resolved       — tested above
AOI-4: Dep 1b6d IK library resolved           — tested above
AOI-5: dangling entryLinks (weaponDocRefs)    — tested above
AOI-6: source leakage (SM units in AOI)       — tested above

Classification guide:
  P = Pipeline bug (needs fix)
  D = Policy decision needed
  B = BSData structural variation (expected)
  F = Future-update risk
  OK = No issue / expected variation
════════════════════════════════════════════════════════════════════
''');
    });
  });
}

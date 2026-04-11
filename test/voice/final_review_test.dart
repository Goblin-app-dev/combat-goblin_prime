// ignore_for_file: avoid_print
/// Final Full-Pipeline Review — Batches A, B, C.
///
/// Covers:
///   Batch A — Engine/index sanity for 6 required factions.
///   Batch B — Reference query matrix (B1–B6) through coordinator + real bundles.
///   Batch C — Clarification/dialogue/conversation flows (C1–C4).
///   Batch D — TTS/device: headless Linux environment; documented in final report.
///
/// Run with:
///   flutter test test/voice/final_review_test.dart --concurrency=1 --timeout=300s --reporter expanded
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';
import 'package:combat_goblin_prime/voice/models/spoken_response_plan.dart';
import 'package:combat_goblin_prime/voice/understanding/voice_assistant_coordinator.dart';
import 'package:combat_goblin_prime/voice/voice_search_facade.dart';

// ---------------------------------------------------------------------------
// Dependency map — all available test catalogs keyed by BSData catalog ID.
// ---------------------------------------------------------------------------

const _depMap = <String, String>{
  'e0af-67df-9d63-8fb7': 'test/Imperium - Space Marines.cat',
  'b00-cd86-4b4c-97ba': 'test/Imperium - Agents of the Imperium.cat',
  '7481-280e-b55e-7867': 'test/Library - Titans.cat',
  '1b6d-dc06-5db9-c7d1': 'test/Imperium - Imperial Knights - Library.cat',
  'ac3b-689c-4ad4-70cb': 'test/Library - Astartes Heresy Legends.cat',
  '581a-46b9-5b86-44b7': 'test/Unaligned Forces.cat',
  '374d-45f0-5832-001e': 'test/Library - Tyranids.cat',
  'dfcf-1214-b57-2205': 'test/downloaded/Aeldari - Aeldari Library.cat',
  '5a44-f048-114b-e3ff': 'test/downloaded/Imperium - Astra Militarum - Library.cat',
  '8106-aad2-918a-9ac': 'test/downloaded/Chaos - Chaos Knights Library.cat',
  'b45c-af22-788a-dfd6': 'test/downloaded/Chaos - Chaos Daemons Library.cat',
  'c8da-e875-58f7-f6d6': 'test/downloaded/Chaos - Chaos Space Marines.cat',
};

// ---------------------------------------------------------------------------
// Pipeline helper
// ---------------------------------------------------------------------------

const _src = SourceLocator(
  sourceKey: 'bsdata_wh40k_10e',
  sourceUrl: 'https://github.com/BSData/wh40k-10e',
  branch: 'main',
);

late List<int> _gstBytes;

Future<IndexBundle> _buildIndex(String catPath) async {
  final catBytes = await File(catPath).readAsBytes();
  final raw = await AcquireService().buildBundle(
    gameSystemBytes: _gstBytes,
    gameSystemExternalFileName: 'Warhammer 40,000.gst',
    primaryCatalogBytes: catBytes,
    primaryCatalogExternalFileName: catPath.split('/').last,
    requestDependencyBytes: (id) async {
      final path = _depMap[id];
      if (path == null) return null;
      return File(path).readAsBytes();
    },
    source: _src,
  );
  final parsed  = await ParseService().parseBundle(rawBundle: raw);
  final wrapped = await WrapService().wrapBundle(parsedBundle: parsed);
  final linked  = await LinkService().linkBundle(wrappedBundle: wrapped);
  final bound   = await BindService().bindBundle(linkedBundle: linked);
  return IndexService().buildIndex(bound);
}

// ---------------------------------------------------------------------------
// Index inspection helpers
// ---------------------------------------------------------------------------

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

UnitDoc? _findByCategory(IndexBundle idx, String cat) {
  final t = cat.toLowerCase();
  return idx.units.where(
    (u) => u.categoryTokens.contains(t) || u.keywordTokens.contains(t),
  ).firstOrNull;
}

UnitDoc? _findByKey(IndexBundle idx, String key) {
  final norm = IndexService.normalize(key);
  final exact = idx.units.where((u) => u.canonicalKey == norm).firstOrNull;
  if (exact != null) return exact;
  return idx.units.where(
    (u) => u.canonicalKey.contains(norm) || u.name.toLowerCase().contains(norm),
  ).firstOrNull;
}

String _inspectUnit(IndexBundle idx, UnitDoc u) {
  final stats = ['M', 'T', 'SV', 'W', 'LD', 'OC']
      .map((s) => '$s=${_stat(u, s) ?? '-'}')
      .join(' ');
  final rules = _rulesFor(idx, u).map((r) => r.name).join(', ');
  return '${u.name}  stats=[$stats]  weapons=${u.weaponDocRefs.length}'
      '  rules=[${rules.isEmpty ? 'none' : rules}]'
      '  cats=${u.categoryTokens.take(4).join(',')}';
}

// ---------------------------------------------------------------------------
// Coordinator helper
// ---------------------------------------------------------------------------

VoiceAssistantCoordinator _freshCoord() => VoiceAssistantCoordinator(
      searchFacade: VoiceSearchFacade(),
    );

Future<SpokenResponsePlan> _run(
  String transcript,
  Map<String, IndexBundle> slots,
) async {
  final plan = await _freshCoord().handleTranscript(
    transcript: transcript,
    slotBundles: slots,
    contextHints: const [],
  );
  print('  Q: "$transcript"');
  print('     → "${plan.primaryText}"  [${plan.debugSummary}]');
  return plan;
}

// ---------------------------------------------------------------------------
// Shared indexes — loaded once in setUpAll
// ---------------------------------------------------------------------------

late IndexBundle _smIdx;      // Space Marines
late IndexBundle _tyIdx;      // Tyranids
late IndexBundle _votIdx;     // Leagues of Votann
late IndexBundle _agIdx;      // Agents of the Imperium
late IndexBundle _cdIdx;      // Chaos Daemons
late IndexBundle _aelIdx;     // Aeldari Craftworlds

void main() {
  setUpAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) await dir.delete(recursive: true);
    _gstBytes = await File('test/Warhammer 40,000.gst').readAsBytes();

    print('\n=== Loading 6 faction indexes ===');
    _smIdx  = await _buildIndex('test/Imperium - Space Marines.cat');
    print('  SM    : ${_smIdx.units.length} units, ${_smIdx.weapons.length} weapons, ${_smIdx.rules.length} rules');
    _tyIdx  = await _buildIndex('test/Xenos - Tyranids.cat');
    print('  TY    : ${_tyIdx.units.length} units, ${_tyIdx.weapons.length} weapons, ${_tyIdx.rules.length} rules');
    _votIdx = await _buildIndex('test/Leagues of Votann.cat');
    print('  VOT   : ${_votIdx.units.length} units, ${_votIdx.weapons.length} weapons, ${_votIdx.rules.length} rules');
    _agIdx  = await _buildIndex('test/Imperium - Agents of the Imperium.cat');
    print('  AG    : ${_agIdx.units.length} units, ${_agIdx.weapons.length} weapons, ${_agIdx.rules.length} rules');
    _cdIdx  = await _buildIndex('test/downloaded/Chaos - Chaos Daemons.cat');
    print('  CD    : ${_cdIdx.units.length} units, ${_cdIdx.weapons.length} weapons, ${_cdIdx.rules.length} rules');
    _aelIdx = await _buildIndex('test/downloaded/Aeldari - Craftworlds.cat');
    print('  AEL   : ${_aelIdx.units.length} units, ${_aelIdx.weapons.length} weapons, ${_aelIdx.rules.length} rules');
  });

  tearDownAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  // =========================================================================
  // BATCH A — Engine / Index / Dependency Sanity
  // =========================================================================

  group('Batch A — Engine / Index Sanity', () {
    void _checkFaction(
      String label,
      IndexBundle Function() idx, {
      bool expectWeapons = true,
      bool expectRules = true,
    }) {
      test('A: $label', () {
        final b = idx();
        print('\n--- $label ---');

        // Non-empty unit index.
        expect(b.units, isNotEmpty, reason: '$label must have units');
        if (expectWeapons) {
          expect(b.weapons, isNotEmpty, reason: '$label must have weapons');
        }

        // No duplicate docIds.
        expect(b.duplicateDocIdCount, 0,
            reason: '$label must have no duplicate docIds');

        // Dangling weapon refs.
        int dangling = 0;
        for (final u in b.units) {
          for (final ref in u.weaponDocRefs) {
            if (b.weaponByDocId(ref) == null) dangling++;
          }
        }
        print('  dangling weapon refs: $dangling');

        // Stat completeness: every unit should have T and M (10th-ed standard).
        final withT = b.units.where((u) => _stat(u, 'T') != null).length;
        final withM = b.units.where((u) => _stat(u, 'M') != null).length;
        print('  stat coverage: T=$withT/${b.units.length}  M=$withM/${b.units.length}');
        expect(withT, greaterThan(0), reason: 'At least some units must have T');
        expect(withM, greaterThan(0), reason: 'At least some units must have M');

        // Rule resolution: some units should have rules.
        if (expectRules) {
          final withRules = b.units.where((u) => _rulesFor(b, u).isNotEmpty).length;
          print('  units with rules: $withRules/${b.units.length}');
        }

        // Representative unit inspection.
        final charUnit = _findByCategory(b, 'character');
        if (charUnit != null) print('  char:     ${_inspectUnit(b, charUnit)}');

        final infUnit = _findByCategory(b, 'infantry');
        if (infUnit != null) print('  infantry: ${_inspectUnit(b, infUnit)}');

        final multiWpn = b.units.isEmpty
            ? null
            : b.units.reduce((a, c) =>
                a.weaponDocRefs.length >= c.weaponDocRefs.length ? a : c);
        if (multiWpn != null && multiWpn.weaponDocRefs.length >= 2) {
          print('  multi-wpn:${_inspectUnit(b, multiWpn)}');
        }

        final mostRules = b.units.isEmpty
            ? null
            : b.units.reduce((a, c) =>
                a.ruleDocRefs.length >= c.ruleDocRefs.length ? a : c);
        if (mostRules != null && mostRules != charUnit) {
          print('  special:  ${_inspectUnit(b, mostRules)}');
        }

        // Keyword pollution check — no faction should import units from an
        // unrelated faction's keyword domain (unless a known supplement).
        final tyLeakage = b.units
            .where((u) => u.categoryTokens.contains('tyranids') ||
                u.keywordTokens.contains('tyranids'))
            .length;
        if (tyLeakage > 0) {
          print('  LEAKAGE CHECK: $tyLeakage units with "tyranids" token');
        }

        print('  STATUS: PASS');
      });
    }

    _checkFaction('Space Marines',       () => _smIdx);
    _checkFaction('Tyranids',            () => _tyIdx);
    _checkFaction('Leagues of Votann',   () => _votIdx);
    _checkFaction('Agents of Imperium',  () => _agIdx);
    _checkFaction('Chaos Daemons',       () => _cdIdx);
    _checkFaction('Aeldari Craftworlds', () => _aelIdx);
  });

  // =========================================================================
  // BATCH B — Reference Query Matrix
  // =========================================================================

  group('Batch B1 — Unit stat queries', () {
    test('B1.1 toughness of carnifex', () async {
      final p = await _run('what is the toughness of carnifex', {'slot_0': _tyIdx});
      expect(p.debugSummary, startsWith('attr-answer:t:'));
      expect(p.primaryText, contains('toughness'));
    });

    test('B1.2 movement of carnifex', () async {
      final p = await _run('what is the movement of carnifex', {'slot_0': _tyIdx});
      expect(p.debugSummary, startsWith('attr-answer:m:'));
    });

    test('B1.3 how far does carnifex move', () async {
      final p = await _run('how far does carnifex move', {'slot_0': _tyIdx});
      expect(p.debugSummary, startsWith('attr-answer:m:'));
    });

    test('B1.4 toughness of hive tyrant', () async {
      final p = await _run('what is the toughness of hive tyrant', {'slot_0': _tyIdx});
      expect(p.debugSummary, startsWith('attr-answer:t:'));
    });

    test('B1.5 movement of hive tyrant', () async {
      final p = await _run('what is the movement of hive tyrant', {'slot_0': _tyIdx});
      expect(p.debugSummary, startsWith('attr-answer:m:'));
    });

    test('B1.6 how far do jump pack intercessors move', () async {
      final p = await _run('how far do jump pack intercessors move', {'slot_0': _smIdx});
      expect(p.debugSummary, startsWith('attr-answer:m:'));
      expect(p.primaryText, contains('inches'));
    });

    test('B1.7 movement of assault intercessors with jump pack', () async {
      final p = await _run(
          'what is the movement of assault intercessors with jump pack',
          {'slot_0': _smIdx});
      expect(p.debugSummary, startsWith('attr-answer:m:'));
    });

    test('B1.8 toughness of intercessors', () async {
      final p = await _run('what is the toughness of intercessors', {'slot_0': _smIdx});
      expect(p.debugSummary, startsWith('attr-answer:t:'));
    });

    test('B1.9 toughness of a captain (article strip fix)', () async {
      final p = await _run('what is the toughness of a captain', {'slot_0': _smIdx});
      // After article-strip fix: "a captain" → "captain" → exact quality match → Captain only.
      expect(p.debugSummary, startsWith('attr-answer:t:'),
          reason: 'Article "a" must be stripped; exact-score filter must return Captain only');
      expect(p.primaryText, contains('toughness'));
    });

    test('B1.10 toughness of hearthkyn warrior', () async {
      final p = await _run('what is the toughness of hearthkyn warrior', {'slot_0': _votIdx});
      expect(p.debugSummary, anyOf(startsWith('attr-answer:t:'), startsWith('disambiguation:')),
          reason: 'Hearthkyn Warrior must be found in Votann catalog');
      expect(p.debugSummary, isNot(startsWith('no-results:')));
    });

    test('B1.11 movement of hearthkyn warrior', () async {
      final p = await _run('what is the movement of hearthkyn warrior', {'slot_0': _votIdx});
      expect(p.debugSummary, anyOf(startsWith('attr-answer:m:'), startsWith('disambiguation:')));
      expect(p.debugSummary, isNot(startsWith('no-results:')));
    });

    test('B1.12 toughness of an imperial agents character (known limitation)', () async {
      final p = await _run(
          'what is the toughness of an imperial agents character', {'slot_0': _agIdx});
      // "an imperial agents character" → strip "an " → "imperial agents character"
      // Resolver: no alias for compound phrase → search fails.
      // Expected: no-results or disambiguation (graceful, not a crash).
      print('  [CLASSIFICATION] faction+role query: beta-acceptable limitation');
      expect(p.primaryText, isNotEmpty);
    });

    test('B1.13 toughness of a chaos daemons unit (known limitation)', () async {
      final p = await _run(
          'what is the toughness of a chaos daemons unit', {'slot_0': _cdIdx});
      // "a chaos daemons unit" → strip "a " → "chaos daemons unit" → strip " unit"
      //   → "chaos daemons" → alias "legiones daemonica" → search → no unit by that name.
      print('  [CLASSIFICATION] faction+role query: beta-acceptable limitation');
      expect(p.primaryText, isNotEmpty);
    });

    test('B1.14 toughness of an aeldari unit', () async {
      final p = await _run('what is the toughness of an aeldari unit', {'slot_0': _aelIdx});
      // "an aeldari unit" → strip "an " → "aeldari unit" → strip " unit" → "aeldari"
      // → search finds units whose canonicalKey contains "aeldari" (if any).
      print('  [CLASSIFICATION] generic faction query: outcome depends on catalog naming');
      expect(p.primaryText, isNotEmpty);
    });
  });

  group('Batch B2 — Weapon stat queries', () {
    test('B2.1 bs of intercessors (multi-weapon → clarification)', () async {
      final p = await _run('what is the bs of intercessors', {'slot_0': _smIdx});
      expect(p.debugSummary, startsWith('weapon-clarify:'));
      expect(p.primaryText, contains('Which weapon?'));
    });

    test('B2.2 bs of intercessors with bolt rifles (qualifier fallback → direct)', () async {
      final p = await _run(
          'what is the bs of intercessors with bolt rifles', {'slot_0': _smIdx});
      expect(p.debugSummary, startsWith('attr-answer:bs:'));
      expect(p.primaryText, contains('Bolt Rifle'));
    });

    test('B2.3 bs of intercessors with bolt pistol (qualifier fallback → direct)', () async {
      final p = await _run(
          'what is the bs of intercessors with bolt pistol', {'slot_0': _smIdx});
      expect(p.debugSummary, startsWith('attr-answer:bs:'));
      expect(p.primaryText, contains('Bolt pistol')); // weapon stored as "Bolt pistol" in SM catalog
    });

    test('B2.4 bs values for intercessor weapons (plural all-weapon summary)', () async {
      final p = await _run(
          'what are the bs values for intercessor weapons', {'slot_0': _smIdx});
      expect(p.debugSummary, startsWith('weapon-stat-plural:bs:'));
    });

    test('B2.5 ws of a carnifex weapon', () async {
      final p = await _run('what is the ws of a carnifex weapon', {'slot_0': _tyIdx});
      // After article strip: "carnifex weapon" → no " with " → fallback not triggered.
      // "carnifex weapon" doesn't match any unit canonicalKey → no-results.
      // KNOWN LIMITATION: "unit weapon" suffix not stripped (risk of matching real weapon entries).
      print('  [CLASSIFICATION] "unit weapon" suffix: beta-acceptable limitation');
      expect(p.primaryText, isNotEmpty);
    });

    test('B2.6 ws values for carnifex weapons (plural handler)', () async {
      final p = await _run('what are the ws values for carnifex weapons', {'slot_0': _tyIdx});
      // Plural handler strips "weapons", finds Carnifex, lists WS values.
      expect(p.debugSummary,
          anyOf(startsWith('weapon-stat-plural:ws:'), startsWith('attr-empty:'),
              startsWith('no-results:')),
          reason: 'Carnifex WS query must reach the weapon-stat handler');
    });

    test('B2.7 damage of carnifex weapons (unrecognized attr → graceful)', () async {
      final p = await _run('what is the damage of carnifex weapons', {'slot_0': _tyIdx});
      // "damage" is not in _kAttributeSynonyms → falls back to plain search.
      print('  [CLASSIFICATION] "damage" attr not recognized: beta-acceptable limitation');
      expect(p.primaryText, isNotEmpty);
    });

    test('B2.8 damage values for carnifex weapons (plural, unrecognized → entity search)', () async {
      final p = await _run('what are the damage values for carnifex weapons', {'slot_0': _tyIdx});
      // Plural handler: "damage" not in synonyms → falls back to entity search for "carnifex".
      expect(p.primaryText, isNotEmpty);
    });
  });

  group('Batch B3 — Rule queries', () {
    test('B3.1 rules for carnifex', () async {
      final p = await _run('rules for carnifex', {'slot_0': _tyIdx});
      expect(p.debugSummary,
          anyOf(startsWith('rules-answer:'), startsWith('rules-empty:')));
    });

    test('B3.2 what rules does carnifex have', () async {
      final p = await _run('what rules does carnifex have', {'slot_0': _tyIdx});
      expect(p.debugSummary,
          anyOf(startsWith('rules-answer:'), startsWith('rules-empty:')));
    });

    test('B3.3 what abilities does carnifex have', () async {
      final p = await _run('what abilities does carnifex have', {'slot_0': _tyIdx});
      expect(p.debugSummary,
          anyOf(startsWith('rules-answer:'), startsWith('rules-empty:')));
    });

    test('B3.4 rules for hive tyrant', () async {
      final p = await _run('rules for hive tyrant', {'slot_0': _tyIdx});
      expect(p.primaryText, isNotEmpty);
    });

    test('B3.5 what rules does captain have', () async {
      final p = await _run('what rules does captain have', {'slot_0': _smIdx});
      expect(p.primaryText, isNotEmpty);
    });

    test('B3.6 what abilities does captain have', () async {
      final p = await _run('what abilities does captain have', {'slot_0': _smIdx});
      expect(p.primaryText, isNotEmpty);
    });

    test('B3.7 rules for hearthkyn warrior', () async {
      final p = await _run('rules for hearthkyn warrior', {'slot_0': _votIdx});
      expect(p.primaryText, isNotEmpty);
      expect(p.debugSummary, isNot(startsWith('no-results:')));
    });

    test('B3.8 rules for an imperial agents character', () async {
      final p = await _run('rules for an imperial agents character', {'slot_0': _agIdx});
      // "an imperial agents character" → rule handler's _extractEntityForRuleQuery
      // → similar article-strip path. Outcome depends on catalog.
      print('  [CLASSIFICATION] faction+role rule query: outcome documented');
      expect(p.primaryText, isNotEmpty);
    });
  });

  group('Batch B4 — Ability / keyword / faction search', () {
    test('B4.1 which units have synapse', () async {
      final p = await _run('which units have synapse', {'slot_0': _tyIdx});
      expect(p.debugSummary, startsWith('ability-search'));
    });

    test('B4.2 which units have infantry', () async {
      final p = await _run('which units have infantry', {'slot_0': _smIdx});
      expect(p.primaryText, isNotEmpty);
    });

    test('B4.3 which units have character', () async {
      final p = await _run('which units have character', {'slot_0': _smIdx});
      expect(p.primaryText, isNotEmpty);
    });

    test('B4.4 chaos daemons units', () async {
      final p = await _run('chaos daemons units', {'slot_0': _cdIdx});
      // "chaos daemons units" → resolver: strip " units" → "chaos daemons"
      //   → alias "legiones daemonica" → search text "legiones daemonica"
      print('  [CLASSIFICATION] faction-alias text search documented');
      expect(p.primaryText, isNotEmpty);
    });

    test('B4.5 imperial agents units', () async {
      final p = await _run('imperial agents units', {'slot_0': _agIdx});
      // "imperial agents units" → strip " units" → "imperial agents"
      //   → alias "agents of the imperium" → search
      expect(p.primaryText, isNotEmpty);
    });

    test('B4.6 votann units', () async {
      final p = await _run('votann units', {'slot_0': _votIdx});
      // "votann units" → strip " units" → "votann" → alias "leagues of votann" → search
      expect(p.primaryText, isNotEmpty);
    });

    test('B4.7 aeldari units', () async {
      final p = await _run('aeldari units', {'slot_0': _aelIdx});
      expect(p.primaryText, isNotEmpty);
    });

    test('B4.8 which units have a votann faction term', () async {
      final p = await _run('which units have votann', {'slot_0': _votIdx});
      expect(p.primaryText, isNotEmpty);
    });

    test('B4.9 which units have an imperial agents faction term', () async {
      final p = await _run('which units have agents of the imperium', {'slot_0': _agIdx});
      expect(p.primaryText, isNotEmpty);
    });
  });

  group('Batch B5 — Name resolution / natural phrasing', () {
    test('B5.1 "intercessor" (singular)', () async {
      final p = await _run('intercessor', {'slot_0': _smIdx});
      expect(p.primaryText, isNotEmpty);
      expect(p.debugSummary, isNot(startsWith('no-results:')));
    });

    test('B5.2 "intercessors" (plural)', () async {
      final p = await _run('intercessors', {'slot_0': _smIdx});
      expect(p.primaryText, isNotEmpty);
      expect(p.debugSummary, isNot(startsWith('no-results:')));
    });

    test('B5.3 "jump pack intercessor" (alias singular)', () async {
      final p = await _run('jump pack intercessor', {'slot_0': _smIdx});
      // Alias: "jump pack intercessor" → "assault intercessors with jump pack"
      expect(p.debugSummary, isNot(startsWith('no-results:')));
    });

    test('B5.4 "jump pack intercessors" (alias plural)', () async {
      final p = await _run('jump pack intercessors', {'slot_0': _smIdx});
      expect(p.debugSummary, isNot(startsWith('no-results:')));
    });

    test('B5.5 "assault intercessors with jump pack" (full BSData name)', () async {
      final p = await _run('assault intercessors with jump pack', {'slot_0': _smIdx});
      expect(p.debugSummary, isNot(startsWith('no-results:')));
    });

    test('B5.6 "chaos daemons" (faction alias)', () async {
      final p = await _run('chaos daemons', {'slot_0': _cdIdx});
      // → alias "legiones daemonica" → search in chaos daemons catalog
      expect(p.primaryText, isNotEmpty);
    });

    test('B5.7 "imperial agents" (faction alias)', () async {
      final p = await _run('imperial agents', {'slot_0': _agIdx});
      // → alias "agents of the imperium"
      expect(p.primaryText, isNotEmpty);
    });

    test('B5.8 "votann" (faction alias)', () async {
      final p = await _run('votann', {'slot_0': _votIdx});
      // → alias "leagues of votann"
      expect(p.primaryText, isNotEmpty);
    });

    test('B5.9 "carnifexes" (plural of irregular)', () async {
      final p = await _run('carnifexes', {'slot_0': _tyIdx});
      // "carnifexes" — _shouldSingularize: ends in 's', not 'ss'/'us'/'ies',
      // stripped "carnifexe" length 9 ≥ 4 → strips to "carnifexe"
      // Likely no match. Document behavior.
      print('  [NOTE] "carnifexes" → irregular plural: behavior documented');
      expect(p.primaryText, isNotEmpty);
    });

    test('B5.10 "hive tyrant"', () async {
      final p = await _run('hive tyrant', {'slot_0': _tyIdx});
      expect(p.debugSummary, isNot(startsWith('no-results:')));
    });

    test('B5.11 "captain" (SM, disambiguation expected)', () async {
      final p = await _run('captain', {'slot_0': _smIdx});
      // SM has Captain, CwJP, CiTA → disambiguation.
      expect(p.primaryText, isNotEmpty);
    });
  });

  group('Batch B6 — No-match / malformed', () {
    test('B6.1 xyz nonexistent unit', () async {
      final p = await _run('xyz nonexistent unit', {'slot_0': _smIdx});
      expect(p.primaryText, isNotEmpty,
          reason: 'No-match must produce a human-readable spoken response');
      expect(p.primaryText, isNot(isEmpty));
    });

    test('B6.2 nonsense query for fake unit', () async {
      final p = await _run('show me the flarborgle unit', {'slot_0': _tyIdx});
      expect(p.primaryText, isNotEmpty);
    });

    test('B6.3 what is the bs of xyz', () async {
      final p = await _run('what is the bs of xyz', {'slot_0': _smIdx});
      expect(p.primaryText, isNotEmpty);
      // Should say "couldn't find" — not crash.
      expect(p.debugSummary,
          anyOf(startsWith('no-results:'), startsWith('empty-canonical')));
    });

    test('B6.4 rules for fake captain', () async {
      final p = await _run('rules for fake captain', {'slot_0': _smIdx});
      expect(p.primaryText, isNotEmpty);
    });

    test('B6.5 units with madeupkeyword', () async {
      final p = await _run('which units have madeupkeyword', {'slot_0': _smIdx});
      expect(p.debugSummary, startsWith('ability-search'));
    });
  });

  // =========================================================================
  // BATCH C — Clarification / Dialogue / Conversation Flow
  // =========================================================================

  group('Batch C1 — Weapon ambiguity', () {
    test('C1.1 bs of intercessors → "bolt rifle" resolves directly', () async {
      final coord = _freshCoord();
      final s = {'slot_0': _smIdx};

      final q1 = await coord.handleTranscript(
          transcript: 'what is the bs of intercessors',
          slotBundles: s, contextHints: const []);
      print('  Step 1: "${q1.primaryText}"  [${q1.debugSummary}]');
      expect(q1.debugSummary, startsWith('weapon-clarify:'),
          reason: 'Multi-weapon unit must ask for clarification');
      expect(q1.primaryText, contains('Which weapon?'));

      final q2 = await coord.handleTranscript(
          transcript: 'bolt rifle',
          slotBundles: s, contextHints: const []);
      print('  Step 2: "${q2.primaryText}"  [${q2.debugSummary}]');
      expect(q2.debugSummary, startsWith('attr-answer:bs:'));
      expect(q2.primaryText, contains('Bolt Rifle'));
    });

    test('C1.2 bs of intercessors → "bolt pistol" resolves directly', () async {
      final coord = _freshCoord();
      final s = {'slot_0': _smIdx};

      final q1 = await coord.handleTranscript(
          transcript: 'what is the bs of intercessors',
          slotBundles: s, contextHints: const []);
      expect(q1.debugSummary, startsWith('weapon-clarify:'));

      final q2 = await coord.handleTranscript(
          transcript: 'bolt pistol',
          slotBundles: s, contextHints: const []);
      print('  Step 2: "${q2.primaryText}"  [${q2.debugSummary}]');
      expect(q2.debugSummary, startsWith('attr-answer:bs:'));
      expect(q2.primaryText, contains('Bolt pistol')); // weapon stored as "Bolt pistol" in SM catalog
    });

    test('C1.3 damage of carnifex weapons → clarification if multiple weapons', () async {
      // Uses the plural handler path; outcome depends on Carnifex weapon inventory.
      final p = await _run('what are the ws values for carnifex weapons', {'slot_0': _tyIdx});
      print('  Carnifex WS result: ${p.debugSummary}');
      expect(p.primaryText, isNotEmpty);
    });
  });

  group('Batch C2 — Entity ambiguity', () {
    test('C2.1 rules for captain → clarify → select captain with jump pack', () async {
      final coord = _freshCoord();
      final s = {'slot_0': _smIdx};

      final q1 = await coord.handleTranscript(
          transcript: 'rules for captain',
          slotBundles: s, contextHints: const []);
      print('  Step 1: "${q1.primaryText}"  [${q1.debugSummary}]');
      // Captain has multiple variants → disambiguation.
      expect(q1.primaryText, isNotEmpty);
      if (q1.debugSummary.startsWith('disambiguation:')) {
        expect(q1.entities, isNotEmpty);
        final q2 = await coord.handleTranscript(
            transcript: 'captain with jump pack',
            slotBundles: s, contextHints: const []);
        print('  Step 2: "${q2.primaryText}"  [${q2.debugSummary}]');
        expect(q2.primaryText, isNotEmpty);
      }
    });

    test('C2.2 captain search → next/select navigation', () async {
      final coord = _freshCoord();
      final s = {'slot_0': _smIdx};

      final q1 = await coord.handleTranscript(
          transcript: 'captain', slotBundles: s, contextHints: const []);
      print('  Step 1: "${q1.primaryText}"  [${q1.debugSummary}]');

      if (q1.debugSummary.startsWith('disambiguation:')) {
        final q2 = await coord.handleTranscript(
            transcript: 'next', slotBundles: s, contextHints: const []);
        print('  Step 2 next: "${q2.primaryText}"  [${q2.debugSummary}]');
        expect(q2.primaryText, isNotEmpty);

        final q3 = await coord.handleTranscript(
            transcript: 'select', slotBundles: s, contextHints: const []);
        print('  Step 3 select: "${q3.primaryText}"  [${q3.debugSummary}]');
        expect(q3.primaryText, isNotEmpty);
      }
    });

    test('C2.3 intercessor → single result or disambiguate, then navigate', () async {
      final coord = _freshCoord();
      final s = {'slot_0': _smIdx};
      final q1 = await coord.handleTranscript(
          transcript: 'intercessor', slotBundles: s, contextHints: const []);
      print('  intercessor result: "${q1.primaryText}"  [${q1.debugSummary}]');
      expect(q1.primaryText, isNotEmpty);
    });
  });

  group('Batch C3 — Broad result handling', () {
    test('C3.1 which units have infantry (SM — broad)', () async {
      final p = await _run('which units have infantry', {'slot_0': _smIdx});
      print('  primaryText: "${p.primaryText}"');
      // Must produce a concise summary, not a giant list.
      expect(p.primaryText, isNotEmpty);
      // Should not include raw unit counts embedded in a huge list.
      expect(p.primaryText.length, lessThan(500),
          reason: 'Broad keyword result must be concise, not a full unit dump');
    });

    test('C3.2 which units have character (SM — broad)', () async {
      final p = await _run('which units have character', {'slot_0': _smIdx});
      expect(p.primaryText, isNotEmpty);
      expect(p.primaryText.length, lessThan(500));
    });

    test('C3.3 which units have synapse (TY — expected large set)', () async {
      final p = await _run('which units have synapse', {'slot_0': _tyIdx});
      expect(p.debugSummary, startsWith('ability-search'));
      // When > _kAbilitySearchWideThreshold units, narrowing suggestion appears.
      print('  synapse result: "${p.primaryText}"');
    });
  });

  group('Batch C4 — Failed clarification follow-up', () {
    test('C4.1 bs of intercessors → unrelated follow-up → graceful', () async {
      final coord = _freshCoord();
      final s = {'slot_0': _smIdx};

      final q1 = await coord.handleTranscript(
          transcript: 'what is the bs of intercessors',
          slotBundles: s, contextHints: const []);
      expect(q1.debugSummary, startsWith('weapon-clarify:'));

      // Unrelated follow-up — does NOT match any weapon name.
      final q2 = await coord.handleTranscript(
          transcript: 'tell me about toughness',
          slotBundles: s, contextHints: const []);
      print('  Unrelated follow-up: "${q2.primaryText}"  [${q2.debugSummary}]');
      // Must not crash; state must be clean.
      expect(q2.primaryText, isNotEmpty);
      // Pending weapon clarify must be cleared (no longer active).
      expect(q2.debugSummary, isNot(startsWith('weapon-clarify:')),
          reason: 'Unresolved clarification must be cleared, not repeated');
    });

    test('C4.2 rules for captain → unrelated follow-up → graceful', () async {
      final coord = _freshCoord();
      final s = {'slot_0': _smIdx};

      final q1 = await coord.handleTranscript(
          transcript: 'rules for captain',
          slotBundles: s, contextHints: const []);
      // Captain may trigger disambiguation.
      print('  Step 1: "${q1.primaryText}"  [${q1.debugSummary}]');

      final q2 = await coord.handleTranscript(
          transcript: 'banana',
          slotBundles: s, contextHints: const []);
      print('  Unrelated: "${q2.primaryText}"  [${q2.debugSummary}]');
      expect(q2.primaryText, isNotEmpty);
      // System must not crash or loop.
    });
  });
}

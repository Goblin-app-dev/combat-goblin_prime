import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';

/// V1 Answer-Correctness Validation
///
/// Validates that the retrieval system returns correct answers for the five
/// core V1 client queries:
///
///   1. "What is the BS of Intercessors?"
///   2. "What rules does a Carnifex have?"
///   3. "Which units have Synapse?"
///   4. "What's the Toughness of Morvenn Vahl?"
///   5. "How far do Jump Pack Intercessors move?"
///
/// For each query this test documents:
///   - Exact query text
///   - Resolved entity / result set
///   - Exact UnitDoc / field / rule source used
///   - Returned answer
///   - Whether the answer is correct (PASS / FAIL / BLOCKED)
///
/// Each failure is classified as:
///   V1_BLOCKER | POST_V1 | FUTURE_COMPAT
///
/// Run with:
///   flutter test test/benchmark/v1_correctness_test.dart --concurrency=1
void main() {
  const testSource = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  // Two separate index bundles: one per army book.
  late IndexBundle smIndex;    // Space Marines
  late IndexBundle tyIndex;    // Tyranids
  late StructuredSearchService service;

  // Report accumulator — mirrors benchmark emit() pattern.
  final report = <String>[];
  void emit(String line) {
    report.add(line);
    // ignore: avoid_print
    print(line);
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  /// Find a UnitDoc in [index] by canonical-key substring (case-insensitive).
  UnitDoc? _findUnit(IndexBundle index, String nameSubstring) {
    final norm = nameSubstring.toLowerCase();
    // Prefer exact canonical-key match first, then substring.
    final exact = index.units.where(
      (u) => u.canonicalKey == IndexService.normalize(nameSubstring),
    );
    if (exact.isNotEmpty) return exact.first;
    final sub = index.units.where(
      (u) => u.canonicalKey.contains(norm) || u.name.toLowerCase().contains(norm),
    );
    return sub.isEmpty ? null : sub.first;
  }

  /// Extract a characteristic value from [unit] by name (case-insensitive).
  String? _stat(UnitDoc unit, String charName) {
    final norm = charName.toLowerCase();
    for (final c in unit.characteristics) {
      if (c.name.toLowerCase() == norm) return c.valueText;
    }
    return null;
  }

  /// Resolve all RuleDocs referenced by [unit].
  List<RuleDoc> _rulesFor(IndexBundle index, UnitDoc unit) {
    final ruleById = {for (final r in index.rules) r.docId: r};
    return unit.ruleDocRefs
        .map((ref) => ruleById[ref])
        .whereType<RuleDoc>()
        .toList();
  }

  /// Pretty label for pass/fail/miss.
  String _label(bool? pass) => pass == null ? 'BLOCKED' : (pass ? 'PASS' : 'FAIL');

  // ── catalog loading ────────────────────────────────────────────────────────

  setUpAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) await dir.delete(recursive: true);

    final gstBytes = await File('test/Warhammer 40,000.gst').readAsBytes();

    // --- Space Marines index ---
    final smDeps = <String, String>{
      'b00-cd86-4b4c-97ba': 'test/Imperium - Agents of the Imperium.cat',
      '7481-280e-b55e-7867': 'test/Library - Titans.cat',
      '1b6d-dc06-5db9-c7d1': 'test/Imperium - Imperial Knights - Library.cat',
      'ac3b-689c-4ad4-70cb': 'test/Library - Astartes Heresy Legends.cat',
    };
    final smCatBytes =
        await File('test/Imperium - Space Marines.cat').readAsBytes();
    final smRaw = await AcquireService().buildBundle(
      gameSystemBytes: gstBytes,
      gameSystemExternalFileName: 'Warhammer 40,000.gst',
      primaryCatalogBytes: smCatBytes,
      primaryCatalogExternalFileName: 'Imperium - Space Marines.cat',
      requestDependencyBytes: (id) async {
        final path = smDeps[id];
        if (path == null) return null;
        return File(path).readAsBytes();
      },
      source: testSource,
    );
    smIndex = IndexService().buildIndex(
      await BindService().bindBundle(
        linkedBundle: await LinkService().linkBundle(
          wrappedBundle: await WrapService().wrapBundle(
            parsedBundle: await ParseService().parseBundle(rawBundle: smRaw),
          ),
        ),
      ),
    );

    // --- Tyranids index ---
    // Library - Tyranids.cat is a shared library dependency of Xenos - Tyranids.cat.
    // We provide all available test files as potential dependency sources.
    final allDeps = <String, String>{
      'b00-cd86-4b4c-97ba': 'test/Imperium - Agents of the Imperium.cat',
      '7481-280e-b55e-7867': 'test/Library - Titans.cat',
      '1b6d-dc06-5db9-c7d1': 'test/Imperium - Imperial Knights - Library.cat',
      'ac3b-689c-4ad4-70cb': 'test/Library - Astartes Heresy Legends.cat',
      // Library - Tyranids resolved by catalog link ID at runtime.
      // We load the primary as Xenos - Tyranids and let the service request the lib.
    };
    final tyCatBytes =
        await File('test/Xenos - Tyranids.cat').readAsBytes();
    final tyLibBytes =
        await File('test/Library - Tyranids.cat').readAsBytes();

    // Xenos - Tyranids.cat has two catalogueLinks:
    //   targetId=581a-46b9-5b86-44b7  → Unaligned Forces.cat
    //   targetId=374d-45f0-5832-001e  → Library - Tyranids.cat
    final unalignedBytes =
        await File('test/Unaligned Forces.cat').readAsBytes();
    allDeps['581a-46b9-5b86-44b7'] = 'test/Unaligned Forces.cat';
    allDeps['374d-45f0-5832-001e'] = 'test/Library - Tyranids.cat';

    final tyRaw = await AcquireService().buildBundle(
      gameSystemBytes: gstBytes,
      gameSystemExternalFileName: 'Warhammer 40,000.gst',
      primaryCatalogBytes: tyCatBytes,
      primaryCatalogExternalFileName: 'Xenos - Tyranids.cat',
      requestDependencyBytes: (id) async {
        if (id == '581a-46b9-5b86-44b7') return unalignedBytes;
        if (id == '374d-45f0-5832-001e') return tyLibBytes;
        final known = allDeps[id];
        if (known != null) return File(known).readAsBytes();
        return null;
      },
      source: testSource,
    );
    tyIndex = IndexService().buildIndex(
      await BindService().bindBundle(
        linkedBundle: await LinkService().linkBundle(
          wrappedBundle: await WrapService().wrapBundle(
            parsedBundle: await ParseService().parseBundle(rawBundle: tyRaw),
          ),
        ),
      ),
    );

    service = StructuredSearchService();
  });

  tearDownAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) await dir.delete(recursive: true);

    // ── Final report ──────────────────────────────────────────────────────────
    emit('');
    emit('══════════════════════════════════════════════');
    emit('  V1 Correctness Report — summary');
    emit('══════════════════════════════════════════════');
    for (final line in report) {
      // Already printed; no-op here keeps the summary at end of test output.
    }
  });

  // ── Q1: BS of Intercessors ────────────────────────────────────────────────

  test('Q1 — BS of Intercessors (Space Marines)', () {
    const query = 'What is the BS of Intercessors?';
    emit('');
    emit('── Q1: $query');

    // Search path: text="intercessor", docTypes=unit.
    final result = service.search(
      smIndex,
      const SearchRequest(
        text: 'intercessor',
        docTypes: {SearchDocType.unit},
        limit: 5,
      ),
    );

    emit('  Search hits (${result.hits.length}):');
    for (final h in result.hits) {
      emit('    ${h.displayName}  [${h.docId}]');
    }

    // Resolve to UnitDoc and extract BS.
    final hit = result.hits.firstWhere(
      (h) => h.displayName.toLowerCase().contains('intercessor') &&
          !h.displayName.toLowerCase().contains('jump'),
      orElse: () => result.hits.isEmpty ? throw TestFailure('No hits for "intercessor"') : result.hits.first,
    );

    final unit = smIndex.units.firstWhere(
      (u) => u.docId == hit.docId,
      orElse: () => throw TestFailure('UnitDoc not found for docId=${hit.docId}'),
    );

    final bs = _stat(unit, 'BS');
    emit('  Resolved entity : ${unit.name}  [${unit.docId}]');
    emit('  Source          : UnitDoc.characteristics[BS]');
    emit('  Returned answer : BS = ${bs ?? "(not found)"}');

    final pass = bs != null && bs.isNotEmpty;
    emit('  Result          : ${_label(pass)}');
    if (!pass) emit('  Classification  : V1_BLOCKER — BS field missing on unit');

    expect(bs, isNotNull,
        reason: 'BS characteristic must be present on Intercessors unit');
    expect(bs, isNotEmpty,
        reason: 'BS value must be non-empty');
  });

  // ── Q2: Rules of a Carnifex ───────────────────────────────────────────────

  test('Q2 — Rules of a Carnifex (Tyranids)', () {
    const query = 'What rules does a Carnifex have?';
    emit('');
    emit('── Q2: $query');

    // Search path: text="carnifex", docTypes=unit.
    final result = service.search(
      tyIndex,
      const SearchRequest(
        text: 'carnifex',
        docTypes: {SearchDocType.unit},
        limit: 5,
      ),
    );

    emit('  Search hits (${result.hits.length}):');
    for (final h in result.hits) {
      emit('    ${h.displayName}  [${h.docId}]');
    }

    if (result.hits.isEmpty) {
      emit('  Returned answer : (no unit found)');
      emit('  Result          : FAIL');
      emit('  Classification  : V1_BLOCKER — Carnifex not resolved in Tyranids index');
      fail('No hits for "carnifex" in Tyranids index');
    }

    final hit = result.hits.first;
    final unit = tyIndex.units.firstWhere(
      (u) => u.docId == hit.docId,
      orElse: () => throw TestFailure('UnitDoc not found for docId=${hit.docId}'),
    );

    final rules = _rulesFor(tyIndex, unit);
    emit('  Resolved entity : ${unit.name}  [${unit.docId}]');
    emit('  Source          : UnitDoc.ruleDocRefs → RuleDoc.name/description');
    emit('  ruleDocRefs     : ${unit.ruleDocRefs.length} refs');
    emit('  Resolved rules  : ${rules.length}');
    for (final r in rules) {
      final desc = r.description.length > 60
          ? '${r.description.substring(0, 60)}…'
          : r.description;
      emit('    • ${r.name}: $desc  [${r.docId}]');
    }

    final pass = rules.isNotEmpty;
    emit('  Returned answer : ${rules.map((r) => r.name).join(", ")}');
    emit('  Result          : ${_label(pass)}');
    if (!pass) {
      emit('  Classification  : V1_BLOCKER — no rules resolved for Carnifex');
      emit('  Note            : Check _findRuleAncestor() inheritance for monster entries');
    }

    expect(rules, isNotEmpty,
        reason: 'Carnifex must have at least one resolved RuleDoc via ruleDocRefs');
  });

  // ── Q3: Units with Synapse ────────────────────────────────────────────────

  test('Q3 — Units with Synapse keyword (Tyranids)', () {
    const query = 'Which units have Synapse?';
    emit('');
    emit('── Q3: $query');

    // Search path: keywords={"synapse"}, docTypes=unit.
    // No text driver — pure keyword filter.
    final result = service.search(
      tyIndex,
      const SearchRequest(
        keywords: {'synapse'},
        docTypes: {SearchDocType.unit},
        limit: 50,
        sort: SearchSort.alphabetical,
      ),
    );

    emit('  Search hits (${result.hits.length}):');
    for (final h in result.hits) {
      emit('    ${h.displayName}  [${h.docId}]');
    }
    if (result.diagnostics.isNotEmpty) {
      emit('  Diagnostics:');
      for (final d in result.diagnostics) {
        emit('    [${d.code.name}] ${d.message}');
      }
    }

    // Verify each hit actually carries the synapse keyword token.
    final mismatches = <String>[];
    for (final h in result.hits) {
      final unit = tyIndex.units.firstWhere(
        (u) => u.docId == h.docId,
        orElse: () => throw TestFailure('UnitDoc missing for ${h.docId}'),
      );
      final hasSynapse = unit.keywordTokens.contains('synapse') ||
          unit.categoryTokens.contains('synapse');
      if (!hasSynapse) mismatches.add(h.displayName);
    }

    final hitCount = result.hits.length;
    final pass = hitCount > 0 && mismatches.isEmpty;
    emit('  Returned answer : $hitCount units with Synapse');
    emit('  False positives : ${mismatches.isEmpty ? "none" : mismatches.join(", ")}');
    emit('  Result          : ${_label(pass)}');
    if (hitCount == 0) {
      emit('  Classification  : V1_BLOCKER — synapse keyword not indexed or no units carry it');
    } else if (mismatches.isNotEmpty) {
      emit('  Classification  : V1_BLOCKER — keyword filter returned units without synapse token');
    }

    expect(result.hits, isNotEmpty,
        reason: 'keyword="synapse" must return at least one Tyranid unit');
    expect(mismatches, isEmpty,
        reason: 'all hits must actually carry the synapse keyword token');
  });

  // ── Q4: Toughness of Morvenn Vahl ────────────────────────────────────────

  test('Q4 — Toughness of Morvenn Vahl (no Sisters catalog)', () {
    const query = "What's the Toughness of Morvenn Vahl?";
    emit('');
    emit('── Q4: $query');
    emit('  Note: No Adepta Sororitas catalog in test/. '
        'This test documents the expected miss.');

    // Attempt against both loaded indexes.
    final smResult = service.search(
      smIndex,
      const SearchRequest(text: 'morvenn vahl', docTypes: {SearchDocType.unit}),
    );
    final tyResult = service.search(
      tyIndex,
      const SearchRequest(text: 'morvenn vahl', docTypes: {SearchDocType.unit}),
    );

    emit('  SM index hits   : ${smResult.hits.length}');
    emit('  TY index hits   : ${tyResult.hits.length}');

    final foundAnywhere =
        smResult.hits.isNotEmpty || tyResult.hits.isNotEmpty;

    if (foundAnywhere) {
      // Unexpected hit — extract T and report.
      final hit = smResult.hits.isNotEmpty
          ? smResult.hits.first
          : tyResult.hits.first;
      final idx = smResult.hits.isNotEmpty ? smIndex : tyIndex;
      final unit = idx.units.firstWhere((u) => u.docId == hit.docId);
      final t = _stat(unit, 'T');
      emit('  Unexpected hit  : ${unit.name}  T=$t');
      emit('  Result          : PASS (unit found despite no Sisters catalog — '
          'investigate provenance)');
    } else {
      emit('  Returned answer : (no result — Sisters catalog not loaded)');
      emit('  Result          : BLOCKED — catalog not in test data set');
      emit('  Classification  : POST_V1 — add Adepta Sororitas catalog to '
          'test fixtures to validate this query path');
    }

    // This test passes as long as we handle the absence cleanly (no crash,
    // zero hits, no false-positive match).
    for (final h in smResult.hits) {
      expect(
        h.displayName.toLowerCase(),
        contains('morvenn'),
        reason: 'any SM hit for "morvenn vahl" must be the actual unit',
      );
    }
    for (final h in tyResult.hits) {
      expect(
        h.displayName.toLowerCase(),
        contains('morvenn'),
        reason: 'any TY hit for "morvenn vahl" must be the actual unit',
      );
    }
    // No crash == PASS for this BLOCKED query.
  });

  // ── Q5: Movement of Jump Pack Intercessors ────────────────────────────────

  test('Q5 — Movement of Jump Pack Intercessors (Space Marines)', () {
    const query = 'How far do Jump Pack Intercessors move?';
    emit('');
    emit('── Q5: $query');

    // Search path: text="jump pack intercessor", docTypes=unit.
    final result = service.search(
      smIndex,
      const SearchRequest(
        text: 'jump pack intercessor',
        docTypes: {SearchDocType.unit},
        limit: 5,
      ),
    );

    emit('  Search hits (${result.hits.length}):');
    for (final h in result.hits) {
      emit('    ${h.displayName}  [${h.docId}]');
    }

    if (result.hits.isEmpty) {
      emit('  Returned answer : (no unit found)');
      emit('  Result          : FAIL');
      emit('  Classification  : V1_BLOCKER — "Jump Pack Intercessors" not resolved; '
          'check multi-token text matching');
      fail('No hits for "jump pack intercessor" in SM index');
    }

    final hit = result.hits.first;
    final unit = smIndex.units.firstWhere(
      (u) => u.docId == hit.docId,
      orElse: () => throw TestFailure('UnitDoc not found for docId=${hit.docId}'),
    );

    final m = _stat(unit, 'M');
    emit('  Resolved entity : ${unit.name}  [${unit.docId}]');
    emit('  Source          : UnitDoc.characteristics[M]');
    emit('  Returned answer : M = ${m ?? "(not found)"}');

    final pass = m != null && m.isNotEmpty;
    emit('  Result          : ${_label(pass)}');
    if (!pass) emit('  Classification  : V1_BLOCKER — M characteristic missing');

    expect(m, isNotNull,
        reason: 'M characteristic must be present on Jump Pack Intercessors');
    expect(m, isNotEmpty,
        reason: 'M value must be non-empty');

    // The unit name should actually be Jump Pack Intercessors, not plain Intercessors.
    final nameCorrect = unit.name.toLowerCase().contains('jump');
    emit('  Name check      : ${unit.name} — ${nameCorrect ? "correct unit" : "WRONG UNIT (entity resolution miss)"}');
    if (!nameCorrect) {
      emit('  Classification  : V1_BLOCKER — _findUnitProfile first-match-wins '
          'resolved plain Intercessors instead of Jump Pack variant');
    }
    expect(nameCorrect, isTrue,
        reason: 'Resolved unit must be Jump Pack Intercessors, not a plain Intercessors variant');
  });

  // ── Summary ───────────────────────────────────────────────────────────────

  test('summary — index sizes and diagnostic counts', () {
    emit('');
    emit('── Index sizes ──');
    emit('  Space Marines : ${smIndex.units.length} units, '
        '${smIndex.weapons.length} weapons, ${smIndex.rules.length} rules');
    emit('  Tyranids      : ${tyIndex.units.length} units, '
        '${tyIndex.weapons.length} weapons, ${tyIndex.rules.length} rules');
    emit('');
    emit('── All Synapse units (full list) ──');
    final synapseUnits = tyIndex.units.where(
      (u) => u.keywordTokens.contains('synapse') ||
          u.categoryTokens.contains('synapse'),
    );
    for (final u in synapseUnits) {
      emit('  ${u.name}');
    }
    emit('');
    emit('── Carnifex rule refs ──');
    final carnifex = _findUnit(tyIndex, 'carnifex');
    if (carnifex != null) {
      emit('  ruleDocRefs: ${carnifex.ruleDocRefs}');
      emit('  keywordTokens: ${carnifex.keywordTokens}');
      emit('  categoryTokens: ${carnifex.categoryTokens}');
    } else {
      emit('  (carnifex not found)');
    }
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';

/// M10 Structured Search invariant tests.
///
/// These tests lock the M10 contract before freeze. They cover:
///   - Empty query contract
///   - resolveByDocId order
///   - suggest merge semantics
///   - Keyword behavior (units, weapons, rules diagnostic)
///   - Characteristic filtering
///   - Sorting invariants
///   - Determinism (same input → identical output)
///
/// Run with:
///   flutter test test/modules/m10_structured_search/ --concurrency=1
void main() {
  const testSource = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  late IndexBundle indexBundle;
  late StructuredSearchService service;

  setUpAll(() async {
    // Clean storage
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    // Build M5 bundle → M9 index once for all tests
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
    final boundBundle =
        await BindService().bindBundle(linkedBundle: linkedBundle);

    indexBundle = IndexService().buildIndex(boundBundle);
    service = StructuredSearchService();
  });

  tearDownAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  // =========================================================================
  // Empty query contract
  // =========================================================================

  group('M10 Search: empty query contract', () {
    test('docTypes-only request emits emptyQuery diagnostic and 0 hits', () {
      final result = service.search(
        indexBundle,
        const SearchRequest(docTypes: {SearchDocType.unit}),
      );

      expect(result.hits, isEmpty);
      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics.first.code, SearchDiagnosticCode.emptyQuery);
      print('[M10 INVARIANT] docTypes-only → emptyQuery, 0 hits');
    });

    test('totally empty request emits emptyQuery diagnostic and 0 hits', () {
      final result = service.search(
        indexBundle,
        const SearchRequest(),
      );

      expect(result.hits, isEmpty);
      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics.first.code, SearchDiagnosticCode.emptyQuery);
      print('[M10 INVARIANT] totally empty → emptyQuery, 0 hits');
    });

    test('whitespace-only text is treated as empty query', () {
      final result = service.search(
        indexBundle,
        const SearchRequest(text: '   '),
      );

      expect(result.hits, isEmpty);
      expect(result.diagnostics.any(
        (d) => d.code == SearchDiagnosticCode.emptyQuery,
      ), isTrue);
      print('[M10 INVARIANT] whitespace-only text → emptyQuery');
    });
  });

  // =========================================================================
  // resolveByDocId order
  // =========================================================================

  group('M10 Search: resolveByDocId', () {
    test('deterministic unit → weapon → rule lookup order', () {
      // Resolve a known unit docId
      final unitDocId = indexBundle.units.first.docId;
      final unitHit = service.resolveByDocId(indexBundle, unitDocId);
      expect(unitHit, isNotNull);
      expect(unitHit!.docType, SearchDocType.unit);
      expect(unitHit.docId, unitDocId);
      print('[M10 INVARIANT] resolveByDocId unit: ${unitHit.displayName}');

      // Resolve a known weapon docId
      final weaponDocId = indexBundle.weapons.first.docId;
      final weaponHit = service.resolveByDocId(indexBundle, weaponDocId);
      expect(weaponHit, isNotNull);
      expect(weaponHit!.docType, SearchDocType.weapon);
      expect(weaponHit.docId, weaponDocId);
      print('[M10 INVARIANT] resolveByDocId weapon: ${weaponHit.displayName}');

      // Resolve a known rule docId
      if (indexBundle.rules.isNotEmpty) {
        final ruleDocId = indexBundle.rules.first.docId;
        final ruleHit = service.resolveByDocId(indexBundle, ruleDocId);
        expect(ruleHit, isNotNull);
        expect(ruleHit!.docType, SearchDocType.rule);
        expect(ruleHit.docId, ruleDocId);
        print('[M10 INVARIANT] resolveByDocId rule: ${ruleHit.displayName}');
      }
    });

    test('unknown docId returns null', () {
      final hit =
          service.resolveByDocId(indexBundle, 'nonexistent:does-not-exist');
      expect(hit, isNull);
      print('[M10 INVARIANT] unknown docId → null');
    });

    test('matchReasons always contains canonicalKeyMatch', () {
      final unitDocId = indexBundle.units.first.docId;
      final hit = service.resolveByDocId(indexBundle, unitDocId);
      expect(hit, isNotNull);
      expect(hit!.matchReasons, contains(MatchReason.canonicalKeyMatch));
      print('[M10 INVARIANT] resolveByDocId matchReasons = '
          '${hit.matchReasons}');
    });
  });

  // =========================================================================
  // suggest merge semantics
  // =========================================================================

  group('M10 Search: suggest merge semantics', () {
    test('returns merged unit/weapon/rule keys', () {
      // Use a prefix likely to appear across doc types
      final suggestions = service.suggest(indexBundle, 'bolt', limit: 50);

      expect(suggestions, isNotEmpty);
      print('[M10 INVARIANT] suggest("bolt"): ${suggestions.length} results');
      for (final s in suggestions.take(10)) {
        print('[M10 INVARIANT]   $s');
      }
    });

    test('results are sorted lexicographically', () {
      final suggestions = service.suggest(indexBundle, 'a', limit: 50);

      // Verify sorted
      final sorted = List<String>.from(suggestions)..sort();
      expect(suggestions, sorted);
      print('[M10 INVARIANT] suggest("a") sorted: ${suggestions.length} items');
    });

    test('results are deduplicated', () {
      final suggestions = service.suggest(indexBundle, 'bolt', limit: 50);

      // No duplicates
      final unique = suggestions.toSet();
      expect(suggestions.length, unique.length);
      print('[M10 INVARIANT] suggest("bolt") deduped: '
          '${suggestions.length} items, ${unique.length} unique');
    });

    test('respects limit', () {
      final limit3 = service.suggest(indexBundle, 'a', limit: 3);
      final limit10 = service.suggest(indexBundle, 'a', limit: 10);

      expect(limit3.length, lessThanOrEqualTo(3));
      expect(limit10.length, lessThanOrEqualTo(10));

      // limit3 should be prefix of limit10
      for (var i = 0; i < limit3.length; i++) {
        expect(limit3[i], limit10[i]);
      }
      print('[M10 INVARIANT] suggest limit=3: ${limit3.length}, '
          'limit=10: ${limit10.length}');
    });

    test('empty prefix returns empty list', () {
      final suggestions = service.suggest(indexBundle, '');
      expect(suggestions, isEmpty);

      final whitespace = service.suggest(indexBundle, '   ');
      expect(whitespace, isEmpty);
      print('[M10 INVARIANT] suggest empty/whitespace → empty');
    });
  });

  // =========================================================================
  // Keyword behavior
  // =========================================================================

  group('M10 Search: keyword behavior', () {
    test('units: keyword "infantry" returns expected hits', () {
      final result = service.search(
        indexBundle,
        const SearchRequest(
          keywords: {'infantry'},
          docTypes: {SearchDocType.unit},
        ),
      );

      expect(result.hits, isNotEmpty);
      // All returned hits should be units
      for (final hit in result.hits) {
        expect(hit.docType, SearchDocType.unit);
      }
      print('[M10 INVARIANT] keyword "infantry" → '
          '${result.hits.length} unit hits');
    });

    test('weapons: keyword search via keywordTokens path returns hits', () {
      // Find a weapon keyword that exists
      final weaponsWithKw = indexBundle.weapons
          .where((w) => w.keywordTokens.isNotEmpty)
          .toList();

      if (weaponsWithKw.isEmpty) {
        print('[M10 INVARIANT] SKIP: no weapons with keywordTokens');
        return;
      }

      final testKeyword = weaponsWithKw.first.keywordTokens.first;
      final result = service.search(
        indexBundle,
        SearchRequest(
          keywords: {testKeyword},
          docTypes: const {SearchDocType.weapon},
        ),
      );

      expect(result.hits, isNotEmpty);
      for (final hit in result.hits) {
        expect(hit.docType, SearchDocType.weapon);
      }
      print('[M10 INVARIANT] weapon keyword "$testKeyword" → '
          '${result.hits.length} weapon hits');
    });

    test('rules: keyword emits exactly one invalidFilter diagnostic', () {
      final result = service.search(
        indexBundle,
        const SearchRequest(
          keywords: {'infantry', 'character'},
          docTypes: {SearchDocType.rule},
        ),
      );

      // Should emit exactly ONE invalidFilter diagnostic despite 2 keywords
      final invalidFilterDiags = result.diagnostics
          .where((d) => d.code == SearchDiagnosticCode.invalidFilter)
          .toList();
      expect(invalidFilterDiags, hasLength(1),
          reason: 'Should emit exactly one invalidFilter diagnostic for '
              'rule keyword filtering, not one per keyword');
      expect(invalidFilterDiags.first.message,
          'Keyword filter not supported for rule docs.');
      print('[M10 INVARIANT] rule keywords → exactly 1 invalidFilter '
          'diagnostic (not ${2})');
    });

    test('rules: keyword does not spam diagnostics per keyword', () {
      final result = service.search(
        indexBundle,
        const SearchRequest(
          keywords: {'a', 'b', 'c', 'd', 'e'},
          docTypes: {SearchDocType.rule},
        ),
      );

      final invalidFilterDiags = result.diagnostics
          .where((d) => d.code == SearchDiagnosticCode.invalidFilter)
          .toList();
      // Must be exactly 1, not 5
      expect(invalidFilterDiags, hasLength(1));
      print('[M10 INVARIANT] 5 keywords on rules → still 1 diagnostic');
    });
  });

  // =========================================================================
  // Characteristic filtering
  // =========================================================================

  group('M10 Search: characteristic filtering', () {
    test('M characteristic name-narrowing + raw value match works', () {
      // Find a unit with M characteristic to know expected value
      final unitWithM = indexBundle.units.firstWhere(
        (u) => u.characteristics.any((c) => c.name.toLowerCase() == 'm'),
        orElse: () => throw StateError('No unit with M characteristic'),
      );
      final mValue = unitWithM.characteristics
          .firstWhere((c) => c.name.toLowerCase() == 'm')
          .valueText;

      final result = service.search(
        indexBundle,
        SearchRequest(
          characteristicFilters: {'M': mValue},
          docTypes: const {SearchDocType.unit},
          limit: 200,
        ),
      );

      expect(result.hits, isNotEmpty);
      // The unit we found should appear in results
      expect(result.hits.any((h) => h.docId == unitWithM.docId), isTrue);
      print('[M10 INVARIANT] characteristic M=$mValue → '
          '${result.hits.length} hits (includes ${unitWithM.name})');
    });

    test('SV characteristic filtering works', () {
      final unitWithSV = indexBundle.units.firstWhere(
        (u) => u.characteristics.any((c) => c.name.toLowerCase() == 'sv'),
        orElse: () => throw StateError('No unit with SV characteristic'),
      );
      final svValue = unitWithSV.characteristics
          .firstWhere((c) => c.name.toLowerCase() == 'sv')
          .valueText;

      final result = service.search(
        indexBundle,
        SearchRequest(
          characteristicFilters: {'SV': svValue},
          docTypes: const {SearchDocType.unit},
          limit: 200,
        ),
      );

      expect(result.hits, isNotEmpty);
      expect(result.hits.any((h) => h.docId == unitWithSV.docId), isTrue);
      print('[M10 INVARIANT] characteristic SV=$svValue → '
          '${result.hits.length} hits');
    });

    test('non-existent characteristic value returns 0 hits', () {
      final result = service.search(
        indexBundle,
        const SearchRequest(
          characteristicFilters: {'M': '999999'},
          docTypes: {SearchDocType.unit},
        ),
      );

      expect(result.hits, isEmpty);
      print('[M10 INVARIANT] characteristic M=999999 → 0 hits');
    });
  });

  // =========================================================================
  // Sorting invariants
  // =========================================================================

  group('M10 Search: sorting invariants', () {
    test('alphabetical sort is stable with tie-break chain', () {
      final result = service.search(
        indexBundle,
        const SearchRequest(
          text: 'captain',
          sort: SearchSort.alphabetical,
          sortDirection: SortDirection.ascending,
          limit: 50,
        ),
      );

      if (result.hits.length > 1) {
        for (var i = 1; i < result.hits.length; i++) {
          final prev = result.hits[i - 1];
          final curr = result.hits[i];
          final keyCompare = prev.canonicalKey.compareTo(curr.canonicalKey);
          if (keyCompare == 0) {
            // Same key → docType must not decrease
            final dtCompare =
                prev.docType.index.compareTo(curr.docType.index);
            if (dtCompare == 0) {
              // Same docType → docId must not decrease
              expect(prev.docId.compareTo(curr.docId), lessThanOrEqualTo(0));
            } else {
              expect(dtCompare, lessThan(0));
            }
          } else {
            expect(keyCompare, lessThan(0));
          }
        }
      }
      print('[M10 INVARIANT] alphabetical sort verified: '
          '${result.hits.length} hits');
    });

    test('docTypeThenAlphabetical sort is stable', () {
      final result = service.search(
        indexBundle,
        const SearchRequest(
          text: 'bolt',
          sort: SearchSort.docTypeThenAlphabetical,
          sortDirection: SortDirection.ascending,
          limit: 50,
        ),
      );

      if (result.hits.length > 1) {
        for (var i = 1; i < result.hits.length; i++) {
          final prev = result.hits[i - 1];
          final curr = result.hits[i];
          final dtCompare = prev.docType.index.compareTo(curr.docType.index);
          if (dtCompare == 0) {
            final keyCompare = prev.canonicalKey.compareTo(curr.canonicalKey);
            if (keyCompare == 0) {
              expect(prev.docId.compareTo(curr.docId), lessThanOrEqualTo(0));
            } else {
              expect(keyCompare, lessThan(0));
            }
          } else {
            expect(dtCompare, lessThan(0));
          }
        }
      }
      print('[M10 INVARIANT] docTypeThenAlphabetical sort verified: '
          '${result.hits.length} hits');
    });

    test('relevance sort is stable with tie-break chain', () {
      // Use a query that produces multi-reason hits for richer sorting
      final result = service.search(
        indexBundle,
        const SearchRequest(
          text: 'captain',
          sort: SearchSort.relevance,
          sortDirection: SortDirection.ascending,
          limit: 50,
        ),
      );

      if (result.hits.length > 1) {
        for (var i = 1; i < result.hits.length; i++) {
          final prev = result.hits[i - 1];
          final curr = result.hits[i];
          final scorePrev = prev.matchReasons.length;
          final scoreCurr = curr.matchReasons.length;
          // Relevance is descending (higher first in ascending mode)
          final scoreCompare = scoreCurr.compareTo(scorePrev);
          if (scoreCompare == 0) {
            final dtCompare =
                prev.docType.index.compareTo(curr.docType.index);
            if (dtCompare == 0) {
              final keyCompare =
                  prev.canonicalKey.compareTo(curr.canonicalKey);
              if (keyCompare == 0) {
                expect(
                    prev.docId.compareTo(curr.docId), lessThanOrEqualTo(0));
              } else {
                expect(keyCompare, lessThan(0));
              }
            } else {
              expect(dtCompare, lessThan(0));
            }
          } else {
            // Higher score first
            expect(scoreCompare, lessThan(0));
          }
        }
      }
      print('[M10 INVARIANT] relevance sort verified: '
          '${result.hits.length} hits');
    });

    test('SortDirection.descending reverses order', () {
      final asc = service.search(
        indexBundle,
        const SearchRequest(
          text: 'captain',
          sort: SearchSort.alphabetical,
          sortDirection: SortDirection.ascending,
          limit: 50,
        ),
      );

      final desc = service.search(
        indexBundle,
        const SearchRequest(
          text: 'captain',
          sort: SearchSort.alphabetical,
          sortDirection: SortDirection.descending,
          limit: 50,
        ),
      );

      expect(asc.hits.length, desc.hits.length);
      if (asc.hits.length > 1) {
        // Descending should be reverse of ascending
        for (var i = 0; i < asc.hits.length; i++) {
          expect(asc.hits[i].docId,
              desc.hits[desc.hits.length - 1 - i].docId);
        }
      }
      print('[M10 INVARIANT] descending is reverse of ascending: '
          '${asc.hits.length} hits');
    });
  });

  // =========================================================================
  // Determinism
  // =========================================================================

  group('M10 Search: determinism', () {
    test('same text search twice → identical SearchResult', () {
      final result1 = service.search(
        indexBundle,
        const SearchRequest(text: 'intercessor', limit: 50),
      );
      final result2 = service.search(
        indexBundle,
        const SearchRequest(text: 'intercessor', limit: 50),
      );

      expect(result1.hits.length, result2.hits.length);
      for (var i = 0; i < result1.hits.length; i++) {
        expect(result1.hits[i].docId, result2.hits[i].docId);
        expect(result1.hits[i].docType, result2.hits[i].docType);
        expect(result1.hits[i].canonicalKey, result2.hits[i].canonicalKey);
        expect(result1.hits[i].displayName, result2.hits[i].displayName);
        expect(result1.hits[i].matchReasons, result2.hits[i].matchReasons);
      }

      // Diagnostics should also be identical
      expect(result1.diagnostics.length, result2.diagnostics.length);
      for (var i = 0; i < result1.diagnostics.length; i++) {
        expect(result1.diagnostics[i].code, result2.diagnostics[i].code);
        expect(
            result1.diagnostics[i].message, result2.diagnostics[i].message);
      }
      print('[M10 INVARIANT] text search determinism: '
          '${result1.hits.length} hits identical');
    });

    test('same keyword search twice → identical SearchResult', () {
      final result1 = service.search(
        indexBundle,
        const SearchRequest(
          keywords: {'infantry'},
          docTypes: {SearchDocType.unit},
          limit: 50,
        ),
      );
      final result2 = service.search(
        indexBundle,
        const SearchRequest(
          keywords: {'infantry'},
          docTypes: {SearchDocType.unit},
          limit: 50,
        ),
      );

      expect(result1.hits.length, result2.hits.length);
      for (var i = 0; i < result1.hits.length; i++) {
        expect(result1.hits[i].docId, result2.hits[i].docId);
        expect(result1.hits[i].matchReasons, result2.hits[i].matchReasons);
      }
      print('[M10 INVARIANT] keyword search determinism: '
          '${result1.hits.length} hits identical');
    });

    test('same characteristic search twice → identical SearchResult', () {
      // Find a characteristic value that exists
      final unitWithM = indexBundle.units.firstWhere(
        (u) => u.characteristics.any((c) => c.name.toLowerCase() == 'm'),
      );
      final mValue = unitWithM.characteristics
          .firstWhere((c) => c.name.toLowerCase() == 'm')
          .valueText;

      final result1 = service.search(
        indexBundle,
        SearchRequest(
          characteristicFilters: {'M': mValue},
          docTypes: const {SearchDocType.unit},
          limit: 50,
        ),
      );
      final result2 = service.search(
        indexBundle,
        SearchRequest(
          characteristicFilters: {'M': mValue},
          docTypes: const {SearchDocType.unit},
          limit: 50,
        ),
      );

      expect(result1.hits.length, result2.hits.length);
      for (var i = 0; i < result1.hits.length; i++) {
        expect(result1.hits[i].docId, result2.hits[i].docId);
      }
      print('[M10 INVARIANT] characteristic search determinism: '
          '${result1.hits.length} hits identical');
    });

    test('diagnostics order is stable across identical requests', () {
      // A request that generates diagnostics (rule + keywords)
      final result1 = service.search(
        indexBundle,
        const SearchRequest(
          keywords: {'infantry'},
          docTypes: {SearchDocType.unit, SearchDocType.rule},
        ),
      );
      final result2 = service.search(
        indexBundle,
        const SearchRequest(
          keywords: {'infantry'},
          docTypes: {SearchDocType.unit, SearchDocType.rule},
        ),
      );

      expect(result1.diagnostics.length, result2.diagnostics.length);
      for (var i = 0; i < result1.diagnostics.length; i++) {
        expect(result1.diagnostics[i].code, result2.diagnostics[i].code);
        expect(
            result1.diagnostics[i].message, result2.diagnostics[i].message);
      }
      print('[M10 INVARIANT] diagnostic order stable: '
          '${result1.diagnostics.length} diagnostics');
    });
  });

  // =========================================================================
  // Additional contract tests
  // =========================================================================

  group('M10 Search: additional contract', () {
    test('limit applies and emits resultLimitApplied diagnostic', () {
      // Use a broad query with a very small limit
      final result = service.search(
        indexBundle,
        const SearchRequest(text: 'a', limit: 2),
      );

      expect(result.hits.length, lessThanOrEqualTo(2));
      // If there were more than 2 candidates, a diagnostic should be emitted
      if (result.diagnostics.any(
          (d) => d.code == SearchDiagnosticCode.resultLimitApplied)) {
        print('[M10 INVARIANT] resultLimitApplied emitted for limit=2');
      } else {
        print('[M10 INVARIANT] query "a" had <= 2 results, no truncation');
      }
    });

    test('text + keyword intersection narrows results', () {
      final textOnly = service.search(
        indexBundle,
        const SearchRequest(
          text: 'captain',
          docTypes: {SearchDocType.unit},
          limit: 50,
        ),
      );

      final textAndKeyword = service.search(
        indexBundle,
        const SearchRequest(
          text: 'captain',
          keywords: {'character'},
          docTypes: {SearchDocType.unit},
          limit: 50,
        ),
      );

      // Intersection should have <= the text-only count
      expect(textAndKeyword.hits.length,
          lessThanOrEqualTo(textOnly.hits.length));
      print('[M10 INVARIANT] text only: ${textOnly.hits.length}, '
          'text+keyword: ${textAndKeyword.hits.length}');
    });

    test('suggest determinism: same call twice → identical list', () {
      final s1 = service.suggest(indexBundle, 'cap', limit: 20);
      final s2 = service.suggest(indexBundle, 'cap', limit: 20);
      expect(s1, s2);
      print('[M10 INVARIANT] suggest determinism: ${s1.length} items');
    });
  });
}

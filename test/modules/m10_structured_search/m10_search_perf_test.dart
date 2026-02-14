import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';

/// Performance baseline tests for M10 Structured Search.
///
/// These tests establish regression baselines for search operations.
/// Run with: flutter test test/modules/m10_structured_search/m10_search_perf_test.dart
///
/// Baselines are informational — tests pass regardless of timing.
/// Use for regression detection, not CI gates.
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

  group('M10 Search: performance baselines', () {
    test('baseline: suggest(prefix) timing', () {
      const prefixes = ['a', 'bo', 'cap', 'inter', 'assault'];
      const runsPerQuery = 100;

      // Warm-up
      service.suggest(indexBundle, 'warm');

      print('[M10 PERF] suggest() baseline:');

      for (final prefix in prefixes) {
        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < runsPerQuery; i++) {
          service.suggest(indexBundle, prefix);
        }
        stopwatch.stop();

        final avgMicros = stopwatch.elapsedMicroseconds / runsPerQuery;
        final results = service.suggest(indexBundle, prefix);
        print('[M10 PERF]   suggest("$prefix"): '
            '${avgMicros.toStringAsFixed(1)} us '
            '(${results.length} results)');
      }

      // No assertion — baseline only
    });

    test('baseline: search(text) timing', () {
      const queries = ['captain', 'intercessor', 'bolt', 'assault', 'veteran'];
      const runsPerQuery = 100;

      // Warm-up
      service.search(indexBundle, const SearchRequest(text: 'warm'));

      print('[M10 PERF] search(text) baseline:');

      for (final query in queries) {
        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < runsPerQuery; i++) {
          service.search(indexBundle, SearchRequest(text: query));
        }
        stopwatch.stop();

        final avgMicros = stopwatch.elapsedMicroseconds / runsPerQuery;
        final results = service.search(indexBundle, SearchRequest(text: query));
        print('[M10 PERF]   search("$query"): '
            '${avgMicros.toStringAsFixed(1)} us '
            '(${results.hits.length} hits)');
      }

      // No assertion — baseline only
    });

    test('baseline: search(keywords) timing', () {
      const keywords = ['infantry', 'character', 'vehicle', 'battleline'];
      const runsPerQuery = 100;

      // Warm-up
      service.search(
        indexBundle,
        const SearchRequest(
          keywords: {'infantry'},
          docTypes: {SearchDocType.unit},
        ),
      );

      print('[M10 PERF] search(keywords) baseline:');

      for (final keyword in keywords) {
        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < runsPerQuery; i++) {
          service.search(
            indexBundle,
            SearchRequest(
              keywords: {keyword},
              docTypes: const {SearchDocType.unit},
            ),
          );
        }
        stopwatch.stop();

        final avgMicros = stopwatch.elapsedMicroseconds / runsPerQuery;
        final results = service.search(
          indexBundle,
          SearchRequest(
            keywords: {keyword},
            docTypes: const {SearchDocType.unit},
          ),
        );
        print('[M10 PERF]   keyword("$keyword"): '
            '${avgMicros.toStringAsFixed(1)} us '
            '(${results.hits.length} hits)');
      }

      // No assertion — baseline only
    });

    test('baseline: search(characteristicFilters) timing', () {
      // Find real characteristic values for benchmarking
      final unitWithM = indexBundle.units.firstWhere(
        (u) => u.characteristics.any((c) => c.name.toLowerCase() == 'm'),
      );
      final mValue = unitWithM.characteristics
          .firstWhere((c) => c.name.toLowerCase() == 'm')
          .valueText;

      final unitWithSV = indexBundle.units.firstWhere(
        (u) => u.characteristics.any((c) => c.name.toLowerCase() == 'sv'),
      );
      final svValue = unitWithSV.characteristics
          .firstWhere((c) => c.name.toLowerCase() == 'sv')
          .valueText;

      final charQueries = <String, String>{
        'M=$mValue': mValue,
        'SV=$svValue': svValue,
      };

      const runsPerQuery = 50;

      // Warm-up
      service.search(
        indexBundle,
        SearchRequest(characteristicFilters: {'M': mValue}),
      );

      print('[M10 PERF] search(characteristicFilters) baseline:');

      for (final entry in charQueries.entries) {
        final charName = entry.key.split('=').first;
        final charValue = entry.value;

        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < runsPerQuery; i++) {
          service.search(
            indexBundle,
            SearchRequest(
              characteristicFilters: {charName: charValue},
              docTypes: const {SearchDocType.unit},
            ),
          );
        }
        stopwatch.stop();

        final avgMicros = stopwatch.elapsedMicroseconds / runsPerQuery;
        final results = service.search(
          indexBundle,
          SearchRequest(
            characteristicFilters: {charName: charValue},
            docTypes: const {SearchDocType.unit},
          ),
        );
        print('[M10 PERF]   char(${entry.key}): '
            '${avgMicros.toStringAsFixed(1)} us '
            '(${results.hits.length} hits)');
      }

      // No assertion — baseline only
    });

    test('baseline: resolveByDocId timing', () {
      const runsPerQuery = 1000;

      final unitDocId = indexBundle.units.first.docId;
      final weaponDocId = indexBundle.weapons.first.docId;
      final ruleDocId =
          indexBundle.rules.isNotEmpty ? indexBundle.rules.first.docId : null;

      // Warm-up
      service.resolveByDocId(indexBundle, unitDocId);

      print('[M10 PERF] resolveByDocId() baseline:');

      // Unit
      final sw1 = Stopwatch()..start();
      for (var i = 0; i < runsPerQuery; i++) {
        service.resolveByDocId(indexBundle, unitDocId);
      }
      sw1.stop();
      print('[M10 PERF]   unit: '
          '${(sw1.elapsedMicroseconds / runsPerQuery).toStringAsFixed(1)} us');

      // Weapon
      final sw2 = Stopwatch()..start();
      for (var i = 0; i < runsPerQuery; i++) {
        service.resolveByDocId(indexBundle, weaponDocId);
      }
      sw2.stop();
      print('[M10 PERF]   weapon: '
          '${(sw2.elapsedMicroseconds / runsPerQuery).toStringAsFixed(1)} us');

      // Rule
      if (ruleDocId != null) {
        final sw3 = Stopwatch()..start();
        for (var i = 0; i < runsPerQuery; i++) {
          service.resolveByDocId(indexBundle, ruleDocId);
        }
        sw3.stop();
        print('[M10 PERF]   rule: '
            '${(sw3.elapsedMicroseconds / runsPerQuery).toStringAsFixed(1)} us');
      }

      // No assertion — baseline only
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';

/// Performance baseline tests for M9 Index-Core.
///
/// These tests establish regression baselines for buildIndex() performance.
/// Run with: flutter test test/modules/m9_index/m9_index_perf_test.dart
///
/// Baselines are informational — tests pass regardless of timing.
/// Use for regression detection, not CI gates.
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

  group('M9 Index: performance baselines', () {
    test('baseline: buildIndex() timing (Space Marines catalog)', () {
      final indexService = IndexService();

      // Warm-up run (JIT compilation)
      indexService.buildIndex(boundBundle);

      // Timed runs
      const runs = 5;
      final timings = <int>[];

      for (var i = 0; i < runs; i++) {
        final stopwatch = Stopwatch()..start();
        final bundle = indexService.buildIndex(boundBundle);
        stopwatch.stop();
        timings.add(stopwatch.elapsedMilliseconds);

        // Sanity check: bundle was actually built
        expect(bundle.units.isNotEmpty, isTrue);
      }

      final avgMs = timings.reduce((a, b) => a + b) / runs;
      final minMs = timings.reduce((a, b) => a < b ? a : b);
      final maxMs = timings.reduce((a, b) => a > b ? a : b);

      print('[M9 PERF] buildIndex() baseline (Space Marines):');
      print('[M9 PERF]   Runs: $runs');
      print('[M9 PERF]   Timings: $timings ms');
      print('[M9 PERF]   Avg: ${avgMs.toStringAsFixed(1)} ms');
      print('[M9 PERF]   Min: $minMs ms');
      print('[M9 PERF]   Max: $maxMs ms');

      // Report bundle size for context
      final bundle = indexService.buildIndex(boundBundle);
      print('[M9 PERF]   Units: ${bundle.units.length}');
      print('[M9 PERF]   Weapons: ${bundle.weapons.length}');
      print('[M9 PERF]   Rules: ${bundle.rules.length}');
      print('[M9 PERF]   Diagnostics: ${bundle.diagnostics.length}');

      // No assertion — this is a baseline, not a gate
      // If you need a regression gate, add:
      // expect(avgMs, lessThan(500), reason: 'buildIndex() should complete in <500ms');
    });

    test('baseline: query timing (findUnitsContaining)', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      const queries = ['captain', 'intercessor', 'bolt', 'assault', 'veteran'];
      const runsPerQuery = 100;

      print('[M9 PERF] findUnitsContaining() baseline:');

      for (final query in queries) {
        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < runsPerQuery; i++) {
          bundle.findUnitsContaining(query);
        }
        stopwatch.stop();

        final avgMicros = stopwatch.elapsedMicroseconds / runsPerQuery;
        final results = bundle.findUnitsContaining(query);
        print('[M9 PERF]   "$query": ${avgMicros.toStringAsFixed(1)} µs '
            '(${results.length} results)');
      }
    });

    test('baseline: query timing (unitsByKeyword)', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      const keywords = ['infantry', 'character', 'vehicle', 'battleline'];
      const runsPerQuery = 100;

      print('[M9 PERF] unitsByKeyword() baseline:');

      for (final keyword in keywords) {
        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < runsPerQuery; i++) {
          bundle.unitsByKeyword(keyword).toList();
        }
        stopwatch.stop();

        final avgMicros = stopwatch.elapsedMicroseconds / runsPerQuery;
        final results = bundle.unitsByKeyword(keyword).toList();
        print('[M9 PERF]   "$keyword": ${avgMicros.toStringAsFixed(1)} µs '
            '(${results.length} results)');
      }
    });

    test('baseline: autocomplete timing', () {
      final indexService = IndexService();
      final bundle = indexService.buildIndex(boundBundle);

      const prefixes = ['a', 'ca', 'cap', 'capt', 'inter'];
      const runsPerQuery = 100;

      print('[M9 PERF] autocompleteUnitKeys() baseline:');

      for (final prefix in prefixes) {
        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < runsPerQuery; i++) {
          bundle.autocompleteUnitKeys(prefix, limit: 10);
        }
        stopwatch.stop();

        final avgMicros = stopwatch.elapsedMicroseconds / runsPerQuery;
        final results = bundle.autocompleteUnitKeys(prefix, limit: 10);
        print('[M9 PERF]   "$prefix": ${avgMicros.toStringAsFixed(1)} µs '
            '(${results.length} results)');
      }
    });
  });
}

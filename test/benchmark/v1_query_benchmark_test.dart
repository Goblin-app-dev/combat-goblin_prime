import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';

/// V1 Query Benchmark — M10 StructuredSearchService
///
/// Establishes timing baselines for all public M10 query operations:
///   - suggest()
///   - search(text)
///   - search(keywords)
///   - search(characteristicFilters)
///   - search(text + keywords) — combined AND query
///   - resolveByDocId()
///
/// Results are informational only — no assertions on timing.
/// Index is built once from Space Marines catalog + its full dependency closure.
///
/// Run with:
///   flutter test test/benchmark/v1_query_benchmark_test.dart --concurrency=1
void main() {
  const testSource = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  late IndexBundle indexBundle;
  late StructuredSearchService service;

  // Benchmark results accumulator
  final lines = <String>[];

  void emit(String line) {
    lines.add(line);
    // ignore: avoid_print
    print(line);
  }

  setUpAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

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

  // -------------------------------------------------------------------------
  // Index size report
  // -------------------------------------------------------------------------

  test('index: size report', () {
    emit('');
    emit('=== V1 Query Benchmark — Space Marines catalog ===');
    emit(
        'index: ${indexBundle.units.length} units, ${indexBundle.weapons.length} weapons, ${indexBundle.rules.length} rules');
    emit('');
  });

  // -------------------------------------------------------------------------
  // suggest()
  // -------------------------------------------------------------------------

  group('suggest()', () {
    const runs = 200;
    const prefixes = ['a', 'bo', 'cap', 'inter', 'assault', 'tactical'];

    test('timing per prefix (N=$runs)', () {
      // Warm-up
      service.suggest(indexBundle, 'warm');

      emit('--- suggest() ---');
      for (final prefix in prefixes) {
        final sw = Stopwatch()..start();
        for (var i = 0; i < runs; i++) {
          service.suggest(indexBundle, prefix);
        }
        sw.stop();

        final results = service.suggest(indexBundle, prefix);
        final avgUs = sw.elapsedMicroseconds / runs;
        emit('  suggest("$prefix"): '
            '${avgUs.toStringAsFixed(1)} µs avg, '
            '${results.length} results');
      }
      emit('');
    });
  });

  // -------------------------------------------------------------------------
  // search(text)
  // -------------------------------------------------------------------------

  group('search(text)', () {
    const runs = 100;
    const queries = [
      'captain',
      'intercessor',
      'bolt',
      'assault',
      'veteran',
      'land raider',
    ];

    test('timing per query (N=$runs)', () {
      // Warm-up
      service.search(indexBundle, const SearchRequest(text: 'warm'));

      emit('--- search(text) ---');
      for (final query in queries) {
        final request = SearchRequest(text: query);
        final sw = Stopwatch()..start();
        for (var i = 0; i < runs; i++) {
          service.search(indexBundle, request);
        }
        sw.stop();

        final result = service.search(indexBundle, request);
        final avgUs = sw.elapsedMicroseconds / runs;
        emit('  text("$query"): '
            '${avgUs.toStringAsFixed(1)} µs avg, '
            '${result.hits.length} hits');
      }
      emit('');
    });
  });

  // -------------------------------------------------------------------------
  // search(keywords) — units only
  // -------------------------------------------------------------------------

  group('search(keywords)', () {
    const runs = 100;
    const keywords = [
      'infantry',
      'character',
      'vehicle',
      'battleline',
      'psyker',
    ];

    test('timing per keyword (N=$runs, units only)', () {
      // Warm-up
      service.search(
        indexBundle,
        const SearchRequest(
          keywords: {'infantry'},
          docTypes: {SearchDocType.unit},
        ),
      );

      emit('--- search(keywords, units) ---');
      for (final keyword in keywords) {
        final request = SearchRequest(
          keywords: {keyword},
          docTypes: const {SearchDocType.unit},
        );
        final sw = Stopwatch()..start();
        for (var i = 0; i < runs; i++) {
          service.search(indexBundle, request);
        }
        sw.stop();

        final result = service.search(indexBundle, request);
        final avgUs = sw.elapsedMicroseconds / runs;
        emit('  keyword("$keyword"): '
            '${avgUs.toStringAsFixed(1)} µs avg, '
            '${result.hits.length} hits');
      }
      emit('');
    });
  });

  // -------------------------------------------------------------------------
  // search(characteristicFilters)
  // -------------------------------------------------------------------------

  group('search(characteristicFilters)', () {
    const runs = 50;

    test('timing per characteristic filter (N=$runs)', () {
      // Collect real values from the index
      final mUnit = indexBundle.units.firstWhere(
        (u) => u.characteristics.any((c) => c.name.toLowerCase() == 'm'),
        orElse: () => indexBundle.units.first,
      );
      final mValue = mUnit.characteristics
          .firstWhere(
            (c) => c.name.toLowerCase() == 'm',
            orElse: () => mUnit.characteristics.first,
          )
          .valueText;

      final svUnit = indexBundle.units.firstWhere(
        (u) => u.characteristics.any((c) => c.name.toLowerCase() == 'sv'),
        orElse: () => indexBundle.units.first,
      );
      final svValue = svUnit.characteristics
          .firstWhere(
            (c) => c.name.toLowerCase() == 'sv',
            orElse: () => svUnit.characteristics.first,
          )
          .valueText;

      final tUnit = indexBundle.units.firstWhere(
        (u) => u.characteristics.any((c) => c.name.toLowerCase() == 't'),
        orElse: () => indexBundle.units.first,
      );
      final tValue = tUnit.characteristics
          .firstWhere(
            (c) => c.name.toLowerCase() == 't',
            orElse: () => tUnit.characteristics.first,
          )
          .valueText;

      final charQueries = <String, Map<String, String>>{
        'M=$mValue': {'M': mValue},
        'SV=$svValue': {'SV': svValue},
        'T=$tValue': {'T': tValue},
      };

      // Warm-up
      service.search(
        indexBundle,
        SearchRequest(characteristicFilters: {'M': mValue}),
      );

      emit('--- search(characteristicFilters, units) ---');
      for (final entry in charQueries.entries) {
        final request = SearchRequest(
          characteristicFilters: entry.value,
          docTypes: const {SearchDocType.unit},
        );
        final sw = Stopwatch()..start();
        for (var i = 0; i < runs; i++) {
          service.search(indexBundle, request);
        }
        sw.stop();

        final result = service.search(indexBundle, request);
        final avgUs = sw.elapsedMicroseconds / runs;
        emit('  char(${entry.key}): '
            '${avgUs.toStringAsFixed(1)} µs avg, '
            '${result.hits.length} hits');
      }
      emit('');
    });
  });

  // -------------------------------------------------------------------------
  // search(text + keywords) — combined AND query
  // -------------------------------------------------------------------------

  group('search(text + keywords combined)', () {
    const runs = 100;

    final queries = <String, SearchRequest>{
      'text=captain + keyword=character': const SearchRequest(
        text: 'captain',
        keywords: {'character'},
        docTypes: {SearchDocType.unit},
      ),
      'text=intercessor + keyword=infantry': const SearchRequest(
        text: 'intercessor',
        keywords: {'infantry'},
        docTypes: {SearchDocType.unit},
      ),
      'text=bolt + keyword=rapid fire': const SearchRequest(
        text: 'bolt',
        keywords: {'rapid fire'},
        docTypes: {SearchDocType.weapon},
      ),
    };

    test('timing per combined query (N=$runs)', () {
      // Warm-up
      service.search(
        indexBundle,
        const SearchRequest(
          text: 'warm',
          keywords: {'infantry'},
          docTypes: {SearchDocType.unit},
        ),
      );

      emit('--- search(text + keywords combined) ---');
      for (final entry in queries.entries) {
        final sw = Stopwatch()..start();
        for (var i = 0; i < runs; i++) {
          service.search(indexBundle, entry.value);
        }
        sw.stop();

        final result = service.search(indexBundle, entry.value);
        final avgUs = sw.elapsedMicroseconds / runs;
        emit('  combined(${entry.key}): '
            '${avgUs.toStringAsFixed(1)} µs avg, '
            '${result.hits.length} hits');
      }
      emit('');
    });
  });

  // -------------------------------------------------------------------------
  // search(sort modes)
  // -------------------------------------------------------------------------

  group('search(sort modes)', () {
    const runs = 50;
    const query = 'marine';

    test('timing per sort mode (N=$runs, text="$query")', () {
      emit('--- search(sort modes, text="$query") ---');

      for (final sort in SearchSort.values) {
        for (final dir in SortDirection.values) {
          final request = SearchRequest(
            text: query,
            sort: sort,
            sortDirection: dir,
          );
          final sw = Stopwatch()..start();
          for (var i = 0; i < runs; i++) {
            service.search(indexBundle, request);
          }
          sw.stop();

          final result = service.search(indexBundle, request);
          final avgUs = sw.elapsedMicroseconds / runs;
          emit('  ${sort.name}/${dir.name}: '
              '${avgUs.toStringAsFixed(1)} µs avg, '
              '${result.hits.length} hits');
        }
      }
      emit('');
    });
  });

  // -------------------------------------------------------------------------
  // resolveByDocId()
  // -------------------------------------------------------------------------

  group('resolveByDocId()', () {
    const runs = 1000;

    test('timing for unit/weapon/rule/miss (N=$runs)', () {
      final unitDocId =
          indexBundle.units.isNotEmpty ? indexBundle.units.first.docId : null;
      final weaponDocId = indexBundle.weapons.isNotEmpty
          ? indexBundle.weapons.first.docId
          : null;
      final ruleDocId =
          indexBundle.rules.isNotEmpty ? indexBundle.rules.first.docId : null;
      const missDocId = 'unit:__nonexistent__';

      // Warm-up
      if (unitDocId != null) service.resolveByDocId(indexBundle, unitDocId);

      emit('--- resolveByDocId() ---');

      if (unitDocId != null) {
        final sw = Stopwatch()..start();
        for (var i = 0; i < runs; i++) {
          service.resolveByDocId(indexBundle, unitDocId);
        }
        sw.stop();
        emit('  unit: '
            '${(sw.elapsedMicroseconds / runs).toStringAsFixed(1)} µs avg');
      }

      if (weaponDocId != null) {
        final sw = Stopwatch()..start();
        for (var i = 0; i < runs; i++) {
          service.resolveByDocId(indexBundle, weaponDocId);
        }
        sw.stop();
        emit('  weapon: '
            '${(sw.elapsedMicroseconds / runs).toStringAsFixed(1)} µs avg');
      }

      if (ruleDocId != null) {
        final sw = Stopwatch()..start();
        for (var i = 0; i < runs; i++) {
          service.resolveByDocId(indexBundle, ruleDocId);
        }
        sw.stop();
        emit('  rule: '
            '${(sw.elapsedMicroseconds / runs).toStringAsFixed(1)} µs avg');
      }

      // Miss path
      final sw = Stopwatch()..start();
      for (var i = 0; i < runs; i++) {
        service.resolveByDocId(indexBundle, missDocId);
      }
      sw.stop();
      emit('  miss: '
          '${(sw.elapsedMicroseconds / runs).toStringAsFixed(1)} µs avg');

      emit('');
      emit('=== End V1 Query Benchmark ===');
      emit('');
    });
  });
}

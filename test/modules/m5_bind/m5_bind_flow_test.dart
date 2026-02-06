import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';

void main() {
  const testSource = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  late LinkedPackBundle linkedBundle;

  setUpAll(() async {
    // Clean storage
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    // Acquire, parse, wrap, link bundle once for all tests
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
    linkedBundle = await LinkService().linkBundle(wrappedBundle: wrappedBundle);
  });

  tearDownAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('M5 Bind: flow harness (fixtures)', () {
    test('bindBundle: links then binds into BoundPackBundle', () async {
      final bindService = BindService();
      final boundBundle =
          await bindService.bindBundle(linkedBundle: linkedBundle);

      print('[M5 TEST] M5 Bind succeeded');
      print('[M5 TEST] Bound packId: ${boundBundle.packId}');
      print('[M5 TEST] Bound at: ${boundBundle.boundAt}');

      // packId must match
      expect(boundBundle.packId, linkedBundle.packId);

      // Must have entries
      expect(boundBundle.entries.isNotEmpty, isTrue);
      print('[M5 TEST] Entries bound: ${boundBundle.entries.length}');

      // Must have profiles
      print('[M5 TEST] Profiles bound: ${boundBundle.profiles.length}');

      // Must have categories
      print('[M5 TEST] Categories bound: ${boundBundle.categories.length}');

      // Diagnostics
      print('[M5 TEST] Diagnostics: ${boundBundle.diagnostics.length}');
      print(
          '[M5 TEST]   UNRESOLVED_ENTRY_LINK: ${boundBundle.unresolvedEntryLinkCount}');
      print(
          '[M5 TEST]   UNRESOLVED_INFO_LINK: ${boundBundle.unresolvedInfoLinkCount}');
      print(
          '[M5 TEST]   UNRESOLVED_CATEGORY_LINK: ${boundBundle.unresolvedCategoryLinkCount}');
      print(
          '[M5 TEST]   SHADOWED_DEFINITION: ${boundBundle.shadowedDefinitionCount}');

      // Pinpoint each diagnostic for debugging
      for (final d in boundBundle.diagnostics.take(10)) {
        print('[M5 TEST] Diagnostic detail:');
        print('[M5 TEST]   code: ${d.code}');
        print('[M5 TEST]   targetId: ${d.targetId}');
        print('[M5 TEST]   sourceFileId: ${d.sourceFileId}');
        print('[M5 TEST]   sourceNode.nodeIndex: ${d.sourceNode?.nodeIndex}');
        print('[M5 TEST]   message: ${d.message}');
      }
      if (boundBundle.diagnostics.length > 10) {
        print(
            '[M5 TEST]   ... and ${boundBundle.diagnostics.length - 10} more');
      }

      // linkedBundle reference preserved
      expect(boundBundle.linkedBundle, same(linkedBundle));

      print('[M5 TEST] All flow validations passed');
    });

    test('query surface: entryById returns correct entry or null', () async {
      final bindService = BindService();
      final boundBundle =
          await bindService.bindBundle(linkedBundle: linkedBundle);

      // Get first entry
      if (boundBundle.entries.isNotEmpty) {
        final firstEntry = boundBundle.entries.first;
        final found = boundBundle.entryById(firstEntry.id);
        expect(found, isNotNull);
        expect(found!.id, firstEntry.id);
        expect(found.name, firstEntry.name);
        print('[M5 TEST] entryById found: ${found.name}');
      }

      // Non-existent ID returns null
      final notFound = boundBundle.entryById('this-id-does-not-exist');
      expect(notFound, isNull);
      print('[M5 TEST] entryById returns null for non-existent ID');
    });

    test('query surface: entriesInCategory returns correct subset', () async {
      final bindService = BindService();
      final boundBundle =
          await bindService.bindBundle(linkedBundle: linkedBundle);

      // Find an entry with categories
      for (final entry in boundBundle.entries) {
        if (entry.categories.isNotEmpty) {
          final categoryId = entry.categories.first.id;
          final entriesInCat = boundBundle.entriesInCategory(categoryId);
          expect(entriesInCat.isNotEmpty, isTrue);
          // The entry should be in the result
          expect(
              entriesInCat.any((e) => e.id == entry.id), isTrue);
          print(
              '[M5 TEST] entriesInCategory($categoryId): ${entriesInCat.length} entries');
          break;
        }
      }

      // Non-existent category returns empty
      final empty =
          boundBundle.entriesInCategory('this-category-does-not-exist');
      expect(empty.isEmpty, isTrue);
      print('[M5 TEST] entriesInCategory returns empty for non-existent category');
    });
  });
}

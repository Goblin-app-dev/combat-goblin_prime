import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

void main() {
  const testSource = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  late ParsedPackBundle parsedBundle;

  setUpAll(() async {
    // Clean storage
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    // Acquire and parse bundle once for all tests
    final gameSystemBytes = await File('test/Warhammer 40,000.gst').readAsBytes();
    final primaryCatalogBytes = await File('test/Imperium - Space Marines.cat').readAsBytes();

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

    parsedBundle = await ParseService().parseBundle(rawBundle: rawBundle);
  });

  tearDownAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('M3 Wrap: flow harness (fixtures)', () {
    test('wrapBundle: parses then wraps into WrappedPackBundle', () async {
      final wrapService = WrapService();
      final wrappedBundle = await wrapService.wrapBundle(parsedBundle: parsedBundle);

      print('[M3 TEST] M3 Wrap succeeded');
      print('[M3 TEST] Wrapped packId: ${wrappedBundle.packId}');
      print('[M3 TEST] Wrapped at: ${wrappedBundle.wrappedAt}');

      // packId must match
      expect(wrappedBundle.packId, parsedBundle.packId);

      // gameSystem provenance
      expect(wrappedBundle.gameSystem.fileId, parsedBundle.gameSystem.fileId);
      expect(wrappedBundle.gameSystem.fileType, SourceFileType.gst);
      expect(wrappedBundle.gameSystem.nodes.isNotEmpty, isTrue);
      print('[M3 TEST] gameSystem wrapped:');
      print('[M3 TEST]   fileId: ${wrappedBundle.gameSystem.fileId}');
      print('[M3 TEST]   nodes: ${wrappedBundle.gameSystem.nodes.length}');
      print('[M3 TEST]   root tag: ${wrappedBundle.gameSystem.root.tagName}');

      // primaryCatalog provenance
      expect(wrappedBundle.primaryCatalog.fileId, parsedBundle.primaryCatalog.fileId);
      expect(wrappedBundle.primaryCatalog.fileType, SourceFileType.cat);
      expect(wrappedBundle.primaryCatalog.nodes.isNotEmpty, isTrue);
      print('[M3 TEST] primaryCatalog wrapped:');
      print('[M3 TEST]   fileId: ${wrappedBundle.primaryCatalog.fileId}');
      print('[M3 TEST]   nodes: ${wrappedBundle.primaryCatalog.nodes.length}');
      print('[M3 TEST]   root tag: ${wrappedBundle.primaryCatalog.root.tagName}');

      // dependencyCatalogs count
      expect(wrappedBundle.dependencyCatalogs.length, parsedBundle.dependencyCatalogs.length);
      expect(wrappedBundle.dependencyCatalogs.length, 4);
      print('[M3 TEST] dependencyCatalogs wrapped: ${wrappedBundle.dependencyCatalogs.length}');

      for (var i = 0; i < wrappedBundle.dependencyCatalogs.length; i++) {
        final wrapped = wrappedBundle.dependencyCatalogs[i];
        final parsed = parsedBundle.dependencyCatalogs[i];
        expect(wrapped.fileId, parsed.fileId);
        expect(wrapped.nodes.isNotEmpty, isTrue);
        print('[M3 TEST]   dependency[$i]: ${wrapped.nodes.length} nodes');
      }

      // Root node must be at index 0
      expect(wrappedBundle.gameSystem.root.ref.nodeIndex, 0);
      expect(wrappedBundle.primaryCatalog.root.ref.nodeIndex, 0);
      for (final dep in wrappedBundle.dependencyCatalogs) {
        expect(dep.root.ref.nodeIndex, 0);
      }

      // Root must have depth 0
      expect(wrappedBundle.gameSystem.root.depth, 0);
      expect(wrappedBundle.primaryCatalog.root.depth, 0);

      // Root must have no parent
      expect(wrappedBundle.gameSystem.root.parent, isNull);
      expect(wrappedBundle.primaryCatalog.root.parent, isNull);

      // Expected root tags
      expect(wrappedBundle.gameSystem.root.tagName, 'gameSystem');
      expect(wrappedBundle.primaryCatalog.root.tagName, 'catalogue');

      print('[M3 TEST] All flow validations passed');
    });
  });
}

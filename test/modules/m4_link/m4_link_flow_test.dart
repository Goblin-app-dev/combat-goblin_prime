import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';

void main() {
  const testSource = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  late WrappedPackBundle wrappedBundle;

  setUpAll(() async {
    // Clean storage
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    // Acquire, parse, and wrap bundle once for all tests
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

    final parsedBundle = await ParseService().parseBundle(rawBundle: rawBundle);
    wrappedBundle = await WrapService().wrapBundle(parsedBundle: parsedBundle);
  });

  tearDownAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('M4 Link: flow harness (fixtures)', () {
    test('linkBundle: wraps then links into LinkedPackBundle', () async {
      final linkService = LinkService();
      final linkedBundle = await linkService.linkBundle(wrappedBundle: wrappedBundle);

      print('[M4 TEST] M4 Link succeeded');
      print('[M4 TEST] Linked packId: ${linkedBundle.packId}');
      print('[M4 TEST] Linked at: ${linkedBundle.linkedAt}');

      // packId must match
      expect(linkedBundle.packId, wrappedBundle.packId);

      // SymbolTable built
      expect(linkedBundle.symbolTable.idCount, greaterThan(0));
      print('[M4 TEST] SymbolTable:');
      print('[M4 TEST]   unique IDs: ${linkedBundle.symbolTable.idCount}');
      print('[M4 TEST]   total entries: ${linkedBundle.symbolTable.entryCount}');
      print('[M4 TEST]   duplicate IDs: ${linkedBundle.symbolTable.duplicateIds.length}');

      // ResolvedRefs created
      expect(linkedBundle.resolvedRefs, isNotEmpty);
      print('[M4 TEST] ResolvedRefs: ${linkedBundle.resolvedRefs.length}');

      // Count resolution stats
      final resolved = linkedBundle.resolvedRefs.where((r) => r.isResolved).length;
      final unique = linkedBundle.resolvedRefs.where((r) => r.isUnique).length;
      final multiHit = linkedBundle.resolvedRefs.where((r) => r.isMultiHit).length;
      final unresolved = linkedBundle.resolvedRefs.where((r) => !r.isResolved).length;

      print('[M4 TEST]   resolved: $resolved');
      print('[M4 TEST]   unique: $unique');
      print('[M4 TEST]   multi-hit: $multiHit');
      print('[M4 TEST]   unresolved: $unresolved');

      // Diagnostics
      print('[M4 TEST] Diagnostics: ${linkedBundle.diagnostics.length}');
      print('[M4 TEST]   UNRESOLVED_TARGET: ${linkedBundle.unresolvedCount}');
      print('[M4 TEST]   DUPLICATE_ID_REFERENCE: ${linkedBundle.duplicateRefCount}');
      print('[M4 TEST]   INVALID_LINK_FORMAT: ${linkedBundle.invalidFormatCount}');

      // wrappedBundle reference preserved
      expect(linkedBundle.wrappedBundle, same(wrappedBundle));

      // Verify diagnostic counts match resolution counts
      expect(linkedBundle.unresolvedCount, unresolved);
      expect(linkedBundle.duplicateRefCount, multiHit);

      print('[M4 TEST] All flow validations passed');
    });
  });
}

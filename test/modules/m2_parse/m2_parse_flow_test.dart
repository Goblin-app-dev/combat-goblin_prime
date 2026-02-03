import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';

void main() {
  // Test source locator for BSData wh40k-10e
  const testSource = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  group('M2 Parse: flow harness (fixtures)', () {
    setUp(() async {
      // Always start clean: deterministic storage root.
      final dir = Directory('appDataRoot');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    tearDown(() async {
      // Keep reruns clean.
      final dir = Directory('appDataRoot');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('parseBundle: acquires RawPackBundle then parses into ParsedPackBundle', () async {
      // --- Step 1: Acquire RawPackBundle via M1 ---
      final gameSystemFile = File('test/Warhammer 40,000.gst');
      final primaryCatalogFile = File('test/Imperium - Space Marines.cat');

      expect(await gameSystemFile.exists(), isTrue,
          reason: 'Missing fixture: test/Warhammer 40,000.gst');
      expect(await primaryCatalogFile.exists(), isTrue,
          reason: 'Missing fixture: test/Imperium - Space Marines.cat');

      final gameSystemBytes = await gameSystemFile.readAsBytes();
      final primaryCatalogBytes = await primaryCatalogFile.readAsBytes();

      // Dependency catalog mapping: targetId -> file path
      final dependencyFiles = <String, String>{
        'b00-cd86-4b4c-97ba': 'test/Imperium - Agents of the Imperium.cat',
        '7481-280e-b55e-7867': 'test/Library - Titans.cat',
        '1b6d-dc06-5db9-c7d1': 'test/Imperium - Imperial Knights - Library.cat',
        'ac3b-689c-4ad4-70cb': 'test/Library - Astartes Heresy Legends.cat',
      };

      final acquireService = AcquireService();

      RawPackBundle rawBundle;
      try {
        rawBundle = await acquireService.buildBundle(
          gameSystemBytes: gameSystemBytes,
          gameSystemExternalFileName: 'Warhammer 40,000.gst',
          primaryCatalogBytes: primaryCatalogBytes,
          primaryCatalogExternalFileName: 'Imperium - Space Marines.cat',
          requestDependencyBytes: (missingTargetId) async {
            final filePath = dependencyFiles[missingTargetId];
            if (filePath == null) return null;
            final file = File(filePath);
            if (!await file.exists()) return null;
            return await file.readAsBytes();
          },
          source: testSource,
        );
      } on AcquireFailure catch (e) {
        fail('M1 Acquire failed unexpectedly: ${e.message} (missing: ${e.missingTargetIds})');
      }

      // M1 must succeed for M2 test to proceed
      expect(rawBundle.packId.isNotEmpty, isTrue);
      expect(rawBundle.dependencyCatalogBytesList.length, 4,
          reason: 'Expected 4 dependency catalogs from M1');
      print('[M2 TEST] M1 Acquire succeeded with packId: ${rawBundle.packId}');
      print('[M2 TEST] Dependencies acquired: ${rawBundle.dependencyCatalogMetadatas.length}');

      // --- Step 2: Parse RawPackBundle via M2 ---
      final parseService = ParseService();

      ParsedPackBundle parsedBundle;
      try {
        parsedBundle = await parseService.parseBundle(rawBundle: rawBundle);
      } on ParseFailure catch (e) {
        fail('M2 Parse failed unexpectedly: ${e.message} (fileId: ${e.fileId}, sourceIndex: ${e.sourceIndex})');
      }

      print('[M2 TEST] M2 Parse succeeded');
      print('[M2 TEST] Parsed packId: ${parsedBundle.packId}');
      print('[M2 TEST] Parsed at: ${parsedBundle.parsedAt}');

      // --- Step 3: Validate ParsedPackBundle structure ---

      // A) packId must match M1 bundle
      expect(parsedBundle.packId, rawBundle.packId);

      // B) gameSystem parsed correctly
      expect(parsedBundle.gameSystem.fileId, rawBundle.gameSystemMetadata.fileId);
      expect(parsedBundle.gameSystem.fileType, SourceFileType.gst);
      expect(parsedBundle.gameSystem.rootId, rawBundle.gameSystemPreflight.rootId);
      print('[M2 TEST] gameSystem parsed:');
      print('[M2 TEST]   fileId: ${parsedBundle.gameSystem.fileId}');
      print('[M2 TEST]   rootId: ${parsedBundle.gameSystem.rootId}');
      print('[M2 TEST]   root tag: ${parsedBundle.gameSystem.root.tagName}');

      // C) primaryCatalog parsed correctly
      expect(parsedBundle.primaryCatalog.fileId, rawBundle.primaryCatalogMetadata.fileId);
      expect(parsedBundle.primaryCatalog.fileType, SourceFileType.cat);
      expect(parsedBundle.primaryCatalog.rootId, rawBundle.primaryCatalogPreflight.rootId);
      print('[M2 TEST] primaryCatalog parsed:');
      print('[M2 TEST]   fileId: ${parsedBundle.primaryCatalog.fileId}');
      print('[M2 TEST]   rootId: ${parsedBundle.primaryCatalog.rootId}');
      print('[M2 TEST]   root tag: ${parsedBundle.primaryCatalog.root.tagName}');

      // D) dependencyCatalogs count matches M1
      expect(parsedBundle.dependencyCatalogs.length, rawBundle.dependencyCatalogMetadatas.length);
      expect(parsedBundle.dependencyCatalogs.length, 4);
      print('[M2 TEST] dependencyCatalogs parsed: ${parsedBundle.dependencyCatalogs.length}');

      // E) Each dependency fileId matches M1
      final rawDepFileIds = rawBundle.dependencyCatalogMetadatas.map((m) => m.fileId).toSet();
      for (final parsedDep in parsedBundle.dependencyCatalogs) {
        expect(rawDepFileIds.contains(parsedDep.fileId), isTrue,
            reason: 'Parsed dependency fileId ${parsedDep.fileId} not found in M1 bundle');
        print('[M2 TEST]   dependency: ${parsedDep.rootId} (fileId: ${parsedDep.fileId.substring(0, 16)}...)');
      }

      // F) Structural sanity for each ParsedFile (without deep schema assertions)
      void validateParsedFile(ParsedFile pf, String label) {
        // Root element exists
        expect(pf.root, isNotNull, reason: '$label: root element is null');

        // Root tag name is non-empty
        expect(pf.root.tagName.isNotEmpty, isTrue,
            reason: '$label: root tag name is empty');

        // Attributes map exists (can be empty)
        expect(pf.root.attributes, isNotNull,
            reason: '$label: attributes map is null');

        // Children list exists (can be empty)
        expect(pf.root.children, isNotNull,
            reason: '$label: children list is null');

        // sourceIndex is optional (nullable) - just check it doesn't crash
        // No assertion on value since it's best-effort

        print('[M2 TEST] $label structural sanity: OK');
        print('[M2 TEST]   tag: ${pf.root.tagName}');
        print('[M2 TEST]   attributes: ${pf.root.attributes.length}');
        print('[M2 TEST]   children: ${pf.root.children.length}');
      }

      validateParsedFile(parsedBundle.gameSystem, 'gameSystem');
      validateParsedFile(parsedBundle.primaryCatalog, 'primaryCatalog');
      for (var i = 0; i < parsedBundle.dependencyCatalogs.length; i++) {
        validateParsedFile(parsedBundle.dependencyCatalogs[i], 'dependency[$i]');
      }

      // G) Verify expected root tags for this fixture set
      expect(parsedBundle.gameSystem.root.tagName, 'gameSystem');
      expect(parsedBundle.primaryCatalog.root.tagName, 'catalogue');
      for (final dep in parsedBundle.dependencyCatalogs) {
        expect(dep.root.tagName, 'catalogue');
      }

      print('[M2 TEST] All validations passed');
    });
  });
}
